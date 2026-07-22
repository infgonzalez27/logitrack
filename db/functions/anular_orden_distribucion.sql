CREATE OR REPLACE FUNCTION public.anular_orden_distribucion(
    p_orden_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_estado_actual TEXT;
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
    SELECT estado
    INTO v_estado_actual
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

    -- Validar estado para anulación
    IF v_estado_actual = 'anulada' THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'La orden de distribución ya se encuentra anulada.',
                'details', NULL
            )
        );
    END IF;

    IF v_estado_actual = 'liquidada' THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'No se puede anular una orden que ya ha sido liquidada.',
                'details', NULL
            )
        );
    END IF;

    IF v_estado_actual IN ('en_transito', 'por_liquidar') THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'No se puede anular una orden que ya ha sido despachada y se encuentra en tránsito o por liquidar.',
                'details', 'Estado actual: ' || v_estado_actual
            )
        );
    END IF;

    -- 2. Procesamiento de Anulación
    -- Si la orden está aprobada, debemos liberar el stock comprometido en almacén
    IF v_estado_actual = 'aprobada' THEN
        FOR v_item IN 
            SELECT producto_id, cantidad_solicitada
            FROM public.detalle_distribucion
            WHERE orden_id = p_orden_id
        LOOP
            -- Sumar de vuelta a stock_disponible, restar de stock_comprometido
            UPDATE public.inventario_almacen
            SET stock_disponible = stock_disponible + v_item.cantidad_solicitada,
                stock_comprometido = stock_comprometido - v_item.cantidad_solicitada,
                updated_at = NOW()
            WHERE producto_id = v_item.producto_id;
        END LOOP;
    END IF;

    -- Cambiar estado de la orden a 'anulada'
    UPDATE public.ordenes_distribucion
    SET estado = 'anulada'
    WHERE id = p_orden_id;

    -- 3. Respuesta Exitosa
    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'orden_id', p_orden_id,
            'nuevo_estado', 'anulada'
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
