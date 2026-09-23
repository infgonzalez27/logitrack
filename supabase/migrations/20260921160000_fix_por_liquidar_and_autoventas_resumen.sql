-- Fix nested aggregates in retorna_ordenes_por_liquidar
-- and productos.codigo -> codigo_producto in retorna_resumen_autoventas_jornada

CREATE OR REPLACE FUNCTION public.retorna_ordenes_por_liquidar()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_data JSONB;
BEGIN
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'cliente_id', sub.cliente_id,
                'razon_social', sub.razon_social,
                'rif_nit', sub.rif_nit,
                'dias_vencidos', sub.dias_vencidos,
                'cant_ordenes', sub.cant_ordenes,
                'monto_por_liquidar', sub.monto_por_liquidar
            )
            ORDER BY sub.dias_vencidos DESC
        ),
        '[]'::jsonb
    )
    INTO v_data
    FROM (
        SELECT
            c.id AS cliente_id,
            c.razon_social,
            c.rif_nit,
            (CURRENT_DATE - MIN(od.fecha_despacho::date))::INT AS dias_vencidos,
            COUNT(od.id)::INT AS cant_ordenes,
            SUM(
                COALESCE(od.total_recaudar_usd, 0.00)
                - COALESCE(abonos.total_recaudado_usd, 0.00)
            ) AS monto_por_liquidar
        FROM public.ordenes_distribucion od
        JOIN public.clientes c ON c.id = od.cliente_id
        LEFT JOIN LATERAL (
            SELECT SUM(COALESCE(dro.recaudado, 0.00)) AS total_recaudado_usd
            FROM public.detalle_rendicion_ordenes dro
            JOIN public.rendiciones_cuentas rc ON dro.rendicion_id = rc.id
            WHERE dro.orden_distribucion_id = od.id
              AND rc.estado = 'aprobada'
        ) abonos ON TRUE
        WHERE od.estado = 'por_liquidar'
        GROUP BY c.id, c.razon_social, c.rif_nit
    ) sub;

    RETURN jsonb_build_object(
        'success', TRUE,
        'data', v_data,
        'error', NULL
    );

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
$function$;

CREATE OR REPLACE FUNCTION public.retorna_resumen_autoventas_jornada(
    p_camion_id UUID,
    p_fecha DATE DEFAULT CURRENT_DATE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_inventario_movil JSONB;
    v_ventas_jornada JSONB;
    v_total_ordenes INT := 0;
    v_total_facturado_usd NUMERIC(14,2) := 0.00;
    v_total_facturado_bs NUMERIC(14,2) := 0.00;
BEGIN
    IF p_camion_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del camión es requerido.');
    END IF;

    SELECT jsonb_agg(
        jsonb_build_object(
            'producto_id', p.id,
            'codigo', p.codigo_producto,
            'nombre', p.nombre,
            'cantidad_cargada', COALESCE(im.cantidad_cargada, 0),
            'cantidad_entregada', COALESCE(im.cantidad_entregada, 0),
            'cantidad_disponible', GREATEST(0, COALESCE(im.cantidad_cargada, 0) - COALESCE(im.cantidad_entregada, 0))
        ) ORDER BY p.nombre ASC
    ) INTO v_inventario_movil
    FROM public.inventario_movil im
    JOIN public.productos p ON im.producto_id = p.id
    WHERE im.camion_id = p_camion_id;

    SELECT
        COUNT(*)::INT,
        COALESCE(SUM(total_recaudar_usd), 0.00),
        COALESCE(SUM(total_recaudar_bs), 0.00)
    INTO v_total_ordenes, v_total_facturado_usd, v_total_facturado_bs
    FROM public.ordenes_distribucion
    WHERE camion_id = p_camion_id
      AND es_autoventa = TRUE
      AND DATE(created_at) = COALESCE(p_fecha, CURRENT_DATE);

    SELECT jsonb_agg(
        jsonb_build_object(
            'orden_id', od.id,
            'correlativo', od.correlativo,
            'factura_origen_numero', od.factura_origen_numero,
            'cliente_nombre', c.razon_social,
            'estado', od.estado,
            'total_recaudar_usd', od.total_recaudar_usd,
            'total_recaudar_bs', od.total_recaudar_bs,
            'created_at', od.created_at
        ) ORDER BY od.created_at DESC
    ) INTO v_ventas_jornada
    FROM public.ordenes_distribucion od
    JOIN public.clientes c ON od.cliente_id = c.id
    WHERE od.camion_id = p_camion_id
      AND od.es_autoventa = TRUE
      AND DATE(od.created_at) = COALESCE(p_fecha, CURRENT_DATE);

    RETURN jsonb_build_object(
        'success', true,
        'data', jsonb_build_object(
            'camion_id', p_camion_id,
            'fecha', COALESCE(p_fecha, CURRENT_DATE),
            'total_ordenes_autoventa', v_total_ordenes,
            'total_facturado_usd', v_total_facturado_usd,
            'total_facturado_bs', v_total_facturado_bs,
            'inventario_movil', COALESCE(v_inventario_movil, '[]'::jsonb),
            'ventas', COALESCE(v_ventas_jornada, '[]'::jsonb)
        ),
        'error', NULL
    );
END;
$$;
