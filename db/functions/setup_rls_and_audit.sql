-- 1. Crear función trigger para auditoría global de cambios
CREATE OR REPLACE FUNCTION public.audit_changes_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_usuario_id UUID;
    v_registro_id UUID;
    v_valores_anteriores JSONB := NULL;
    v_valores_nuevos JSONB := NULL;
BEGIN
    -- Obtener el ID del usuario autenticado actual desde auth.uid() de Supabase
    BEGIN
        v_usuario_id := auth.uid();
    EXCEPTION WHEN OTHERS THEN
        v_usuario_id := NULL;
    END;

    -- Determinar el ID del registro afectado (id o perfil_id)
    IF TG_OP = 'DELETE' THEN
        IF to_jsonb(OLD) ? 'id' THEN
            v_registro_id := (OLD.id)::UUID;
        ELSIF to_jsonb(OLD) ? 'perfil_id' THEN
            v_registro_id := (OLD.perfil_id)::UUID;
        ELSE
            v_registro_id := gen_random_uuid();
        END IF;
        v_valores_anteriores := to_jsonb(OLD);
    ELSE
        IF to_jsonb(NEW) ? 'id' THEN
            v_registro_id := (NEW.id)::UUID;
        ELSIF to_jsonb(NEW) ? 'perfil_id' THEN
            v_registro_id := (NEW.perfil_id)::UUID;
        ELSE
            v_registro_id := gen_random_uuid();
        END IF;
        
        IF TG_OP = 'UPDATE' THEN
            v_valores_anteriores := to_jsonb(OLD);
            v_valores_nuevos := to_jsonb(NEW);
        ELSIF TG_OP = 'INSERT' THEN
            v_valores_nuevos := to_jsonb(NEW);
        END IF;
    END IF;

    -- Insertar en la tabla de logs de auditoría
    INSERT INTO public.logs_auditoria (
        usuario_id,
        tabla_afectada,
        accion,
        registro_id,
        valores_anteriores,
        valores_nuevos,
        fecha_registro
    ) VALUES (
        v_usuario_id,
        TG_TABLE_NAME::TEXT,
        TG_OP,
        v_registro_id,
        v_valores_anteriores,
        v_valores_nuevos,
        NOW()
    );

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$;

-- 2. Vincular trigger de auditoría a tablas críticas (eliminar si ya existen)
DROP TRIGGER IF EXISTS audit_ordenes_distribucion ON public.ordenes_distribucion;
CREATE TRIGGER audit_ordenes_distribucion
AFTER INSERT OR UPDATE OR DELETE ON public.ordenes_distribucion
FOR EACH ROW EXECUTE FUNCTION public.audit_changes_trigger();

DROP TRIGGER IF EXISTS audit_detalle_distribucion ON public.detalle_distribucion;
CREATE TRIGGER audit_detalle_distribucion
AFTER INSERT OR UPDATE OR DELETE ON public.detalle_distribucion
FOR EACH ROW EXECUTE FUNCTION public.audit_changes_trigger();

DROP TRIGGER IF EXISTS audit_inventario_almacen ON public.inventario_almacen;
CREATE TRIGGER audit_inventario_almacen
AFTER INSERT OR UPDATE OR DELETE ON public.inventario_almacen
FOR EACH ROW EXECUTE FUNCTION public.audit_changes_trigger();

DROP TRIGGER IF EXISTS audit_inventario_movil ON public.inventario_movil;
CREATE TRIGGER audit_inventario_movil
AFTER INSERT OR UPDATE OR DELETE ON public.inventario_movil
FOR EACH ROW EXECUTE FUNCTION public.audit_changes_trigger();

DROP TRIGGER IF EXISTS audit_movimientos_contenedores ON public.movimientos_contenedores;
CREATE TRIGGER audit_movimientos_contenedores
AFTER INSERT OR UPDATE OR DELETE ON public.movimientos_contenedores
FOR EACH ROW EXECUTE FUNCTION public.audit_changes_trigger();


-- 3. Crear función helper para validar rol del usuario autenticado actual
CREATE OR REPLACE FUNCTION public.user_has_role(
    p_role_names TEXT[]
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID;
    v_has_role BOOLEAN;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RETURN FALSE;
    END IF;

    SELECT EXISTS (
        SELECT 1 
        FROM public.perfiles_usuario p
        JOIN public.roles r ON r.id = p.rol_id
        WHERE p.id = v_user_id AND r.nombre = ANY(p_role_names)
    ) INTO v_has_role;

    RETURN v_has_role;
END;
$$;


-- 4. Habilitar RLS y Configurar políticas en la tabla ordenes_distribucion
ALTER TABLE public.ordenes_distribucion ENABLE ROW LEVEL SECURITY;

-- Eliminar políticas previas para evitar conflictos
DROP POLICY IF EXISTS select_ordenes_distribucion ON public.ordenes_distribucion;
DROP POLICY IF EXISTS modify_ordenes_distribucion ON public.ordenes_distribucion;

-- Crear política de lectura restrictiva por rol
CREATE POLICY select_ordenes_distribucion ON public.ordenes_distribucion
FOR SELECT
USING (
    -- Si es administrador, gerente o despachador, puede ver todas las órdenes
    public.user_has_role(ARRAY['admin', 'gerente', 'despachador'])
    -- Si es chofer, solo puede ver las asignadas a él
    OR (public.user_has_role(ARRAY['chofer_cobrador']) AND chofer_id = auth.uid())
);

-- Crear política de modificación para personal administrativo
CREATE POLICY modify_ordenes_distribucion ON public.ordenes_distribucion
FOR ALL
USING (
    public.user_has_role(ARRAY['admin', 'gerente', 'despachador'])
);
