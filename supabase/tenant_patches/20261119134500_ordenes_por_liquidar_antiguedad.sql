-- ==============================================================================
-- PARCHE: Órdenes por liquidar agrupadas por antigüedad (tramos de días vencidos)
-- Fecha: 2026-11-19
-- Descripción:
--   Crea el RPC idempotente `public.retorna_ordenes_por_liquidar_antiguedad()`
--   que devuelve el detalle por orden (estado 'por_liquidar', excluyendo cortesías)
--   calculando `dias_vencidos` desde `fecha_despacho` y asignando su tramo:
--     1. menor_7      (0 - 6 días)   -> "Vencidas menores de 7 días"
--     2. entre_7_15   (7 - 15 días)  -> "Entre 7 y 15 días"
--     3. entre_16_30  (16 - 30 días) -> "Entre 16 y 30 días"
--     4. entre_31_45  (31 - 45 días) -> "Entre 31 y 45 días"
--     5. entre_46_90  (46 - 90 días) -> "Entre 46 y 90 días"
--     6. mayor_90     (> 90 días)    -> "Vencidas mayores a 90 días"
--   No modifica `public.retorna_ordenes_por_liquidar()` para mantener compatibilidad.
-- ==============================================================================

DROP FUNCTION IF EXISTS public.retorna_ordenes_por_liquidar_antiguedad();

CREATE OR REPLACE FUNCTION public.retorna_ordenes_por_liquidar_antiguedad()
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
                'orden_id', sub.orden_id,
                'correlativo', sub.correlativo,
                'factura_origen_numero', sub.factura_origen_numero,
                'cliente_id', sub.cliente_id,
                'razon_social', sub.razon_social,
                'rif_nit', sub.rif_nit,
                'vendedor_id', sub.vendedor_id,
                'fecha_despacho', sub.fecha_despacho,
                'dias_vencidos', sub.dias_vencidos,
                'tramo_key', sub.tramo_key,
                'tramo_orden', sub.tramo_orden,
                'total_orden_usd', sub.total_orden_usd,
                'abonado_usd', sub.abonado_usd,
                'monto_por_liquidar', sub.monto_por_liquidar
            )
            ORDER BY sub.tramo_orden ASC, sub.dias_vencidos DESC, sub.correlativo DESC
        ),
        '[]'::jsonb
    )
    INTO v_data
    FROM (
        SELECT
            base.*,
            CASE
                WHEN base.dias_vencidos < 7 THEN 'menor_7'
                WHEN base.dias_vencidos BETWEEN 7 AND 15 THEN 'entre_7_15'
                WHEN base.dias_vencidos BETWEEN 16 AND 30 THEN 'entre_16_30'
                WHEN base.dias_vencidos BETWEEN 31 AND 45 THEN 'entre_31_45'
                WHEN base.dias_vencidos BETWEEN 46 AND 90 THEN 'entre_46_90'
                ELSE 'mayor_90'
            END AS tramo_key,
            CASE
                WHEN base.dias_vencidos < 7 THEN 1
                WHEN base.dias_vencidos BETWEEN 7 AND 15 THEN 2
                WHEN base.dias_vencidos BETWEEN 16 AND 30 THEN 3
                WHEN base.dias_vencidos BETWEEN 31 AND 45 THEN 4
                WHEN base.dias_vencidos BETWEEN 46 AND 90 THEN 5
                ELSE 6
            END AS tramo_orden
        FROM (
            SELECT
                od.id AS orden_id,
                od.correlativo,
                od.factura_origen_numero,
                c.id AS cliente_id,
                c.razon_social,
                c.rif_nit,
                od.vendedor_id,
                od.fecha_despacho,
                GREATEST(
                    0,
                    (CURRENT_DATE - COALESCE(od.fecha_despacho::date, od.created_at::date, CURRENT_DATE))::INT
                ) AS dias_vencidos,
                COALESCE(od.total_recaudar_usd, 0.00) AS total_orden_usd,
                COALESCE(abonos.total_recaudado_usd, 0.00) AS abonado_usd,
                GREATEST(
                    0.00,
                    COALESCE(od.total_recaudar_usd, 0.00) - COALESCE(abonos.total_recaudado_usd, 0.00)
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
              AND (od.es_cortesia IS NULL OR od.es_cortesia = FALSE)
        ) base
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

GRANT EXECUTE ON FUNCTION public.retorna_ordenes_por_liquidar_antiguedad() TO authenticated, service_role;
