CREATE OR REPLACE FUNCTION public.retorna_lista_radars_segun_rango_fechas(
    p_despachador_id UUID DEFAULT NULL,
    p_fecha_inicial DATE DEFAULT NULL,
    p_fecha_limite DATE DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_despachador_id UUID;
    v_resultado JSONB;
BEGIN
    -- Si no se pasa despachador_id, toma el usuario autenticado
    v_despachador_id := COALESCE(p_despachador_id, auth.uid());

    IF v_despachador_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'Se requiere el ID de despachador o estar autenticado.'
            )
        );
    END IF;

    SELECT jsonb_build_object(
        'success', TRUE,
        'data', COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'fecha_despacho', r.fecha_despacho,
                    'id_radar', r.id,
                    'correlativo', r.correlativo,
                    'total_paradas', COALESCE(ord_stats.total_paradas, 0),
                    'items', COALESCE(ord_stats.total_items, 0),
                    'sku', COALESCE(ord_stats.total_sku, 0),
                    'status_radar', COALESCE(r.status_radar, FALSE),
                    'aprobado', COALESCE(r.aprobado, FALSE)
                ) ORDER BY r.fecha_despacho DESC, r.correlativo DESC
            ),
            '[]'::jsonb
        ),
        'error', NULL
    ) INTO v_resultado
    FROM public.radars r
    LEFT JOIN LATERAL (
        SELECT 
            COUNT(DISTINCT o.id) AS total_paradas,
            SUM(COALESCE(d.cantidad_despachada, d.cantidad_solicitada, 0)) AS total_items,
            COUNT(DISTINCT d.producto_id) AS total_sku
        FROM public.ordenes_distribucion o
        LEFT JOIN public.detalle_distribucion d ON d.orden_id = o.id
        WHERE o.radar_id = r.id
    ) ord_stats ON TRUE
    WHERE r.despachador_id = v_despachador_id
      AND (p_fecha_inicial IS NULL OR r.fecha_despacho >= p_fecha_inicial)
      AND (p_fecha_limite IS NULL OR r.fecha_despacho <= p_fecha_limite);

    RETURN v_resultado;

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', FALSE,
        'data', NULL,
        'error', jsonb_build_object(
            'code', SQLSTATE,
            'message', SQLERRM
        )
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.retorna_lista_radars_segun_rango_fechas TO authenticated, service_role;

COMMENT ON FUNCTION public.retorna_lista_radars_segun_rango_fechas(UUID, DATE, DATE) IS 'Retorna la lista de radares asignados a un despachador ordenados por fecha descendente en un rango de fechas con métricas consolidadas (paradas, items, sku).';
