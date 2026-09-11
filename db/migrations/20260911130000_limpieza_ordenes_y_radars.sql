-- Migration: 20260911130000_limpieza_ordenes_y_radars.sql
-- Description: Limpieza completa de las tablas detalle_distribucion, ordenes_distribucion y radars.

TRUNCATE TABLE public.detalle_distribucion CASCADE;
TRUNCATE TABLE public.ordenes_distribucion CASCADE;
TRUNCATE TABLE public.radars CASCADE;
