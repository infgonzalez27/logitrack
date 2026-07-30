CREATE OR REPLACE FUNCTION public.retorna_tasas_cambio_por_rango(
    p_fecha_desde DATE,
    p_fecha_hasta DATE
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_tasas JSON;
BEGIN
    IF p_fecha_desde IS NULL OR p_fecha_hasta IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'Las fechas de inicio y fin son requeridas.',
                'details', NULL
            )
        );
    END IF;

    SELECT COALESCE(json_agg(
        json_build_object(
            'fecha_tasa', fecha_tasa,
            'tasa_cambio', tasa_cambio,
            'created_at', created_at
        ) ORDER BY fecha_tasa DESC
    ), '[]'::json)
    INTO v_tasas
    FROM public.tasa_cambio
    WHERE fecha_tasa >= p_fecha_desde AND fecha_tasa <= p_fecha_hasta;

    RETURN json_build_object(
        'success', true,
        'data', v_tasas,
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
