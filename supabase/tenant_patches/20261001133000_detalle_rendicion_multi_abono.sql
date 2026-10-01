-- Permite varios abonos (cobranzas parciales) por la misma orden.
-- Un UNIQUE(orden_distribucion_id) provocaba duplicate key al registrar el 2.º cobro.

DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT c.conname
    FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE n.nspname = 'public'
      AND t.relname = 'detalle_rendicion_ordenes'
      AND c.contype = 'u'
      AND pg_get_constraintdef(c.oid) ILIKE '%(orden_distribucion_id)%'
  LOOP
    EXECUTE format(
      'ALTER TABLE public.detalle_rendicion_ordenes DROP CONSTRAINT IF EXISTS %I',
      r.conname
    );
  END LOOP;
END $$;

DROP INDEX IF EXISTS public.detalle_rendicion_ordenes_orden_distribucion_id_key;

CREATE INDEX IF NOT EXISTS detalle_rendicion_ordenes_orden_distribucion_id_idx
  ON public.detalle_rendicion_ordenes (orden_distribucion_id);
