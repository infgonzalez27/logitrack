-- Migración: RPC retorna_lista_rutas (Tarea DB-020)

CREATE OR REPLACE FUNCTION public.retorna_lista_rutas()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_total_registros INT;
    v_data JSONB;
BEGIN
    -- Obtenemos el total de registros en la tabla rutas
    SELECT COUNT(*) INTO v_total_registros FROM public.rutas;

    -- Obtenemos el arreglo de rutas ordenadas por nombre_ruta
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'id_ruta', id_ruta,
                'nombre_ruta', nombre_ruta,
                'descripcion_ruta', descripcion_ruta,
                'created_at', created_at
            )
            ORDER BY nombre_ruta ASC
        ),
        '[]'::jsonb
    ) INTO v_data
    FROM public.rutas;

    -- Retornamos respuesta exitosa
    RETURN jsonb_build_object(
        'success', TRUE,
        'total_registros', v_total_registros,
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

COMMENT ON FUNCTION public.retorna_lista_rutas() IS 'Retorna el listado completo de rutas y la cantidad total de registros almacenados';
