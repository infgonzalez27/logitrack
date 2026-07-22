-- Script para registrar 3 camiones
INSERT INTO public.camiones (placa, modelo, capacidad_kg, volumen_m3, estado)
VALUES 
    ('CAM-001', 'Camion 1', 3500.00, 12.00, 'disponible'),
    ('CAM-002', 'Camion 2', 4500.00, 15.00, 'disponible'),
    ('CAM-003', 'Camion 3', 8000.00, 32.00, 'disponible')
ON CONFLICT (placa) DO UPDATE 
SET modelo = EXCLUDED.modelo,
    capacidad_kg = EXCLUDED.capacidad_kg,
    volumen_m3 = EXCLUDED.volumen_m3;

-- Script para registrar 2 choferes usando la función registra_nuevo_usuario
DO $$
DECLARE
    v_res JSONB;
BEGIN
    -- Registrar Andres Guzman (Chofer 1)
    IF NOT EXISTS (SELECT 1 FROM auth.users WHERE email = 'andres.guzman@logitrack.com') THEN
        v_res := public.registra_nuevo_usuario(
            'andres.guzman@logitrack.com', 
            'ChoferPass123!', 
            'Andres Guzman', 
            '+584120000001', 
            'chofer'
        );
        RAISE NOTICE 'Registro Andres Guzman: %', v_res;
    ELSE
        RAISE NOTICE 'Andres Guzman ya está registrado.';
    END IF;

    -- Registrar Manuel Gomez (Chofer 2)
    IF NOT EXISTS (SELECT 1 FROM auth.users WHERE email = 'manuel.gomez@logitrack.com') THEN
        v_res := public.registra_nuevo_usuario(
            'manuel.gomez@logitrack.com', 
            'ChoferPass123!', 
            'Manuel Gomez', 
            '+584120000002', 
            'chofer'
        );
        RAISE NOTICE 'Registro Manuel Gomez: %', v_res;
    ELSE
        RAISE NOTICE 'Manuel Gomez ya está registrado.';
    END IF;
END;
$$;
