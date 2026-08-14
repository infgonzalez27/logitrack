CREATE OR REPLACE FUNCTION public.liquidar_orden_distribucion(
    p_orden_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_estado_orden TEXT;
    v_cliente_id UUID;
    v_camion_id UUID;
    v_chofer_id UUID;
    v_rendicion_aprobada BOOLEAN := FALSE;
    v_det RECORD;
BEGIN
    -- Validar parámetro
    IF p_orden_id IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID de la orden es requerido.'
            )
        );
    END IF;

    -- Obtener orden
    SELECT estado, cliente_id, camion_id, chofer_id
    INTO v_estado_orden, v_cliente_id, v_camion_id, v_chofer_id
    FROM public.ordenes_distribucion
    WHERE id = p_orden_id;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'ORDEN_INEXISTENTE',
                'message', 'La orden de distribución especificada no existe.'
            )
        );
    END IF;

    IF v_estado_orden != 'por_liquidar' THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo se pueden liquidar órdenes que estén en estado por_liquidar.'
            )
        );
    END IF;

    -- Verificar que exista una rendición aprobada vinculada a esta orden
    SELECT EXISTS (
        SELECT 1 
        FROM public.detalle_rendicion_ordenes dro
        JOIN public.rendiciones_cuentas rc ON dro.rendicion_id = rc.id
        WHERE dro.orden_distribucion_id = p_orden_id
          AND rc.estado = 'aprobada'
    ) INTO v_rendicion_aprobada;

    IF NOT v_rendicion_aprobada THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'COBRANZA_PENDIENTE',
                'message', 'La orden no tiene una rendición de cuentas aprobada vinculada.'
            )
        );
    END IF;

    -- A. Reingresar mercancía devuelta/rechazada de inventario móvil al almacén principal
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

    -- B. Trasladar envases retirados provisionales de detalle_distribucion a movimientos_contenedores y actualizar saldo
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

    -- C. Liberar camión y chofer
    UPDATE public.camiones SET estado = 'disponible' WHERE id = v_camion_id;
    UPDATE public.choferes SET estado = 'disponible' WHERE perfil_id = v_chofer_id;

    -- D. Transicionar orden a 'liquidada'
    UPDATE public.ordenes_distribucion SET estado = 'liquidada' WHERE id = p_orden_id;

    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'orden_id', p_orden_id,
            'nuevo_estado', 'liquidada'
        ),
        'error', NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'SQL_ERROR',
                'message', SQLERRM,
                'details', 'SQLSTATE: ' || SQLSTATE
            )
        );
END;
$$;
