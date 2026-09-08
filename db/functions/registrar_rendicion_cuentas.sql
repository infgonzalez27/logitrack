CREATE OR REPLACE FUNCTION public.registrar_rendicion_cuentas(
    p_cliente_id UUID,
    p_observaciones TEXT,
    p_creado_por UUID,
    p_ordenes JSONB,  -- Array: [{"orden_id": "...", "monto_recaudado": 150.00, "monto_recaudado_bs": 7500.00}]
    p_pagos JSONB,     -- Array: [{"fpago_id": "...", "monto": 200.00, "monto_bs": 10000.00, "monto_usd": 200.00, "cuenta_bancaria_id": "...", "referencia_bancaria": "...", "cuenta_bancaria": "...", "capture_url": "..."}]
    p_tasa_cambio NUMERIC DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_rendicion_id UUID;
    v_tasa_cambio NUMERIC(10, 4);
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

    -- Determinar tasa de cambio
    IF p_tasa_cambio IS NOT NULL AND p_tasa_cambio > 0 THEN
        v_tasa_cambio := p_tasa_cambio;
    ELSE
        SELECT COALESCE(tasa_cambio, 1.0000) INTO v_tasa_cambio
        FROM public.tasa_cambio
        ORDER BY fecha_tasa DESC, created_at DESC
        LIMIT 1;

        IF v_tasa_cambio IS NULL THEN
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

    -- 3. Validar y clasificar formas de pago (USD y Bs)
    FOR v_pago IN SELECT * FROM jsonb_to_recordset(p_pagos) AS y(fpago_id UUID, monto NUMERIC(12,2), monto_bs NUMERIC(12,2), monto_usd NUMERIC(12,2), cuenta_bancaria_id UUID, referencia_bancaria TEXT, cuenta_bancaria TEXT, capture_url TEXT) LOOP
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

    -- 4. Crear el registro principal (Cabecera) en rendiciones_cuentas
    INSERT INTO public.rendiciones_cuentas (
        cliente_id,
        fecha_rendicion,
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
        NOW(),
        v_tasa_cambio,
        v_total_efectivo,
        v_total_transferencias,
        v_total_pagos_bs,
        v_total_pagos,
        0.00,
        'revision',
        p_observaciones,
        NULL
    ) RETURNING id INTO v_rendicion_id;

    -- 5. Registrar detalle de órdenes asociadas
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
    END LOOP;

    -- 6. Registrar formas de pago (detalle_rendicion_fpagos)
    FOR v_pago IN SELECT * FROM jsonb_to_recordset(p_pagos) AS y(fpago_id UUID, monto NUMERIC(12,2), monto_bs NUMERIC(12,2), monto_usd NUMERIC(12,2), cuenta_bancaria_id UUID, referencia_bancaria TEXT, cuenta_bancaria TEXT, capture_url TEXT) LOOP
        IF v_pago.monto_bs IS NOT NULL AND v_pago.monto_bs > 0 THEN
            v_item_bs := v_pago.monto_bs;
            v_item_usd := COALESCE(v_pago.monto_usd, v_item_bs / v_tasa_cambio);
        ELSE
            v_item_usd := COALESCE(v_pago.monto_usd, v_pago.monto, 0.00);
            v_item_bs := COALESCE(v_pago.monto_bs, v_item_usd * v_tasa_cambio);
        END IF;

        INSERT INTO public.detalle_rendicion_fpagos (
            rendicion_id,
            fpago_id,
            cuenta_bancaria_id,
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
            v_item_usd,
            v_item_bs,
            v_item_usd,
            v_pago.referencia_bancaria,
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
            NOW()
        );
    END IF;

    -- 8. Manejo de Excedente de Pago (Crédito a Favor Generado)
    IF v_total_pagos > v_total_ordenes THEN
        v_exceso := v_total_pagos - v_total_ordenes;
        v_exceso_bs := v_total_pagos_bs - v_total_ordenes_bs;

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

        UPDATE public.clientes
        SET saldo_favor = COALESCE(saldo_favor, 0.00) + v_exceso
        WHERE id = p_cliente_id;
    END IF;

    -- 9. Retorno Exitoso
    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'rendicion_id', v_rendicion_id,
            'tasa_cambio', v_tasa_cambio,
            'total_ordenes', v_total_ordenes,
            'total_ordenes_bs', v_total_ordenes_bs,
            'total_pagos', v_total_pagos,
            'total_pagos_bs', v_total_pagos_bs,
            'saldo_favor_usado', v_saldo_favor_usado,
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
