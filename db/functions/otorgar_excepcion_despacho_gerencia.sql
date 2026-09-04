CREATE OR REPLACE FUNCTION public.otorgar_excepcion_despacho_gerencia(
    p_cliente_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_is_gerente_admin BOOLEAN := FALSE;
BEGIN
    IF p_cliente_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID del cliente es obligatorio.'
            )
        );
    END IF;

    -- Validar permisos: Solo gerente o admin pueden autorizar excepción
    v_is_gerente_admin := public.user_has_role(ARRAY['admin', 'gerente']);
    IF NOT v_is_gerente_admin THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'ACCESO_DENEGADO',
                'message', 'Solo el personal gerencial o administrador puede otorgar excepciones de despacho.'
            )
        );
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.clientes WHERE id = p_cliente_id) THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'CLIENTE_INEXISTENTE',
                'message', 'El cliente especificado no existe.'
            )
        );
    END IF;

    -- Activar la excepción de uso único para el cliente
    UPDATE public.clientes
    SET excepcion_despacho_gerencia = TRUE
    WHERE id = p_cliente_id;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Excepción de despacho otorgada exitosamente por gerencia (Válida por 1 despacho).',
        'data', jsonb_build_object(
            'cliente_id', p_cliente_id,
            'excepcion_despacho_gerencia', TRUE
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

COMMENT ON FUNCTION public.otorgar_excepcion_despacho_gerencia(UUID) IS 'Otorga un permiso excepcional de despacho de uso único a un cliente por parte de la Gerencia';
