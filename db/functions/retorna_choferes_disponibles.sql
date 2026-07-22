DROP FUNCTION IF EXISTS public.retorna_choferes_disponibles();

CREATE OR REPLACE FUNCTION public.retorna_choferes_disponibles()
RETURNS TABLE (
    perfil_id UUID,
    nombre_completo TEXT,
    cedula_licencia TEXT,
    telefono TEXT,
    estado TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Retorna únicamente los choferes que están con estado 'disponible'
    -- y cuyo perfil de usuario esté activo.
    RETURN QUERY 
    SELECT 
        c.perfil_id,
        p.nombre_completo,
        c.cedula_licencia,
        -- Prioriza el movil1 del chofer, si no existe toma el teléfono del perfil
        COALESCE(c.movil1, p.telefono) AS telefono,
        c.estado::TEXT
    FROM public.choferes c
    JOIN public.perfiles_usuario p ON c.perfil_id = p.id
    WHERE c.estado = 'disponible' 
      AND p.activo = TRUE
    ORDER BY p.nombre_completo ASC;
END;
$$;
