CREATE OR REPLACE FUNCTION public.actualizar_registro_perfil_usuarios_segun_id(
    p_id UUID,
    p_rol_id UUID,
    p_nombre_completo TEXT,
    p_telefono TEXT,
    p_activo BOOLEAN
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE public.perfiles_usuario
    SET 
        rol_id = p_rol_id,
        nombre_completo = p_nombre_completo,
        telefono = p_telefono,
        activo = p_activo,
        updated_at = NOW()
    WHERE id = p_id;

    RETURN FOUND;
END;
$$;
