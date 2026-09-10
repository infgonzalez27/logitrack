-- Migración: Actualizar RPC solicita_aprobar_radar para carga de contenedores entregados y políticas de crédito por max_facturas_vencidas

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

    -- 2. Cargar en el estado de cuenta del cliente los contenedores ENTREGADOS en el despacho
    -- si el producto tiene un contenedor asignado: CEIL(cantidad_despachada * unidades_por_contenedor)
    FOR v_rec_entregados IN
        SELECT 
            o.cliente_id,
            d.orden_id,
            COALESCE(d.contenedor_id, p.contenedor_id) AS contenedor_id,
            SUM(CEIL(COALESCE(d.cantidad_despachada, 0)::numeric * COALESCE(p.unidades_por_contenedor, 1))) AS total_entregados
        FROM public.ordenes_distribucion o
        JOIN public.detalle_distribucion d ON d.orden_id = o.id
        JOIN public.productos p ON p.id = d.producto_id
        WHERE o.radar_id = p_radar_id
          AND COALESCE(d.cantidad_despachada, 0) > 0
          AND COALESCE(d.contenedor_id, p.contenedor_id) IS NOT NULL
        GROUP BY o.cliente_id, d.orden_id, COALESCE(d.contenedor_id, p.contenedor_id)
    LOOP
        v_contenedores_entregados := v_rec_entregados.total_entregados::INT;
        IF v_contenedores_entregados > 0 THEN
            INSERT INTO public.movimientos_contenedores (
                cliente_id, orden_id, contenedor_id, cantidad_entregada, cantidad_retirada, creado_por
            ) VALUES (
                v_rec_entregados.cliente_id, v_rec_entregados.orden_id, v_rec_entregados.contenedor_id, v_contenedores_entregados, 0, auth.uid()
            );

            INSERT INTO public.saldo_contenedores_clientes (
                cliente_id, contenedor_id, saldo_pendiente, updated_at
            ) VALUES (
                v_rec_entregados.cliente_id, v_rec_entregados.contenedor_id, v_contenedores_entregados, NOW()
            )
            ON CONFLICT (cliente_id, contenedor_id)
            DO UPDATE SET 
                saldo_pendiente = public.saldo_contenedores_clientes.saldo_pendiente + EXCLUDED.saldo_pendiente,
                updated_at = NOW();

            v_contenedores_entregados_procesados := v_contenedores_entregados_procesados + v_contenedores_entregados;
        END IF;
    END LOOP;

    -- 3. Procesar movimiento de envases RETIRADOS/DEVUELTOS por clientes (contenedores_retirados)
    FOR v_rec IN
        SELECT 
            o.cliente_id,
            d.orden_id,
            COALESCE(d.contenedor_id, p.contenedor_id) AS contenedor_id,
            SUM(COALESCE(d.contenedores_retirados, 0)) AS total_retirados
        FROM public.ordenes_distribucion o
        JOIN public.detalle_distribucion d ON d.orden_id = o.id
        LEFT JOIN public.productos p ON p.id = d.producto_id
        WHERE o.radar_id = p_radar_id
          AND COALESCE(d.contenedores_retirados, 0) > 0
        GROUP BY o.cliente_id, d.orden_id, COALESCE(d.contenedor_id, p.contenedor_id)
    LOOP
        IF v_rec.contenedor_id IS NOT NULL THEN
            INSERT INTO public.movimientos_contenedores (
                cliente_id, orden_id, contenedor_id, cantidad_entregada, cantidad_retirada, creado_por
            ) VALUES (
                v_rec.cliente_id, v_rec.orden_id, v_rec.contenedor_id, 0, v_rec.total_retirados, auth.uid()
            );

            INSERT INTO public.saldo_contenedores_clientes (
                cliente_id, contenedor_id, saldo_pendiente, updated_at
            ) VALUES (
                v_rec.cliente_id, v_rec.contenedor_id, 0, NOW()
            )
            ON CONFLICT (cliente_id, contenedor_id)
            DO UPDATE SET 
                saldo_pendiente = GREATEST(0, public.saldo_contenedores_clientes.saldo_pendiente - v_rec.total_retirados),
                updated_at = NOW();

            v_contenedores_retirados_procesados := v_contenedores_retirados_procesados + v_rec.total_retirados;
        END IF;
    END LOOP;

    -- 4. Devuelve el inventario no despachado del camión al almacén principal
    v_inv_res := public.retorna_inventario_no_despachado_para_almacen(p_radar_id);

    -- 5. Las órdenes en estado 'devuelta' pasan al estado final 'anulada'
    WITH ordenes_devueltas AS (
        UPDATE public.ordenes_distribucion
        SET estado = 'anulada'
        WHERE radar_id = p_radar_id AND estado = 'devuelta'
        RETURNING id
    )
    SELECT COUNT(*) INTO v_ordenes_anuladas_count FROM ordenes_devueltas;

    -- 6. Evaluar políticas de crédito respecto a clientes.max_facturas_vencidas
    -- Para cada cliente en el radar, si sus órdenes por liquidar >= max_facturas_vencidas (y max_facturas_vencidas > 0)
    -- deshabilitar permiso_despacho_manual = FALSE
    FOR v_rec_cliente IN
        SELECT DISTINCT c.id AS cliente_id, COALESCE(c.max_facturas_vencidas, 0) AS max_facturas_vencidas
        FROM public.ordenes_distribucion o
        JOIN public.clientes c ON c.id = o.cliente_id
        WHERE o.radar_id = p_radar_id
          AND COALESCE(c.max_facturas_vencidas, 0) > 0
    LOOP
        SELECT COUNT(*) INTO v_ordenes_por_liquidar_count
        FROM public.ordenes_distribucion
        WHERE cliente_id = v_rec_cliente.cliente_id
          AND estado = 'por_liquidar';

        IF v_ordenes_por_liquidar_count >= v_rec_cliente.max_facturas_vencidas THEN
            UPDATE public.clientes
            SET permiso_despacho_manual = FALSE
            WHERE id = v_rec_cliente.cliente_id;

            v_clientes_deshabilitados_count := v_clientes_deshabilitados_count + 1;
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Radar aprobado exitosamente. Saldos de contenedores actualizados, políticas de crédito evaluadas, inventario restituido a almacén y órdenes devueltas anuladas.',
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

COMMENT ON FUNCTION public.solicita_aprobar_radar(UUID) IS 'Aprueba el radar (status_radar = TRUE), carga envases entregados/retirados a saldos de clientes, evalúa políticas de crédito (max_facturas_vencidas), reingresa inventario a almacén y anula órdenes devueltas.';
