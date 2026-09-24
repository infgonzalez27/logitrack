-- Storage de un tenant lt_* (idempotente): buckets y políticas iguales a Central.
-- Los catálogos y productos están en seed_base.sql.

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types) VALUES
  ('rendiciones-captures', 'rendiciones-captures', true, 10485760,
    ARRAY['image/jpeg','image/jpg','image/png','image/webp','image/heic','application/pdf']),
  ('productos', 'productos', true, 5242880,
    ARRAY['image/webp','image/png','image/jpeg','image/jpg']),
  ('usuarios', 'usuarios', true, 5242880,
    ARRAY['image/webp','image/png','image/jpeg','image/jpg'])
ON CONFLICT (id) DO NOTHING;

DO $$
DECLARE
  b text;
BEGIN
  FOREACH b IN ARRAY ARRAY['productos', 'rendiciones-captures', 'usuarios'] LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON storage.objects', 'Lectura publica de ' || b);
    EXECUTE format(
      'CREATE POLICY %I ON storage.objects FOR SELECT TO public USING (bucket_id = %L)',
      'Lectura publica de ' || b, b);

    EXECUTE format('DROP POLICY IF EXISTS %I ON storage.objects', 'Insercion autenticada de ' || b);
    EXECUTE format(
      'CREATE POLICY %I ON storage.objects FOR INSERT TO public WITH CHECK (bucket_id = %L AND auth.role() IN (''authenticated'', ''service_role''))',
      'Insercion autenticada de ' || b, b);

    EXECUTE format('DROP POLICY IF EXISTS %I ON storage.objects', 'Actualizacion autenticada de ' || b);
    EXECUTE format(
      'CREATE POLICY %I ON storage.objects FOR UPDATE TO public USING (bucket_id = %L AND auth.role() IN (''authenticated'', ''service_role''))',
      'Actualizacion autenticada de ' || b, b);
  END LOOP;

  DROP POLICY IF EXISTS "Eliminacion autenticada de rendiciones-captures" ON storage.objects;
  CREATE POLICY "Eliminacion autenticada de rendiciones-captures" ON storage.objects
    FOR DELETE TO public
    USING (bucket_id = 'rendiciones-captures' AND auth.role() IN ('authenticated', 'service_role'));
END
$$;
