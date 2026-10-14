-- ==============================================================================
-- Migración / Parche: Eliminar sobrecarga obsoleta de crear_orden_distribucion (7 parámetros)
-- Fecha: 2026-10-13 19:25:00
-- Descripción: Elimina la versión antigua huérfana de 7 parámetros de public.crear_orden_distribucion
--              para resolver la ambigüedad en PostgreSQL ("Could not choose the best candidate function").
--              La versión vigente es la de 8 parámetros que incluye p_es_cortesia BOOLEAN DEFAULT FALSE.
-- ==============================================================================

DROP FUNCTION IF EXISTS public.crear_orden_distribucion(UUID, UUID, UUID, NUMERIC, JSONB, UUID, UUID);
DROP FUNCTION IF EXISTS public.crear_orden_distribucion(UUID, UUID, UUID, UUID, JSONB);
