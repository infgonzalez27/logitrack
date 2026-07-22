CREATE OR REPLACE FUNCTION public.aprobar_orden_distribucion(
    p_orden_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_estado_actual TEXT;
    v_item RECORD;
    v_producto_nombre TEXT;
    v_stock_disponible INT;
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

    -- Obtener estado actual de la orden
    SELECT estado INTO v_estado_actual
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

    -- Validar que esté en estado 'borrador'
    IF v_estado_actual != 'borrador' THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo las órdenes en estado borrador pueden ser aprobadas.',
                'details', 'Estado actual: ' || v_estado_actual
            )
        );
    END IF;

    -- 2. Validar stock disponible para todos los detalles en almacén
    FOR v_item IN 
        SELECT d.producto_id, d.cantidad_solicitada, p.nombre
        FROM public.detalle_distribucion d
        JOIN public.productos p ON p.id = d.producto_id
        WHERE d.orden_id = p_orden_id
    LOOP
        -- Buscar stock disponible en el almacén principal
        SELECT stock_disponible 
        INTO v_stock_disponible
        FROM public.inventario_almacen
        WHERE producto_id = v_item.producto_id
        FOR UPDATE; -- Bloquear fila para evitar condiciones de carrera

        IF NOT FOUND THEN
            RETURN json_build_object(
                'success', false,
                'data', NULL,
                'error', json_build_object(
                    'code', 'SIN_REGISTRO_INVENTARIO',
                    'message', 'El producto ' || v_item.nombre || ' no tiene registro de inventario en almacén.',
                    'details', 'Producto ID: ' || v_item.producto_id
                )
            );
        END IF;

        -- Verificar si el stock es suficiente
        IF v_stock_disponible < v_item.cantidad_solicitada THEN
            RETURN json_build_object(
                'success', false,
                'data', NULL,
                'error', json_build_object(
                    'code', 'STOCK_INSUFICIENTE',
                    'message', 'Stock insuficiente en almacén para el producto: ' || v_item.nombre,
                    'details', 'Disponible: ' || v_stock_disponible || ', Solicitado: ' || v_item.cantidad_solicitada
                )
            );
        END IF;
    END LOOP;

    -- 3. Comprometer stock y cambiar estado (Transacción Atómica)
    FOR v_item IN 
        SELECT producto_id, cantidad_solicitada
        FROM public.detalle_distribucion
        WHERE orden_id = p_orden_id
    LOOP
        -- Descontar de stock_disponible y sumar a stock_comprometido
        UPDATE public.inventario_almacen
        SET stock_disponible = stock_disponible - v_item.cantidad_solicitada,
            stock_comprometido = stock_comprometido + v_item.cantidad_solicitada,
            updated_at = NOW()
        WHERE producto_id = v_item.producto_id;
    END LOOP;

    -- Cambiar estado de la orden a 'aprobada'
    UPDATE public.ordenes_distribucion
    SET estado = 'aprobada'
    WHERE id = p_orden_id;

    -- 4. Retorno exitoso
    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'orden_id', p_orden_id,
            'nuevo_estado', 'aprobada'
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
