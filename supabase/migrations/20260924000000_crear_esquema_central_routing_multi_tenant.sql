-- Migración: Crear Esquema de Base de Datos Central y Enrutamiento Multi-Tenant

-- 1. Crear tabla catálogo de empresas (empresas tenant lt_*)
CREATE TABLE IF NOT EXISTS public.empresas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_empresa VARCHAR(50) NOT NULL UNIQUE,
    nombre_empresa VARCHAR(150) NOT NULL,
    supabase_url TEXT NOT NULL,
    supabase_anon_key TEXT NOT NULL,
    activo BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Crear tabla relación usuario-empresa
CREATE TABLE IF NOT EXISTS public.usuarios_empresas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    empresa_id UUID NOT NULL REFERENCES public.empresas(id) ON DELETE CASCADE,
    rol VARCHAR(50) DEFAULT 'operador',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_user_empresa UNIQUE (user_id, empresa_id)
);

-- 3. Habilitar Aislamiento RLS
ALTER TABLE public.empresas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.usuarios_empresas ENABLE ROW LEVEL SECURITY;

-- 4. Crear Políticas RLS
DROP POLICY IF EXISTS "Allow users to read their own mapping" ON public.usuarios_empresas;
CREATE POLICY "Allow users to read their own mapping" 
ON public.usuarios_empresas FOR SELECT TO authenticated 
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Allow users to read assigned empresa details" ON public.empresas;
CREATE POLICY "Allow users to read assigned empresa details" 
ON public.empresas FOR SELECT TO authenticated 
USING (id IN (SELECT empresa_id FROM public.usuarios_empresas WHERE user_id = auth.uid()));
