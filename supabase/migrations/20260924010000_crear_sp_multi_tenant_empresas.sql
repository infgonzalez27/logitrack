-- Migración: Crear Stored Procedures para Gestión de Empresas y Usuarios Multi-Tenant

-- 1. Función para crear nueva empresa
CREATE OR REPLACE FUNCTION public.crea_nueva_empresa(
    p_codigo_empresa VARCHAR,
    p_nombre_empresa VARCHAR,
    p_supabase_url TEXT,
    p_supabase_anon_key TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_empresa_id UUID;
    v_response JSONB;
BEGIN
    -- Validar que el código no exista
    IF EXISTS (SELECT 1 FROM public.empresas WHERE codigo_empresa = p_codigo_empresa) THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', null,
            'error', jsonb_build_object(
                'code', 'CODIGO_EMPRESA_DUPLICADO',
                'message', 'El código de empresa especificado ya existe en el sistema.',
                'details', null
            )
        );
    END IF;

    -- Insertar nueva empresa
    INSERT INTO public.empresas (
        codigo_empresa,
        nombre_empresa,
        supabase_url,
        supabase_anon_key
    ) VALUES (
        p_codigo_empresa,
        p_nombre_empresa,
        p_supabase_url,
        p_supabase_anon_key
    ) RETURNING id INTO v_empresa_id;

    -- Construir respuesta de éxito
    RETURN jsonb_build_object(
        'success', true,
        'message', 'Empresa creada exitosamente.',
        'data', jsonb_build_object(
            'empresa_id', v_empresa_id,
            'codigo_empresa', p_codigo_empresa,
            'nombre_empresa', p_nombre_empresa
        ),
        'error', null
    );
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false,
        'data', null,
        'error', jsonb_build_object(
            'code', 'DB_ERROR',
            'message', 'Error interno al crear la empresa.',
            'details', SQLERRM
        )
    );
END;
$$;

-- 2. Función para asignar usuario a empresa
CREATE OR REPLACE FUNCTION public.asignar_usuario_empresa(
    p_user_id UUID,
    p_empresa_id UUID,
    p_rol VARCHAR DEFAULT 'operador'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_asignacion_id UUID;
    v_response JSONB;
BEGIN
    -- Validar que la empresa exista
    IF NOT EXISTS (SELECT 1 FROM public.empresas WHERE id = p_empresa_id) THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', null,
            'error', jsonb_build_object(
                'code', 'EMPRESA_INEXISTENTE',
                'message', 'No se encontró la empresa especificada.',
                'details', null
            )
        );
    END IF;

    -- Usamos UPSERT (ON CONFLICT) dado que existe la restricción unique_user_empresa
    INSERT INTO public.usuarios_empresas (
        user_id,
        empresa_id,
        rol
    ) VALUES (
        p_user_id,
        p_empresa_id,
        p_rol
    )
    ON CONFLICT (user_id, empresa_id) 
    DO UPDATE SET 
        rol = EXCLUDED.rol
    RETURNING id INTO v_asignacion_id;

    -- Construir respuesta de éxito
    RETURN jsonb_build_object(
        'success', true,
        'message', 'Usuario asignado a la empresa exitosamente.',
        'data', jsonb_build_object(
            'asignacion_id', v_asignacion_id,
            'user_id', p_user_id,
            'empresa_id', p_empresa_id,
            'rol', p_rol
        ),
        'error', null
    );
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false,
        'data', null,
        'error', jsonb_build_object(
            'code', 'DB_ERROR',
            'message', 'Error interno al asignar el usuario a la empresa.',
            'details', SQLERRM
        )
    );
END;
$$;
