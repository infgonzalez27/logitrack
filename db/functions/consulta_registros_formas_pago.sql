CREATE OR REPLACE FUNCTION public.consulta_registros_formas_pago()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_data JSON;
BEGIN
    SELECT json_agg(
        json_build_object(
            'fpago_id', fpago_id,
            'fpago_concepto', fpago_concepto,
            'fpago_info', fpago_info
        ) ORDER BY fpago_concepto
    ) INTO v_data
    FROM public.fpagos;

    RETURN json_build_object(
        'success', true,
        'data', COALESCE(v_data, '[]'::json),
        'error', NULL
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'SQL_ERROR',
                'message', SQLERRM,
                'details', 'SQLSTATE: ' || SQLSTATE
            )
        );
END;
$$;
