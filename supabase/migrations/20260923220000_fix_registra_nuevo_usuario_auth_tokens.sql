-- Fix: GoTrue falla con "Database error querying schema" si token columns son NULL.
-- registra_nuevo_usuario debe setear strings vacíos (no omitir email_change).

CREATE OR REPLACE FUNCTION public.registra_nuevo_usuario(
    p_email text,
    p_password text,
    p_nombre_completo text,
    p_telefono text,
    p_rol_nombre text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, extensions
AS $function$
DECLARE
    v_user_id UUID;
    v_rol_id UUID;
    v_rol_normalizado TEXT;
    v_identity_id UUID;
BEGIN
    IF p_email IS NULL OR btrim(p_email) = '' THEN
        RETURN jsonb_build_object('success', false, 'message', 'El correo electrónico es requerido.');
    END IF;

    IF p_password IS NULL OR p_password = '' THEN
        RETURN jsonb_build_object('success', false, 'message', 'La contraseña es requerida.');
    END IF;

    IF p_nombre_completo IS NULL OR btrim(p_nombre_completo) = '' THEN
        RETURN jsonb_build_object('success', false, 'message', 'El nombre completo es requerido.');
    END IF;

    IF EXISTS (SELECT 1 FROM auth.users WHERE lower(email) = lower(btrim(p_email))) THEN
        RETURN jsonb_build_object('success', false, 'message', 'El correo electrónico ya está registrado.');
    END IF;

    v_rol_normalizado := lower(btrim(p_rol_nombre));

    SELECT id INTO v_rol_id FROM public.roles WHERE nombre = v_rol_normalizado;
    IF v_rol_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El rol ' || p_rol_nombre || ' no existe en el sistema.');
    END IF;

    v_user_id := gen_random_uuid();
    v_identity_id := gen_random_uuid();

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
        is_super_admin,
        is_sso_user,
        is_anonymous,
        confirmation_token,
        recovery_token,
        email_change_token_new,
        email_change,
        email_change_token_current,
        phone_change,
        phone_change_token,
        reauthentication_token,
        email_change_confirm_status
    ) VALUES (
        v_user_id,
        '00000000-0000-0000-0000-000000000000',
        lower(btrim(p_email)),
        crypt(p_password, gen_salt('bf')),
        now(),
        now(),
        now(),
        jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email')),
        jsonb_build_object('full_name', btrim(p_nombre_completo)),
        'authenticated',
        'authenticated',
        false,
        false,
        false,
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        0
    );

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
        jsonb_build_object(
            'sub', v_user_id::text,
            'email', lower(btrim(p_email)),
            'email_verified', true,
            'phone_verified', false
        ),
        'email',
        v_user_id::text,
        now(),
        now(),
        now()
    );

    INSERT INTO public.perfiles_usuario (
        id, rol_id, nombre_completo, telefono, activo, updated_at
    ) VALUES (
        v_user_id,
        v_rol_id,
        btrim(p_nombre_completo),
        COALESCE(p_telefono, ''),
        true,
        now()
    )
    ON CONFLICT (id) DO UPDATE
    SET
        rol_id = EXCLUDED.rol_id,
        nombre_completo = EXCLUDED.nombre_completo,
        telefono = EXCLUDED.telefono,
        updated_at = now();

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
$function$;

GRANT EXECUTE ON FUNCTION public.registra_nuevo_usuario(text, text, text, text, text) TO service_role;
