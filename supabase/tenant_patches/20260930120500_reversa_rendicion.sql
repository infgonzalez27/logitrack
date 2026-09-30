-- Parche para implementar la reversión de rendición de cuentas
-- Fecha: 2026-09-30

ALTER TABLE IF EXISTS public.movimientos_saldo_favor 
  DROP CONSTRAINT IF EXISTS movimientos_saldo_favor_tipo_check;

ALTER TABLE public.movimientos_saldo_favor 
  ADD CONSTRAINT movimientos_saldo_favor_tipo_check 
  CHECK (tipo = ANY (ARRAY['abono_recaudacion'::text, 'cargo_pago_orden'::text, 'devolucion_efectivo'::text, 'reverso_rendicion'::text]));

CREATE OR REPLACE FUNCTION public.reversa_rendicion_cuenta_segun_id_rendicion(p_id_rendicion UUID)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_estado_actual TEXT;
    v_cliente_id UUID;
    v_rol TEXT;
    v_movimiento RECORD;
    v_orden RECORD;
BEGIN
    -- Validar rol (Solo gerente)
    SELECT public.lt_current_user_rol() INTO v_rol;
    IF v_rol != 'gerente' THEN
        RAISE EXCEPTION 'Permiso denegado: Solo los usuarios con rol de Gerente pueden revertir rendiciones.';
    END IF;

    -- Validar existencia y estado de la rendición
    SELECT estado, cliente_id 
    INTO v_estado_actual, v_cliente_id 
    FROM public.rendiciones_cuentas 
    WHERE id = p_id_rendicion;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La rendición especificada no existe (ID: %)', p_id_rendicion;
    END IF;

    IF v_estado_actual ILIKE 'reversada' THEN
        RAISE EXCEPTION 'La rendición ya se encuentra reversada (ID: %)', p_id_rendicion;
    END IF;

    IF v_estado_actual NOT ILIKE 'aprobada' AND v_estado_actual NOT ILIKE 'liquidada' AND v_estado_actual NOT ILIKE 'cerrada' THEN
        RAISE EXCEPTION 'La rendición no está en un estado válido para ser reversada (Estado actual: %)', v_estado_actual;
    END IF;

    -- 1. Actualizar el estado de la rendición (Cabecera) a 'reversada'
    UPDATE public.rendiciones_cuentas
    SET estado = 'reversada',
        observaciones = COALESCE(observaciones, '') || ' [REVERSADA por Gerente el ' || TO_CHAR(NOW(), 'YYYY-MM-DD HH24:MI') || ']'
    WHERE id = p_id_rendicion;

    -- 2. Liberación de Órdenes de Distribución
    -- Al pasar la rendición a 'reversada', liquidar_orden_distribucion dejará de sumar estos abonos
    FOR v_orden IN (
        SELECT orden_distribucion_id 
        FROM public.detalle_rendicion_ordenes 
        WHERE rendicion_id = p_id_rendicion
    ) LOOP
        PERFORM public.liquidar_orden_distribucion(v_orden.orden_distribucion_id);
    END LOOP;

    -- 3. Reversión de Saldos de Cliente (Caja Principal)
    FOR v_movimiento IN (
        SELECT id, monto, tipo, orden_id
        FROM public.movimientos_saldo_favor
        WHERE rendicion_id = p_id_rendicion
    ) LOOP
        -- Registrar movimiento inverso
        INSERT INTO public.movimientos_saldo_favor (
            cliente_id,
            rendicion_id,
            orden_id,
            monto,
            tipo,
            observaciones,
            created_at
        ) VALUES (
            v_cliente_id,
            p_id_rendicion,
            v_movimiento.orden_id,
            (v_movimiento.monto * -1),
            'reverso_rendicion',
            'Reversión del movimiento ID ' || v_movimiento.id,
            NOW()
        );

        -- Ajustar el saldo del cliente
        UPDATE public.clientes
        SET saldo_favor = COALESCE(saldo_favor, 0) + (v_movimiento.monto * -1)
        WHERE id = v_cliente_id;
    END LOOP;

    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'rendicion_id', p_id_rendicion,
            'estado_nuevo', 'reversada'
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

ALTER FUNCTION public.reversa_rendicion_cuenta_segun_id_rendicion(UUID) OWNER TO postgres;
