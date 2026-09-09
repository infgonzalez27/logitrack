-- Migración: Corrección de columnas de totalización en la cabecera ordenes_distribucion (total_recaudar_usd)

-- =============================================================================
-- 1. RPC: retorna_ordenes_por_liquidar
-- =============================================================================
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
                        COALESCE(od.total_recaudar_usd, 0.00) - COALESCE(abonos.total_recaudado_usd, 0.00)
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


-- =============================================================================
-- 2. RPC: solicita_abonos_orden_distribucion
-- =============================================================================
CREATE OR REPLACE FUNCTION public.solicita_abonos_orden_distribucion(
    p_cliente_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_saldo_favor NUMERIC(12, 2) := 0.00;
    v_tasa_oficial NUMERIC(10, 4) := 1.0000;
    v_ordenes JSON;
BEGIN
    IF p_cliente_id IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID de cliente es requerido.'
            )
        );
    END IF;

    SELECT COALESCE(saldo_favor, 0.00) INTO v_saldo_favor
    FROM public.clientes
    WHERE id = p_cliente_id;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'CLIENTE_INEXISTENTE',
                'message', 'El cliente especificado no existe.'
            )
        );
    END IF;

    SELECT COALESCE(tasa_cambio, 1.0000) INTO v_tasa_oficial
    FROM public.tasa_cambio
    ORDER BY fecha_tasa DESC, created_at DESC
    LIMIT 1;

    SELECT json_agg(
        json_build_object(
            'orden_id', od.id,
            'correlativo', od.correlativo,
            'fecha_despacho', od.fecha_despacho,
            'tasa_orden', COALESCE(od.tasa_cambio, v_tasa_oficial),
            'monto_total_orden', COALESCE(od.total_recaudar_usd, 0.00),
            'monto_total_orden_bs', COALESCE(od.total_recaudar_bs, (COALESCE(od.total_recaudar_usd, 0.00) * COALESCE(od.tasa_cambio, v_tasa_oficial)), 0.00),
            'abonos_acumulados', COALESCE(abonos.total_recaudado_usd, 0.00),
            'abonos_acumulados_bs', COALESCE(abonos.total_recaudado_bs, 0.00),
            'saldo_pendiente', COALESCE(od.total_recaudar_usd, 0.00) - COALESCE(abonos.total_recaudado_usd, 0.00),
            'saldo_pendiente_bs', COALESCE(od.total_recaudar_bs, (COALESCE(od.total_recaudar_usd, 0.00) * COALESCE(od.tasa_cambio, v_tasa_oficial)), 0.00) - COALESCE(abonos.total_recaudado_bs, 0.00)
        ) ORDER BY od.created_at ASC
    ) INTO v_ordenes
    FROM public.ordenes_distribucion od
    LEFT JOIN LATERAL (
        SELECT 
            SUM(COALESCE(dro.recaudado, 0.00)) AS total_recaudado_usd,
            SUM(COALESCE(dro.recaudado_bs, (COALESCE(dro.recaudado, 0.00) * COALESCE(rc.tasa_cambio, v_tasa_oficial)), 0.00)) AS total_recaudado_bs
        FROM public.detalle_rendicion_ordenes dro
        JOIN public.rendiciones_cuentas rc ON dro.rendicion_id = rc.id
        WHERE dro.orden_distribucion_id = od.id
          AND rc.estado = 'aprobada'
    ) abonos ON TRUE
    WHERE od.cliente_id = p_cliente_id
      AND od.estado = 'por_liquidar';

    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'cliente_id', p_cliente_id,
            'saldo_favor', v_saldo_favor,
            'saldo_favor_bs', (v_saldo_favor * v_tasa_oficial),
            'tasa_oficial_actual', v_tasa_oficial,
            'ordenes', COALESCE(v_ordenes, '[]'::json)
        ),
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


-- =============================================================================
-- 3. RPC: liquidar_orden_distribucion
-- =============================================================================
CREATE OR REPLACE FUNCTION public.liquidar_orden_distribucion(
    p_orden_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_estado_orden TEXT;
    v_cliente_id UUID;
    v_camion_id UUID;
    v_subtotal_recaudar NUMERIC(12, 2) := 0.00;
    v_total_abonos_aprobados NUMERIC(12, 2) := 0.00;
BEGIN
    IF p_orden_id IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID de la orden es requerido.'
            )
        );
    END IF;

    SELECT estado, cliente_id, camion_id, COALESCE(total_recaudar_usd, 0.00)
    INTO v_estado_orden, v_cliente_id, v_camion_id, v_subtotal_recaudar
    FROM public.ordenes_distribucion
    WHERE id = p_orden_id;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'ORDEN_INEXISTENTE',
                'message', 'La orden de distribución especificada no existe.'
            )
        );
    END IF;

    IF v_estado_orden != 'por_liquidar' THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo se pueden evaluar o liquidar financieramente órdenes en estado por_liquidar.'
            )
        );
    END IF;

    SELECT COALESCE(SUM(dro.recaudado), 0.00)
    INTO v_total_abonos_aprobados
    FROM public.detalle_rendicion_ordenes dro
    JOIN public.rendiciones_cuentas rc ON dro.rendicion_id = rc.id
    WHERE dro.orden_distribucion_id = p_orden_id
      AND rc.estado = 'aprobada';

    IF v_total_abonos_aprobados >= v_subtotal_recaudar THEN
        IF v_camion_id IS NOT NULL THEN
            UPDATE public.camiones SET estado = 'disponible' WHERE id = v_camion_id;
        END IF;

        UPDATE public.ordenes_distribucion 
        SET estado = 'liquidada' 
        WHERE id = p_orden_id;

        RETURN json_build_object(
            'success', true,
            'data', json_build_object(
                'orden_id', p_orden_id,
                'nuevo_estado', 'liquidada',
                'total_recaudado', v_total_abonos_aprobados,
                'subtotal_recaudar', v_subtotal_recaudar
            ),
            'error', NULL
        );
    ELSE
        RETURN json_build_object(
            'success', true,
            'data', json_build_object(
                'orden_id', p_orden_id,
                'nuevo_estado', 'por_liquidar',
                'total_recaudado', v_total_abonos_aprobados,
                'subtotal_recaudar', v_subtotal_recaudar,
                'saldo_pendiente', (v_subtotal_recaudar - v_total_abonos_aprobados)
            ),
            'error', NULL
        );
    END IF;

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
