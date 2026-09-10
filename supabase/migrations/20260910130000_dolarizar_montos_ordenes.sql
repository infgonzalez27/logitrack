-- Dolarización de órdenes: blanquea montos Bs y asegura integridad USD.
-- detalle_distribucion: valor_unitario_recaudar / subtotal_recaudar → NULL
-- ordenes_distribucion: total_recaudar_bs → NULL
-- USD: valor_unitario_usd, subtotal_recaudar_usd, total_recaudar_usd

-- 1) Completar valor_unitario_usd desde precio de lista / legado en recaudar
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

-- 2) Recalcular subtotal USD = cantidad_solicitada * valor_unitario_usd
UPDATE public.detalle_distribucion
SET subtotal_recaudar_usd = ROUND(
  COALESCE(cantidad_solicitada, 0)::numeric * COALESCE(valor_unitario_usd, 0)::numeric,
  2
);

-- 3) Blanquear campos Bs en detalle
UPDATE public.detalle_distribucion
SET
  valor_unitario_recaudar = NULL,
  subtotal_recaudar = NULL;

-- 4) Recalcular total USD de cabecera y blanquear Bs
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

-- Órdenes sin detalle: total_usd 0 / null Bs
UPDATE public.ordenes_distribucion o
SET
  total_recaudar_usd = COALESCE(o.total_recaudar_usd, 0),
  total_recaudar_bs = NULL
WHERE NOT EXISTS (
  SELECT 1 FROM public.detalle_distribucion d WHERE d.orden_id = o.id
);
