-- Migraci├│n para agregar/corregir la columna despachador_id en la tabla clientes
-- Permite la asignaci├│n opcional de un usuario despachador a la ficha del cliente (relaci├│n 1:N con perfiles_usuario)

DO $$
BEGIN
    -- Si la columna ya existe pero no es de tipo UUID (ej: int2/integer de esquemas legados), se elimina la vieja para reemplazarla por UUID
    IF EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'clientes' 
          AND column_name = 'despachador_id'
          AND data_type != 'uuid'
    ) THEN
        ALTER TABLE public.clientes DROP COLUMN despachador_id;
    END IF;

    -- Agregar la columna UUID con Foreign Key si no existe
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'clientes' 
          AND column_name = 'despachador_id'
    ) THEN
        ALTER TABLE public.clientes 
        ADD COLUMN despachador_id UUID REFERENCES public.perfiles_usuario(id) ON DELETE SET NULL;
    END IF;
END $$;

COMMENT ON COLUMN public.clientes.despachador_id IS 'ID del perfil de usuario con rol despachador asignado preferencialmente al cliente';
