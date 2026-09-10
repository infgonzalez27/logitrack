-- Misma migración disponible como script DB (ver supabase/migrations/).
-- Dolarización: NULL en campos Bs; integridad USD en detalle y cabecera.

UPDATE public.detalle_distribucion d
SET valor_unitario_usd = ROUND(
  COALESCE(
    NULLIF(d.valor_unitario_usd, 0),
    NULLIF(d.valor_unitario_recaudar, 0),
    NULLIF(p.precio_lista1, 0),
    NULLIF(p.precio, 0),
    0
  )::numeric,
  2
)
FROM public.productos p
WHERE p.id = d.producto_id;

UPDATE public.detalle_distribucion
SET subtotal_recaudar_usd = ROUND(
  COALESCE(cantidad_solicitada, 0)::numeric * COALESCE(valor_unitario_usd, 0)::numeric,
  2
);

UPDATE public.detalle_distribucion
SET
  valor_unitario_recaudar = NULL,
  subtotal_recaudar = NULL;

UPDATE public.ordenes_distribucion o
SET
  total_recaudar_usd = COALESCE(agg.suma_usd, 0),
  total_recaudar_bs = NULL
FROM (
  SELECT
    orden_id,
    ROUND(SUM(COALESCE(subtotal_recaudar_usd, 0))::numeric, 2) AS suma_usd
  FROM public.detalle_distribucion
  GROUP BY orden_id
) agg
WHERE agg.orden_id = o.id;

UPDATE public.ordenes_distribucion o
SET
  total_recaudar_usd = COALESCE(o.total_recaudar_usd, 0),
  total_recaudar_bs = NULL
WHERE NOT EXISTS (
  SELECT 1 FROM public.detalle_distribucion d WHERE d.orden_id = o.id
);
