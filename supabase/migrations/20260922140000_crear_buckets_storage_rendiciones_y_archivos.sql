-- Migración: Crear buckets de Supabase Storage para rendiciones-captures, productos y usuarios con sus respectivas políticas RLS.

-- 1. Insertar bucket 'rendiciones-captures' (público)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'rendiciones-captures',
    'rendiciones-captures',
    true,
    10485760, -- 10 MB límite por archivo
    ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp', 'image/heic', 'application/pdf']
)
ON CONFLICT (id) DO UPDATE SET public = true;

-- 2. Insertar bucket 'productos' (público)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'productos',
    'productos',
    true,
    5242880, -- 5 MB límite por archivo
    ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE SET public = true;

-- 3. Insertar bucket 'usuarios' (público)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'usuarios',
    'usuarios',
    true,
    5242880, -- 5 MB límite por archivo
    ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE SET public = true;

-- ==========================================
-- 4. POLÍTICAS RLS PARA 'rendiciones-captures'
-- ==========================================
DROP POLICY IF EXISTS "Lectura publica de rendiciones-captures" ON storage.objects;
CREATE POLICY "Lectura publica de rendiciones-captures"
ON storage.objects FOR SELECT
USING (bucket_id = 'rendiciones-captures');

DROP POLICY IF EXISTS "Insercion autenticada de rendiciones-captures" ON storage.objects;
CREATE POLICY "Insercion autenticada de rendiciones-captures"
ON storage.objects FOR INSERT
WITH CHECK (
    bucket_id = 'rendiciones-captures' 
    AND (auth.role() = 'authenticated' OR auth.role() = 'service_role')
);

DROP POLICY IF EXISTS "Actualizacion autenticada de rendiciones-captures" ON storage.objects;
CREATE POLICY "Actualizacion autenticada de rendiciones-captures"
ON storage.objects FOR UPDATE
USING (
    bucket_id = 'rendiciones-captures' 
    AND (auth.role() = 'authenticated' OR auth.role() = 'service_role')
);

DROP POLICY IF EXISTS "Eliminacion autenticada de rendiciones-captures" ON storage.objects;
CREATE POLICY "Eliminacion autenticada de rendiciones-captures"
ON storage.objects FOR DELETE
USING (
    bucket_id = 'rendiciones-captures' 
    AND (auth.role() = 'authenticated' OR auth.role() = 'service_role')
);

-- ==========================================
-- 5. POLÍTICAS RLS PARA 'productos'
-- ==========================================
DROP POLICY IF EXISTS "Lectura publica de productos" ON storage.objects;
CREATE POLICY "Lectura publica de productos"
ON storage.objects FOR SELECT
USING (bucket_id = 'productos');

DROP POLICY IF EXISTS "Insercion autenticada de productos" ON storage.objects;
CREATE POLICY "Insercion autenticada de productos"
ON storage.objects FOR INSERT
WITH CHECK (
    bucket_id = 'productos' 
    AND (auth.role() = 'authenticated' OR auth.role() = 'service_role')
);

DROP POLICY IF EXISTS "Actualizacion autenticada de productos" ON storage.objects;
CREATE POLICY "Actualizacion autenticada de productos"
ON storage.objects FOR UPDATE
USING (
    bucket_id = 'productos' 
    AND (auth.role() = 'authenticated' OR auth.role() = 'service_role')
);

-- ==========================================
-- 6. POLÍTICAS RLS PARA 'usuarios'
-- ==========================================
DROP POLICY IF EXISTS "Lectura publica de usuarios" ON storage.objects;
CREATE POLICY "Lectura publica de usuarios"
ON storage.objects FOR SELECT
USING (bucket_id = 'usuarios');

DROP POLICY IF EXISTS "Insercion autenticada de usuarios" ON storage.objects;
CREATE POLICY "Insercion autenticada de usuarios"
ON storage.objects FOR INSERT
WITH CHECK (
    bucket_id = 'usuarios' 
    AND (auth.role() = 'authenticated' OR auth.role() = 'service_role')
);

DROP POLICY IF EXISTS "Actualizacion autenticada de usuarios" ON storage.objects;
CREATE POLICY "Actualizacion autenticada de usuarios"
ON storage.objects FOR UPDATE
USING (
    bucket_id = 'usuarios' 
    AND (auth.role() = 'authenticated' OR auth.role() = 'service_role')
);
