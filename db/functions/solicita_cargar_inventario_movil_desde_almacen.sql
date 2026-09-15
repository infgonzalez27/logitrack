CREATE OR REPLACE FUNCTION public.solicita_cargar_inventario_movil_desde_almacen(
    p_camion_id UUID,
    p_resumen_productos JSONB,
    p_radar_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_item JSONB;
    v_items_array JSONB;
    v_producto_id UUID;
    v_cantidad_solicitada INT;
    v_total_productos_cargados INT := 0;
    v_unidades_totales INT := 0;
    v_camion_existe BOOLEAN;
    v_ordenes_actualizadas INT := 0;
BEGIN
    -- 1. Validaciones básicas
    IF p_camion_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID del camión es requerido.'
            )
        );
    END IF;

    SELECT EXISTS(SELECT 1 FROM public.camiones WHERE id = p_camion_id) INTO v_camion_existe;
    IF NOT v_camion_existe THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'CAMION_INEXISTENTE',
                'message', 'El camión especificado no existe.'
            )
        );
    END IF;

    -- Extraer el arreglo de productos (soporta directo [...] u objeto {"resumen_productos": [...]})
    IF jsonb_typeof(p_resumen_productos) = 'array' THEN
        v_items_array := p_resumen_productos;
    ELSIF jsonb_typeof(p_resumen_productos) = 'object' AND p_resumen_productos ? 'resumen_productos' THEN
        v_items_array := p_resumen_productos->'resumen_productos';
    ELSE
        v_items_array := '[]'::jsonb;
    END IF;

    IF v_items_array IS NULL OR jsonb_array_length(v_items_array) = 0 THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'DATOS_VACIOS',
                'message', 'El resumen de productos a cargar no contiene elementos válidos.'
            )
        );
    END IF;

    -- 2. Procesamiento de Carga de Inventario
    FOR v_item IN SELECT * FROM jsonb_array_elements(v_items_array) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad_solicitada := COALESCE((v_item->>'cantidad_solicitada')::INT, 0);

        IF v_producto_id IS NOT NULL AND v_cantidad_solicitada > 0 THEN
            -- Descontar del almacén principal (reducir stock_comprometido y/o stock_disponible)
            UPDATE public.inventario_almacen
            SET stock_comprometido = GREATEST(0, stock_comprometido - v_cantidad_solicitada),
                stock_disponible = CASE 
                    WHEN stock_comprometido < v_cantidad_solicitada 
                    THEN GREATEST(0, stock_disponible - (v_cantidad_solicitada - stock_comprometido))
                    ELSE stock_disponible 
                END,
                updated_at = NOW()
            WHERE producto_id = v_producto_id;

            -- Upsert en inventario móvil del camión (sumar a cantidad_cargada)
            INSERT INTO public.inventario_movil (
                camion_id,
                producto_id,
                cantidad_cargada,
                cantidad_entregada,
                cantidad_devolucion,
                updated_at
            ) VALUES (
                p_camion_id,
                v_producto_id,
                v_cantidad_solicitada,
                0,
                0,
                NOW()
            )
            ON CONFLICT (camion_id, producto_id)
            DO UPDATE SET
                cantidad_cargada = public.inventario_movil.cantidad_cargada + v_cantidad_solicitada,
                updated_at = NOW();

            v_total_productos_cargados := v_total_productos_cargados + 1;
            v_unidades_totales := v_unidades_totales + v_cantidad_solicitada;
        END IF;
    END LOOP;

    -- 3. Actualizar estado del camión a 'en_ruta'
    UPDATE public.camiones
    SET estado = 'en_ruta',
        updated_at = NOW()
    WHERE id = p_camion_id;

    -- 4. Transicionar órdenes vinculadas a 'en_transito' y fijar fecha_despacho = NOW()
    IF p_radar_id IS NOT NULL THEN
        UPDATE public.ordenes_distribucion
        SET estado = 'en_transito',
            fecha_despacho = NOW(),
            updated_at = NOW()
        WHERE radar_id = p_radar_id AND estado = 'aprobada';
        
        GET DIAGNOSTICS v_ordenes_actualizadas = ROW_COUNT;
    ELSE
        UPDATE public.ordenes_distribucion
        SET estado = 'en_transito',
            fecha_despacho = NOW(),
            updated_at = NOW()
        WHERE camion_id = p_camion_id AND estado = 'aprobada';
        
        GET DIAGNOSTICS v_ordenes_actualizadas = ROW_COUNT;
    END IF;

    -- 5. Inicializar cantidad_despachada = cantidad_solicitada en detalle_distribucion para las órdenes en_transito
    IF p_radar_id IS NOT NULL THEN
        UPDATE public.detalle_distribucion dd
        SET cantidad_despachada = dd.cantidad_solicitada
        FROM public.ordenes_distribucion od
        WHERE dd.orden_id = od.id
          AND od.radar_id = p_radar_id
          AND od.estado = 'en_transito';
    ELSE
        UPDATE public.detalle_distribucion dd
        SET cantidad_despachada = dd.cantidad_solicitada
        FROM public.ordenes_distribucion od
        WHERE dd.orden_id = od.id
          AND od.camion_id = p_camion_id
          AND od.estado = 'en_transito';
    END IF;

    -- 6. Respuesta Exitosa
    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Carga a inventario móvil procesada exitosamente desde el almacén.',
        'data', jsonb_build_object(
            'camion_id', p_camion_id,
            'radar_id', p_radar_id,
            'total_productos_cargados', v_total_productos_cargados,
            'unidades_totales', v_unidades_totales,
            'ordenes_despachadas', v_ordenes_actualizadas
        ),
        'error', NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'SQL_ERROR',
                'message', SQLERRM,
                'details', 'SQLSTATE: ' || SQLSTATE
            )
        );
END;
$$;

GRANT EXECUTE ON FUNCTION public.solicita_cargar_inventario_movil_desde_almacen(UUID, JSONB, UUID) TO authenticated, service_role;
