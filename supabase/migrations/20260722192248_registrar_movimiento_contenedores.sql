CREATE OR REPLACE FUNCTION public.registrar_movimiento_contenedores(
    p_cliente_id UUID,
    p_orden_id UUID,
    p_contenedor_id UUID,
    p_cantidad_entregada INT,
    p_cantidad_retirada INT,
    p_creado_por UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_estado_orden TEXT;
    v_movimiento_id UUID;
BEGIN
    -- 1. Validaciones básicas
    IF p_cliente_id IS NULL OR p_orden_id IS NULL OR p_contenedor_id IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'Los IDs de cliente, orden y contenedor son requeridos.',
                'details', NULL
            )
        );
    END IF;

    IF p_cantidad_entregada IS NULL OR p_cantidad_entregada < 0 OR
       p_cantidad_retirada IS NULL OR p_cantidad_retirada < 0 THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'Las cantidades entregadas y retiradas deben ser mayores o iguales a 0.',
                'details', NULL
            )
        );
    END IF;

    -- Validar si el cliente existe
    IF NOT EXISTS (SELECT 1 FROM public.clientes WHERE id = p_cliente_id) THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'CLIENTE_INEXISTENTE',
                'message', 'El cliente especificado no existe.',
                'details', 'ID: ' || p_cliente_id
            )
        );
    END IF;

    -- Validar si la orden existe y obtener su estado
    SELECT estado INTO v_estado_orden
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

    -- Validar que la orden esté en ruta o entregada en espera de conciliación
    IF v_estado_orden NOT IN ('en_transito', 'por_liquidar') THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo se pueden registrar movimientos de envases para órdenes en tránsito o por liquidar.',
                'details', 'Estado actual de la orden: ' || v_estado_orden
            )
        );
    END IF;

    -- Validar si el contenedor existe
    IF NOT EXISTS (SELECT 1 FROM public.tipos_contenedores WHERE id = p_contenedor_id) THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'CONTENEDOR_INEXISTENTE',
                'message', 'El tipo de contenedor especificado no existe.',
                'details', 'ID: ' || p_contenedor_id
            )
        );
    END IF;

    -- 2. Registrar movimiento
    INSERT INTO public.movimientos_contenedores (
        cliente_id,
        orden_id,
        contenedor_id,
        cantidad_entregada,
        cantidad_retirada,
        creado_por,
        created_at
    ) VALUES (
        p_cliente_id,
        p_orden_id,
        p_contenedor_id,
        p_cantidad_entregada,
        p_cantidad_retirada,
        p_creado_por,
        NOW()
    ) RETURNING id INTO v_movimiento_id;

    -- 3. Respuesta Exitosa
    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'movimiento_id', v_movimiento_id
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
