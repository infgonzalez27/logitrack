CREATE OR REPLACE FUNCTION public.retorna_ultima_tasa_cambio()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result RECORD;
BEGIN
    SELECT fecha_tasa, tasa_cambio, created_at
    INTO v_result
    FROM public.tasa_cambio
    ORDER BY fecha_tasa DESC
    LIMIT 1;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', true,
            'data', NULL,
            'error', NULL
        );
    END IF;

    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'fecha_tasa', v_result.fecha_tasa,
            'tasa_cambio', v_result.tasa_cambio,
            'created_at', v_result.created_at
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
