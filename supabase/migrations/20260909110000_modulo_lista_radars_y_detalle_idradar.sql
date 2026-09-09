-- Migración: Módulo de Consulta de Lista de Radares por Rango de Fecha y Detalle de Órdenes por Radar ID

-- =============================================================================
-- 1. RPC: retorna_lista_radars_segun_rango_fechas
-- =============================================================================
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


-- =============================================================================
-- 2. RPC: retorna_ordenes_distribucion_segun_idradar
-- =============================================================================
CREATE OR REPLACE FUNCTION public.retorna_ordenes_distribucion_segun_idradar(
    p_radar_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_resultado JSONB;
BEGIN
    IF p_radar_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID del radar es requerido.'
            )
        );
    END IF;

    SELECT jsonb_build_object(
        'success', TRUE,
        'data', COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'id_orden_distribucion', o.id,
                    'correlativo', o.correlativo,
                    'ruta', COALESCE(rut.nombre_ruta, 'Sin Ruta'),
                    'razon_social', c.razon_social,
                    'direccion_fiscal', c.direccion_fiscal,
                    'items', COALESCE(det_stats.total_items, 0),
                    'sku', COALESCE(det_stats.total_sku, 0),
                    'contenedores_retirados', COALESCE(det_stats.total_contenedores_retirados, 0)
                ) ORDER BY o.correlativo ASC
            ),
            '[]'::jsonb
        ),
        'error', NULL
    ) INTO v_resultado
    FROM public.ordenes_distribucion o
    LEFT JOIN public.clientes c ON c.id = o.cliente_id
    LEFT JOIN public.rutas rut ON c.id_ruta = rut.id_ruta
    LEFT JOIN LATERAL (
        SELECT 
            SUM(COALESCE(d.cantidad_despachada, d.cantidad_solicitada, 0)) AS total_items,
            COUNT(DISTINCT d.producto_id) AS total_sku,
            SUM(COALESCE(d.contenedores_retirados, 0)) AS total_contenedores_retirados
        FROM public.detalle_distribucion d
        WHERE d.orden_id = o.id
    ) det_stats ON TRUE
    WHERE o.radar_id = p_radar_id;

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

GRANT EXECUTE ON FUNCTION public.retorna_ordenes_distribucion_segun_idradar TO authenticated, service_role;

COMMENT ON FUNCTION public.retorna_ordenes_distribucion_segun_idradar(UUID) IS 'Retorna el detalle resumido de las órdenes de distribución vinculadas a un id_radar específico.';
