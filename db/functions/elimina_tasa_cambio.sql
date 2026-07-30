CREATE OR REPLACE FUNCTION public.elimina_tasa_cambio(
    p_fecha_tasa DATE
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF p_fecha_tasa IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'La fecha de la tasa es requerida.',
                'details', NULL
            )
        );
    END IF;

    DELETE FROM public.tasa_cambio WHERE fecha_tasa = p_fecha_tasa;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'TASA_NO_ENCONTRADA',
                'message', 'No se encontró ninguna tasa registrada para la fecha ' || p_fecha_tasa::text,
                'details', NULL
            )
        );
    END IF;

    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'fecha_tasa', p_fecha_tasa,
            'eliminado', true
        ),
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
