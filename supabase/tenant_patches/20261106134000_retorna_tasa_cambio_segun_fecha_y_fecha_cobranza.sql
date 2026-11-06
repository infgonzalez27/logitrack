-- ==============================================================================
-- Parche Idempotente: Tasa de Cambio según Fecha y Fecha de Pago / Registro en Cobranzas
-- Fecha: 2026-11-06 13:40:00
-- Descripción:
--   1. Agrega la columna `fecha_registro TIMESTAMPTZ NOT NULL DEFAULT NOW()` a la
--      tabla cabecera `public.rendiciones_cuentas` para distinguir la fecha efectiva
--      del pago/abono (`fecha_rendicion`) de la fecha y hora exacta de registro en
--      el sistema (`fecha_registro`).
--   2. Crea la función RPC `public.retorna_tasa_cambio_segun_fecha(dfecha date)`
--      que retorna la tasa registrada para la fecha indicada o informa
--      "Tasa no registrada" cuando no existe registro para ese día.
--   3. Actualiza `public.registrar_rendicion_cuentas` incorporando `p_fecha_pago`
--      (con DEFAULT NULL para retrocompatibilidad), permitiendo guardar la fecha
--      del pago en `fecha_rendicion`, la fecha/hora actual en `fecha_registro`,
--      aplicar tasa según fecha o tasa manual, y asegurar el registro en
--      `public.logs_auditoria` con la fecha y hora exacta del momento.
--   4. Actualiza `public.reporte_formas_pago_rendicion` para exponer `fecha_registro`.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Columna fecha_registro y trigger de auditoría en public.rendiciones_cuentas
-- ------------------------------------------------------------------------------
ALTER TABLE public.rendiciones_cuentas
    ADD COLUMN IF NOT EXISTS fecha_registro TIMESTAMPTZ NOT NULL DEFAULT NOW();

COMMENT ON COLUMN public.rendiciones_cuentas.fecha_rendicion IS
    'Fecha efectiva del pago o abono reportado en la cobranza.';

COMMENT ON COLUMN public.rendiciones_cuentas.fecha_registro IS
    'Fecha y hora exacta en que se registró la cobranza en el sistema.';

DROP TRIGGER IF EXISTS audit_rendiciones_cuentas ON public.rendiciones_cuentas;
CREATE TRIGGER audit_rendiciones_cuentas
    AFTER INSERT OR DELETE OR UPDATE ON public.rendiciones_cuentas
    FOR EACH ROW EXECUTE FUNCTION public.procesar_log_auditoria();

-- ------------------------------------------------------------------------------
-- 2. Función RPC: public.retorna_tasa_cambio_segun_fecha(dFecha)
-- ------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.retorna_tasa_cambio_segun_fecha(date);

CREATE OR REPLACE FUNCTION public.retorna_tasa_cambio_segun_fecha(
    dfecha date
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_record RECORD;
BEGIN
    IF dfecha IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'message', 'La fecha de consulta (dFecha) es requerida.',
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'La fecha de consulta (dFecha) es requerida.',
                'details', NULL
            )
        );
    END IF;

    SELECT fecha_tasa, tasa_cambio, created_at
    INTO v_record
    FROM public.tasa_cambio
    WHERE fecha_tasa = dfecha
    LIMIT 1;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'message', 'Tasa no registrada',
            'data', NULL,
            'error', json_build_object(
                'code', 'TASA_NO_REGISTRADA',
                'message', 'Tasa no registrada',
                'details', 'No existe tasa de cambio registrada para la fecha ' || TO_CHAR(dfecha, 'YYYY-MM-DD')
            )
        );
    END IF;

    RETURN json_build_object(
        'success', true,
        'message', 'Tasa de cambio obtenida exitosamente.',
        'data', json_build_object(
            'fecha_tasa', v_record.fecha_tasa,
            'tasa_cambio', v_record.tasa_cambio,
            'created_at', v_record.created_at
        ),
        'error', NULL
    );

EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object(
        'success', false,
        'message', SQLERRM,
        'data', NULL,
        'error', json_build_object(
            'code', 'SQL_ERROR',
            'message', SQLERRM,
            'details', 'SQLSTATE: ' || SQLSTATE
        )
    );
END;
$$;

ALTER FUNCTION public.retorna_tasa_cambio_segun_fecha(date) OWNER TO postgres;
GRANT ALL ON FUNCTION public.retorna_tasa_cambio_segun_fecha(date) TO anon, authenticated, service_role;

-- ------------------------------------------------------------------------------
-- 3. Actualización de public.registrar_rendicion_cuentas
--    Soporta p_tasa_cambio (automática o manual) y p_fecha_pago (fecha del pago).
-- ------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.registrar_rendicion_cuentas(uuid, text, uuid, jsonb, jsonb);
DROP FUNCTION IF EXISTS public.registrar_rendicion_cuentas(uuid, text, uuid, jsonb, jsonb, numeric);
DROP FUNCTION IF EXISTS public.registrar_rendicion_cuentas(uuid, text, uuid, jsonb, jsonb, numeric, date);

CREATE OR REPLACE FUNCTION public.registrar_rendicion_cuentas(
    p_cliente_id uuid,
    p_observaciones text,
    p_creado_por uuid,
    p_ordenes jsonb,
    p_pagos jsonb,
    p_tasa_cambio numeric DEFAULT NULL::numeric,
    p_fecha_pago date DEFAULT NULL::date
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_rendicion_id UUID;
    v_tasa_cambio NUMERIC(10, 4);
    v_fecha_registro TIMESTAMPTZ := NOW();
    v_fecha_pago_ts TIMESTAMPTZ;
    v_hoy_caracas DATE := (NOW() AT TIME ZONE 'America/Caracas')::date;
    v_total_ordenes NUMERIC(12, 2) := 0.00;
    v_total_ordenes_bs NUMERIC(12, 2) := 0.00;
    v_total_pagos NUMERIC(12, 2) := 0.00;
    v_total_pagos_bs NUMERIC(12, 2) := 0.00;
    v_total_efectivo NUMERIC(12, 2) := 0.00;
    v_total_transferencias NUMERIC(12, 2) := 0.00;
    v_saldo_favor_usado NUMERIC(12, 2) := 0.00;
    v_cliente_saldo_favor NUMERIC(12, 2) := 0.00;
    v_item RECORD;
    v_pago RECORD;
    v_exceso NUMERIC(12, 2) := 0.00;
    v_exceso_bs NUMERIC(12, 2) := 0.00;
    v_fpago_concepto TEXT;
    v_fpago_info BOOLEAN;
    v_item_usd NUMERIC(12, 2);
    v_item_bs NUMERIC(12, 2);
    v_rec_usd NUMERIC(12, 2);
    v_rec_bs NUMERIC(12, 2);
    v_codigo_banco VARCHAR(4);
    v_referencia TEXT;
    v_nombre_banco TEXT;
BEGIN
    -- 1. Validaciones básicas
    IF p_cliente_id IS NULL OR p_creado_por IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID de cliente y el usuario creador son requeridos.',
                'details', NULL
            )
        );
    END IF;

    -- Determinar fecha efectiva del pago (fecha_rendicion) vs fecha_registro (NOW())
    IF p_fecha_pago IS NULL OR p_fecha_pago = v_hoy_caracas THEN
        v_fecha_pago_ts := v_fecha_registro;
    ELSE
        -- Mediodía UTC (08:00 AM America/Caracas) preserva exactamente la fecha civil en UTC y Caracas
        v_fecha_pago_ts := (p_fecha_pago::timestamp + interval '12 hours') AT TIME ZONE 'UTC';
    END IF;

    -- Determinar tasa de cambio:
    -- a) Tasa explícita enviada (tasa de la fecha o escrita manualmente por el usuario)
    -- b) Tasa registrada para p_fecha_pago en public.tasa_cambio
    -- c) Fallback a última tasa registrada
    IF p_tasa_cambio IS NOT NULL AND p_tasa_cambio > 0 THEN
        v_tasa_cambio := ROUND(p_tasa_cambio, 4);
    ELSIF p_fecha_pago IS NOT NULL THEN
        SELECT tasa_cambio INTO v_tasa_cambio
        FROM public.tasa_cambio
        WHERE fecha_tasa = p_fecha_pago
        LIMIT 1;
    END IF;

    IF v_tasa_cambio IS NULL OR v_tasa_cambio <= 0 THEN
        SELECT COALESCE(tasa_cambio, 1.0000) INTO v_tasa_cambio
        FROM public.tasa_cambio
        ORDER BY fecha_tasa DESC, created_at DESC
        LIMIT 1;

        IF v_tasa_cambio IS NULL OR v_tasa_cambio <= 0 THEN
            v_tasa_cambio := 1.0000;
        END IF;
    END IF;

    -- Validar que el cliente exista y obtener saldo a favor actual
    SELECT COALESCE(saldo_favor, 0.00)
    INTO v_cliente_saldo_favor
    FROM public.clientes
    WHERE id = p_cliente_id;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'CLIENTE_INEXISTENTE',
                'message', 'El cliente especificado no existe.',
                'details', NULL
            )
        );
    END IF;

    -- Validar que las listas hijas tengan al menos un elemento
    IF p_ordenes IS NULL OR jsonb_array_length(p_ordenes) = 0 THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'DETALLE_REQUISITO_FALTANTE',
                'message', 'Debe registrar al menos una orden en el detalle de la rendición.',
                'details', NULL
            )
        );
    END IF;

    IF p_pagos IS NULL OR jsonb_array_length(p_pagos) = 0 THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'DETALLE_REQUISITO_FALTANTE',
                'message', 'Debe registrar al menos una forma de pago en la rendición.',
                'details', NULL
            )
        );
    END IF;

    -- 2. Calcular totales de órdenes
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_ordenes) AS x(orden_id UUID, monto_recaudado NUMERIC(12,2), monto_recaudado_bs NUMERIC(12,2)) LOOP
        v_rec_usd := COALESCE(v_item.monto_recaudado, 0.00);
        v_rec_bs := COALESCE(v_item.monto_recaudado_bs, v_rec_usd * v_tasa_cambio);

        v_total_ordenes := v_total_ordenes + v_rec_usd;
        v_total_ordenes_bs := v_total_ordenes_bs + v_rec_bs;
    END LOOP;

    -- 3. Validar y clasificar formas de pago (USD y Bs) + validar banco y referencia
    FOR v_pago IN SELECT * FROM jsonb_to_recordset(p_pagos) AS y(
        fpago_id UUID,
        monto NUMERIC(12,2),
        monto_bs NUMERIC(12,2),
        monto_usd NUMERIC(12,2),
        cuenta_bancaria_id UUID,
        codigo_banco VARCHAR(4),
        referencia_bancaria TEXT,
        cuenta_bancaria TEXT,
        capture_url TEXT
    ) LOOP
        -- Calcular valores en ambas monedas
        IF v_pago.monto_bs IS NOT NULL AND v_pago.monto_bs > 0 THEN
            v_item_bs := v_pago.monto_bs;
            v_item_usd := COALESCE(v_pago.monto_usd, v_item_bs / v_tasa_cambio);
        ELSE
            v_item_usd := COALESCE(v_pago.monto_usd, v_pago.monto, 0.00);
            v_item_bs := COALESCE(v_pago.monto_bs, v_item_usd * v_tasa_cambio);
        END IF;

        v_total_pagos := v_total_pagos + v_item_usd;
        v_total_pagos_bs := v_total_pagos_bs + v_item_bs;

        -- Obtener información de la forma de pago
        SELECT fpago_concepto, fpago_info
        INTO v_fpago_concepto, v_fpago_info
        FROM public.fpagos
        WHERE fpago_id = v_pago.fpago_id;

        IF v_fpago_concepto IS NULL THEN
            RETURN json_build_object(
                'success', false,
                'data', NULL,
                'error', json_build_object(
                    'code', 'FORMA_PAGO_INEXISTENTE',
                    'message', 'La forma de pago especificada no existe.',
                    'details', 'fpago_id: ' || v_pago.fpago_id
                )
            );
        END IF;

        v_codigo_banco := NULLIF(TRIM(COALESCE(v_pago.codigo_banco, '')), '');
        v_referencia := NULLIF(TRIM(COALESCE(v_pago.referencia_bancaria, '')), '');

        -- Validar entidad bancaria y duplicidad cuando se indica banco y referencia
        IF v_codigo_banco IS NOT NULL THEN
            SELECT COALESCE(nombre_corto, nombre_eb)
            INTO v_nombre_banco
            FROM public.entidades_bancarias
            WHERE codigo_eb = v_codigo_banco AND activo = TRUE;

            IF NOT FOUND THEN
                RETURN json_build_object(
                    'success', false,
                    'data', NULL,
                    'error', json_build_object(
                        'code', 'ENTIDAD_BANCARIA_INVALIDA',
                        'message', 'La entidad bancaria seleccionada (' || v_codigo_banco || ') no existe o está inactiva.',
                        'details', 'codigo_banco: ' || v_codigo_banco
                    )
                );
            END IF;

            IF v_referencia IS NOT NULL THEN
                IF EXISTS (
                    SELECT 1
                    FROM public.detalle_rendicion_fpagos dfp
                    WHERE dfp.codigo_banco = v_codigo_banco
                      AND dfp.referencia_bancaria = v_referencia
                ) THEN
                    RETURN json_build_object(
                        'success', false,
                        'data', NULL,
                        'error', json_build_object(
                            'code', 'REFERENCIA_DUPLICADA',
                            'message', 'La referencia bancaria ' || v_referencia || ' del banco ' || v_codigo_banco || ' (' || v_nombre_banco || ') ya fue registrada previamente en otra cobranza.',
                            'details', 'codigo_banco: ' || v_codigo_banco || ', referencia_bancaria: ' || v_referencia
                        )
                    );
                END IF;
            END IF;
        END IF;

        -- Verificar si es uso de Saldo a Favor
        IF v_fpago_concepto ILIKE '%saldo%favor%' THEN
            v_saldo_favor_usado := v_saldo_favor_usado + v_item_usd;
        ELSIF v_fpago_info = FALSE THEN
            v_total_efectivo := v_total_efectivo + v_item_usd;
        ELSE
            v_total_transferencias := v_total_transferencias + v_item_usd;
        END IF;
    END LOOP;

    -- Validar si el saldo a favor usado excede el disponible del cliente
    IF v_saldo_favor_usado > v_cliente_saldo_favor THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'SALDO_FAVOR_INSUFICIENTE',
                'message', 'El saldo a favor utilizado (' || v_saldo_favor_usado || ') supera el saldo a favor disponible del cliente (' || v_cliente_saldo_favor || ').',
                'details', NULL
            )
        );
    END IF;

    -- 4. Crear el registro principal (Cabecera) en rendiciones_cuentas con estado = 'aprobada'
    --    fecha_rendicion guarda la fecha del pago/abono; fecha_registro guarda el momento exacto del registro.
    INSERT INTO public.rendiciones_cuentas (
        cliente_id,
        fecha_rendicion,
        fecha_registro,
        tasa_cambio,
        total_efectivo_recaudado,
        total_transferencias_recaudado,
        total_recaudado_bs,
        total_recaudado_usd,
        total_devoluciones_valoradas,
        estado,
        observaciones,
        auditado_por
    ) VALUES (
        p_cliente_id,
        v_fecha_pago_ts,
        v_fecha_registro,
        v_tasa_cambio,
        v_total_efectivo,
        v_total_transferencias,
        v_total_pagos_bs,
        v_total_pagos,
        0.00,
        'aprobada',
        p_observaciones,
        NULL
    ) RETURNING id INTO v_rendicion_id;

    -- Asegurar que en logs_auditoria quede registrado el usuario creador y la fecha/hora exacta del momento
    UPDATE public.logs_auditoria
    SET usuario_id = COALESCE(usuario_id, p_creado_por),
        fecha_registro = v_fecha_registro
    WHERE tabla_afectada = 'rendiciones_cuentas'
      AND registro_id = v_rendicion_id
      AND accion = 'INSERT';

    -- 5. Registrar detalle de órdenes asociadas y actualizar estado de las órdenes
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_ordenes) AS x(orden_id UUID, monto_recaudado NUMERIC(12,2), monto_recaudado_bs NUMERIC(12,2)) LOOP
        v_rec_usd := COALESCE(v_item.monto_recaudado, 0.00);
        v_rec_bs := COALESCE(v_item.monto_recaudado_bs, v_rec_usd * v_tasa_cambio);

        INSERT INTO public.detalle_rendicion_ordenes (
            rendicion_id,
            orden_distribucion_id,
            recaudado,
            recaudado_bs
        ) VALUES (
            v_rendicion_id,
            v_item.orden_id,
            v_rec_usd,
            v_rec_bs
        );

        -- Evaluar y liquidar financieramente la orden de distribución
        PERFORM public.liquidar_orden_distribucion(v_item.orden_id);
    END LOOP;

    -- 6. Registrar formas de pago (detalle_rendicion_fpagos)
    FOR v_pago IN SELECT * FROM jsonb_to_recordset(p_pagos) AS y(
        fpago_id UUID,
        monto NUMERIC(12,2),
        monto_bs NUMERIC(12,2),
        monto_usd NUMERIC(12,2),
        cuenta_bancaria_id UUID,
        codigo_banco VARCHAR(4),
        referencia_bancaria TEXT,
        cuenta_bancaria TEXT,
        capture_url TEXT
    ) LOOP
        IF v_pago.monto_bs IS NOT NULL AND v_pago.monto_bs > 0 THEN
            v_item_bs := v_pago.monto_bs;
            v_item_usd := COALESCE(v_pago.monto_usd, v_item_bs / v_tasa_cambio);
        ELSE
            v_item_usd := COALESCE(v_pago.monto_usd, v_pago.monto, 0.00);
            v_item_bs := COALESCE(v_pago.monto_bs, v_item_usd * v_tasa_cambio);
        END IF;

        v_codigo_banco := NULLIF(TRIM(COALESCE(v_pago.codigo_banco, '')), '');
        v_referencia := NULLIF(TRIM(COALESCE(v_pago.referencia_bancaria, '')), '');

        INSERT INTO public.detalle_rendicion_fpagos (
            rendicion_id,
            fpago_id,
            cuenta_bancaria_id,
            codigo_banco,
            monto,
            monto_bs,
            monto_usd,
            referencia_bancaria,
            cuenta_bancaria,
            capture_url
        ) VALUES (
            v_rendicion_id,
            v_pago.fpago_id,
            v_pago.cuenta_bancaria_id,
            v_codigo_banco,
            v_item_usd,
            v_item_bs,
            v_item_usd,
            v_referencia,
            v_pago.cuenta_bancaria,
            v_pago.capture_url
        );
    END LOOP;

    -- 7. Procesar uso de Saldo a Favor si aplica
    IF v_saldo_favor_usado > 0 THEN
        UPDATE public.clientes
        SET saldo_favor = saldo_favor - v_saldo_favor_usado
        WHERE id = p_cliente_id;

        INSERT INTO public.movimientos_saldo_favor (
            cliente_id,
            rendicion_id,
            orden_id,
            monto,
            tipo,
            observaciones,
            created_at
        ) VALUES (
            p_cliente_id,
            v_rendicion_id,
            NULL,
            -v_saldo_favor_usado,
            'cargo_pago_orden',
            'Uso de saldo a favor en rendición de cuentas ID: ' || v_rendicion_id,
            v_fecha_registro
        );
    END IF;

    -- 8. Manejo de Excedente de Pago (Crédito a Favor Generado)
    IF v_total_pagos > v_total_ordenes THEN
        v_exceso := v_total_pagos - v_total_ordenes;
        v_exceso_bs := v_exceso * v_tasa_cambio;

        INSERT INTO public.movimientos_saldo_favor (
            cliente_id,
            rendicion_id,
            orden_id,
            monto,
            tipo,
            observaciones,
            created_at
        ) VALUES (
            p_cliente_id,
            v_rendicion_id,
            NULL,
            v_exceso,
            'abono_recaudacion',
            'Excedente en formas de pago de rendición de cuentas ID: ' || v_rendicion_id,
            v_fecha_registro
        );

        UPDATE public.clientes
        SET saldo_favor = COALESCE(saldo_favor, 0.00) + v_exceso
        WHERE id = p_cliente_id;
    END IF;

    -- 9. Retorno Exitoso
    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'rendicion_id', v_rendicion_id,
            'fecha_rendicion', v_fecha_pago_ts,
            'fecha_registro', v_fecha_registro,
            'tasa_cambio', v_tasa_cambio,
            'total_ordenes', v_total_ordenes,
            'total_ordenes_bs', v_total_ordenes_bs,
            'total_pagos', v_total_pagos,
            'total_pagos_bs', v_total_pagos_bs,
            'saldo_favor_usado', v_saldo_favor_usado,
            'saldo_favor_generado', v_exceso,
            'saldo_favor_generado_bs', v_exceso_bs
        ),
        'error', NULL
    );

EXCEPTION
    WHEN unique_violation THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'REFERENCIA_DUPLICADA',
                'message', 'La referencia bancaria indicada ya se encuentra registrada para ese mismo banco.',
                'details', 'SQLSTATE: ' || SQLSTATE || ' - ' || SQLERRM
            )
        );
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

ALTER FUNCTION public.registrar_rendicion_cuentas(uuid, text, uuid, jsonb, jsonb, numeric, date) OWNER TO postgres;
GRANT ALL ON FUNCTION public.registrar_rendicion_cuentas(uuid, text, uuid, jsonb, jsonb, numeric, date) TO anon, authenticated, service_role;

-- ------------------------------------------------------------------------------
-- 4. Actualización de public.reporte_formas_pago_rendicion (expone fecha_registro)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reporte_formas_pago_rendicion(
    p_fecha_desde date DEFAULT NULL::date,
    p_fecha_hasta date DEFAULT NULL::date,
    p_solo_bancarios boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_fecha_desde DATE;
    v_fecha_hasta DATE;
    v_movimientos JSONB;
    v_total_registros INT := 0;
    v_monto_total_bs NUMERIC(14,2) := 0.00;
    v_monto_total_usd NUMERIC(14,2) := 0.00;
BEGIN
    v_fecha_desde := COALESCE(p_fecha_desde, date_trunc('month', CURRENT_DATE)::date);
    v_fecha_hasta := COALESCE(p_fecha_hasta, CURRENT_DATE);

    SELECT
        COUNT(*)::INT,
        COALESCE(SUM(dfp.monto_bs), 0.00),
        COALESCE(SUM(dfp.monto_usd), 0.00)
    INTO v_total_registros, v_monto_total_bs, v_monto_total_usd
    FROM public.detalle_rendicion_fpagos dfp
    JOIN public.rendiciones_cuentas rc ON dfp.rendicion_id = rc.id
    JOIN public.fpagos fp ON dfp.fpago_id = fp.fpago_id
    WHERE rc.fecha_rendicion::date >= v_fecha_desde
      AND rc.fecha_rendicion::date <= v_fecha_hasta
      AND rc.estado = 'aprobada'
      AND (p_solo_bancarios = FALSE OR fp.es_bancario = TRUE);

    SELECT jsonb_agg(
        jsonb_build_object(
            'rendicion_id', rc.id,
            'fecha_rendicion', rc.fecha_rendicion,
            'fecha_registro', rc.fecha_registro,
            'tasa_cambio', rc.tasa_cambio,
            'cliente_id', c.id,
            'cliente_nombre', c.razon_social,
            'cliente_rif', c.rif_nit,
            'fpago_id', fp.fpago_id,
            'fpago_concepto', fp.fpago_concepto,
            'es_bancario', fp.es_bancario,
            'codigo_banco', dfp.codigo_banco,
            'nombre_banco', COALESCE(eb.nombre_corto, eb.nombre_eb),
            'referencia_bancaria', dfp.referencia_bancaria,
            'cuenta_bancaria', COALESCE(cbe.cuenta_bancaria, dfp.cuenta_bancaria),
            'capture_url', dfp.capture_url,
            'monto_bs', COALESCE(dfp.monto_bs, (dfp.monto_usd * COALESCE(rc.tasa_cambio, 0))),
            'monto_usd', dfp.monto_usd
        ) ORDER BY rc.fecha_rendicion DESC, dfp.id DESC
    ) INTO v_movimientos
    FROM public.detalle_rendicion_fpagos dfp
    JOIN public.rendiciones_cuentas rc ON dfp.rendicion_id = rc.id
    JOIN public.fpagos fp ON dfp.fpago_id = fp.fpago_id
    JOIN public.clientes c ON rc.cliente_id = c.id
    LEFT JOIN public.entidades_bancarias eb ON dfp.codigo_banco = eb.codigo_eb
    LEFT JOIN public.cuentas_bancarias_empresa cbe ON dfp.cuenta_bancaria_id = cbe.id
    WHERE rc.fecha_rendicion::date >= v_fecha_desde
      AND rc.fecha_rendicion::date <= v_fecha_hasta
      AND rc.estado = 'aprobada'
      AND (p_solo_bancarios = FALSE OR fp.es_bancario = TRUE);

    RETURN jsonb_build_object(
        'success', true,
        'data', jsonb_build_object(
            'fecha_desde', v_fecha_desde,
            'fecha_hasta', v_fecha_hasta,
            'solo_bancarios', p_solo_bancarios,
            'total_registros', v_total_registros,
            'monto_total_bs', v_monto_total_bs,
            'monto_total_usd', v_monto_total_usd,
            'movimientos', COALESCE(v_movimientos, '[]'::jsonb)
        ),
        'error', NULL
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'SQL_ERROR',
                'message', SQLERRM,
                'details', 'SQLSTATE: ' || SQLSTATE
            )
        );
END;
$$;

ALTER FUNCTION public.reporte_formas_pago_rendicion(date, date, boolean) OWNER TO postgres;
GRANT ALL ON FUNCTION public.reporte_formas_pago_rendicion(date, date, boolean) TO anon, authenticated, service_role;
