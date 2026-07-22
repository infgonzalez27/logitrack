CREATE OR REPLACE FUNCTION public.registrar_entrega_detalle(
    p_detalle_id UUID,
    p_cantidad_despachada INT,
    p_estado_entrega TEXT,
    p_motivo_rechazo TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_orden_id UUID;
    v_producto_id UUID;
    v_cantidad_solicitada INT;
    v_estado_orden TEXT;
    v_camion_id UUID;
    v_devolucion INT;
    v_pendientes_count INT;
    v_nuevo_estado_orden TEXT;
BEGIN
    -- 1. Validaciones básicas
    IF p_detalle_id IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID del detalle de distribución es requerido.',
                'details', NULL
            )
        );
    END IF;

    IF p_estado_entrega NOT IN ('entregado', 'entregado_parcial', 'rechazado') THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El estado de entrega debe ser entregado, entregado_parcial o rechazado.',
                'details', 'Estado recibido: ' || COALESCE(p_estado_entrega, 'NULL')
            )
        );
    END IF;

    IF p_cantidad_despachada IS NULL OR p_cantidad_despachada < 0 THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'La cantidad despachada/entregada debe ser mayor o igual a 0.',
                'details', NULL
            )
        );
    END IF;

    -- Obtener información del detalle
    SELECT orden_id, producto_id, cantidad_solicitada
    INTO v_orden_id, v_producto_id, v_cantidad_solicitada
    FROM public.detalle_distribucion
    WHERE id = p_detalle_id;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'DETALLE_INEXISTENTE',
                'message', 'El registro de detalle de distribución no existe.',
                'details', 'ID: ' || p_detalle_id
            )
        );
    END IF;

    -- Obtener información de la orden
    SELECT estado, camion_id
    INTO v_estado_orden, v_camion_id
    FROM public.ordenes_distribucion
    WHERE id = v_orden_id;

    -- Validar que la orden esté en tránsito
    IF v_estado_orden != 'en_transito' THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo se pueden registrar entregas para órdenes en estado en_transito.',
                'details', 'Estado actual de la orden: ' || v_estado_orden
            )
        );
    END IF;

    -- Validar que la cantidad despachada no sea mayor a la solicitada/cargada
    IF p_cantidad_despachada > v_cantidad_solicitada THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'CANTIDAD_EXCEDIDA',
                'message', 'La cantidad entregada no puede ser mayor que la cantidad solicitada.',
                'details', 'Solicitado: ' || v_cantidad_solicitada || ', Entregado: ' || p_cantidad_despachada
            )
        );
    END IF;

    -- Si el estado es 'rechazado', la cantidad entregada debe ser 0
    IF p_estado_entrega = 'rechazado' AND p_cantidad_despachada != 0 THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'RECHAZO_CON_CANTIDAD',
                'message', 'Si el estado es rechazado, la cantidad despachada debe ser 0.',
                'details', NULL
            )
        );
    END IF;

    -- Si el estado es 'entregado', la cantidad entregada debe ser igual a la solicitada
    IF p_estado_entrega = 'entregado' AND p_cantidad_despachada != v_cantidad_solicitada THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ENTREGA_INCOMPLETA',
                'message', 'Si el estado es entregado, la cantidad despachada debe ser igual a la solicitada. De lo contrario, use entregado_parcial.',
                'details', 'Solicitado: ' || v_cantidad_solicitada || ', Entregado: ' || p_cantidad_despachada
            )
        );
    END IF;

    -- 2. Procesamiento de Inventario Móvil
    -- Calcular la devolución
    v_devolucion := v_cantidad_solicitada - p_cantidad_despachada;

    -- Actualizar inventario móvil (resta de cantidad_cargada, suma a cantidad_entregada y cantidad_devolucion)
    UPDATE public.inventario_movil
    SET cantidad_cargada = cantidad_cargada - v_cantidad_solicitada,
        cantidad_entregada = cantidad_entregada + p_cantidad_despachada,
        cantidad_devolucion = cantidad_devolucion + v_devolucion,
        updated_at = NOW()
    WHERE camion_id = v_camion_id AND producto_id = v_producto_id;

    -- 3. Actualizar la línea de detalle
    UPDATE public.detalle_distribucion
    SET cantidad_despachada = p_cantidad_despachada,
        estado_entrega = p_estado_entrega,
        motivo_rechazo = p_motivo_rechazo
    WHERE id = p_detalle_id;

    -- 4. Verificar si todas las líneas están entregadas para transicionar la orden a 'por_liquidar'
    SELECT COUNT(*) INTO v_pendientes_count
    FROM public.detalle_distribucion
    WHERE orden_id = v_orden_id AND estado_entrega = 'pendiente';

    v_nuevo_estado_orden := v_estado_orden;

    IF v_pendientes_count = 0 THEN
        UPDATE public.ordenes_distribucion
        SET estado = 'por_liquidar'
        WHERE id = v_orden_id;
        v_nuevo_estado_orden := 'por_liquidar';
    END IF;

    -- 5. Respuesta Exitosa
    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'detalle_id', p_detalle_id,
            'estado_entrega', p_estado_entrega,
            'orden_estado', v_nuevo_estado_orden
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
