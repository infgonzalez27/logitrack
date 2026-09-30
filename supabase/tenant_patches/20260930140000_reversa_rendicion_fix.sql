-- Corrección de reversa_rendicion_cuenta_segun_id_rendicion (parche 20260930120500).
-- Fecha: 2026-09-30
--
-- Problemas del parche original, verificados en Ramirez y Berraco:
--   1. rendiciones_cuentas_estado_check no admite 'reversada': el UPDATE siempre falla.
--   2. movimientos_saldo_favor_tipo_check no admite 'reverso_rendicion': el INSERT siempre falla.
--   3. liquidar_orden_distribucion solo evalúa órdenes en 'por_liquidar'; las 'liquidada'
--      nunca volvían a la cola de cobranzas.
--   4. IF v_rol != 'gerente' con rol NULL (anon / sin perfil) no bloquea, y la función
--      tenía EXECUTE para PUBLIC y anon.
--   5. Si el cliente ya usó el saldo a favor generado por la cobranza, el reverso choca
--      con clientes_saldo_favor_check sin un mensaje claro.
--
-- Idempotente: se puede ejecutar más de una vez.

ALTER TABLE public.rendiciones_cuentas
  DROP CONSTRAINT IF EXISTS rendiciones_cuentas_estado_check;
ALTER TABLE public.rendiciones_cuentas
  ADD CONSTRAINT rendiciones_cuentas_estado_check
  CHECK (estado = ANY (ARRAY['revision'::text, 'aprobada'::text, 'con_discrepancia'::text, 'reversada'::text]));

ALTER TABLE public.movimientos_saldo_favor
  DROP CONSTRAINT IF EXISTS movimientos_saldo_favor_tipo_check;
ALTER TABLE public.movimientos_saldo_favor
  ADD CONSTRAINT movimientos_saldo_favor_tipo_check
  CHECK (tipo = ANY (ARRAY['abono_recaudacion'::text, 'cargo_pago_orden'::text, 'devolucion_efectivo'::text, 'reverso_rendicion'::text]));

CREATE OR REPLACE FUNCTION public.reversa_rendicion_cuenta_segun_id_rendicion(p_id_rendicion uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_rol TEXT;
    v_estado_actual TEXT;
    v_cliente_id UUID;
    v_neto_saldo_favor NUMERIC(12, 2) := 0.00;
    v_saldo_cliente NUMERIC(12, 2) := 0.00;
    v_movimiento RECORD;
    v_orden RECORD;
    v_ordenes_liberadas INTEGER := 0;
BEGIN
    v_rol := public.lt_current_user_rol();
    IF v_rol IS DISTINCT FROM 'gerente' THEN
        RAISE EXCEPTION 'Permiso denegado: solo el gerente puede reversar cobranzas.';
    END IF;

    SELECT estado, cliente_id
    INTO v_estado_actual, v_cliente_id
    FROM public.rendiciones_cuentas
    WHERE id = p_id_rendicion
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La cobranza especificada no existe.';
    END IF;

    IF v_estado_actual = 'reversada' THEN
        RAISE EXCEPTION 'La cobranza ya está reversada.';
    END IF;

    IF v_estado_actual <> 'aprobada' THEN
        RAISE EXCEPTION 'Solo se pueden reversar cobranzas aprobadas (estado actual: %).', v_estado_actual;
    END IF;

    -- Saldo a favor: neto que esta cobranza movió (+ excedente generado, − saldo usado).
    SELECT COALESCE(SUM(monto), 0.00)
    INTO v_neto_saldo_favor
    FROM public.movimientos_saldo_favor
    WHERE rendicion_id = p_id_rendicion;

    SELECT COALESCE(saldo_favor, 0.00)
    INTO v_saldo_cliente
    FROM public.clientes
    WHERE id = v_cliente_id
    FOR UPDATE;

    IF v_saldo_cliente - v_neto_saldo_favor < 0 THEN
        RAISE EXCEPTION 'El cliente ya usó % del saldo a favor que generó esta cobranza (saldo actual: %). Reversa primero la cobranza donde lo usó.',
            (v_neto_saldo_favor - v_saldo_cliente), v_saldo_cliente;
    END IF;

    -- 1. Cabecera: al dejar de estar 'aprobada', sus abonos ya no cuentan en
    --    liquidar_orden_distribucion, retorna_ordenes_por_liquidar ni reportes.
    UPDATE public.rendiciones_cuentas
    SET estado = 'reversada',
        observaciones = TRIM(COALESCE(observaciones, '') || ' [REVERSADA por gerente el ' || TO_CHAR(NOW(), 'YYYY-MM-DD HH24:MI') || ']')
    WHERE id = p_id_rendicion;

    -- 2. Órdenes: vuelven a 'por_liquidar' y se reevalúan con las cobranzas aprobadas restantes.
    FOR v_orden IN
        SELECT DISTINCT orden_distribucion_id AS id
        FROM public.detalle_rendicion_ordenes
        WHERE rendicion_id = p_id_rendicion
    LOOP
        UPDATE public.ordenes_distribucion
        SET estado = 'por_liquidar'
        WHERE id = v_orden.id
          AND estado = 'liquidada';

        PERFORM public.liquidar_orden_distribucion(v_orden.id);
        v_ordenes_liberadas := v_ordenes_liberadas + 1;
    END LOOP;

    -- 3. Movimientos inversos de saldo a favor.
    FOR v_movimiento IN
        SELECT id, monto, orden_id
        FROM public.movimientos_saldo_favor
        WHERE rendicion_id = p_id_rendicion
          AND tipo <> 'reverso_rendicion'
    LOOP
        INSERT INTO public.movimientos_saldo_favor (
            cliente_id, rendicion_id, orden_id, monto, tipo, observaciones, created_at
        ) VALUES (
            v_cliente_id,
            p_id_rendicion,
            v_movimiento.orden_id,
            -v_movimiento.monto,
            'reverso_rendicion',
            'Reverso del movimiento ID ' || v_movimiento.id,
            NOW()
        );
    END LOOP;

    IF v_neto_saldo_favor <> 0 THEN
        UPDATE public.clientes
        SET saldo_favor = COALESCE(saldo_favor, 0.00) - v_neto_saldo_favor
        WHERE id = v_cliente_id;
    END IF;

    RETURN json_build_object(
        'success', true,
        'message', 'Cobranza reversada. ' || v_ordenes_liberadas || ' orden(es) vuelven a por liquidar.',
        'data', json_build_object(
            'rendicion_id', p_id_rendicion,
            'estado_nuevo', 'reversada',
            'ordenes_liberadas', v_ordenes_liberadas,
            'saldo_favor_ajuste', -v_neto_saldo_favor
        ),
        'error', NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'SQL_ERROR',
                'message', SQLERRM,
                'details', 'SQLSTATE: ' || SQLSTATE
            )
        );
END;
$$;

ALTER FUNCTION public.reversa_rendicion_cuenta_segun_id_rendicion(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.reversa_rendicion_cuenta_segun_id_rendicion(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reversa_rendicion_cuenta_segun_id_rendicion(uuid) TO authenticated, service_role;
