CREATE OR REPLACE FUNCTION public.solicita_editar_o_sincronizar_radar(
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
    v_carga_inventario BOOLEAN;
    v_ordenes_excluidas UUID[];
    v_correlativo INT;
    v_tot_solicitada NUMERIC(10,0);
    v_tot_despachada NUMERIC(10,0);
    v_tot_retirados NUMERIC(10,0);
    v_total_ordenes INT;
    v_desvinculadas INT := 0;
    v_vinculadas INT := 0;
BEGIN
    -- 1. Validaciones básicas
    IF p_radar_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID del radar es obligatorio.'
            )
        );
    END IF;

    -- Obtener datos del radar
    SELECT despachador_id, fecha_despacho, correlativo,
           COALESCE(status_radar, FALSE), COALESCE(carga_inventario_movil, FALSE),
           COALESCE(ordenes_excluidas, '{}'::UUID[])
    INTO v_despachador_id, v_fecha_despacho, v_correlativo, v_status_radar, v_carga_inventario, v_ordenes_excluidas
    FROM public.radars
    WHERE id = p_radar_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'RADAR_INEXISTENTE',
                'message', 'El radar especificado no existe.'
            )
        );
    END IF;

    -- Validar bloqueos
    IF v_status_radar = TRUE THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'RADAR_APROBADO_BLOQUEADO',
                'message', 'El radar especificado ya ha sido aprobado por la Gerencia y no se puede modificar.'
            )
        );
    END IF;

    IF v_carga_inventario = TRUE THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'RADAR_INVENTARIO_CARGADO',
                'message', 'Para modificar el Radar debe reversar el inventario movil al almacén'
            )
        );
    END IF;

    -- Fase 1: Desvincular las órdenes de distribución actualmente vinculadas al radar en estado editable ('aprobada') o anuladas
    UPDATE public.ordenes_distribucion
    SET radar_id = NULL
    WHERE radar_id = p_radar_id
      AND estado IN ('aprobada', 'anulada');

    GET DIAGNOSTICS v_desvinculadas = ROW_COUNT;

    -- Fase 2: Volver a vincular las órdenes aprobadas con fecha <= v_fecha_despacho (o en ruta de la fecha exacta)
    -- respetando las órdenes excluidas manualmente de este radar (Comportamiento A)
    UPDATE public.ordenes_distribucion o
    SET radar_id = p_radar_id
    FROM public.clientes c
    WHERE o.cliente_id = c.id
      AND COALESCE(o.despachador_id, c.despachador_id) = v_despachador_id
      AND (
          (o.estado = 'aprobada' AND o.fecha_despacho::date <= v_fecha_despacho)
          OR
          (o.estado IN ('en_transito', 'por_liquidar', 'liquidada', 'devuelta') AND o.fecha_despacho::date = v_fecha_despacho)
      )
      AND (o.radar_id IS NULL OR o.radar_id = p_radar_id)
      AND COALESCE(o.es_autoventa, FALSE) = FALSE
      AND NOT (o.id = ANY(v_ordenes_excluidas));

    GET DIAGNOSTICS v_vinculadas = ROW_COUNT;

    -- Recalcular totales consolidado del radar
    SELECT 
        COALESCE(SUM(d.cantidad_solicitada), 0),
        COALESCE(SUM(d.cantidad_despachada), 0),
        COALESCE(SUM(d.contenedores_retirados), 0),
        COUNT(DISTINCT o.id)
    INTO v_tot_solicitada, v_tot_despachada, v_tot_retirados, v_total_ordenes
    FROM public.ordenes_distribucion o
    JOIN public.detalle_distribucion d ON d.orden_id = o.id
    WHERE o.radar_id = p_radar_id
      AND o.estado <> 'anulada';

    UPDATE public.radars
    SET total_cantidad_solicitada = v_tot_solicitada,
        total_cantidad_despachada = v_tot_despachada,
        total_contenedores_retirados = v_tot_retirados
    WHERE id = p_radar_id;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Radar re-sincronizado y actualizado exitosamente.',
        'data', jsonb_build_object(
            'radar_id', p_radar_id,
            'correlativo', v_correlativo,
            'despachador_id', v_despachador_id,
            'fecha_despacho', v_fecha_despacho,
            'ordenes_desvinculadas', v_desvinculadas,
            'ordenes_vinculadas', v_total_ordenes,
            'total_cantidad_solicitada', v_tot_solicitada,
            'total_cantidad_despachada', v_tot_despachada,
            'total_contenedores_retirados', v_tot_retirados
        ),
        'error', NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'SQL_ERROR',
                'message', SQLERRM,
                'details', 'SQLSTATE: ' || SQLSTATE
            )
        );
END;
$$;

GRANT EXECUTE ON FUNCTION public.solicita_editar_o_sincronizar_radar(UUID) TO authenticated, service_role;
