CREATE OR REPLACE FUNCTION public.cargar_datos_demo_dashboard()
RETURNS TABLE (
    ordenes INT,
    rendiciones INT,
    camiones INT,
    facturas INT,
    "choferId" UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_rol_admin_id UUID;
    v_rol_gerente_id UUID;
    v_rol_despachador_id UUID;
    v_rol_vendedor_id UUID;
    v_rol_chofer_id UUID;
    v_rol_cobrador_id UUID;
    
    v_user_vendedor_id UUID;
    v_user_chofer_id UUID;
    v_user_gerente_id UUID;
    
    v_cliente_1_id UUID;
    v_cliente_2_id UUID;
    v_cliente_3_id UUID;
    
    v_camion_1_id UUID;
    v_camion_2_id UUID;
    v_camion_3_id UUID;
    
    v_prod_1_id UUID;
    v_prod_2_id UUID;
    v_prod_3_id UUID;
    v_prod_4_id UUID;
    
    v_orden_1_id UUID;
    v_orden_2_id UUID;
    v_orden_3_id UUID;
    v_orden_4_id UUID;
    
    v_rendicion_1_id UUID;
    v_rendicion_2_id UUID;
    
    v_proveedor_id UUID;
    v_factura_id UUID;
    
    v_count_ordenes INT;
    v_count_rendiciones INT;
    v_count_camiones INT;
    v_count_facturas INT;
BEGIN
    -- 1. Asegurar la existencia de los roles
    INSERT INTO public.roles (nombre, descripcion)
    VALUES 
        ('admin', 'Administrador del sistema'),
        ('gerente', 'Gerente general'),
        ('despachador', 'Despachador de almacén'),
        ('vendedor', 'Vendedor / preventa'),
        ('chofer', 'Chofer distribuidor'),
        ('cobrador', 'Cobrador / cajero')
    ON CONFLICT (nombre) DO UPDATE SET descripcion = EXCLUDED.descripcion;

    -- Obtener IDs de los roles
    SELECT id INTO v_rol_admin_id FROM public.roles WHERE nombre = 'admin';
    SELECT id INTO v_rol_gerente_id FROM public.roles WHERE nombre = 'gerente';
    SELECT id INTO v_rol_despachador_id FROM public.roles WHERE nombre = 'despachador';
    SELECT id INTO v_rol_vendedor_id FROM public.roles WHERE nombre = 'vendedor';
    SELECT id INTO v_rol_chofer_id FROM public.roles WHERE nombre = 'chofer';
    SELECT id INTO v_rol_cobrador_id FROM public.roles WHERE nombre = 'cobrador';

    -- 2. Asegurar la existencia de usuarios demo en auth.users y public.perfiles_usuario
    -- Demo Vendedor
    SELECT id INTO v_user_vendedor_id FROM auth.users WHERE email = 'vendedor.demo@logitrack.com';
    IF v_user_vendedor_id IS NULL THEN
        v_user_vendedor_id := gen_random_uuid();
        INSERT INTO auth.users (id, instance_id, email, encrypted_password, email_confirmed_at, aud, role, is_anonymous, confirmation_token, recovery_token, email_change_token_new, email_change_token_current, phone_change_token, reauthentication_token)
        VALUES (v_user_vendedor_id, '00000000-0000-0000-0000-000000000000', 'vendedor.demo@logitrack.com', crypt('Demo1234_', gen_salt('bf')), NOW(), 'authenticated', 'authenticated', FALSE, '', '', '', '', '', '');
        
        INSERT INTO auth.identities (id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at)
        VALUES (gen_random_uuid(), v_user_vendedor_id, jsonb_build_object('sub', v_user_vendedor_id::text, 'email', 'vendedor.demo@logitrack.com', 'email_verified', true), 'email', v_user_vendedor_id::text, NOW(), NOW(), NOW());
    END IF;
    INSERT INTO public.perfiles_usuario (id, rol_id, nombre_completo, telefono, activo, updated_at)
    VALUES (v_user_vendedor_id, v_rol_vendedor_id, 'Pedro Pérez (Vendedor Demo)', '+584141112233', TRUE, NOW())
    ON CONFLICT (id) DO UPDATE SET rol_id = EXCLUDED.rol_id, nombre_completo = EXCLUDED.nombre_completo;

    -- Demo Chofer
    SELECT id INTO v_user_chofer_id FROM auth.users WHERE email = 'chofer.demo@logitrack.com';
    IF v_user_chofer_id IS NULL THEN
        v_user_chofer_id := gen_random_uuid();
        INSERT INTO auth.users (id, instance_id, email, encrypted_password, email_confirmed_at, aud, role, is_anonymous, confirmation_token, recovery_token, email_change_token_new, email_change_token_current, phone_change_token, reauthentication_token)
        VALUES (v_user_chofer_id, '00000000-0000-0000-0000-000000000000', 'chofer.demo@logitrack.com', crypt('Demo1234_', gen_salt('bf')), NOW(), 'authenticated', 'authenticated', FALSE, '', '', '', '', '', '');
        
        INSERT INTO auth.identities (id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at)
        VALUES (gen_random_uuid(), v_user_chofer_id, jsonb_build_object('sub', v_user_chofer_id::text, 'email', 'chofer.demo@logitrack.com', 'email_verified', true), 'email', v_user_chofer_id::text, NOW(), NOW(), NOW());
    END IF;
    INSERT INTO public.perfiles_usuario (id, rol_id, nombre_completo, telefono, activo, updated_at)
    VALUES (v_user_chofer_id, v_rol_chofer_id, 'Manuel Carreño (Chofer Demo)', '+584144445566', TRUE, NOW())
    ON CONFLICT (id) DO UPDATE SET rol_id = EXCLUDED.rol_id, nombre_completo = EXCLUDED.nombre_completo;
    
    INSERT INTO public.choferes (perfil_id, cedula_licencia, movil1, estado, created_at)
    VALUES (v_user_chofer_id, 'V-12345678', '+584144445566', 'disponible', NOW())
    ON CONFLICT (perfil_id) DO UPDATE SET cedula_licencia = EXCLUDED.cedula_licencia;

    -- Demo Gerente
    SELECT id INTO v_user_gerente_id FROM auth.users WHERE email = 'gerente.demo@logitrack.com';
    IF v_user_gerente_id IS NULL THEN
        v_user_gerente_id := gen_random_uuid();
        INSERT INTO auth.users (id, instance_id, email, encrypted_password, email_confirmed_at, aud, role, is_anonymous, confirmation_token, recovery_token, email_change_token_new, email_change_token_current, phone_change_token, reauthentication_token)
        VALUES (v_user_gerente_id, '00000000-0000-0000-0000-000000000000', 'gerente.demo@logitrack.com', crypt('Demo1234_', gen_salt('bf')), NOW(), 'authenticated', 'authenticated', FALSE, '', '', '', '', '', '');
        
        INSERT INTO auth.identities (id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at)
        VALUES (gen_random_uuid(), v_user_gerente_id, jsonb_build_object('sub', v_user_gerente_id::text, 'email', 'gerente.demo@logitrack.com', 'email_verified', true), 'email', v_user_gerente_id::text, NOW(), NOW(), NOW());
    END IF;
    INSERT INTO public.perfiles_usuario (id, rol_id, nombre_completo, telefono, activo, updated_at)
    VALUES (v_user_gerente_id, v_rol_gerente_id, 'Carlos Mendoza (Gerente Demo)', '+584149990000', TRUE, NOW())
    ON CONFLICT (id) DO UPDATE SET rol_id = EXCLUDED.rol_id, nombre_completo = EXCLUDED.nombre_completo;

    -- 3. Asegurar la existencia de clientes
    INSERT INTO public.clientes (rif_nit, razon_social, direccion_fiscal, telefono, activo)
    VALUES 
        ('J-12345678-9', 'Automercados Plaza''s C.A.', 'Av. Principal de Los Palos Grandes, Caracas', '+582122849922', TRUE),
        ('J-87654321-0', 'Supermercados Unicasa C.A.', 'Av. Francisco de Miranda, La California, Caracas', '+582122415511', TRUE),
        ('J-45678901-2', 'Central Madeirense C.A.', 'Zona Industrial La Yaguara, Caracas', '+582124712233', TRUE)
    ON CONFLICT (rif_nit) DO UPDATE SET razon_social = EXCLUDED.razon_social;
    
    SELECT id INTO v_cliente_1_id FROM public.clientes WHERE rif_nit = 'J-12345678-9';
    SELECT id INTO v_cliente_2_id FROM public.clientes WHERE rif_nit = 'J-87654321-0';
    SELECT id INTO v_cliente_3_id FROM public.clientes WHERE rif_nit = 'J-45678901-2';

    -- 4. Asegurar la existencia de camiones
    INSERT INTO public.camiones (placa, modelo, capacidad_kg, volumen_m3, estado)
    VALUES 
        ('A10BC3D', 'Iveco Daily 35-10', 3500.00, 12.00, 'disponible'),
        ('B99XX2Y', 'Toyota Dyna 4.5', 4500.00, 15.00, 'disponible'),
        ('C44ZZ5W', 'Chevrolet FVR 8.0', 8000.00, 32.00, 'disponible')
    ON CONFLICT (placa) DO UPDATE SET modelo = EXCLUDED.modelo;

    SELECT id INTO v_camion_1_id FROM public.camiones WHERE placa = 'A10BC3D';
    SELECT id INTO v_camion_2_id FROM public.camiones WHERE placa = 'B99XX2Y';
    SELECT id INTO v_camion_3_id FROM public.camiones WHERE placa = 'C44ZZ5W';

    -- 5. Asegurar la existencia de productos e inventario
    INSERT INTO public.productos (codigo_barras, nombre, descripcion, unidad_medida, peso_unitario_kg, cant_unidad_medida)
    VALUES 
        ('7591024000123', 'Harina de Maíz Precocida 1kg', 'Harina de maíz blanco ideal para arepas', 'bulto', 1.00, 20),
        ('7591024000456', 'Aceite Vegetal Mezcla 1L', 'Aceite para freír y cocinar', 'caja', 0.92, 12),
        ('7591024000789', 'Arroz Blanco Primor 1kg', 'Arroz tipo I pulido de grano largo', 'bulto', 1.00, 24),
        ('7591024000987', 'Pasta Larga Spaghetti 500g', 'Pasta de sémola de trigo durum', 'bulto', 0.50, 40)
    ON CONFLICT (codigo_barras) DO UPDATE SET nombre = EXCLUDED.nombre, peso_unitario_kg = EXCLUDED.peso_unitario_kg;

    SELECT id INTO v_prod_1_id FROM public.productos WHERE codigo_barras = '7591024000123';
    SELECT id INTO v_prod_2_id FROM public.productos WHERE codigo_barras = '7591024000456';
    SELECT id INTO v_prod_3_id FROM public.productos WHERE codigo_barras = '7591024000789';
    SELECT id INTO v_prod_4_id FROM public.productos WHERE codigo_barras = '7591024000987';

    -- Se coloca inventario en el almacén principal
    INSERT INTO public.inventario_almacen (producto_id, stock_disponible, stock_comprometido, ubicacion_pasillo)
    VALUES 
        (v_prod_1_id, 1500, 0, 'Pasillo A-03'),
        (v_prod_2_id, 800, 0, 'Pasillo B-12'),
        (v_prod_3_id, 1200, 0, 'Pasillo A-05'),
        (v_prod_4_id, 2000, 0, 'Pasillo C-01')
    ON CONFLICT (producto_id) DO UPDATE SET stock_disponible = EXCLUDED.stock_disponible;

    -- 6. Asegurar la existencia de órdenes de distribución
    -- Orden 1: Liquidada
    SELECT id INTO v_orden_1_id FROM public.ordenes_distribucion WHERE factura_origen_numero = 'FAC-000101';
    IF v_orden_1_id IS NULL THEN
        v_orden_1_id := gen_random_uuid();
        INSERT INTO public.ordenes_distribucion (id, correlativo, cliente_id, camion_id, chofer_id, estado, fecha_despacho, peso_total_calculado, factura_origen_numero, creado_por, created_at)
        VALUES (v_orden_1_id, 101, v_cliente_1_id, v_camion_1_id, v_user_chofer_id, 'liquidada', NOW() - INTERVAL '2 days', 240.00, 'FAC-000101', v_user_vendedor_id, NOW() - INTERVAL '2 days');
        
        INSERT INTO public.detalle_distribucion (orden_id, producto_id, cantidad_solicitada, cantidad_despachada, valor_unitario_recaudar, subtotal_recaudar, secuencia_entrega, estado_entrega)
        VALUES 
            (v_orden_1_id, v_prod_1_id, 100, 100, 1.20, 120.00, 1, 'entregado'),
            (v_orden_1_id, v_prod_3_id, 120, 120, 1.00, 120.00, 2, 'entregado');
    END IF;

    -- Orden 2: En tránsito
    SELECT id INTO v_orden_2_id FROM public.ordenes_distribucion WHERE factura_origen_numero = 'FAC-000102';
    IF v_orden_2_id IS NULL THEN
        v_orden_2_id := gen_random_uuid();
        INSERT INTO public.ordenes_distribucion (id, correlativo, cliente_id, camion_id, chofer_id, estado, fecha_despacho, peso_total_calculado, factura_origen_numero, creado_por, created_at)
        VALUES (v_orden_2_id, 102, v_cliente_2_id, v_camion_2_id, v_user_chofer_id, 'en_transito', NOW() - INTERVAL '3 hours', 150.00, 'FAC-000102', v_user_vendedor_id, NOW() - INTERVAL '5 hours');
        
        INSERT INTO public.detalle_distribucion (orden_id, producto_id, cantidad_solicitada, cantidad_despachada, valor_unitario_recaudar, subtotal_recaudar, secuencia_entrega, estado_entrega)
        VALUES 
            (v_orden_2_id, v_prod_2_id, 50, 50, 2.50, 125.00, 1, 'pendiente'),
            (v_orden_2_id, v_prod_4_id, 200, 200, 0.60, 120.00, 2, 'pendiente');

        -- Carga en inventario móvil para camión 2
        INSERT INTO public.inventario_movil (camion_id, producto_id, cantidad_cargada, cantidad_entregada, cantidad_devolucion)
        VALUES 
            (v_camion_2_id, v_prod_2_id, 50, 0, 0),
            (v_camion_2_id, v_prod_4_id, 200, 0, 0)
        ON CONFLICT (camion_id, producto_id) DO UPDATE SET cantidad_cargada = EXCLUDED.cantidad_cargada;
        
        -- Poner camión y chofer en ruta
        UPDATE public.camiones SET estado = 'en_ruta' WHERE id = v_camion_2_id;
        UPDATE public.choferes SET estado = 'en_ruta' WHERE perfil_id = v_user_chofer_id;
    END IF;

    -- Orden 3: Lista para carga
    SELECT id INTO v_orden_3_id FROM public.ordenes_distribucion WHERE factura_origen_numero = 'FAC-000103';
    IF v_orden_3_id IS NULL THEN
        v_orden_3_id := gen_random_uuid();
        INSERT INTO public.ordenes_distribucion (id, correlativo, cliente_id, camion_id, chofer_id, estado, fecha_despacho, peso_total_calculado, factura_origen_numero, creado_por, created_at)
        VALUES (v_orden_3_id, 103, v_cliente_3_id, v_camion_3_id, v_user_chofer_id, 'lista_para_carga', NULL, 180.00, 'FAC-000103', v_user_vendedor_id, NOW() - INTERVAL '10 hours');
        
        INSERT INTO public.detalle_distribucion (orden_id, producto_id, cantidad_solicitada, cantidad_despachada, valor_unitario_recaudar, subtotal_recaudar, secuencia_entrega, estado_entrega)
        VALUES 
            (v_orden_3_id, v_prod_1_id, 80, 0, 1.20, 96.00, 1, 'pendiente'),
            (v_orden_3_id, v_prod_3_id, 100, 0, 1.00, 100.00, 2, 'pendiente');

        -- Comprometer stock en almacén para orden 3
        UPDATE public.inventario_almacen SET stock_disponible = stock_disponible - 80, stock_comprometido = stock_comprometido + 80 WHERE producto_id = v_prod_1_id;
        UPDATE public.inventario_almacen SET stock_disponible = stock_disponible - 100, stock_comprometido = stock_comprometido + 100 WHERE producto_id = v_prod_3_id;
    END IF;

    -- Orden 4: Borrador
    SELECT id INTO v_orden_4_id FROM public.ordenes_distribucion WHERE factura_origen_numero = 'FAC-000104';
    IF v_orden_4_id IS NULL THEN
        v_orden_4_id := gen_random_uuid();
        INSERT INTO public.ordenes_distribucion (id, correlativo, cliente_id, camion_id, chofer_id, estado, fecha_despacho, peso_total_calculado, factura_origen_numero, creado_por, created_at)
        VALUES (v_orden_4_id, 104, v_cliente_1_id, v_camion_1_id, v_user_chofer_id, 'borrador', NULL, 12.00, 'FAC-000104', v_user_vendedor_id, NOW());
        
        INSERT INTO public.detalle_distribucion (orden_id, producto_id, cantidad_solicitada, cantidad_despachada, valor_unitario_recaudar, subtotal_recaudar, secuencia_entrega, estado_entrega)
        VALUES 
            (v_orden_4_id, v_prod_2_id, 10, 0, 2.55, 25.50, 1, 'pendiente'),
            (v_orden_4_id, v_prod_4_id, 5, 0, 0.65, 3.25, 2, 'pendiente');
    END IF;

    -- 7. Asegurar la existencia de proveedores y facturas de compras
    INSERT INTO public.proveedores (rif_nit, razon_social, direccion_fiscal, telefono, activo)
    VALUES 
        ('J-99999999-9', 'Alimentos Polar Comercial C.A.', 'Av. Rómulo Gallegos, Caracas', '+582122023111', TRUE)
    ON CONFLICT (rif_nit) DO UPDATE SET razon_social = EXCLUDED.razon_social;

    SELECT id INTO v_proveedor_id FROM public.proveedores WHERE rif_nit = 'J-99999999-9';

    SELECT id INTO v_factura_id FROM public.facturas_compras WHERE numero_factura = 'COMP-990011';
    IF v_factura_id IS NULL THEN
        v_factura_id := gen_random_uuid();
        INSERT INTO public.facturas_compras (id, proveedor_id, numero_factura, fecha_emision, fecha_vencimiento, monto_subtotal, monto_impuesto, monto_total, estado_pago, created_at)
        VALUES (v_factura_id, v_proveedor_id, 'COMP-990011', CURRENT_DATE - 5, CURRENT_DATE + 25, 1500.00, 240.00, 1740.00, 'pendiente', NOW());
        
        INSERT INTO public.detalle_facturas_compras (factura_id, producto_id, cantidad_comprada, precio_unitario_compra, sub_total_compra, monto_linea)
        VALUES 
            (v_factura_id, v_prod_1_id, 1000, 1.00, 1000.00, 1000.00),
            (v_factura_id, v_prod_2_id, 200, 2.50, 500.00, 500.00);
    END IF;

    -- 8. Asegurar la existencia de rendiciones de cuentas
    SELECT id INTO v_rendicion_1_id FROM public.rendiciones_cuentas WHERE observaciones = 'Rendición de viaje lunes - Ruta Este';
    IF v_rendicion_1_id IS NULL THEN
        v_rendicion_1_id := gen_random_uuid();
        INSERT INTO public.rendiciones_cuentas (id, cliente_id, fecha_rendicion, total_efectivo_recaudado, total_transferencias_recaudado, total_devoluciones_valoradas, estado, observaciones, auditado_por)
        VALUES (v_rendicion_1_id, v_cliente_1_id, NOW() - INTERVAL '1 day', 240.00, 0.00, 0.00, 'aprobada', 'Rendición de viaje lunes - Ruta Este', v_user_gerente_id);
        
        INSERT INTO public.detalle_rendicion_ordenes (rendicion_id, orden_distribucion_id, recaudado)
        VALUES (v_rendicion_1_id, v_orden_1_id, 240.00);
        
        INSERT INTO public.detalle_rendicion_pagos (rendicion_id, metodo_pago, monto, referencia_bancaria, cuenta_bancaria)
        VALUES (v_rendicion_1_id, 'efectivo_usd', 240.00, NULL, NULL);
    END IF;

    -- Calcular conteos finales para retornar
    SELECT COUNT(*)::INT INTO v_count_ordenes FROM public.ordenes_distribucion;
    SELECT COUNT(*)::INT INTO v_count_rendiciones FROM public.rendiciones_cuentas;
    SELECT COUNT(*)::INT INTO v_count_camiones FROM public.camiones;
    SELECT COUNT(*)::INT INTO v_count_facturas FROM public.facturas_compras;

    RETURN QUERY 
    SELECT 
        v_count_ordenes AS ordenes,
        v_count_rendiciones AS rendiciones,
        v_count_camiones AS camiones,
        v_count_facturas AS facturas,
        v_user_chofer_id AS "choferId";
END;
$$;
