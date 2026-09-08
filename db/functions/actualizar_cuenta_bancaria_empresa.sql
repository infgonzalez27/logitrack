CREATE OR REPLACE FUNCTION public.actualizar_cuenta_bancaria_empresa(
    p_id UUID,
    p_cuenta_bancaria TEXT DEFAULT NULL,
    p_entidad_bancaria TEXT DEFAULT NULL,
    p_status_cuenta BOOLEAN DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_rec RECORD;
BEGIN
    IF p_id IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID de la cuenta bancaria es requerido.'
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

    IF p_cuenta_bancaria IS NOT NULL AND TRIM(p_cuenta_bancaria) <> '' THEN
        IF EXISTS (SELECT 1 FROM public.cuentas_bancarias_empresa WHERE cuenta_bancaria = TRIM(p_cuenta_bancaria) AND id <> p_id) THEN
            RETURN json_build_object(
                'success', false,
                'data', NULL,
                'error', json_build_object(
                    'code', 'CUENTA_DUPLICADA',
                    'message', 'El número de cuenta especificado pertenece a otra cuenta registrada.'
                )
            );
        END IF;
    END IF;

    UPDATE public.cuentas_bancarias_empresa
    SET 
        cuenta_bancaria = COALESCE(NULLIF(TRIM(p_cuenta_bancaria), ''), cuenta_bancaria),
        entidad_bancaria = COALESCE(NULLIF(TRIM(p_entidad_bancaria), ''), entidad_bancaria),
        status_cuenta = COALESCE(p_status_cuenta, status_cuenta)
    WHERE id = p_id
    RETURNING id, cuenta_bancaria, entidad_bancaria, status_cuenta, created_at
    INTO v_rec;

    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'id', v_rec.id,
            'cuenta_bancaria', v_rec.cuenta_bancaria,
            'entidad_bancaria', v_rec.entidad_bancaria,
            'status_cuenta', v_rec.status_cuenta
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
