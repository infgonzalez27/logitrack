CREATE OR REPLACE FUNCTION public.retorna_ordenes_distribucion_segun_estado(
    p_estado TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_is_vendedor BOOLEAN := FALSE;
    v_is_gerente_admin BOOLEAN := FALSE;
    v_ordenes JSON;
BEGIN
    IF p_estado IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El estado de la orden es requerido.',
                'details', NULL
            )
        );
    END IF;

    -- Evaluar rol del usuario
    v_is_gerente_admin := public.user_has_role(ARRAY['admin', 'gerente', 'despachador']);
    v_is_vendedor := public.user_has_role(ARRAY['vendedor']);

    SELECT COALESCE(json_agg(
        json_build_object(
            'id', o.id,
            'correlativo', o.correlativo,
            'cliente_id', o.cliente_id,
            'cliente_razon_social', c.razon_social,
            'cliente_vendedor_id', c.vendedor_id,
            'camion_id', o.camion_id,
            'chofer_id', o.chofer_id,
            'estado', o.estado,
            'fecha_despacho', o.fecha_despacho,
            'peso_total_calculado', o.peso_total_calculado,
            'factura_origen_numero', o.factura_origen_numero,
            'tasa_cambio', o.tasa_cambio,
            'total_recaudar_bs', o.total_recaudar_bs,
            'total_recaudar_usd', o.total_recaudar_usd,
            'creado_por', o.creado_por,
            'created_at', o.created_at
        ) ORDER BY o.correlativo DESC
    ), '[]'::json)
    INTO v_ordenes
    FROM public.ordenes_distribucion o
    LEFT JOIN public.clientes c ON c.id = o.cliente_id
    WHERE o.estado = p_estado
      AND (
          v_is_gerente_admin 
          OR (v_is_vendedor AND (c.vendedor_id = v_user_id OR o.creado_por = v_user_id))
      );

    RETURN json_build_object(
        'success', true,
        'data', v_ordenes,
        'error', NULL
    );

EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object(
        'success', false,
        'data', NULL,
        'error', json_build_object(
            'code', 'SQL_ERROR',
            'message', SQLERRM,
            'details', NULL
        )
    );
END;
$$;
