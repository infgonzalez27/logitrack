-- Migration: Módulo de Rendición de Cuentas y Liquidación (Flujo Completo)

-- 1. Insertar la forma de pago 'Saldo a favor' en la tabla fpagos
INSERT INTO public.fpagos (fpago_id, fpago_concepto, fpago_info)
VALUES ('7eb1e02e-ad11-4446-ee6f-de99870b477b', 'Saldo a favor', false)
ON CONFLICT (fpago_concepto) DO UPDATE 
SET fpago_info = EXCLUDED.fpago_info;

-- 2. Función consulta solicita_abonos_orden_distribucion
CREATE OR REPLACE FUNCTION public.solicita_abonos_orden_distribucion(
    p_cliente_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_saldo_favor NUMERIC(12, 2) := 0.00;
    v_ordenes JSON;
BEGIN
    -- Validar parámetro
    IF p_cliente_id IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID de cliente es requerido.'
            )
        );
    END IF;

    -- Validar que el cliente exista y obtener saldo a favor
    SELECT COALESCE(saldo_favor, 0.00) INTO v_saldo_favor
    FROM public.clientes
    WHERE id = p_cliente_id;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'CLIENTE_INEXISTENTE',
                'message', 'El cliente especificado no existe.'
            )
        );
    END IF;

    -- Obtener ordenes por_liquidar con abonos acumulados
    SELECT json_agg(
        json_build_object(
            'orden_id', od.id,
            'correlativo', od.correlativo,
            'fecha_despacho', od.fecha_despacho,
            'monto_total_orden', COALESCE(od.subtotal_recaudar, od.subtotal, 0.00),
            'abonos_acumulados', COALESCE(abonos.total_recaudado, 0.00),
            'saldo_pendiente', COALESCE(od.subtotal_recaudar, od.subtotal, 0.00) - COALESCE(abonos.total_recaudado, 0.00)
        ) ORDER BY od.created_at ASC
    ) INTO v_ordenes
    FROM public.ordenes_distribucion od
    LEFT JOIN LATERAL (
        SELECT SUM(dro.recaudado) AS total_recaudado
        FROM public.detalle_rendicion_ordenes dro
        JOIN public.rendiciones_cuentas rc ON dro.rendicion_id = rc.id
        WHERE dro.orden_distribucion_id = od.id
          AND rc.estado = 'aprobada'
    ) abonos ON TRUE
    WHERE od.cliente_id = p_cliente_id
      AND od.estado = 'por_liquidar';

    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'cliente_id', p_cliente_id,
            'saldo_favor', v_saldo_favor,
            'ordenes', COALESCE(v_ordenes, '[]'::json)
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


-- 3. Función registrar_rendicion_cuentas (Soporta uso de Saldo a Favor)
CREATE OR REPLACE FUNCTION public.registrar_rendicion_cuentas(
    p_cliente_id UUID,
    p_observaciones TEXT,
    p_creado_por UUID,
    p_ordenes JSONB,  -- Array: [{"orden_id": "...", "monto_recaudado": 150.00}]
    p_pagos JSONB      -- Array: [{"fpago_id": "...", "monto": 200.00, "referencia_bancaria": "...", "cuenta_bancaria": "...", "capture_url": "..."}]
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
    v_saldo_favor_usado NUMERIC(12, 2) := 0.00;
    v_cliente_saldo_favor NUMERIC(12, 2) := 0.00;
    v_item RECORD;
    v_pago RECORD;
    v_exceso NUMERIC(12, 2) := 0.00;
    v_fpago_concepto TEXT;
    v_fpago_info BOOLEAN;
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
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_ordenes) AS x(orden_id UUID, monto_recaudado NUMERIC(12,2)) LOOP
        v_total_ordenes := v_total_ordenes + COALESCE(v_item.monto_recaudado, 0.00);
    END LOOP;

    -- 3. Validar y clasificar formas de pago
    FOR v_pago IN SELECT * FROM jsonb_to_recordset(p_pagos) AS y(fpago_id UUID, monto NUMERIC(12,2), referencia_bancaria TEXT, cuenta_bancaria TEXT, capture_url TEXT) LOOP
        v_total_pagos := v_total_pagos + COALESCE(v_pago.monto, 0.00);
        
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
            v_saldo_favor_usado := v_saldo_favor_usado + COALESCE(v_pago.monto, 0.00);
        ELSIF v_fpago_info = FALSE THEN
            v_total_efectivo := v_total_efectivo + COALESCE(v_pago.monto, 0.00);
        ELSE
            v_total_transferencias := v_total_transferencias + COALESCE(v_pago.monto, 0.00);
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
        0.00,
        'revision',
        p_observaciones,
        NULL
    ) RETURNING id INTO v_rendicion_id;

    -- 5. Registrar detalle de órdenes asociadas
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

    -- 6. Registrar formas de pago (detalle_rendicion_fpagos)
    FOR v_pago IN SELECT * FROM jsonb_to_recordset(p_pagos) AS y(fpago_id UUID, monto NUMERIC(12,2), referencia_bancaria TEXT, cuenta_bancaria TEXT, capture_url TEXT) LOOP
        INSERT INTO public.detalle_rendicion_fpagos (
            rendicion_id,
            fpago_id,
            monto,
            referencia_bancaria,
            cuenta_bancaria,
            capture_url
        ) VALUES (
            v_rendicion_id,
            v_pago.fpago_id,
            v_pago.monto,
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
            'total_ordenes', v_total_ordenes,
            'total_pagos', v_total_pagos,
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


-- 4. Función liquidar_orden_distribucion con evaluación de cobro 100%
CREATE OR REPLACE FUNCTION public.liquidar_orden_distribucion(
    p_orden_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_estado_orden TEXT;
    v_cliente_id UUID;
    v_camion_id UUID;
    v_subtotal_recaudar NUMERIC(12, 2) := 0.00;
    v_total_abonos_aprobados NUMERIC(12, 2) := 0.00;
BEGIN
    -- Validar parámetro
    IF p_orden_id IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID de la orden es requerido.'
            )
        );
    END IF;

    -- Obtener orden
    SELECT estado, cliente_id, camion_id, COALESCE(subtotal_recaudar, subtotal, 0.00)
    INTO v_estado_orden, v_cliente_id, v_camion_id, v_subtotal_recaudar
    FROM public.ordenes_distribucion
    WHERE id = p_orden_id;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'ORDEN_INEXISTENTE',
                'message', 'La orden de distribución especificada no existe.'
            )
        );
    END IF;

    IF v_estado_orden != 'por_liquidar' THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo se pueden evaluar o liquidar financieramente órdenes en estado por_liquidar.'
            )
        );
    END IF;

    -- Calcular la suma de todos los abonos aprobados para esta orden
    SELECT COALESCE(SUM(dro.recaudado), 0.00)
    INTO v_total_abonos_aprobados
    FROM public.detalle_rendicion_ordenes dro
    JOIN public.rendiciones_cuentas rc ON dro.rendicion_id = rc.id
    WHERE dro.orden_distribucion_id = p_orden_id
      AND rc.estado = 'aprobada';

    -- Si la suma de abonos alcanza o supera el subtotal a recaudar
    IF v_total_abonos_aprobados >= v_subtotal_recaudar THEN
        -- Liberar camión si aplica
        IF v_camion_id IS NOT NULL THEN
            UPDATE public.camiones SET estado = 'disponible' WHERE id = v_camion_id;
        END IF;

        -- Transicionar orden a 'liquidada'
        UPDATE public.ordenes_distribucion 
        SET estado = 'liquidada' 
        WHERE id = p_orden_id;

        RETURN json_build_object(
            'success', true,
            'data', json_build_object(
                'orden_id', p_orden_id,
                'nuevo_estado', 'liquidada',
                'total_recaudado', v_total_abonos_aprobados,
                'subtotal_recaudar', v_subtotal_recaudar
            ),
            'error', NULL
        );
    ELSE
        -- Se mantiene en 'por_liquidar' ya que la recaudación acumulada es parcial
        RETURN json_build_object(
            'success', true,
            'data', json_build_object(
                'orden_id', p_orden_id,
                'nuevo_estado', 'por_liquidar',
                'total_recaudado', v_total_abonos_aprobados,
                'subtotal_recaudar', v_subtotal_recaudar,
                'saldo_pendiente', (v_subtotal_recaudar - v_total_abonos_aprobados)
            ),
            'error', NULL
        );
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'SQL_ERROR',
                'message', SQLERRM,
                'details', 'SQLSTATE: ' || SQLSTATE
            )
        );
END;
$$;


-- 5. Función reporte_recaudaciones_gerenciales
CREATE OR REPLACE FUNCTION public.reporte_recaudaciones_gerenciales(
    p_fecha_desde DATE DEFAULT NULL,
    p_fecha_hasta DATE DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_data JSON;
    v_desde TIMESTAMP WITH TIME ZONE;
    v_hasta TIMESTAMP WITH TIME ZONE;
BEGIN
    -- Configurar fechas por defecto si no son pasadas (mes actual)
    v_desde := COALESCE(p_fecha_desde::TIMESTAMP WITH TIME ZONE, date_trunc('month', CURRENT_DATE));
    v_hasta := COALESCE((p_fecha_hasta + INTERVAL '1 day - 1 microsecond')::TIMESTAMP WITH TIME ZONE, CURRENT_TIMESTAMP);

    SELECT json_agg(
        json_build_object(
            'rendicion_id', rc.id,
            'fecha_rendicion', rc.fecha_rendicion,
            'cliente_id', rc.cliente_id,
            'cliente_nombre', c.razon_social,
            'cliente_rif', c.rif_nit,
            'estado', rc.estado,
            'total_efectivo_recaudado', rc.total_efectivo_recaudado,
            'total_transferencias_recaudado', rc.total_transferencias_recaudado,
            'observaciones', rc.observaciones,
            'detalle_fpagos', COALESCE(fpagos_agg.fpagos, '[]'::json),
            'detalle_ordenes', COALESCE(ordenes_agg.ordenes, '[]'::json)
        ) ORDER BY rc.fecha_rendicion DESC
    ) INTO v_data
    FROM public.rendiciones_cuentas rc
    JOIN public.clientes c ON rc.cliente_id = c.id
    LEFT JOIN LATERAL (
        SELECT json_agg(
            json_build_object(
                'fpago_id', dfp.fpago_id,
                'concepto', fp.fpago_concepto,
                'monto', dfp.monto,
                'referencia_bancaria', dfp.referencia_bancaria,
                'cuenta_bancaria', dfp.cuenta_bancaria,
                'capture_url', dfp.capture_url
            )
        ) AS fpagos
        FROM public.detalle_rendicion_fpagos dfp
        LEFT JOIN public.fpagos fp ON dfp.fpago_id = fp.fpago_id
        WHERE dfp.rendicion_id = rc.id
    ) fpagos_agg ON TRUE
    LEFT JOIN LATERAL (
        SELECT json_agg(
            json_build_object(
                'orden_id', dro.orden_distribucion_id,
                'correlativo', od.correlativo,
                'recaudado', dro.recaudado
            )
        ) AS ordenes
        FROM public.detalle_rendicion_ordenes dro
        LEFT JOIN public.ordenes_distribucion od ON dro.orden_distribucion_id = od.id
        WHERE dro.rendicion_id = rc.id
    ) ordenes_agg ON TRUE
    WHERE rc.fecha_rendicion >= v_desde
      AND rc.fecha_rendicion <= v_hasta;

    RETURN json_build_object(
        'success', true,
        'data', COALESCE(v_data, '[]'::json),
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
