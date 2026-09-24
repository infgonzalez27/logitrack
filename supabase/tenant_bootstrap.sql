-- Datos base de un tenant lt_* (idempotente). Se aplica después de schema_base.sql.
-- Catálogos según docs/task_20260924a_Seed_Catalogos.txt (sin roles chofer/cobrador).
-- Los IDs de catálogos coinciden con la BD Central: rol_id de perfiles_usuario
-- se copia tal cual al espejar usuarios.

INSERT INTO public.roles (id, nombre, descripcion) VALUES
  ('46d3145e-e1e0-45b6-a120-84299f0ac9c6', 'admin', 'Administrador con acceso total al sistema'),
  ('fd75454e-ebe0-4c92-bdaa-1f80d3242e0f', 'gerente', 'Acceso a reportes, estadísticas y auditorías'),
  ('44d1e9a8-0d96-4151-8e99-5c82ab0c8748', 'vendedor', 'Encargado de tomar pedidos de los clientes y crear órdenes de distribución'),
  ('be60dbec-a4e0-4d8a-ae9b-4cd50ff12d10', 'despachador', 'personal logístico en ruta que entrega mercancía')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.camiones (placa, modelo, capacidad_kg) VALUES
  ('CAM-001', 'Sin especificar', 0)
ON CONFLICT (placa) DO NOTHING;

INSERT INTO public.rutas (id_ruta, nombre_ruta, descripcion_ruta) VALUES
  ('00000000-0000-4000-8000-000000000001', 'Ruta01', '')
ON CONFLICT (id_ruta) DO NOTHING;

INSERT INTO public.fpagos (fpago_id, fpago_concepto, fpago_info, es_bancario) VALUES
  ('3c7da6ea-69de-4002-aa2e-9a55437d033d', 'Efectivo Bs', false, false),
  ('4d8eb7fb-7ade-4113-bb3f-ab66548e144e', 'Efectivo USD', false, false),
  ('7eb1e02e-ad11-4446-ee6f-de99870b477b', 'Saldo a favor', false, false),
  ('1a5b84c8-47bc-4ee0-880c-7833215be11b', 'Pago movil', true, true),
  ('2b6c95d9-58cd-4ff1-991d-8944326cf22c', 'Transferencia', true, true),
  ('5e9fc80c-8bef-4224-cc4f-bc77659f255f', 'ZELLE', true, true),
  ('6fa0d91d-9c00-4335-dd5f-cd88760a366a', 'BINANCE', true, true)
ON CONFLICT (fpago_id) DO NOTHING;

INSERT INTO public.tipos_contenedores (id, codigo, nombre, descripcion) VALUES
  ('f870ab73-b725-49e2-a40e-58160ec92862', 'C0136', 'VACÍO 36B', 'VACÍO DE 36 BOTELLAS')
ON CONFLICT (id) DO NOTHING;

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
