CREATE OR REPLACE FUNCTION public.retorna_cuentas_bancarias_empresa(
    p_solo_activas BOOLEAN DEFAULT TRUE
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_data JSON;
BEGIN
    SELECT json_agg(
        json_build_object(
            'id', id,
            'cuenta_bancaria', cuenta_bancaria,
            'entidad_bancaria', entidad_bancaria,
            'status_cuenta', status_cuenta,
            'created_at', created_at
        ) ORDER BY entidad_bancaria ASC, cuenta_bancaria ASC
    ) INTO v_data
    FROM public.cuentas_bancarias_empresa
    WHERE (NOT p_solo_activas OR status_cuenta = TRUE);

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
