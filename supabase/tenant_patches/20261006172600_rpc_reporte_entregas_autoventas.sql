CREATE OR REPLACE FUNCTION public.retorna_reporte_autoventas_entregas_cliente(
    p_camion_id UUID,
    p_fecha DATE DEFAULT CURRENT_DATE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_total_general_usd NUMERIC(14,2) := 0.00;
    v_entregas JSONB;
    v_inventario JSONB;
BEGIN
    IF p_camion_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del camión es requerido.');
    END IF;

    -- Calcular el total general del día para este camión
    SELECT COALESCE(SUM(od.total_recaudar_usd), 0.00)
    INTO v_total_general_usd
    FROM public.ordenes_distribucion od
    WHERE od.camion_id = p_camion_id
      AND od.es_autoventa = TRUE
      AND (od.fecha_despacho AT TIME ZONE 'America/Caracas')::DATE = COALESCE(p_fecha, (CURRENT_TIMESTAMP AT TIME ZONE 'America/Caracas')::DATE)
      AND od.estado != 'anulada';

    -- Calcular el inventario cargado, entregado y devolución
    SELECT jsonb_agg(
        jsonb_build_object(
            'producto_id', p.id,
            'codigo', p.codigo,
            'nombre', p.nombre,
            'cantidad_cargada', COALESCE(im.cantidad_cargada, 0),
            'cantidad_entregada', COALESCE(im.cantidad_entregada, 0),
            'devolucion', GREATEST(0, COALESCE(im.cantidad_cargada, 0) - COALESCE(im.cantidad_entregada, 0))
        ) ORDER BY p.nombre ASC
    ) INTO v_inventario
    FROM public.inventario_movil im
    JOIN public.productos p ON im.producto_id = p.id
    WHERE im.camion_id = p_camion_id;

    -- Construir el JSON de entregas agrupado por cliente
    SELECT jsonb_agg(
        jsonb_build_object(
            'cliente_id', t.cliente_id,
            'razon_social', t.razon_social,
            'rif_nit', t.rif_nit,
            'orden_id', t.orden_id,
            'correlativo', t.correlativo,
            'total_orden_usd', t.total_recaudar_usd,
            'productos', t.productos
        ) ORDER BY t.correlativo ASC
    ) INTO v_entregas
    FROM (
        SELECT 
            c.id AS cliente_id,
            c.razon_social,
            c.rif_nit,
            od.id AS orden_id,
            od.correlativo,
            od.total_recaudar_usd,
            (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'producto_id', p.id,
                        'codigo', p.codigo,
                        'nombre', p.nombre,
                        'cantidad_cargada', odd.cantidad_solicitada,
                        'cantidad_entregada', odd.cantidad_despachada,
                        'devolucion', COALESCE(odd.cantidad_solicitada, 0) - COALESCE(odd.cantidad_despachada, 0),
                        'precio_unitario_usd', odd.valor_unitario_usd,
                        'subtotal_usd', odd.subtotal_recaudar_usd
                    ) ORDER BY p.nombre ASC
                )
                FROM public.detalle_distribucion odd
                JOIN public.productos p ON odd.producto_id = p.id
                WHERE odd.orden_id = od.id
            ) AS productos
        FROM public.ordenes_distribucion od
        JOIN public.clientes c ON od.cliente_id = c.id
        WHERE od.camion_id = p_camion_id
          AND od.es_autoventa = TRUE
          AND (od.fecha_despacho AT TIME ZONE 'America/Caracas')::DATE = COALESCE(p_fecha, (CURRENT_TIMESTAMP AT TIME ZONE 'America/Caracas')::DATE)
          AND od.estado != 'anulada'
    ) t;

    RETURN jsonb_build_object(
        'success', true,
        'data', jsonb_build_object(
            'camion_id', p_camion_id,
            'fecha', COALESCE(p_fecha, CURRENT_DATE),
            'total_general_usd', v_total_general_usd,
            'inventario', COALESCE(v_inventario, '[]'::jsonb),
            'entregas', COALESCE(v_entregas, '[]'::jsonb)
        ),
        'error', NULL
    );
END;
$$;
