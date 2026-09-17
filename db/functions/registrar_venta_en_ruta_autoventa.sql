CREATE OR REPLACE FUNCTION public.registrar_venta_en_ruta_autoventa(
    p_vendedor_id UUID,
    p_cliente_id UUID,
    p_camion_id UUID,
    p_productos_json JSONB DEFAULT '[]'::jsonb,
    p_contenedores_json JSONB DEFAULT '[]'::jsonb,
    p_observaciones TEXT DEFAULT NULL,
    p_tasa_cambio NUMERIC DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_orden_id UUID;
    v_correlativo INT;
    v_factura_origen VARCHAR(30);
    v_tasa_cambio NUMERIC(14,4);
    
    v_vendedor_id UUID;
    v_despachador_id UUID;
    v_id_ruta UUID;
    v_camion_estado TEXT;
    
    v_peso_total NUMERIC(10,2) := 0.00;
    v_total_recaudar_usd NUMERIC(14,2) := 0.00;
    v_total_recaudar_bs NUMERIC(14,2) := 0.00;
    
    v_item JSONB;
    v_secuencia INT := 1;
    v_producto_id UUID;
    v_cantidad INT;
    v_stock_disponible_movil INT := 0;
    v_val_usd NUMERIC(14,2);
    v_val_usd_prod NUMERIC(14,2);
    v_subtotal_usd NUMERIC(14,2);
    v_peso_unitario NUMERIC(10,2);
    
    v_cont_item JSONB;
    v_cont_id UUID;
    v_cant_entregada INT;
    v_cant_retirada INT;
BEGIN
    -- Validaciones de parámetros
    IF p_vendedor_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del vendedor es requerido.');
    END IF;

    IF p_cliente_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del cliente es requerido.');
    END IF;

    IF p_camion_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del camión es requerido.');
    END IF;

    IF p_productos_json IS NULL OR jsonb_array_length(p_productos_json) = 0 THEN
        RETURN jsonb_build_object('success', false, 'message', 'Debe incluir al menos un producto en la orden de AutoVenta.');
    END IF;

    -- Validar existencia del camión y estado ('en_ruta' o 'asignado')
    SELECT estado INTO v_camion_estado
    FROM public.camiones
    WHERE id = p_camion_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'message', 'El camión especificado no existe.');
    END IF;

    IF v_camion_estado NOT IN ('en_ruta', 'asignado') THEN
        RETURN jsonb_build_object('success', false, 'message', 'El camión debe estar en ruta para registrar AutoVentas. Estado actual: ' || v_camion_estado);
    END IF;

    -- Obtener datos del cliente (vendedor, despachador, ruta)
    SELECT c.vendedor_id, c.despachador_id, c.id_ruta
    INTO v_vendedor_id, v_despachador_id, v_id_ruta
    FROM public.clientes c
    WHERE c.id = p_cliente_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'message', 'El cliente especificado no existe.');
    END IF;

    v_vendedor_id := COALESCE(p_vendedor_id, v_vendedor_id);

    -- Determinar tasa de cambio
    IF p_tasa_cambio IS NOT NULL AND p_tasa_cambio > 0 THEN
        v_tasa_cambio := p_tasa_cambio;
    ELSE
        SELECT tasa_cambio INTO v_tasa_cambio
        FROM public.tasa_cambio
        WHERE fecha_tasa = CURRENT_DATE;

        IF v_tasa_cambio IS NULL THEN
            SELECT tasa_cambio INTO v_tasa_cambio
            FROM public.tasa_cambio
            ORDER BY fecha_tasa DESC, created_at DESC
            LIMIT 1;
        END IF;

        IF v_tasa_cambio IS NULL THEN
            v_tasa_cambio := 1.0000;
        END IF;
    END IF;

    -- 1. Validar disponibilidad de stock en inventario_movil para cada producto
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;

        IF v_cantidad IS NULL OR v_cantidad <= 0 THEN
            RETURN jsonb_build_object('success', false, 'message', 'La cantidad solicitada para cada producto debe ser mayor a cero.');
        END IF;

        -- Consultar disponibilidad real en inventario_movil (cargado - entregado)
        SELECT (COALESCE(cantidad_cargada, 0) - COALESCE(cantidad_entregada, 0))
        INTO v_stock_disponible_movil
        FROM public.inventario_movil
        WHERE camion_id = p_camion_id AND producto_id = v_producto_id;

        IF v_stock_disponible_movil IS NULL THEN
            v_stock_disponible_movil := 0;
        END IF;

        IF v_stock_disponible_movil < v_cantidad THEN
            RETURN jsonb_build_object(
                'success', false,
                'message', 'Stock insuficiente en el camión para el producto seleccionado. Disponible: ' || v_stock_disponible_movil || ', Solicitado: ' || v_cantidad
            );
        END IF;
    END LOOP;

    -- 2. Generar correlativo e ID de orden
    v_correlativo := nextval('public.ordenes_distribucion_correlativo_seq');
    v_factura_origen := 'AV-' || LPAD(v_correlativo::text, 6, '0');
    v_orden_id := gen_random_uuid();

    -- 3. Calcular montos y pesos
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;

        SELECT COALESCE(precio_lista1, 0.00), COALESCE(peso_unitario_kg, 0.00) 
        INTO v_val_usd_prod, v_peso_unitario
        FROM public.productos
        WHERE id = v_producto_id;

        v_val_usd := COALESCE((v_item->>'valor_unitario_usd')::NUMERIC, (v_item->>'precio_unitario')::NUMERIC, v_val_usd_prod);
        IF v_val_usd <= 0 THEN
            v_val_usd := v_val_usd_prod;
        END IF;

        v_subtotal_usd := ROUND(v_cantidad * v_val_usd, 2);
        v_peso_total := v_peso_total + (COALESCE(v_peso_unitario, 0.00) * v_cantidad);
        v_total_recaudar_usd := v_total_recaudar_usd + v_subtotal_usd;
    END LOOP;

    v_total_recaudar_bs := ROUND(v_total_recaudar_usd * v_tasa_cambio, 2);

    -- 4. Insertar la orden en ordenes_distribucion (estado = 'por_liquidar', es_autoventa = TRUE, radar_id = NULL)
    INSERT INTO public.ordenes_distribucion (
        id,
        correlativo,
        cliente_id,
        camion_id,
        vendedor_id,
        despachador_id,
        id_ruta,
        estado,
        es_autoventa,
        radar_id,
        fecha_despacho,
        peso_total_calculado,
        factura_origen_numero,
        creado_por,
        created_at,
        tasa_cambio,
        total_recaudar_usd,
        total_recaudar_bs
    ) VALUES (
        v_orden_id,
        v_correlativo,
        p_cliente_id,
        p_camion_id,
        v_vendedor_id,
        v_despachador_id,
        v_id_ruta,
        'por_liquidar',
        TRUE,
        NULL,
        NOW(),
        v_peso_total,
        v_factura_origen,
        p_vendedor_id,
        NOW(),
        v_tasa_cambio,
        v_total_recaudar_usd,
        v_total_recaudar_bs
    );

    -- 5. Insertar detalles y actualizar inventario_movil (cantidad_entregada += v_cantidad)
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;

        SELECT COALESCE(precio_lista1, 0.00) INTO v_val_usd_prod FROM public.productos WHERE id = v_producto_id;
        v_val_usd := COALESCE((v_item->>'valor_unitario_usd')::NUMERIC, (v_item->>'precio_unitario')::NUMERIC, v_val_usd_prod);
        IF v_val_usd <= 0 THEN v_val_usd := v_val_usd_prod; END IF;
        v_subtotal_usd := ROUND(v_cantidad * v_val_usd, 2);

        INSERT INTO public.detalle_distribucion (
            id,
            orden_id,
            producto_id,
            cantidad_solicitada,
            cantidad_despachada,
            valor_unitario_usd,
            valor_total_usd,
            secuencia_orden,
            created_at
        ) VALUES (
            gen_random_uuid(),
            v_orden_id,
            v_producto_id,
            v_cantidad,
            v_cantidad,
            v_val_usd,
            v_subtotal_usd,
            v_secuencia,
            NOW()
        );

        v_secuencia := v_secuencia + 1;

        -- Incrementar cantidad_entregada en el inventario móvil del camión
        UPDATE public.inventario_movil
        SET cantidad_entregada = cantidad_entregada + v_cantidad,
            updated_at = NOW()
        WHERE camion_id = p_camion_id AND producto_id = v_producto_id;
    END LOOP;

    -- 6. Procesar movimiento de envases / contenedores si fueron suministrados
    IF p_contenedores_json IS NOT NULL AND jsonb_array_length(p_contenedores_json) > 0 THEN
        FOR v_cont_item IN SELECT * FROM jsonb_array_elements(p_contenedores_json) LOOP
            v_cont_id := (v_cont_item->>'contenedor_id')::UUID;
            v_cant_entregada := COALESCE((v_cont_item->>'cantidad_entregada')::INT, 0);
            v_cant_retirada := COALESCE((v_cont_item->>'cantidad_retirada')::INT, 0);

            IF v_cont_id IS NOT NULL AND (v_cant_entregada > 0 OR v_cant_retirada > 0) THEN
                -- Registro histórico del movimiento
                INSERT INTO public.movimientos_contenedores (
                    cliente_id,
                    orden_id,
                    contenedor_id,
                    cantidad_entregada,
                    cantidad_retirada,
                    created_at
                ) VALUES (
                    p_cliente_id,
                    v_orden_id,
                    v_cont_id,
                    v_cant_entregada,
                    v_cant_retirada,
                    NOW()
                );

                -- Actualización del saldo acumulado del cliente
                INSERT INTO public.saldo_contenedores_clientes (
                    cliente_id,
                    contenedor_id,
                    saldo_pendiente,
                    updated_at
                ) VALUES (
                    p_cliente_id,
                    v_cont_id,
                    GREATEST(0, v_cant_entregada - v_cant_retirada),
                    NOW()
                )
                ON CONFLICT (cliente_id, contenedor_id)
                DO UPDATE SET
                    saldo_pendiente = GREATEST(0, public.saldo_contenedores_clientes.saldo_pendiente + v_cant_entregada - v_cant_retirada),
                    updated_at = NOW();
            END IF;
        END LOOP;
    END IF;

    -- 7. Respuesta exitosa
    RETURN jsonb_build_object(
        'success', true,
        'message', 'Venta en ruta (AutoVenta) registrada exitosamente.',
        'data', jsonb_build_object(
            'orden_id', v_orden_id,
            'correlativo', v_correlativo,
            'factura_origen_numero', v_factura_origen,
            'cliente_id', p_cliente_id,
            'camion_id', p_camion_id,
            'estado', 'por_liquidar',
            'es_autoventa', true,
            'total_recaudar_usd', v_total_recaudar_usd,
            'total_recaudar_bs', v_total_recaudar_bs,
            'tasa_cambio', v_tasa_cambio
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
