-- Migración de datos: Crear empresa de pruebas (lt_tests) y asignar usuarios superadmin

DO $$
DECLARE
    v_empresa_id UUID;
    v_response JSONB;
    v_user RECORD;
BEGIN
    -- 1. Crear la empresa usando el SP
    v_response := public.crea_nueva_empresa(
        'LT-TESTS', 
        'tests', 
        'https://tests-project-url.supabase.co', 
        'dummy-anon-key-tests'
    );
    
    -- Extraer el ID de la empresa recién creada
    v_empresa_id := (v_response->'data'->>'empresa_id')::UUID;
    
    -- 2. Asignar todos los usuarios actuales de auth.users a la nueva empresa
    -- Como la tabla de usuarios se vació recientemente, asumimos que los dos 
    -- que existen actualmente son los superadmins que mencionaste.
    FOR v_user IN SELECT id FROM auth.users LOOP
        PERFORM public.asignar_usuario_empresa(v_user.id, v_empresa_id, 'superadmin');
    END LOOP;
END;
$$;
