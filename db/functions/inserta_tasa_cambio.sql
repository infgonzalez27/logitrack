CREATE OR REPLACE FUNCTION public.inserta_tasa_cambio(
    p_fecha_tasa DATE,
    p_tasa NUMERIC
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF p_fecha_tasa IS NULL OR p_tasa IS NULL OR p_tasa <= 0 THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'La fecha y el monto de la tasa deben ser válidos y mayores a cero.',
                'details', NULL
            )
        );
    END IF;

    IF EXISTS (SELECT 1 FROM public.tasa_cambio WHERE fecha_tasa = p_fecha_tasa) THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'FECHA_TASA_DUPLICADA',
                'message', 'Ya existe una tasa registrada para la fecha ' || p_fecha_tasa::text || '. Para modificarla, elimínela primero.',
                'details', NULL
            )
        );
    END IF;

    INSERT INTO public.tasa_cambio (fecha_tasa, tasa_cambio)
    VALUES (p_fecha_tasa, p_tasa);

    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'fecha_tasa', p_fecha_tasa,
            'tasa_cambio', p_tasa
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
