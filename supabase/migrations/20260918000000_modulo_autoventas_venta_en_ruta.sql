-- Migración: Módulo de AutoVentas (Venta en Ruta / Almacén Móvil sin Radar)

-- 1. Modificación de esquema: Agregar columna es_autoventa a public.ordenes_distribucion
ALTER TABLE public.ordenes_distribucion 
ADD COLUMN IF NOT EXISTS es_autoventa BOOLEAN DEFAULT FALSE;

COMMENT ON COLUMN public.ordenes_distribucion.es_autoventa IS 'Indica si la orden fue generada como venta en caliente en ruta de AutoVentas (sin radar).';

-- 2. Stored Procedure: registrar_venta_en_ruta_autoventa
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


-- 3. Stored Procedure: retorna_resumen_autoventas_jornada
CREATE OR REPLACE FUNCTION public.retorna_resumen_autoventas_jornada(
    p_camion_id UUID,
    p_fecha DATE DEFAULT CURRENT_DATE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_inventario_movil JSONB;
    v_ventas_jornada JSONB;
    v_total_ordenes INT := 0;
    v_total_facturado_usd NUMERIC(14,2) := 0.00;
    v_total_facturado_bs NUMERIC(14,2) := 0.00;
BEGIN
    IF p_camion_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del camión es requerido.');
    END IF;

    -- Consultar estado del inventario móvil cargado vs entregado
    SELECT jsonb_agg(
        jsonb_build_object(
            'producto_id', p.id,
            'codigo', p.codigo,
            'nombre', p.nombre,
            'cantidad_cargada', COALESCE(im.cantidad_cargada, 0),
            'cantidad_entregada', COALESCE(im.cantidad_entregada, 0),
            'cantidad_disponible', GREATEST(0, COALESCE(im.cantidad_cargada, 0) - COALESCE(im.cantidad_entregada, 0))
        ) ORDER BY p.nombre ASC
    ) INTO v_inventario_movil
    FROM public.inventario_movil im
    JOIN public.productos p ON im.producto_id = p.id
    WHERE im.camion_id = p_camion_id;

    -- Consultar resumen de ventas registradas hoy en AutoVentas
    SELECT 
        COUNT(*)::INT,
        COALESCE(SUM(total_recaudar_usd), 0.00),
        COALESCE(SUM(total_recaudar_bs), 0.00)
    INTO v_total_ordenes, v_total_facturado_usd, v_total_facturado_bs
    FROM public.ordenes_distribucion
    WHERE camion_id = p_camion_id
      AND es_autoventa = TRUE
      AND DATE(created_at) = COALESCE(p_fecha, CURRENT_DATE);

    SELECT jsonb_agg(
        jsonb_build_object(
            'orden_id', od.id,
            'correlativo', od.correlativo,
            'factura_origen_numero', od.factura_origen_numero,
            'cliente_nombre', c.nombre_negocio,
            'estado', od.estado,
            'total_recaudar_usd', od.total_recaudar_usd,
            'total_recaudar_bs', od.total_recaudar_bs,
            'created_at', od.created_at
        ) ORDER BY od.created_at DESC
    ) INTO v_ventas_jornada
    FROM public.ordenes_distribucion od
    JOIN public.clientes c ON od.cliente_id = c.id
    WHERE od.camion_id = p_camion_id
      AND od.es_autoventa = TRUE
      AND DATE(od.created_at) = COALESCE(p_fecha, CURRENT_DATE);

    RETURN jsonb_build_object(
        'success', true,
        'data', jsonb_build_object(
            'camion_id', p_camion_id,
            'fecha', COALESCE(p_fecha, CURRENT_DATE),
            'total_ordenes_autoventa', v_total_ordenes,
            'total_facturado_usd', v_total_facturado_usd,
            'total_facturado_bs', v_total_facturado_bs,
            'inventario_movil', COALESCE(v_inventario_movil, '[]'::jsonb),
            'ventas', COALESCE(v_ventas_jornada, '[]'::jsonb)
        ),
        'error', NULL
    );
END;
$$;


-- 4. Protección y Filtrado: Actualizar crear_o_obtener_radar para IGNORAR ordenes de AutoVentas
CREATE OR REPLACE FUNCTION public.crear_o_obtener_radar(
    p_despachador_id UUID DEFAULT NULL,
    p_fecha_despacho DATE DEFAULT CURRENT_DATE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_despachador_id UUID;
    v_radar_id UUID;
    v_correlativo INT;
    v_status_radar BOOLEAN;
    v_tot_solicitada NUMERIC(10,0);
    v_tot_despachada NUMERIC(10,0);
    v_tot_retirados NUMERIC(10,0);
    v_total_ordenes INT;
    v_resultado JSONB;
BEGIN
    v_despachador_id := COALESCE(p_despachador_id, auth.uid());

    IF v_despachador_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_REQUERIDO',
                'message', 'Se requiere especificar un despachador_id o estar autenticado.'
            )
        );
    END IF;

    -- Verificar si existe un radar para este despachador y fecha
    SELECT id, correlativo, status_radar
    INTO v_radar_id, v_correlativo, v_status_radar
    FROM public.radars
    WHERE despachador_id = v_despachador_id
      AND fecha_despacho = p_fecha_despacho
    ORDER BY created_at DESC
    LIMIT 1;

    -- Si no existe, crearlo
    IF v_radar_id IS NULL THEN
        INSERT INTO public.radars (despachador_id, fecha_despacho, status_radar)
        VALUES (v_despachador_id, p_fecha_despacho, FALSE)
        RETURNING id, correlativo, status_radar INTO v_radar_id, v_correlativo, v_status_radar;
    END IF;

    -- EXCLUIR VENTA EN RUTA (es_autoventa = TRUE): No asociar órdenes de AutoVentas al Radar
    UPDATE public.ordenes_distribucion o
    SET radar_id = v_radar_id
    FROM public.clientes c
    WHERE o.cliente_id = c.id
      AND c.despachador_id = v_despachador_id
      AND o.fecha_despacho::date = p_fecha_despacho
      AND o.estado IN ('aprobada', 'en_transito', 'por_liquidar', 'liquidada', 'devuelta')
      AND (o.radar_id IS NULL OR o.radar_id = v_radar_id)
      AND COALESCE(o.es_autoventa, FALSE) = FALSE;

    -- Recalcular totales del radar
    SELECT 
        COALESCE(SUM(d.cantidad_solicitada), 0),
        COALESCE(SUM(d.cantidad_despachada), 0),
        COALESCE(SUM(d.contenedores_retirados), 0),
        COUNT(DISTINCT o.id)
    INTO v_tot_solicitada, v_tot_despachada, v_tot_retirados, v_total_ordenes
    FROM public.ordenes_distribucion o
    JOIN public.detalle_distribucion d ON d.orden_id = o.id
    WHERE o.radar_id = v_radar_id;

    UPDATE public.radars
    SET total_cantidad_solicitada = v_tot_solicitada,
        total_cantidad_despachada = v_tot_despachada,
        total_contenedores_retirados = v_tot_retirados
    WHERE id = v_radar_id;

    SELECT jsonb_build_object(
        'success', TRUE,
        'message', 'Radar obtenido/creado exitosamente.',
        'data', jsonb_build_object(
            'id', v_radar_id,
            'correlativo', v_correlativo,
            'despachador_id', v_despachador_id,
            'fecha_despacho', p_fecha_despacho,
            'status_radar', v_status_radar,
            'total_cantidad_solicitada', v_tot_solicitada,
            'total_cantidad_despachada', v_tot_despachada,
            'total_contenedores_retirados', v_tot_retirados,
            'total_ordenes', v_total_ordenes
        )
    ) INTO v_resultado;

    RETURN v_resultado;
END;
$$;


-- 5. Protección y Filtrado: Actualizar solicita_editar_o_sincronizar_radar para IGNORAR ordenes de AutoVentas
CREATE OR REPLACE FUNCTION public.solicita_editar_o_sincronizar_radar(
    p_radar_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_despachador_id UUID;
    v_fecha_despacho DATE;
    v_status_radar BOOLEAN;
    v_carga_inventario BOOLEAN;
    v_correlativo INT;
    v_tot_solicitada NUMERIC(10,0);
    v_tot_despachada NUMERIC(10,0);
    v_tot_retirados NUMERIC(10,0);
    v_total_ordenes INT;
    v_desvinculadas INT := 0;
    v_vinculadas INT := 0;
BEGIN
    IF p_radar_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID del radar es obligatorio.'
            )
        );
    END IF;

    SELECT despachador_id, fecha_despacho, correlativo,
           COALESCE(status_radar, FALSE), COALESCE(carga_inventario_movil, FALSE)
    INTO v_despachador_id, v_fecha_despacho, v_correlativo, v_status_radar, v_carga_inventario
    FROM public.radars
    WHERE id = p_radar_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'RADAR_INEXISTENTE',
                'message', 'El radar especificado no existe.'
            )
        );
    END IF;

    IF v_status_radar = TRUE THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'RADAR_APROBADO_BLOQUEADO',
                'message', 'El radar especificado ya ha sido aprobado por la Gerencia y no se puede modificar.'
            )
        );
    END IF;

    IF v_carga_inventario = TRUE THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'RADAR_INVENTARIO_CARGADO',
                'message', 'Para modificar el Radar debe reversar el inventario movil al almacén'
            )
        );
    END IF;

    -- Desvincular únicamente órdenes estándar en estado 'aprobada'
    UPDATE public.ordenes_distribucion
    SET radar_id = NULL
    WHERE radar_id = p_radar_id AND estado = 'aprobada';

    GET DIAGNOSTICS v_desvinculadas = ROW_COUNT;

    -- EXCLUIR VENTA EN RUTA (es_autoventa = TRUE): Volver a vincular únicamente órdenes estándar
    UPDATE public.ordenes_distribucion o
    SET radar_id = p_radar_id
    FROM public.clientes c
    WHERE o.cliente_id = c.id
      AND c.despachador_id = v_despachador_id
      AND o.fecha_despacho::date = v_fecha_despacho
      AND o.estado IN ('aprobada', 'en_transito', 'por_liquidar', 'liquidada', 'devuelta')
      AND (o.radar_id IS NULL OR o.radar_id = p_radar_id)
      AND COALESCE(o.es_autoventa, FALSE) = FALSE;

    GET DIAGNOSTICS v_vinculadas = ROW_COUNT;

    -- Recalcular totales consolidado del radar
    SELECT 
        COALESCE(SUM(d.cantidad_solicitada), 0),
        COALESCE(SUM(d.cantidad_despachada), 0),
        COALESCE(SUM(d.contenedores_retirados), 0),
        COUNT(DISTINCT o.id)
    INTO v_tot_solicitada, v_tot_despachada, v_tot_retirados, v_total_ordenes
    FROM public.ordenes_distribucion o
    JOIN public.detalle_distribucion d ON d.orden_id = o.id
    WHERE o.radar_id = p_radar_id;

    UPDATE public.radars
    SET total_cantidad_solicitada = v_tot_solicitada,
        total_cantidad_despachada = v_tot_despachada,
        total_contenedores_retirados = v_tot_retirados
    WHERE id = p_radar_id;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Radar re-sincronizado y actualizado exitosamente.',
        'data', jsonb_build_object(
            'radar_id', p_radar_id,
            'correlativo', v_correlativo,
            'despachador_id', v_despachador_id,
            'fecha_despacho', v_fecha_despacho,
            'ordenes_desvinculadas', v_desvinculadas,
            'ordenes_vinculadas', v_total_ordenes,
            'total_cantidad_solicitada', v_tot_solicitada,
            'total_cantidad_despachada', v_tot_despachada,
            'total_contenedores_retirados', v_tot_retirados
        ),
        'error', NULL
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.registrar_venta_en_ruta_autoventa(UUID, UUID, UUID, JSONB, JSONB, TEXT, NUMERIC) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.retorna_resumen_autoventas_jornada(UUID, DATE) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.crear_o_obtener_radar(UUID, DATE) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.solicita_editar_o_sincronizar_radar(UUID) TO authenticated, service_role;
