CREATE OR REPLACE FUNCTION public.actualiza_registro_rutas_segun_uuid(
    p_id_ruta UUID,
    p_nombre_ruta TEXT,
    p_descripcion_ruta TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_ruta_actualizada RECORD;
BEGIN
    -- Validar que el id_ruta no sea nulo
    IF p_id_ruta IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El par├ímetro p_id_ruta es obligatorio.'
            )
        );
    END IF;

    -- Validar que el nombre_ruta no est├® vac├¡o
    IF p_nombre_ruta IS NULL OR TRIM(p_nombre_ruta) = '' THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El par├ímetro p_nombre_ruta es obligatorio y no puede estar vac├¡o.'
            )
        );
    END IF;

    -- Verificar si la ruta existe
    IF NOT EXISTS (SELECT 1 FROM public.rutas WHERE id_ruta = p_id_ruta) THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'RUTA_INEXISTENTE',
                'message', 'No se encontr├│ ninguna ruta con el id_ruta especificado.'
            )
        );
    END IF;

    -- Actualizar el registro en la tabla rutas
    UPDATE public.rutas
    SET nombre_ruta = TRIM(p_nombre_ruta),
        descripcion_ruta = p_descripcion_ruta
    WHERE id_ruta = p_id_ruta
    RETURNING id_ruta, nombre_ruta, descripcion_ruta, created_at
    INTO v_ruta_actualizada;

    -- Retornar ├®xito
    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Ruta actualizada exitosamente.',
        'data', jsonb_build_object(
            'id_ruta', v_ruta_actualizada.id_ruta,
            'nombre_ruta', v_ruta_actualizada.nombre_ruta,
            'descripcion_ruta', v_ruta_actualizada.descripcion_ruta,
            'created_at', v_ruta_actualizada.created_at
        )
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

COMMENT ON FUNCTION public.actualiza_registro_rutas_segun_uuid(UUID, TEXT, TEXT) IS 'Actualiza el nombre y descripci├│n de una ruta existente identificada por su id_ruta (UUID)';
