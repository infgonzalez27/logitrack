-- Migraci├│n: M├│dulo de Reporte de Formas de Pago por Rango de Fechas (Rendici├│n de Cuentas)

-- 1. Agregar columna es_bancario a la tabla public.fpagos
ALTER TABLE public.fpagos 
ADD COLUMN IF NOT EXISTS es_bancario BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN public.fpagos.es_bancario IS 'Indica si la forma de pago corresponde a una transacci├│n bancaria/electr├│nica (Pago M├│vil, Transferencia, Zelle, Binance, etc.)';

-- 2. Marcar como bancarias/electr├│nicas las formas de pago correspondientes
UPDATE public.fpagos
SET es_bancario = TRUE
WHERE fpago_id IN (
    '1a5b84c8-47bc-4ee0-880c-7833215be11b', -- Pago movil
    '2b6c95d9-58cd-4ff1-991d-8944326cf22c', -- Transferencia
    '5e9fc80c-8bef-4224-cc4f-bc77659f255f', -- ZELLE
    '6fa0d91d-9c00-4335-dd5f-cd88760a366a'  -- BINANCE
) OR fpago_concepto ILIKE '%pago%movil%'
  OR fpago_concepto ILIKE '%transferencia%'
  OR fpago_concepto ILIKE '%zelle%'
  OR fpago_concepto ILIKE '%binance%';

-- 3. Stored Procedure: reporte_formas_pago_rendicion
CREATE OR REPLACE FUNCTION public.reporte_formas_pago_rendicion(
    p_fecha_desde DATE DEFAULT NULL,
    p_fecha_hasta DATE DEFAULT NULL,
    p_solo_bancarios BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_fecha_desde DATE;
    v_fecha_hasta DATE;
    v_movimientos JSONB;
    v_total_registros INT := 0;
    v_monto_total_bs NUMERIC(14,2) := 0.00;
    v_monto_total_usd NUMERIC(14,2) := 0.00;
BEGIN
    -- Determinar rango de fechas por defecto (mes actual si no se proporciona)
    v_fecha_desde := COALESCE(p_fecha_desde, date_trunc('month', CURRENT_DATE)::date);
    v_fecha_hasta := COALESCE(p_fecha_hasta, CURRENT_DATE);

    -- Consultar movimientos de detalle_rendicion_fpagos
    SELECT 
        COUNT(*)::INT,
        COALESCE(SUM(dfp.monto_bs), 0.00),
        COALESCE(SUM(dfp.monto_usd), 0.00)
    INTO v_total_registros, v_monto_total_bs, v_monto_total_usd
    FROM public.detalle_rendicion_fpagos dfp
    JOIN public.rendiciones_cuentas rc ON dfp.rendicion_id = rc.id
    JOIN public.fpagos fp ON dfp.fpago_id = fp.fpago_id
    WHERE rc.fecha_rendicion::date >= v_fecha_desde
      AND rc.fecha_rendicion::date <= v_fecha_hasta
      AND rc.estado = 'aprobada'
      AND (p_solo_bancarios = FALSE OR fp.es_bancario = TRUE);

    -- Construir la lista detallada de movimientos
    SELECT jsonb_agg(
        jsonb_build_object(
            'rendicion_id', rc.id,
            'fecha_rendicion', rc.fecha_rendicion,
            'tasa_cambio', rc.tasa_cambio,
            'cliente_id', c.id,
            'cliente_nombre', c.razon_social,
            'cliente_rif', c.rif_nit,
            'fpago_id', fp.fpago_id,
            'fpago_concepto', fp.fpago_concepto,
            'es_bancario', fp.es_bancario,
            'referencia_bancaria', dfp.referencia_bancaria,
            'cuenta_bancaria', dfp.cuenta_bancaria,
            'capture_url', dfp.capture_url,
            'monto_bs', COALESCE(dfp.monto_bs, (dfp.monto_usd * rc.tasa_cambio)),
            'monto_usd', dfp.monto_usd
        ) ORDER BY rc.fecha_rendicion DESC, dfp.id DESC
    ) INTO v_movimientos
    FROM public.detalle_rendicion_fpagos dfp
    JOIN public.rendiciones_cuentas rc ON dfp.rendicion_id = rc.id
    JOIN public.fpagos fp ON dfp.fpago_id = fp.fpago_id
    JOIN public.clientes c ON rc.cliente_id = c.id
    WHERE rc.fecha_rendicion::date >= v_fecha_desde
      AND rc.fecha_rendicion::date <= v_fecha_hasta
      AND rc.estado = 'aprobada'
      AND (p_solo_bancarios = FALSE OR fp.es_bancario = TRUE);

    RETURN jsonb_build_object(
        'success', true,
        'data', jsonb_build_object(
            'fecha_desde', v_fecha_desde,
            'fecha_hasta', v_fecha_hasta,
            'solo_bancarios', p_solo_bancarios,
            'total_registros', v_total_registros,
            'monto_total_bs', v_monto_total_bs,
            'monto_total_usd', v_monto_total_usd,
            'movimientos', COALESCE(v_movimientos, '[]'::jsonb)
        ),
        'error', NULL
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'SQL_ERROR',
                'message', SQLERRM,
                'details', 'SQLSTATE: ' || SQLSTATE
            )
        );
END;
$$;

GRANT EXECUTE ON FUNCTION public.reporte_formas_pago_rendicion(DATE, DATE, BOOLEAN) TO authenticated, service_role;
