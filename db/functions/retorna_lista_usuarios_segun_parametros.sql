CREATE OR REPLACE FUNCTION public.retorna_lista_usuarios_segun_parametros(
    p_nombre TEXT,
    p_rol TEXT
)
RETURNS TABLE (
    id UUID,
    nombre_completo TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY 
    SELECT 
        pu.id, 
        pu.nombre_completo
    FROM public.perfiles_usuario pu
    LEFT JOIN public.roles r ON pu.rol_id = r.id
    WHERE 
        (p_nombre IS NULL OR p_nombre = '' OR pu.nombre_completo ILIKE '%' || p_nombre || '%')
        AND 
        (p_rol IS NULL OR p_rol = '' OR r.nombre ILIKE '%' || p_rol || '%');
END;
$$;
