-- 1. Crear tabla maestra de tipos de contenedores
CREATE TABLE IF NOT EXISTS public.tipos_contenedores (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    codigo TEXT NOT NULL UNIQUE,
    nombre TEXT NOT NULL,
    descripcion TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. Crear tabla de saldo de contenedores por cliente
CREATE TABLE IF NOT EXISTS public.saldo_contenedores_clientes (
    cliente_id UUID REFERENCES public.clientes(id) ON DELETE CASCADE,
    contenedor_id UUID REFERENCES public.tipos_contenedores(id) ON DELETE RESTRICT,
    saldo_pendiente INT NOT NULL DEFAULT 0 CHECK (saldo_pendiente >= 0),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    PRIMARY KEY (cliente_id, contenedor_id)
);

-- 3. Modificar la tabla de productos para relacionarla con contenedores
ALTER TABLE public.productos 
ADD COLUMN IF NOT EXISTS contenedor_id UUID REFERENCES public.tipos_contenedores(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS unidades_por_contenedor NUMERIC(5,0) DEFAULT 1;

-- 4. Crear la tabla de transacciones de movimientos de contenedores en ruta
CREATE TABLE IF NOT EXISTS public.movimientos_contenedores (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    cliente_id UUID REFERENCES public.clientes(id) ON DELETE RESTRICT,
    orden_id UUID REFERENCES public.ordenes_distribucion(id) ON DELETE CASCADE,
    contenedor_id UUID REFERENCES public.tipos_contenedores(id) ON DELETE RESTRICT,
    cantidad_entregada INT NOT NULL DEFAULT 0 CHECK (cantidad_entregada >= 0),
    cantidad_retirada INT NOT NULL DEFAULT 0 CHECK (cantidad_retirada >= 0),
    creado_por UUID REFERENCES auth.users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 5. Actualizar la restricción CHECK de estado en la tabla ordenes_distribucion
-- Primero eliminamos la restricción existente para evitar que bloquee la actualización de estados
ALTER TABLE public.ordenes_distribucion DROP CONSTRAINT IF EXISTS ordenes_distribucion_estado_check;

-- Migramos datos existentes de 'lista_para_carga' a 'aprobada'
UPDATE public.ordenes_distribucion SET estado = 'aprobada' WHERE estado = 'lista_para_carga';

-- Creamos la nueva restricción con los nuevos estados permitidos
ALTER TABLE public.ordenes_distribucion 
ADD CONSTRAINT ordenes_distribucion_estado_check 
CHECK (estado IN ('borrador', 'aprobada', 'en_transito', 'por_liquidar', 'liquidada', 'anulada'));

-- 6. Insertar algunos tipos de contenedores por defecto para iniciar
INSERT INTO public.tipos_contenedores (codigo, nombre, descripcion)
VALUES 
  ('huacal_plastico', 'Huacal Plástico', 'Cesta plástica estándar para botellas o productos varios'),
  ('caja_carton_retornable', 'Caja de Cartón Retornable', 'Caja de cartón reforzado para transporte y retorno'),
  ('pallet_madera', 'Pallet de Madera', 'Plataforma de madera para transporte de carga pesada')
ON CONFLICT (codigo) DO NOTHING;
