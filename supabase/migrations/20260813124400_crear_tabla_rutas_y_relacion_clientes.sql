-- Migración para crear la tabla maestra rutas e integrar id_ruta en clientes

-- 1. Crear tabla rutas
CREATE TABLE IF NOT EXISTS public.rutas (
    id_ruta UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    nombre_ruta TEXT NOT NULL,
    descripcion_ruta TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

COMMENT ON TABLE public.rutas IS 'Tabla maestra de rutas de despacho y distribución';
COMMENT ON COLUMN public.rutas.id_ruta IS 'Identificador único de la ruta (UUID)';
COMMENT ON COLUMN public.rutas.nombre_ruta IS 'Nombre identificador de la ruta (no nulo)';
COMMENT ON COLUMN public.rutas.descripcion_ruta IS 'Descripción o detalles adicionales de la ruta (acepta nulo)';

-- 2. Habilitar RLS en rutas y definir políticas de acceso
ALTER TABLE public.rutas ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Usuarios autenticados pueden ver rutas"
ON public.rutas FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "Admin y Gerente pueden gestionar rutas"
ON public.rutas FOR ALL
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.perfiles_usuario p
        JOIN public.roles r ON p.rol_id = r.id
        WHERE p.id = auth.uid()
          AND r.nombre IN ('admin', 'gerente')
    )
);

-- 3. Agregar campo id_ruta a la tabla clientes
ALTER TABLE public.clientes
ADD COLUMN IF NOT EXISTS id_ruta UUID REFERENCES public.rutas(id_ruta) ON DELETE SET NULL;

COMMENT ON COLUMN public.clientes.id_ruta IS 'FK hacia la ruta asignada al cliente';
