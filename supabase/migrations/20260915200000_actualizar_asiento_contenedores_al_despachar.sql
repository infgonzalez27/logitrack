-- Migración: Actualizar asiento de envases/contenedores al despachar en registrar_despacho_cliente_radar y desacoplar de solicita_aprobar_radar

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

    -- Variables para procesamiento y resumen de saldos de contenedores
    v_rec_prev RECORD;
    v_rec_cont RECORD;
    v_saldo_previo INT;
    v_saldo_nuevo INT;
    v_cant_entregada INT;
    v_cant_retirada INT;
    v_contenedores_resumen JSONB := '[]'::JSONB;
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

    -- Obtener información de la orden, cliente y radar asociado
    SELECT o.estado, o.camion_id, o.cliente_id, o.radar_id,
           COALESCE(c.excepcion_despacho_gerencia, FALSE),
           TRUE
    INTO v_estado_orden, v_camion_id, v_cliente_id, v_radar_id, v_excepcion_gerencia, v_despacho_permitido
    FROM public.ordenes_distribucion o
    JOIN public.clientes c ON o.cliente_id = c.id
    WHERE o.id = p_orden_id;

    -- Desactivar temporalmente bloqueos por crédito: permitir despacho siempre
    v_despacho_permitido := TRUE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'ORDEN_INEXISTENTE',
                'message', 'No se encontró la orden especificada.'
            )
        );
    END IF;

    -- Validar si el radar asociado ya fue aprobado/cerrado por Gerencia (status_radar = TRUE)
    IF v_radar_id IS NOT NULL THEN
        SELECT COALESCE(status_radar, FALSE)
        INTO v_status_radar
        FROM public.radars
        WHERE id = v_radar_id;

        IF v_status_radar = TRUE THEN
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

    -- =========================================================================
    -- PROCESAMIENTO Y ASIENTO DE SALDOS DE CONTENEDORES (AL MOMENTO DEL DESPACHO)
    -- =========================================================================
    -- 1. Reversar movimientos previos registrados para esta orden (para permitir re-edición idempotente)
    FOR v_rec_prev IN
        SELECT contenedor_id, cantidad_entregada, cantidad_retirada
        FROM public.movimientos_contenedores
        WHERE orden_id = p_orden_id
    LOOP
        UPDATE public.saldo_contenedores_clientes
        SET saldo_pendiente = GREATEST(0, saldo_pendiente - v_rec_prev.cantidad_entregada + v_rec_prev.cantidad_retirada),
            updated_at = NOW()
        WHERE cliente_id = v_cliente_id AND contenedor_id = v_rec_prev.contenedor_id;
    END LOOP;

    DELETE FROM public.movimientos_contenedores WHERE orden_id = p_orden_id;

    -- 2. Calcular entregas y retiros por tipo de contenedor asignado
    FOR v_rec_cont IN
        SELECT 
            COALESCE(d.contenedor_id, p.contenedor_id) AS contenedor_id,
            SUM(
                CASE 
                    WHEN COALESCE(d.contenedor_id, p.contenedor_id) IS NOT NULL AND COALESCE(d.cantidad_despachada, 0) > 0 THEN
                        CEIL(COALESCE(d.cantidad_despachada, 0)::numeric / GREATEST(COALESCE(p.unidades_por_contenedor, 1)::numeric, 1))
                    ELSE 0
                END
            )::INT AS total_entregados,
            SUM(COALESCE(d.contenedores_retirados, 0))::INT AS total_retirados
        FROM public.detalle_distribucion d
        LEFT JOIN public.productos p ON p.id = d.producto_id
        WHERE d.orden_id = p_orden_id
          AND COALESCE(d.contenedor_id, p.contenedor_id) IS NOT NULL
        GROUP BY COALESCE(d.contenedor_id, p.contenedor_id)
    LOOP
        v_cant_entregada := v_rec_cont.total_entregados;
        v_cant_retirada := v_rec_cont.total_retirados;

        IF v_cant_entregada > 0 OR v_cant_retirada > 0 THEN
            -- Obtener saldo anterior del cliente para este contenedor
            SELECT COALESCE(saldo_pendiente, 0)
            INTO v_saldo_previo
            FROM public.saldo_contenedores_clientes
            WHERE cliente_id = v_cliente_id AND contenedor_id = v_rec_cont.contenedor_id;

            IF NOT FOUND THEN
                v_saldo_previo := 0;
            END IF;

            v_saldo_nuevo := GREATEST(0, v_saldo_previo + v_cant_entregada - v_cant_retirada);

            -- Registrar movimiento individual
            INSERT INTO public.movimientos_contenedores (
                cliente_id, orden_id, contenedor_id, cantidad_entregada, cantidad_retirada, creado_por
            ) VALUES (
                v_cliente_id, p_orden_id, v_rec_cont.contenedor_id, v_cant_entregada, v_cant_retirada, auth.uid()
            );

            -- Upsert del saldo del cliente
            INSERT INTO public.saldo_contenedores_clientes (
                cliente_id, contenedor_id, saldo_pendiente, updated_at
            ) VALUES (
                v_cliente_id, v_rec_cont.contenedor_id, v_saldo_nuevo, NOW()
            )
            ON CONFLICT (cliente_id, contenedor_id)
            DO UPDATE SET
                saldo_pendiente = EXCLUDED.saldo_pendiente,
                updated_at = NOW();

            -- Construir resumen para el Frontend
            v_contenedores_resumen := v_contenedores_resumen || jsonb_build_object(
                'contenedor_id', v_rec_cont.contenedor_id,
                'saldo_anterior', v_saldo_previo,
                'cantidad_entregada', v_cant_entregada,
                'cantidad_retirada', v_cant_retirada,
                'saldo_actualizado', v_saldo_nuevo
            );
        END IF;
    END LOOP;

    -- Validar si quedan ítems pendientes en la orden
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
            'total_despachado', v_total_despachado,
            'contenedores_resumen', v_contenedores_resumen
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


CREATE OR REPLACE FUNCTION public.solicita_aprobar_radar(
    p_radar_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_despachador_id UUID;
    v_fecha_despacho DATE;
    v_status_radar BOOLEAN;
    v_rec RECORD;
    v_rec_entregados RECORD;
    v_rec_cliente RECORD;
    v_inv_res JSONB;
    v_ordenes_anuladas_count INT := 0;
    v_contenedores_retirados_procesados INT := 0;
    v_contenedores_entregados_procesados INT := 0;
    v_clientes_deshabilitados_count INT := 0;
    v_ordenes_por_liquidar_count INT := 0;
    v_contenedores_entregados INT := 0;
BEGIN
    IF p_radar_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID del radar es obligatorio.'
            )
        );
    END IF;

    -- Verificar existencia del radar y su estado actual
    SELECT despachador_id, fecha_despacho, COALESCE(status_radar, FALSE)
    INTO v_despachador_id, v_fecha_despacho, v_status_radar
    FROM public.radars
    WHERE id = p_radar_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'RADAR_INEXISTENTE',
                'message', 'El radar especificado no existe.'
            )
        );
    END IF;

    IF v_status_radar = TRUE THEN
        RETURN jsonb_build_object(
            'success', TRUE,
            'message', 'El radar ya se encuentra previamente aprobado.',
            'data', jsonb_build_object(
                'radar_id', p_radar_id,
                'status_radar', TRUE
            ),
            'error', NULL
        );
    END IF;

    -- 1. Marcar el radar como aprobado y cerrado (.T.) mediante status_radar = TRUE
    UPDATE public.radars
    SET status_radar = TRUE
    WHERE id = p_radar_id;

    -- Note: El cálculo de contenedores entregados y retirados fue trasladado a registrar_despacho_cliente_radar
    -- para asentar los saldos al momento de confirmar el despacho.
    v_contenedores_entregados_procesados := 0;
    v_contenedores_retirados_procesados := 0;

    -- 2. Devuelve el inventario no despachado del camión al almacén principal
    v_inv_res := public.retorna_inventario_no_despachado_para_almacen(p_radar_id);

    -- 3. Las órdenes en estado 'devuelta' pasan al estado final 'anulada'
    WITH ordenes_devueltas AS (
        UPDATE public.ordenes_distribucion
        SET estado = 'anulada'
        WHERE radar_id = p_radar_id AND estado = 'devuelta'
        RETURNING id
    )
    SELECT COUNT(*) INTO v_ordenes_anuladas_count FROM ordenes_devueltas;

    -- 4. Políticas de crédito desactivadas temporalmente para mantener todos los clientes activos
    v_clientes_deshabilitados_count := 0;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Radar aprobado exitosamente. Saldos de contenedores actualizados al despachar, inventario restituido a almacén y órdenes devueltas anuladas.',
        'data', jsonb_build_object(
            'radar_id', p_radar_id,
            'status_radar', TRUE,
            'contenedores_entregados_procesados', v_contenedores_entregados_procesados,
            'contenedores_retirados_procesados', v_contenedores_retirados_procesados,
            'clientes_deshabilitados_credito', v_clientes_deshabilitados_count,
            'ordenes_anuladas', v_ordenes_anuladas_count,
            'inventario_reintegrado', COALESCE(v_inv_res->'data', '[]'::jsonb)
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

GRANT EXECUTE ON FUNCTION public.solicita_aprobar_radar TO authenticated, service_role;
