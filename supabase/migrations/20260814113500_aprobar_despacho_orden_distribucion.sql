-- Migración para el procedimiento aprobar_despacho_orden_distribucion y separación de flujo físico vs financiero

-- 1. Actualización de restricciones CHECK en ordenes_distribucion si aplica
DO $$
BEGIN
    ALTER TABLE public.ordenes_distribucion DROP CONSTRAINT IF EXISTS ordenes_distribucion_estado_check;
    ALTER TABLE public.ordenes_distribucion ADD CONSTRAINT ordenes_distribucion_estado_check 
        CHECK (estado IN ('borrador', 'aprobada', 'en_transito', 'despachada', 'por_liquidar', 'liquidada', 'anulada'));
EXCEPTION
    WHEN OTHERS THEN NULL;
END $$;

-- 2. RPC aprobar_despacho_orden_distribucion (Aprobación física de almacén / gerencia)
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
    IF p_orden_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El parámetro p_orden_id es obligatorio.'
            )
        );
    END IF;

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

    -- A. Reingresar mercancía devuelta del inventario móvil al almacén principal
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

-- 3. Actualizar registrar_despacho_cliente_radar para transicionar a despachada
CREATE OR REPLACE FUNCTION public.registrar_despacho_cliente_radar(
    p_orden_id UUID,
    p_detalles_json JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_estado_orden TEXT;
    v_camion_id UUID;
    v_item JSONB;
    v_detalle_id UUID;
    v_cantidad_despachada INT;
    v_estado_entrega TEXT;
    v_motivo_rechazo TEXT;
    v_contenedores_retirados INT;
    v_contenedor_id UUID;
    v_producto_id UUID;
    v_cantidad_solicitada INT;
    v_devolucion INT;
    v_pendientes_count INT;
BEGIN
    IF p_orden_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El parámetro p_orden_id es obligatorio.'
            )
        );
    END IF;

    SELECT estado, camion_id INTO v_estado_orden, v_camion_id
    FROM public.ordenes_distribucion
    WHERE id = p_orden_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'ORDEN_INEXISTENTE',
                'message', 'No se encontró la orden especificada.'
            )
        );
    END IF;

    IF v_estado_orden NOT IN ('en_transito', 'despachada') THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo se pueden registrar entregas de órdenes en estado en_transito o despachada.'
            )
        );
    END IF;

    IF p_detalles_json IS NOT NULL AND jsonb_array_length(p_detalles_json) > 0 THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(p_detalles_json) LOOP
            v_detalle_id := (v_item->>'detalle_id')::UUID;
            v_cantidad_despachada := (v_item->>'cantidad_despachada')::INT;
            v_estado_entrega := v_item->>'estado_entrega';
            v_motivo_rechazo := v_item->>'motivo_rechazo';
            v_contenedores_retirados := COALESCE((v_item->>'contenedores_retirados')::INT, 0);
            v_contenedor_id := (v_item->>'contenedor_id')::UUID;

            SELECT producto_id, cantidad_solicitada INTO v_producto_id, v_cantidad_solicitada
            FROM public.detalle_distribucion
            WHERE id = v_detalle_id AND orden_id = p_orden_id;

            IF FOUND THEN
                v_devolucion := GREATEST(0, v_cantidad_solicitada - v_cantidad_despachada);

                UPDATE public.inventario_movil
                SET cantidad_cargada = GREATEST(0, cantidad_cargada - v_cantidad_solicitada),
                    cantidad_entregada = cantidad_entregada + v_cantidad_despachada,
                    cantidad_devolucion = cantidad_devolucion + v_devolucion,
                    updated_at = NOW()
                WHERE camion_id = v_camion_id AND producto_id = v_producto_id;

                UPDATE public.detalle_distribucion
                SET cantidad_despachada = v_cantidad_despachada,
                    estado_entrega = v_estado_entrega,
                    motivo_rechazo = v_motivo_rechazo,
                    contenedores_retirados = v_contenedores_retirados,
                    contenedor_id = v_contenedor_id
                WHERE id = v_detalle_id;
            END IF;
        END LOOP;
    END IF;

    SELECT COUNT(*) INTO v_pendientes_count
    FROM public.detalle_distribucion
    WHERE orden_id = p_orden_id AND (estado_entrega IS NULL OR estado_entrega = 'pendiente');

    IF v_pendientes_count = 0 THEN
        UPDATE public.ordenes_distribucion
        SET estado = 'despachada'
        WHERE id = p_orden_id;
        v_estado_orden := 'despachada';
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Despacho registrado en radar exitosamente.',
        'data', jsonb_build_object(
            'orden_id', p_orden_id,
            'nuevo_estado_orden', v_estado_orden
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

-- 4. Actualizar liquidar_orden_distribucion (Liquidación financiera)
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
BEGIN
    IF p_orden_id IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID de la orden es requerido.'
            )
        );
    END IF;

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
                'message', 'Solo se pueden liquidar financieramente órdenes que estén en estado por_liquidar.'
            )
        );
    END IF;

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

    UPDATE public.camiones SET estado = 'disponible' WHERE id = v_camion_id;
    UPDATE public.choferes SET estado = 'disponible' WHERE perfil_id = v_chofer_id;

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
