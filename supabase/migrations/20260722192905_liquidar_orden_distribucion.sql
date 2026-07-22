CREATE OR REPLACE FUNCTION public.liquidar_orden_distribucion(
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
    v_cliente_id UUID;
    v_rendicion_id UUID;
    v_rendicion_estado TEXT;
    v_item RECORD;
    v_mov RECORD;
    v_devolucion INT;
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
    SELECT estado, camion_id, chofer_id, cliente_id
    INTO v_estado_actual, v_camion_id, v_chofer_id, v_cliente_id
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

    -- Validar que la orden esté en estado 'por_liquidar'
    IF v_estado_actual != 'por_liquidar' THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'La orden debe estar en estado por_liquidar para poder ser liquidada.',
                'details', 'Estado actual: ' || v_estado_actual
            )
        );
    END IF;

    -- 2. Validar rendición de cuentas (Módulo 4)
    -- Buscar si hay un detalle de rendición asociado a esta orden
    SELECT rendicion_id INTO v_rendicion_id
    FROM public.detalle_rendicion_ordenes
    WHERE orden_distribucion_id = p_orden_id;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'COBRANZA_PENDIENTE',
                'message', 'No se puede liquidar la orden porque no tiene ninguna rendición de cuentas registrada.',
                'details', NULL
            )
        );
    END IF;

    -- Obtener estado de la rendición
    SELECT estado INTO v_rendicion_estado
    FROM public.rendiciones_cuentas
    WHERE id = v_rendicion_id;

    -- Validar que la rendición esté aprobada
    IF v_rendicion_estado != 'aprobada' THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'COBRANZA_PENDIENTE',
                'message', 'No se puede liquidar la orden porque la rendición de cuentas asociada no ha sido aprobada por el gerente.',
                'details', 'Rendición ID: ' || v_rendicion_id || ' - Estado: ' || v_rendicion_estado
            )
        );
    END IF;

    -- 3. Conciliación Física de Inventario (Devoluciones al almacén principal)
    FOR v_item IN 
        SELECT producto_id, cantidad_solicitada, cantidad_despachada
        FROM public.detalle_distribucion
        WHERE orden_id = p_orden_id
    LOOP
        -- La cantidad despachada en detalle_distribucion es la que realmente recibió el cliente (se actualiza en registrar_entrega_detalle)
        -- Por lo tanto, las devoluciones son: cantidad_solicitada (cargada) - cantidad_despachada (recibida)
        v_devolucion := v_item.cantidad_solicitada - v_item.cantidad_despachada;

        IF v_devolucion > 0 THEN
            -- Regresar la mercancía al stock disponible del almacén principal
            UPDATE public.inventario_almacen
            SET stock_disponible = stock_disponible + v_devolucion,
                updated_at = NOW()
            WHERE producto_id = v_item.producto_id;

            -- Descontar del inventario móvil del camión (las devoluciones ya no están en el camión)
            UPDATE public.inventario_movil
            SET cantidad_devolucion = cantidad_devolucion - v_devolucion,
                updated_at = NOW()
            WHERE camion_id = v_camion_id AND producto_id = v_item.producto_id;
        END IF;
    END LOOP;

    -- 4. Consolidación del Saldo de Contenedores del Cliente
    FOR v_mov IN 
        SELECT contenedor_id, cantidad_entregada, cantidad_retirada
        FROM public.movimientos_contenedores
        WHERE orden_id = p_orden_id
    LOOP
        -- Insertar o actualizar el saldo del cliente para este tipo de contenedor
        INSERT INTO public.saldo_contenedores_clientes (
            cliente_id,
            contenedor_id,
            saldo_pendiente,
            updated_at
        ) VALUES (
            v_cliente_id,
            v_mov.contenedor_id,
            GREATEST(0, v_mov.cantidad_entregada - v_mov.cantidad_retirada),
            NOW()
        )
        ON CONFLICT (cliente_id, contenedor_id)
        DO UPDATE SET
            saldo_pendiente = GREATEST(0, saldo_contenedores_clientes.saldo_pendiente + (v_mov.cantidad_entregada - v_mov.cantidad_retirada)),
            updated_at = NOW();
    END LOOP;

    -- 5. Liberar recursos de transporte (Camión y Chofer a disponible)
    UPDATE public.camiones
    SET estado = 'disponible'
    WHERE id = v_camion_id;

    UPDATE public.choferes
    SET estado = 'disponible'
    WHERE perfil_id = v_chofer_id;

    -- Cambiar estado de la orden a 'liquidada'
    UPDATE public.ordenes_distribucion
    SET estado = 'liquidada'
    WHERE id = p_orden_id;

    -- 6. Respuesta Exitosa
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
            'data', NULL,
            'error', json_build_object(
                'code', 'SQL_ERROR',
                'message', SQLERRM,
                'details', 'SQLSTATE: ' || SQLSTATE
            )
        );
END;
$$;
