CREATE OR REPLACE FUNCTION public.cambiar_status_cuenta_bancaria_empresa(
    p_id UUID,
    p_status_cuenta BOOLEAN
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF p_id IS NULL OR p_status_cuenta IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID de la cuenta y el estatus son requeridos.'
            )
        );
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.cuentas_bancarias_empresa WHERE id = p_id) THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'CUENTA_INEXISTENTE',
                'message', 'La cuenta bancaria especificada no existe.'
            )
        );
    END IF;

    UPDATE public.cuentas_bancarias_empresa
    SET status_cuenta = p_status_cuenta
    WHERE id = p_id;

    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'id', p_id,
            'status_cuenta', p_status_cuenta
        ),
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
