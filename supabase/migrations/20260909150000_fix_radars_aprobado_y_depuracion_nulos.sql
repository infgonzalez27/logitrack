-- Migración: Asegurar existencia de columna 'aprobado' en public.radars, depuración de órdenes con camion_id o vendedor_id NULOS y actualización de RPCs

-- =============================================================================
-- 1. DDL: Asegurar columna 'aprobado' en public.radars
-- =============================================================================
ALTER TABLE public.radars ADD COLUMN IF NOT EXISTS aprobado BOOLEAN DEFAULT FALSE;


-- =============================================================================
-- 2. DEPURACIÓN: Eliminar ordenes con camion_id IS NULL o vendedor_id IS NULL
-- =============================================================================
DELETE FROM public.detalle_distribucion
WHERE orden_id IN (
    SELECT id FROM public.ordenes_distribucion
    WHERE camion_id IS NULL OR vendedor_id IS NULL
);

DELETE FROM public.ordenes_distribucion
WHERE camion_id IS NULL OR vendedor_id IS NULL;


-- =============================================================================
-- 3. RPC: registrar_despacho_cliente_radar
-- =============================================================================
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
    v_radar_id UUID;
    v_status_radar BOOLEAN;
    v_aprobado BOOLEAN;
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
    v_total_despachado INT := 0;
    v_cliente_id UUID;
    v_despacho_permitido BOOLEAN;
    v_excepcion_gerencia BOOLEAN;
    v_nuevo_estado_orden TEXT;
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

    SELECT o.estado, o.camion_id, o.cliente_id, o.radar_id,
           COALESCE(c.excepcion_despacho_gerencia, FALSE),
           (COALESCE(c.excepcion_despacho_gerencia, FALSE) = TRUE OR (
               COALESCE(c.permiso_despacho_manual, TRUE) = TRUE
               AND (COALESCE(c.limite_credito, 0.00) = 0.00 OR COALESCE(o.total_recaudar_bs, 0.00) <= COALESCE(c.limite_credito, 0.00))
           ))
    INTO v_estado_orden, v_camion_id, v_cliente_id, v_radar_id, v_excepcion_gerencia, v_despacho_permitido
    FROM public.ordenes_distribucion o
    JOIN public.clientes c ON o.cliente_id = c.id
    WHERE o.id = p_orden_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'ORDEN_INEXISTENTE',
                'message', 'No se encontró la orden especificada.'
            )
        );
    END IF;

    IF v_radar_id IS NOT NULL THEN
        SELECT COALESCE(status_radar, FALSE), COALESCE(aprobado, FALSE)
        INTO v_status_radar, v_aprobado
        FROM public.radars
        WHERE id = v_radar_id;

        IF v_status_radar = TRUE OR v_aprobado = TRUE THEN
            RETURN jsonb_build_object(
                'success', FALSE,
                'error', jsonb_build_object(
                    'code', 'RADAR_APROBADO_BLOQUEADO',
                    'message', 'El radar correspondiente ya ha sido aprobado por la Gerencia y se encuentra bloqueado para modificaciones.'
                )
            );
        END IF;
    END IF;

    IF NOT v_despacho_permitido THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'DESPACHO_BLOQUEADO_CREDITO',
                'message', 'No se puede despachar la orden: El cliente se encuentra bloqueado por política de crédito y no posee una excepción gerencial activa.'
            )
        );
    END IF;

    IF v_estado_orden NOT IN ('en_transito', 'despachada', 'por_liquidar', 'devuelta') THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo se pueden registrar entregas de órdenes activas en ruta.'
            )
        );
    END IF;

    IF p_detalles_json IS NOT NULL AND jsonb_array_length(p_detalles_json) > 0 THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(p_detalles_json) LOOP
            v_detalle_id := (v_item->>'detalle_id')::UUID;
            v_cantidad_despachada := COALESCE((v_item->>'cantidad_despachada')::INT, 0);
            v_estado_entrega := v_item->>'estado_entrega';
            v_motivo_rechazo := v_item->>'motivo_rechazo';
            v_contenedores_retirados := COALESCE((v_item->>'contenedores_retirados')::INT, 0);
            v_contenedor_id := (v_item->>'contenedor_id')::UUID;

            SELECT producto_id, cantidad_solicitada INTO v_producto_id, v_cantidad_solicitada
            FROM public.detalle_distribucion
            WHERE id = v_detalle_id AND orden_id = p_orden_id;

            IF FOUND THEN
                v_devolucion := GREATEST(0, v_cantidad_solicitada - v_cantidad_despachada);

                IF v_camion_id IS NOT NULL THEN
                    UPDATE public.inventario_movil
                    SET cantidad_entregada = cantidad_entregada + v_cantidad_despachada,
                        cantidad_devolucion = cantidad_devolucion + v_devolucion,
                        updated_at = NOW()
                    WHERE camion_id = v_camion_id AND producto_id = v_producto_id;
                END IF;

                UPDATE public.detalle_distribucion
                SET cantidad_despachada = v_cantidad_despachada,
                    estado_entrega = COALESCE(v_estado_entrega, CASE WHEN v_cantidad_despachada > 0 THEN 'entregado' ELSE 'rechazado' END),
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
        SELECT COALESCE(SUM(cantidad_despachada), 0) INTO v_total_despachado
        FROM public.detalle_distribucion
        WHERE orden_id = p_orden_id;

        IF v_total_despachado = 0 THEN
            v_nuevo_estado_orden := 'devuelta';
        ELSE
            v_nuevo_estado_orden := 'por_liquidar';
        END IF;

        UPDATE public.ordenes_distribucion
        SET estado = v_nuevo_estado_orden
        WHERE id = p_orden_id;

        IF v_excepcion_gerencia THEN
            UPDATE public.clientes
            SET excepcion_despacho_gerencia = FALSE
            WHERE id = v_cliente_id;
        END IF;
    ELSE
        v_nuevo_estado_orden := v_estado_orden;
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Despacho registrado en radar exitosamente.',
        'data', jsonb_build_object(
            'orden_id', p_orden_id,
            'nuevo_estado', v_nuevo_estado_orden,
            'total_despachado', v_total_despachado
        ),
        'error', NULL
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

GRANT EXECUTE ON FUNCTION public.registrar_despacho_cliente_radar TO authenticated, service_role;
