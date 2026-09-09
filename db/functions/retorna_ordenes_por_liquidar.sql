CREATE OR REPLACE FUNCTION public.retorna_ordenes_por_liquidar()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_resultado JSONB;
BEGIN
    SELECT jsonb_build_object(
        'success', TRUE,
        'data', COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'cliente_id', c.id,
                    'razon_social', c.razon_social,
                    'rif_nit', c.rif_nit,
                    'dias_vencidos', (CURRENT_DATE - MIN(od.fecha_despacho::date))::INT,
                    'cant_ordenes', COUNT(od.id),
                    'monto_por_liquidar', SUM(
                        COALESCE(od.subtotal_recaudar, od.subtotal, od.total_recaudar_usd, 0.00) - COALESCE(abonos.total_recaudado_usd, 0.00)
                    )
                ) ORDER BY (CURRENT_DATE - MIN(od.fecha_despacho::date)) DESC
            ),
            '[]'::jsonb
        ),
        'error', NULL
    ) INTO v_resultado
    FROM public.ordenes_distribucion od
    JOIN public.clientes c ON c.id = od.cliente_id
    LEFT JOIN LATERAL (
        SELECT 
            SUM(COALESCE(dro.recaudado, 0.00)) AS total_recaudado_usd
        FROM public.detalle_rendicion_ordenes dro
        JOIN public.rendiciones_cuentas rc ON dro.rendicion_id = rc.id
        WHERE dro.orden_distribucion_id = od.id
          AND rc.estado = 'aprobada'
    ) abonos ON TRUE
    WHERE od.estado = 'por_liquidar'
    GROUP BY c.id, c.razon_social, c.rif_nit;

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

GRANT EXECUTE ON FUNCTION public.retorna_ordenes_por_liquidar TO authenticated, service_role;

COMMENT ON FUNCTION public.retorna_ordenes_por_liquidar() IS 'Retorna el listado de órdenes en estado por_liquidar agrupadas por cliente y ordenadas por días vencidos descendente.';
