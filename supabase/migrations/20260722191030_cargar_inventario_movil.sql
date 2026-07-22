CREATE OR REPLACE FUNCTION public.cargar_inventario_movil(
    p_orden_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_estado_actual TEXT;
    v_camion_id UUID;
    v_chofer_id UUID;
    v_item RECORD;
BEGIN
    -- 1. Validaciones básicas
    IF p_orden_id IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID de la orden es requerido.',
                'details', NULL
            )
        );
    END IF;

    -- Obtener datos de la orden
    SELECT estado, camion_id, chofer_id
    INTO v_estado_actual, v_camion_id, v_chofer_id
    FROM public.ordenes_distribucion
    WHERE id = p_orden_id;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ORDEN_INEXISTENTE',
                'message', 'La orden de distribución especificada no existe.',
                'details', 'ID: ' || p_orden_id
            )
        );
    END IF;

    -- Validar estado 'aprobada'
    IF v_estado_actual != 'aprobada' THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'La orden debe estar en estado aprobada para poder ser despachada.',
                'details', 'Estado actual: ' || v_estado_actual
            )
        );
    END IF;

    -- Validar que camión y chofer estén asignados
    IF v_camion_id IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'CAMION_NO_ASIGNADO',
                'message', 'No se puede despachar la orden porque no tiene un camión asignado.',
                'details', NULL
            )
        );
    END IF;

    IF v_chofer_id IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'CHOFER_NO_ASIGNADO',
                'message', 'No se puede despachar la orden porque no tiene un chofer asignado.',
                'details', NULL
            )
        );
    END IF;

    -- 2. Procesamiento e Integración de Inventario (Operaciones Atómicas)
    FOR v_item IN 
        SELECT producto_id, cantidad_solicitada
        FROM public.detalle_distribucion
        WHERE orden_id = p_orden_id
    LOOP
        -- Descontar del comprometido del almacén principal (sale físicamente del centro de distribución)
        UPDATE public.inventario_almacen
        SET stock_comprometido = stock_comprometido - v_item.cantidad_solicitada,
            updated_at = NOW()
        WHERE producto_id = v_item.producto_id;

        -- Upsert en el inventario móvil del camión (suma a la cantidad cargada)
        INSERT INTO public.inventario_movil (
            camion_id,
            producto_id,
            cantidad_cargada,
            cantidad_entregada,
            cantidad_devolucion,
            updated_at
        ) VALUES (
            v_camion_id,
            v_item.producto_id,
            v_item.cantidad_solicitada,
            0,
            0,
            NOW()
        )
        ON CONFLICT (camion_id, producto_id) 
        DO UPDATE SET 
            cantidad_cargada = inventario_movil.cantidad_cargada + v_item.cantidad_solicitada,
            updated_at = NOW();

        -- Inicializar cantidad_despachada como cargada
        UPDATE public.detalle_distribucion
        SET cantidad_despachada = v_item.cantidad_solicitada
        WHERE orden_id = p_orden_id AND producto_id = v_item.producto_id;
    END LOOP;

    -- 3. Actualizar estados de recursos de transporte
    -- Cambiar camión a estado 'en_ruta'
    UPDATE public.camiones
    SET estado = 'en_ruta'
    WHERE id = v_camion_id;

    -- Cambiar chofer a estado 'en_ruta'
    UPDATE public.choferes
    SET estado = 'en_ruta'
    WHERE perfil_id = v_chofer_id;

    -- Cambiar orden a estado 'en_transito'
    UPDATE public.ordenes_distribucion
    SET estado = 'en_transito',
        fecha_despacho = NOW()
    WHERE id = p_orden_id;

    -- 4. Respuesta Exitosa
    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'orden_id', p_orden_id,
            'nuevo_estado', 'en_transito'
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
