CREATE OR REPLACE FUNCTION public.aprobar_despacho_orden_distribucion(
    p_orden_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_estado_orden TEXT;
    v_cliente_id UUID;
    v_camion_id UUID;
    v_det RECORD;
    v_pendientes_count INT;
BEGIN
    -- 1. Validar parámetro
    IF p_orden_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El parámetro p_orden_id es obligatorio.'
            )
        );
    END IF;

    -- 2. Obtener información de la orden
    SELECT estado, cliente_id, camion_id
    INTO v_estado_orden, v_cliente_id, v_camion_id
    FROM public.ordenes_distribucion
    WHERE id = p_orden_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'ORDEN_INEXISTENTE',
                'message', 'No se encontró la orden de distribución especificada.'
            )
        );
    END IF;

    -- Validar estado actual de la orden
    IF v_estado_orden NOT IN ('en_transito', 'despachada') THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo se puede aprobar el despacho de órdenes en estado en_transito o despachada.',
                'details', 'Estado actual: ' || v_estado_orden
            )
        );
    END IF;

    -- Validar que no existan líneas pendientes por despachar en la orden
    SELECT COUNT(*) INTO v_pendientes_count
    FROM public.detalle_distribucion
    WHERE orden_id = p_orden_id AND (estado_entrega IS NULL OR estado_entrega = 'pendiente');

    IF v_pendientes_count > 0 THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'ENTREGA_INCOMPLETA',
                'message', 'La orden aún tiene productos pendientes por despachar en el radar.',
                'details', 'Líneas pendientes: ' || v_pendientes_count
            )
        );
    END IF;

    -- A. Reingresar mercancía devuelta/rechazada del inventario móvil al almacén principal
    FOR v_det IN 
        SELECT producto_id, (cantidad_solicitada - COALESCE(cantidad_despachada, 0)) AS cantidad_devuelta
        FROM public.detalle_distribucion
        WHERE orden_id = p_orden_id AND (cantidad_solicitada - COALESCE(cantidad_despachada, 0)) > 0
    LOOP
        UPDATE public.inventario_almacen
        SET stock_disponible = stock_disponible + v_det.cantidad_devuelta,
            updated_at = NOW()
        WHERE producto_id = v_det.producto_id;

        UPDATE public.inventario_movil
        SET cantidad_devolucion = GREATEST(0, cantidad_devolucion - v_det.cantidad_devuelta),
            updated_at = NOW()
        WHERE camion_id = v_camion_id AND producto_id = v_det.producto_id;
    END LOOP;

    -- B. Trasladar envases retirados provisionales de detalle_distribucion a movimientos_contenedores y actualizar saldo del cliente
    FOR v_det IN
        SELECT contenedor_id, SUM(contenedores_retirados) AS total_retirados
        FROM public.detalle_distribucion
        WHERE orden_id = p_orden_id AND contenedor_id IS NOT NULL AND contenedores_retirados > 0
        GROUP BY contenedor_id
    LOOP
        -- Insertar auditoría oficial de movimiento de contenedores
        INSERT INTO public.movimientos_contenedores (
            cliente_id,
            orden_id,
            contenedor_id,
            cantidad_entregada,
            cantidad_retirada,
            creado_por,
            created_at
        ) VALUES (
            v_cliente_id,
            p_orden_id,
            v_det.contenedor_id,
            0,
            v_det.total_retirados,
            auth.uid(),
            NOW()
        );

        -- Rebajar el saldo del cliente
        INSERT INTO public.saldo_contenedores_clientes (
            cliente_id,
            contenedor_id,
            saldo_pendiente,
            updated_at
        ) VALUES (
            v_cliente_id,
            v_det.contenedor_id,
            0,
            NOW()
        )
        ON CONFLICT (cliente_id, contenedor_id)
        DO UPDATE SET
            saldo_pendiente = GREATEST(0, saldo_contenedores_clientes.saldo_pendiente - v_det.total_retirados),
            updated_at = NOW();
    END LOOP;

    -- C. Transicionar el estado de la orden a 'por_liquidar'
    UPDATE public.ordenes_distribucion
    SET estado = 'por_liquidar'
    WHERE id = p_orden_id;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Despacho de orden aprobado exitosamente. Orden pasa a estado por_liquidar.',
        'data', jsonb_build_object(
            'orden_id', p_orden_id,
            'nuevo_estado', 'por_liquidar'
        )
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', SQLSTATE,
                'message', SQLERRM
            )
        );
END;
$$;

COMMENT ON FUNCTION public.aprobar_despacho_orden_distribucion(UUID) IS 'Aprueba el despacho físico de la orden al cierre de día, ajusta inventarios de almacén, registra movimientos de envases retirados y transiciona a por_liquidar';
