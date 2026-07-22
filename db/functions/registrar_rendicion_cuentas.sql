CREATE OR REPLACE FUNCTION public.registrar_rendicion_cuentas(
    p_cliente_id UUID,
    p_observaciones TEXT,
    p_creado_por UUID,
    p_ordenes JSONB,  -- Array de objetos: [{"orden_id": "...", "monto_recaudado": 150.00}]
    p_pagos JSONB      -- Array de objetos: [{"metodo_pago": "efectivo_usd", "monto": 200.00, "referencia_bancaria": "...", "cuenta_bancaria": "...", "capture_url": "..."}]
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_rendicion_id UUID;
    v_total_ordenes NUMERIC(12, 2) := 0.00;
    v_total_pagos NUMERIC(12, 2) := 0.00;
    v_total_efectivo NUMERIC(12, 2) := 0.00;
    v_total_transferencias NUMERIC(12, 2) := 0.00;
    v_item RECORD;
    v_pago RECORD;
    v_exceso NUMERIC(12, 2) := 0.00;
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

    -- Validar que el cliente exista
    IF NOT EXISTS (SELECT 1 FROM public.clientes WHERE id = p_cliente_id) THEN
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

    -- 2. Calcular totales
    -- Calcular total recaudado de las órdenes
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_ordenes) AS x(orden_id UUID, monto_recaudado NUMERIC(12,2)) LOOP
        v_total_ordenes := v_total_ordenes + v_item.monto_recaudado;
    END LOOP;

    -- Calcular total y clasificar según formas de pago
    FOR v_pago IN SELECT * FROM jsonb_to_recordset(p_pagos) AS y(metodo_pago TEXT, monto NUMERIC(12,2), referencia_bancaria TEXT, cuenta_bancaria TEXT, capture_url TEXT) LOOP
        v_total_pagos := v_total_pagos + v_pago.monto;
        IF v_pago.metodo_pago IN ('efectivo_usd', 'efectivo_bs') THEN
            v_total_efectivo := v_total_efectivo + v_pago.monto;
        ELSIF v_pago.metodo_pago IN ('transferencia', 'pago_movil') THEN
            v_total_transferencias := v_total_transferencias + v_pago.monto;
        END IF;
    END LOOP;

    -- 3. Crear el registro principal (Cabecera) en rendiciones_cuentas
    INSERT INTO public.rendiciones_cuentas (
        cliente_id,
        fecha_rendicion,
        total_efectivo_recaudado,
        total_transferencias_recaudado,
        total_devoluciones_valoradas,
        estado,
        observaciones,
        auditado_por
    ) VALUES (
        p_cliente_id,
        NOW(),
        v_total_efectivo,
        v_total_transferencias,
        0.00, -- Inicialmente 0, se puede valorizar al auditar
        'revision', -- Estado inicial
        p_observaciones,
        NULL -- Aún no auditado
    ) RETURNING id INTO v_rendicion_id;

    -- 4. Registrar detalle de órdenes asociadas (detalle_rendicion_ordenes)
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_ordenes) AS x(orden_id UUID, monto_recaudado NUMERIC(12,2)) LOOP
        INSERT INTO public.detalle_rendicion_ordenes (
            rendicion_id,
            orden_distribucion_id,
            recaudado
        ) VALUES (
            v_rendicion_id,
            v_item.orden_id,
            v_item.monto_recaudado
        );
    END LOOP;

    -- 5. Registrar formas de pago (detalle_rendicion_fpagos)
    FOR v_pago IN SELECT * FROM jsonb_to_recordset(p_pagos) AS y(metodo_pago TEXT, monto NUMERIC(12,2), referencia_bancaria TEXT, cuenta_bancaria TEXT, capture_url TEXT) LOOP
        INSERT INTO public.detalle_rendicion_fpagos (
            rendicion_id,
            metodo_pago,
            monto,
            referencia_bancaria,
            cuenta_bancaria,
            capture_url
        ) VALUES (
            v_rendicion_id,
            v_pago.metodo_pago,
            v_pago.monto,
            v_pago.referencia_bancaria,
            v_pago.cuenta_bancaria,
            v_pago.capture_url
        );
    END LOOP;

    -- 6. Manejo de Crédito a Favor del Cliente
    IF v_total_pagos > v_total_ordenes THEN
        v_exceso := v_total_pagos - v_total_ordenes;

        -- Registrar abono histórico
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
            NOW()
        );

        -- Actualizar saldo deudor/acreedor en la tabla clientes
        UPDATE public.clientes
        SET saldo_favor = COALESCE(saldo_favor, 0.00) + v_exceso
        WHERE id = p_cliente_id;
    END IF;

    -- 7. Retorno Exitoso
    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'rendicion_id', v_rendicion_id,
            'total_ordenes', v_total_ordenes,
            'total_pagos', v_total_pagos,
            'saldo_favor_generado', v_exceso
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
