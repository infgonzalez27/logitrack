CREATE OR REPLACE FUNCTION public.solicita_reversar_carga_inventario_movil_a_almacen(
    p_camion_id UUID,
    p_resumen_productos JSONB DEFAULT NULL,
    p_radar_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_item JSONB;
    v_items_array JSONB := '[]'::jsonb;
    v_producto_id UUID;
    v_cantidad INT;
    v_total_productos_reversados INT := 0;
    v_unidades_totales INT := 0;
    v_camion_existe BOOLEAN;
    v_radar_id UUID;
    v_carga_inventario BOOLEAN;
    v_entregas_existentes INT := 0;
    v_ordenes_reversadas INT := 0;
    v_rec RECORD;
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

    -- Obtener o confirmar radar_id
    v_radar_id := p_radar_id;
    IF v_radar_id IS NULL THEN
        SELECT radar_id INTO v_radar_id
        FROM public.ordenes_distribucion
        WHERE camion_id = p_camion_id AND radar_id IS NOT NULL
        ORDER BY updated_at DESC
        LIMIT 1;
    END IF;

    -- Verificar estado del radar y carga de inventario
    IF v_radar_id IS NOT NULL THEN
        SELECT COALESCE(carga_inventario_movil, FALSE) INTO v_carga_inventario
        FROM public.radars
        WHERE id = v_radar_id;

        IF NOT v_carga_inventario THEN
            RETURN jsonb_build_object(
                'success', FALSE,
                'data', NULL,
                'error', jsonb_build_object(
                    'code', 'INVENTARIO_NO_CARGADO',
                    'message', 'El inventario móvil de este radar no ha sido cargado previamente o ya fue reversado.'
                )
            );
        END IF;

        -- Validar si existen despachos/entregas iniciadas en las órdenes del radar
        SELECT COUNT(*) INTO v_entregas_existentes
        FROM public.ordenes_distribucion
        WHERE radar_id = v_radar_id AND estado IN ('despachada', 'por_liquidar', 'liquidada', 'devuelta');

        IF v_entregas_existentes > 0 THEN
            RETURN jsonb_build_object(
                'success', FALSE,
                'data', NULL,
                'error', jsonb_build_object(
                    'code', 'REVERSO_BLOQUEADO_POR_ENTREGAS',
                    'message', 'No se puede reversar la carga al almacén porque ya existen entregas o despachos registrados en esta ruta.'
                )
            );
        END IF;
    END IF;

    -- Extraer elementos a reversar
    IF p_resumen_productos IS NOT NULL THEN
        IF jsonb_typeof(p_resumen_productos) = 'array' THEN
            v_items_array := p_resumen_productos;
        ELSIF jsonb_typeof(p_resumen_productos) = 'object' AND p_resumen_productos ? 'resumen_productos' THEN
            v_items_array := p_resumen_productos->'resumen_productos';
        END IF;
    END IF;

    IF jsonb_array_length(v_items_array) > 0 THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(v_items_array) LOOP
            v_producto_id := (v_item->>'producto_id')::UUID;
            v_cantidad := COALESCE((v_item->>'cantidad_solicitada')::INT, 0);

            IF v_producto_id IS NOT NULL AND v_cantidad > 0 THEN
                -- Reingresar stock al almacén principal (inventario_almacen)
                INSERT INTO public.inventario_almacen (producto_id, stock_disponible, stock_comprometido, updated_at)
                VALUES (v_producto_id, v_cantidad, 0, NOW())
                ON CONFLICT (producto_id)
                DO UPDATE SET
                    stock_disponible = public.inventario_almacen.stock_disponible + v_cantidad,
                    updated_at = NOW();

                -- Restar del inventario móvil del camión
                UPDATE public.inventario_movil
                SET cantidad_cargada = GREATEST(0, cantidad_cargada - v_cantidad),
                    updated_at = NOW()
                WHERE camion_id = p_camion_id AND producto_id = v_producto_id;

                v_total_productos_reversados := v_total_productos_reversados + 1;
                v_unidades_totales := v_unidades_totales + v_cantidad;
            END IF;
        END LOOP;
    ELSE
        -- Fallback: reversar acumulado de inventario_movil para este camión
        FOR v_rec IN 
            SELECT producto_id, cantidad_cargada
            FROM public.inventario_movil
            WHERE camion_id = p_camion_id AND cantidad_cargada > 0
        LOOP
            INSERT INTO public.inventario_almacen (producto_id, stock_disponible, stock_comprometido, updated_at)
            VALUES (v_rec.producto_id, v_rec.cantidad_cargada, 0, NOW())
            ON CONFLICT (producto_id)
            DO UPDATE SET
                stock_disponible = public.inventario_almacen.stock_disponible + v_rec.cantidad_cargada,
                updated_at = NOW();

            UPDATE public.inventario_movil
            SET cantidad_cargada = 0,
                updated_at = NOW()
            WHERE camion_id = p_camion_id AND producto_id = v_rec.producto_id;

            v_total_productos_reversados := v_total_productos_reversados + 1;
            v_unidades_totales := v_unidades_totales + v_rec.cantidad_cargada;
        END LOOP;
    END IF;

    -- 2. Transicionar órdenes de vuelta a 'aprobada' (SIN TOCAR fecha_despacho)
    IF v_radar_id IS NOT NULL THEN
        UPDATE public.ordenes_distribucion
        SET estado = 'aprobada',
            updated_at = NOW()
        WHERE radar_id = v_radar_id AND estado = 'en_transito';

        GET DIAGNOSTICS v_ordenes_reversadas = ROW_COUNT;
    ELSE
        UPDATE public.ordenes_distribucion
        SET estado = 'aprobada',
            updated_at = NOW()
        WHERE camion_id = p_camion_id AND estado = 'en_transito';

        GET DIAGNOSTICS v_ordenes_reversadas = ROW_COUNT;
    END IF;

    -- 3. Resetear cantidad_despachada = 0 en detalle_distribucion
    IF v_radar_id IS NOT NULL THEN
        UPDATE public.detalle_distribucion dd
        SET cantidad_despachada = 0
        FROM public.ordenes_distribucion od
        WHERE dd.orden_id = od.id AND od.radar_id = v_radar_id;
    ELSE
        UPDATE public.detalle_distribucion dd
        SET cantidad_despachada = 0
        FROM public.ordenes_distribucion od
        WHERE dd.orden_id = od.id AND od.camion_id = p_camion_id;
    END IF;

    -- 4. Revertir estado del camión a 'asignado'
    UPDATE public.camiones
    SET estado = 'asignado',
        updated_at = NOW()
    WHERE id = p_camion_id;

    -- 5. Cambiar carga_inventario_movil = FALSE en radars
    IF v_radar_id IS NOT NULL THEN
        UPDATE public.radars
        SET carga_inventario_movil = FALSE,
            updated_at = NOW()
        WHERE id = v_radar_id;
    END IF;

    -- 6. Respuesta Exitosa
    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Reverso de inventario móvil al almacén procesado exitosamente.',
        'data', jsonb_build_object(
            'camion_id', p_camion_id,
            'radar_id', v_radar_id,
            'carga_inventario_movil', FALSE,
            'total_productos_reversados', v_total_productos_reversados,
            'unidades_totales', v_unidades_totales,
            'ordenes_reversadas', v_ordenes_reversadas
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

GRANT EXECUTE ON FUNCTION public.solicita_reversar_carga_inventario_movil_a_almacen(UUID, JSONB, UUID) TO authenticated, service_role;
