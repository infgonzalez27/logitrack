CREATE OR REPLACE FUNCTION public.crear_cuenta_bancaria_empresa(
    p_cuenta_bancaria TEXT,
    p_entidad_bancaria TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_id UUID;
BEGIN
    IF p_cuenta_bancaria IS NULL OR TRIM(p_cuenta_bancaria) = '' THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El número de cuenta bancaria es requerido.'
            )
        );
    END IF;

    IF p_entidad_bancaria IS NULL OR TRIM(p_entidad_bancaria) = '' THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'La entidad bancaria es requerida.'
            )
        );
    END IF;

    IF EXISTS (SELECT 1 FROM public.cuentas_bancarias_empresa WHERE cuenta_bancaria = TRIM(p_cuenta_bancaria)) THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'CUENTA_DUPLICADA',
                'message', 'La cuenta bancaria especificada ya está registrada.'
            )
        );
    END IF;

    INSERT INTO public.cuentas_bancarias_empresa (
        cuenta_bancaria,
        entidad_bancaria,
        status_cuenta
    ) VALUES (
        TRIM(p_cuenta_bancaria),
        TRIM(p_entidad_bancaria),
        TRUE
    ) RETURNING id INTO v_id;

    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'id', v_id,
            'cuenta_bancaria', TRIM(p_cuenta_bancaria),
            'entidad_bancaria', TRIM(p_entidad_bancaria),
            'status_cuenta', true
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
