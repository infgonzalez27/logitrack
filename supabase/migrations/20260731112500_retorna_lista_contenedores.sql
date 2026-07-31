-- Migration: RPC Consulta de Lista de Contenedores (DB-019)

CREATE OR REPLACE FUNCTION public.retorna_lista_contenedores()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_contenedores JSON;
BEGIN
    SELECT COALESCE(json_agg(
        json_build_object(
            'id', id,
            'nombre', nombre
        ) ORDER BY nombre ASC
    ), '[]'::json)
    INTO v_contenedores
    FROM public.tipos_contenedores;

    RETURN json_build_object(
        'success', true,
        'data', v_contenedores,
        'error', NULL
    );
EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object(
        'success', false,
        'data', NULL,
        'error', json_build_object(
            'code', 'SQL_ERROR',
            'message', SQLERRM,
            'details', NULL
        )
    );
END;
$$;
