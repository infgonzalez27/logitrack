CREATE OR REPLACE FUNCTION public.retorna_usuarios_despachadores()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_data JSONB;
BEGIN
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'id', p.id,
                'nombre_completo', p.nombre_completo,
                'telefono', p.telefono
            )
            ORDER BY p.nombre_completo ASC
        ),
        '[]'::jsonb
    ) INTO v_data
    FROM public.perfiles_usuario p
    JOIN public.roles r ON p.rol_id = r.id
    WHERE r.nombre = 'despachador'
      AND p.activo = TRUE;

    RETURN jsonb_build_object(
        'success', TRUE,
        'data', v_data
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', SQLSTATE,
                'message', SQLERRM
            )
        );
END;
$$;

COMMENT ON FUNCTION public.retorna_usuarios_despachadores() IS 'Retorna la lista de usuarios activos que poseen el rol de despachador';
