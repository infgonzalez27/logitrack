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
    v_inv_res JSONB;
    v_ordenes_anuladas_count INT := 0;
    v_ordenes_reprogramadas_count INT := 0;
    v_contenedores_retirados_procesados INT := 0;
    v_contenedores_entregados_procesados INT := 0;
    v_clientes_deshabilitados_count INT := 0;
    v_tot_solicitada NUMERIC(10,0);
    v_tot_despachada NUMERIC(10,0);
    v_tot_retirados NUMERIC(10,0);
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

    -- 4. Las órdenes que NO pudieron ser despachadas (quedaron en 'aprobada' o 'en_transito'
    --    con todas sus líneas pendientes) vuelven a estado 'aprobada' y se desvinculan (radar_id = NULL)
    UPDATE public.detalle_distribucion dd
    SET cantidad_despachada = 0,
        estado_entrega = 'pendiente',
        motivo_rechazo = NULL
    FROM public.ordenes_distribucion o
    WHERE dd.orden_id = o.id
      AND o.radar_id = p_radar_id
      AND o.estado IN ('aprobada', 'en_transito')
      AND NOT EXISTS (
          SELECT 1
          FROM public.detalle_distribucion dd2
          WHERE dd2.orden_id = o.id
            AND COALESCE(dd2.estado_entrega, 'pendiente') <> 'pendiente'
      );

    WITH ordenes_no_despachadas AS (
        UPDATE public.ordenes_distribucion o
        SET estado = 'aprobada',
            radar_id = NULL
        WHERE o.radar_id = p_radar_id
          AND o.estado IN ('aprobada', 'en_transito')
          AND NOT EXISTS (
              SELECT 1
              FROM public.detalle_distribucion dd2
              WHERE dd2.orden_id = o.id
                AND COALESCE(dd2.estado_entrega, 'pendiente') <> 'pendiente'
          )
        RETURNING o.id
    )
    SELECT COUNT(*) INTO v_ordenes_reprogramadas_count FROM ordenes_no_despachadas;

    -- 5. Recalcular totales finales del radar cerrado
    SELECT 
        COALESCE(SUM(d.cantidad_solicitada), 0),
        COALESCE(SUM(CASE WHEN COALESCE(d.estado_entrega, 'pendiente') <> 'pendiente' THEN COALESCE(d.cantidad_despachada, 0) ELSE 0 END), 0),
        COALESCE(SUM(d.contenedores_retirados), 0)
    INTO v_tot_solicitada, v_tot_despachada, v_tot_retirados
    FROM public.ordenes_distribucion o
    JOIN public.detalle_distribucion d ON d.orden_id = o.id
    WHERE o.radar_id = p_radar_id
      AND o.estado <> 'anulada';

    UPDATE public.radars
    SET total_cantidad_solicitada = v_tot_solicitada,
        total_cantidad_despachada = v_tot_despachada,
        total_contenedores_retirados = v_tot_retirados
    WHERE id = p_radar_id;

    v_clientes_deshabilitados_count := 0;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Radar aprobado exitosamente. Inventario sobrante restituido al almacén, órdenes devueltas anuladas y órdenes no despachadas liberadas como aprobadas.',
        'data', jsonb_build_object(
            'radar_id', p_radar_id,
            'status_radar', TRUE,
            'contenedores_entregados_procesados', v_contenedores_entregados_procesados,
            'contenedores_retirados_procesados', v_contenedores_retirados_procesados,
            'clientes_deshabilitados_credito', v_clientes_deshabilitados_count,
            'ordenes_anuladas', v_ordenes_anuladas_count,
            'ordenes_reprogramadas', v_ordenes_reprogramadas_count,
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

COMMENT ON FUNCTION public.solicita_aprobar_radar(UUID) IS 'Aprueba el radar (status_radar = TRUE), reingresa inventario no despachado a almacén, anula órdenes devueltas y libera órdenes no despachadas como aprobadas.';
