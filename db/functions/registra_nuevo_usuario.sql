CREATE OR REPLACE FUNCTION public.registra_nuevo_usuario(
    p_email TEXT,
    p_password TEXT,
    p_nombre_completo TEXT,
    p_telefono TEXT,
    p_rol_nombre TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID;
    v_rol_id UUID;
    v_rol_normalizado TEXT;
    v_identity_id UUID;
BEGIN
    -- Validaciones básicas
    IF p_email IS NULL OR p_email = '' THEN
        RETURN jsonb_build_object('success', false, 'message', 'El correo electrónico es requerido.');
    END IF;

    IF p_password IS NULL OR p_password = '' THEN
        RETURN jsonb_build_object('success', false, 'message', 'La contraseña es requerida.');
    END IF;

    IF p_nombre_completo IS NULL OR p_nombre_completo = '' THEN
        RETURN jsonb_build_object('success', false, 'message', 'El nombre completo es requerido.');
    END IF;

    -- Validar duplicados en auth.users
    IF EXISTS (SELECT 1 FROM auth.users WHERE email = p_email) THEN
        RETURN jsonb_build_object('success', false, 'message', 'El correo electrónico ya está registrado.');
    END IF;

    -- Validar y obtener el rol
    -- Normalizar nombre del rol
    v_rol_normalizado := LOWER(TRIM(p_rol_nombre));
    IF v_rol_normalizado = 'chofer_cobrador' THEN
        v_rol_normalizado := 'chofer';
    END IF;

    SELECT id INTO v_rol_id FROM public.roles WHERE nombre = v_rol_normalizado;
    IF v_rol_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El rol ' || p_rol_nombre || ' no existe en el sistema.');
    END IF;

    -- Generar IDs
    v_user_id := gen_random_uuid();
    v_identity_id := gen_random_uuid();

    -- 1. Insertar en auth.users
    INSERT INTO auth.users (
        id,
        instance_id,
        email,
        encrypted_password,
        email_confirmed_at,
        created_at,
        updated_at,
        raw_app_meta_data,
        raw_user_meta_data,
        aud,
        role,
        is_anonymous,
        confirmation_token,
        recovery_token,
        email_change_token_new,
        email_change_token_current,
        phone_change_token,
        reauthentication_token
    ) VALUES (
        v_user_id,
        '00000000-0000-0000-0000-000000000000',
        p_email,
        crypt(p_password, gen_salt('bf')),
        NOW(),
        NOW(),
        NOW(),
        jsonb_build_object('provider', 'email', 'providers', array_to_json(array['email'])),
        jsonb_build_object('full_name', p_nombre_completo),
        'authenticated',
        'authenticated',
        FALSE,
        '',
        '',
        '',
        '',
        '',
        ''
    );

    -- 2. Insertar en auth.identities (Crítico para GoTrue/Supabase Auth)
    INSERT INTO auth.identities (
        id,
        user_id,
        identity_data,
        provider,
        provider_id,
        last_sign_in_at,
        created_at,
        updated_at
    ) VALUES (
        v_identity_id,
        v_user_id,
        jsonb_build_object('sub', v_user_id::text, 'email', p_email, 'email_verified', true, 'phone_verified', false),
        'email',
        v_user_id::text, -- Provider ID para email suele ser el mismo user_id
        NOW(),
        NOW(),
        NOW()
    );

    -- 3. Insertar o actualizar en public.perfiles_usuario
    INSERT INTO public.perfiles_usuario (
        id,
        rol_id,
        nombre_completo,
        telefono,
        activo,
        updated_at
    ) VALUES (
        v_user_id,
        v_rol_id,
        p_nombre_completo,
        p_telefono,
        TRUE,
        NOW()
    )
    ON CONFLICT (id) DO UPDATE 
    SET rol_id = EXCLUDED.rol_id,
        nombre_completo = EXCLUDED.nombre_completo,
        telefono = EXCLUDED.telefono,
        updated_at = NOW();

    -- 4. Si el rol es Chofer, insertar en la tabla choferes
    IF v_rol_normalizado = 'chofer' THEN
        INSERT INTO public.choferes (
            perfil_id,
            cedula_licencia,
            movil1,
            estado,
            created_at
        ) VALUES (
            v_user_id,
            'LIC-' || UPPER(substring(v_user_id::text, 1, 8)),
            p_telefono,
            'disponible',
            NOW()
        )
        ON CONFLICT (perfil_id) DO NOTHING;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'message', 'Usuario y perfil creados exitosamente.',
        'user_id', v_user_id
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false,
        'message', 'Error en el registro del usuario: ' || SQLERRM
    );
END;
$$;
