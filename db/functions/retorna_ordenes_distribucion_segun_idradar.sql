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
