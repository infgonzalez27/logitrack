CREATE OR REPLACE FUNCTION public.reporte_recaudaciones_gerenciales(
    p_fecha_desde DATE DEFAULT NULL,
    p_fecha_hasta DATE DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_data JSON;
    v_desde TIMESTAMP WITH TIME ZONE;
    v_hasta TIMESTAMP WITH TIME ZONE;
BEGIN
    -- Configurar fechas por defecto si no son pasadas (mes actual)
    v_desde := COALESCE(p_fecha_desde::TIMESTAMP WITH TIME ZONE, date_trunc('month', CURRENT_DATE));
    v_hasta := COALESCE((p_fecha_hasta + INTERVAL '1 day - 1 microsecond')::TIMESTAMP WITH TIME ZONE, CURRENT_TIMESTAMP);

    SELECT json_agg(
        json_build_object(
            'rendicion_id', rc.id,
            'fecha_rendicion', rc.fecha_rendicion,
            'tasa_cambio', COALESCE(rc.tasa_cambio, 1.0000),
            'cliente_id', rc.cliente_id,
            'cliente_nombre', c.razon_social,
            'cliente_rif', c.rif_nit,
            'estado', rc.estado,
            'total_efectivo_recaudado', rc.total_efectivo_recaudado,
            'total_transferencias_recaudado', rc.total_transferencias_recaudado,
            'total_recaudado_usd', COALESCE(rc.total_recaudado_usd, 0.00),
            'total_recaudado_bs', COALESCE(rc.total_recaudado_bs, 0.00),
            'observaciones', rc.observaciones,
            'detalle_fpagos', COALESCE(fpagos_agg.fpagos, '[]'::json),
            'detalle_ordenes', COALESCE(ordenes_agg.ordenes, '[]'::json)
        ) ORDER BY rc.fecha_rendicion DESC
    ) INTO v_data
    FROM public.rendiciones_cuentas rc
    JOIN public.clientes c ON rc.cliente_id = c.id
    LEFT JOIN LATERAL (
        SELECT json_agg(
            json_build_object(
                'fpago_id', dfp.fpago_id,
                'concepto', fp.fpago_concepto,
                'monto', dfp.monto,
                'monto_bs', COALESCE(dfp.monto_bs, 0.00),
                'monto_usd', COALESCE(dfp.monto_usd, dfp.monto, 0.00),
                'cuenta_bancaria_id', dfp.cuenta_bancaria_id,
                'entidad_bancaria', cbe.entidad_bancaria,
                'cuenta_bancaria', COALESCE(cbe.cuenta_bancaria, dfp.cuenta_bancaria),
                'referencia_bancaria', dfp.referencia_bancaria,
                'capture_url', dfp.capture_url
            )
        ) AS fpagos
        FROM public.detalle_rendicion_fpagos dfp
        LEFT JOIN public.fpagos fp ON dfp.fpago_id = fp.fpago_id
        LEFT JOIN public.cuentas_bancarias_empresa cbe ON dfp.cuenta_bancaria_id = cbe.id
        WHERE dfp.rendicion_id = rc.id
    ) fpagos_agg ON TRUE
    LEFT JOIN LATERAL (
        SELECT json_agg(
            json_build_object(
                'orden_id', dro.orden_distribucion_id,
                'correlativo', od.correlativo,
                'recaudado', dro.recaudado,
                'recaudado_bs', COALESCE(dro.recaudado_bs, 0.00)
            )
        ) AS ordenes
        FROM public.detalle_rendicion_ordenes dro
        LEFT JOIN public.ordenes_distribucion od ON dro.orden_distribucion_id = od.id
        WHERE dro.rendicion_id = rc.id
    ) ordenes_agg ON TRUE
    WHERE rc.fecha_rendicion >= v_desde
      AND rc.fecha_rendicion <= v_hasta;

    RETURN json_build_object(
        'success', true,
        'data', COALESCE(v_data, '[]'::json),
        'error', NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'SQL_ERROR',
                'message', SQLERRM,
                'details', 'SQLSTATE: ' || SQLSTATE
            )
        );
END;
$$;
