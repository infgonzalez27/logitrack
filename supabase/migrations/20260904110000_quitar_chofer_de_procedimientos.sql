-- Migration: Quitar chofer de todos los procedimientos almacenados y políticas RLS

-- 1. liquidar_orden_distribucion
CREATE OR REPLACE FUNCTION public.liquidar_orden_distribucion(
    p_orden_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_estado_orden TEXT;
    v_cliente_id UUID;
    v_camion_id UUID;
    v_rendicion_aprobada BOOLEAN := FALSE;
BEGIN
    IF p_orden_id IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID de la orden es requerido.'
            )
        );
    END IF;

    SELECT estado, cliente_id, camion_id
    INTO v_estado_orden, v_cliente_id, v_camion_id
    FROM public.ordenes_distribucion
    WHERE id = p_orden_id;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'ORDEN_INEXISTENTE',
                'message', 'La orden de distribución especificada no existe.'
            )
        );
    END IF;

    IF v_estado_orden != 'por_liquidar' THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo se pueden liquidar financieramente órdenes que estén en estado por_liquidar.'
            )
        );
    END IF;

    SELECT EXISTS (
        SELECT 1 
        FROM public.detalle_rendicion_ordenes dro
        JOIN public.rendiciones_cuentas rc ON dro.rendicion_id = rc.id
        WHERE dro.orden_distribucion_id = p_orden_id
          AND rc.estado = 'aprobada'
    ) INTO v_rendicion_aprobada;

    IF NOT v_rendicion_aprobada THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'COBRANZA_PENDIENTE',
                'message', 'La orden no tiene una rendición de cuentas aprobada vinculada.'
            )
        );
    END IF;

    UPDATE public.camiones SET estado = 'disponible' WHERE id = v_camion_id;
    UPDATE public.ordenes_distribucion SET estado = 'liquidada' WHERE id = p_orden_id;

    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'orden_id', p_orden_id,
            'nuevo_estado', 'liquidada'
        ),
        'error', NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'SQL_ERROR',
                'message', SQLERRM,
                'details', 'SQLSTATE: ' || SQLSTATE
            )
        );
END;
$$;

-- 2. actualizar_estado_orden_distribucion
CREATE OR REPLACE FUNCTION public.actualizar_estado_orden_distribucion(
    p_orden_id UUID,
    p_estado TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_estado_actual TEXT;
    v_camion_id UUID;
    v_creado_por UUID;
    v_user_id UUID := auth.uid();
    v_item RECORD;
    v_producto_nombre TEXT;
    v_stock_disponible INT;
    v_stock_comprometido INT;
BEGIN
    IF p_orden_id IS NULL THEN
        RAISE EXCEPTION 'El ID de la orden es requerido.';
    END IF;

    IF p_estado IS NULL THEN
        RAISE EXCEPTION 'El estado de destino es requerido.';
    END IF;

    IF p_estado NOT IN ('borrador', 'lista_para_carga', 'en_transito', 'liquidada', 'anulada') THEN
        RAISE EXCEPTION 'El estado % no es un estado válido para la orden.', p_estado;
    END IF;

    SELECT estado, camion_id, creado_por 
    INTO v_estado_actual, v_camion_id, v_creado_por
    FROM public.ordenes_distribucion
    WHERE id = p_orden_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La orden de distribución con ID % no existe.', p_orden_id;
    END IF;

    IF public.user_has_role(ARRAY['vendedor']) AND NOT public.user_has_role(ARRAY['admin', 'gerente', 'despachador']) THEN
        IF v_user_id IS NOT NULL AND v_creado_por IS DISTINCT FROM v_user_id THEN
            RAISE EXCEPTION 'ACCESO_DENEGADO: Un vendedor solo puede modificar las órdenes que ha registrado.';
        END IF;
    END IF;

    IF v_estado_actual = p_estado THEN
        RETURN;
    END IF;

    IF v_estado_actual = 'borrador' AND p_estado NOT IN ('lista_para_carga', 'anulada') THEN
        RAISE EXCEPTION 'Transición no permitida: de % a %.', v_estado_actual, p_estado;
    ELSIF v_estado_actual = 'lista_para_carga' AND p_estado NOT IN ('en_transito', 'borrador', 'anulada') THEN
        RAISE EXCEPTION 'Transición no permitida: de % a %.', v_estado_actual, p_estado;
    ELSIF v_estado_actual = 'en_transito' AND p_estado NOT IN ('liquidada', 'anulada') THEN
        RAISE EXCEPTION 'Transición no permitida: de % a %.', v_estado_actual, p_estado;
    ELSIF v_estado_actual IN ('liquidada', 'anulada') THEN
        RAISE EXCEPTION 'No se pueden realizar cambios de estado en una orden %.', v_estado_actual;
    END IF;

    IF v_estado_actual = 'borrador' AND p_estado = 'lista_para_carga' THEN
        FOR v_item IN 
            SELECT producto_id, cantidad_solicitada 
            FROM public.detalle_distribucion 
            WHERE orden_id = p_orden_id
        LOOP
            SELECT stock_disponible, stock_comprometido 
            INTO v_stock_disponible, v_stock_comprometido
            FROM public.inventario_almacen
            WHERE producto_id = v_item.producto_id
            FOR UPDATE;

            IF NOT FOUND THEN
                SELECT nombre INTO v_producto_nombre FROM public.productos WHERE id = v_item.producto_id;
                RAISE EXCEPTION 'El producto % no tiene un registro de inventario en almacén.', COALESCE(v_producto_nombre, v_item.producto_id::text);
            END IF;

            IF v_stock_disponible < v_item.cantidad_solicitada THEN
                SELECT nombre INTO v_producto_nombre FROM public.productos WHERE id = v_item.producto_id;
                RAISE EXCEPTION 'Stock insuficiente en almacén para el producto % (Disponible: %, Requerido: %).', 
                    COALESCE(v_producto_nombre, v_item.producto_id::text), v_stock_disponible, v_item.cantidad_solicitada;
            END IF;

            UPDATE public.inventario_almacen
            SET stock_disponible = stock_disponible - v_item.cantidad_solicitada,
                stock_comprometido = stock_comprometido + v_item.cantidad_solicitada,
                updated_at = NOW()
            WHERE producto_id = v_item.producto_id;
        END LOOP;

        UPDATE public.ordenes_distribucion
        SET estado = 'lista_para_carga'
        WHERE id = p_orden_id;

    ELSIF v_estado_actual = 'lista_para_carga' AND p_estado = 'borrador' THEN
        FOR v_item IN 
            SELECT producto_id, cantidad_solicitada 
            FROM public.detalle_distribucion 
            WHERE orden_id = p_orden_id
        LOOP
            UPDATE public.inventario_almacen
            SET stock_disponible = stock_disponible + v_item.cantidad_solicitada,
                stock_comprometido = stock_comprometido - v_item.cantidad_solicitada,
                updated_at = NOW()
            WHERE producto_id = v_item.producto_id;
        END LOOP;

        UPDATE public.ordenes_distribucion
        SET estado = 'borrador'
        WHERE id = p_orden_id;

    ELSIF v_estado_actual = 'lista_para_carga' AND p_estado = 'en_transito' THEN
        IF v_camion_id IS NULL THEN
            RAISE EXCEPTION 'No se puede despachar la orden porque no tiene un camión asignado.';
        END IF;

        UPDATE public.camiones
        SET estado = 'en_ruta'
        WHERE id = v_camion_id;

        FOR v_item IN 
            SELECT producto_id, cantidad_solicitada 
            FROM public.detalle_distribucion 
            WHERE orden_id = p_orden_id
        LOOP
            UPDATE public.inventario_almacen
            SET stock_comprometido = stock_comprometido - v_item.cantidad_solicitada,
                updated_at = NOW()
            WHERE producto_id = v_item.producto_id;

            INSERT INTO public.inventario_movil (
                camion_id,
                producto_id,
                cantidad_cargada,
                cantidad_entregada,
                cantidad_devolucion,
                updated_at
            ) VALUES (
                v_camion_id,
                v_item.producto_id,
                v_item.cantidad_solicitada,
                0,
                0,
                NOW()
            )
            ON CONFLICT (camion_id, producto_id) 
            DO UPDATE SET 
                cantidad_cargada = inventario_movil.cantidad_cargada + v_item.cantidad_solicitada,
                updated_at = NOW();

            UPDATE public.detalle_distribucion
            SET cantidad_despachada = v_item.cantidad_solicitada
            WHERE orden_id = p_orden_id AND producto_id = v_item.producto_id;
        END LOOP;

        UPDATE public.ordenes_distribucion
        SET estado = 'en_transito',
            fecha_despacho = NOW()
        WHERE id = p_orden_id;

    ELSIF v_estado_actual = 'en_transito' AND p_estado = 'liquidada' THEN
        UPDATE public.camiones
        SET estado = 'disponible'
        WHERE id = v_camion_id;

        FOR v_item IN 
            SELECT producto_id, cantidad_despachada, COALESCE(estado_entrega, 'pendiente') as estado_entrega
            FROM public.detalle_distribucion 
            WHERE orden_id = p_orden_id
        LOOP
            IF v_item.estado_entrega IN ('entregado', 'pendiente', 'entregado_parcial') THEN
                UPDATE public.inventario_movil
                SET cantidad_cargada = cantidad_cargada - v_item.cantidad_despachada,
                    cantidad_entregada = cantidad_entregada + v_item.cantidad_despachada,
                    updated_at = NOW()
                WHERE camion_id = v_camion_id AND producto_id = v_item.producto_id;

            ELSIF v_item.estado_entrega = 'rechazado' THEN
                UPDATE public.inventario_movil
                SET cantidad_cargada = cantidad_cargada - v_item.cantidad_despachada,
                    cantidad_devolucion = cantidad_devolucion + v_item.cantidad_despachada,
                    updated_at = NOW()
                WHERE camion_id = v_camion_id AND producto_id = v_item.producto_id;

                UPDATE public.inventario_almacen
                SET stock_disponible = stock_disponible + v_item.cantidad_despachada,
                    updated_at = NOW()
                WHERE producto_id = v_item.producto_id;
            END IF;
        END LOOP;

        UPDATE public.ordenes_distribucion
        SET estado = 'liquidada'
        WHERE id = p_orden_id;

    ELSIF p_estado = 'anulada' THEN
        IF v_estado_actual = 'borrador' THEN
            NULL;

        ELSIF v_estado_actual = 'lista_para_carga' THEN
            FOR v_item IN 
                SELECT producto_id, cantidad_solicitada 
                FROM public.detalle_distribucion 
                WHERE orden_id = p_orden_id
            LOOP
                UPDATE public.inventario_almacen
                SET stock_disponible = stock_disponible + v_item.cantidad_solicitada,
                    stock_comprometido = stock_comprometido - v_item.cantidad_solicitada,
                    updated_at = NOW()
                WHERE producto_id = v_item.producto_id;
            END LOOP;

        ELSIF v_estado_actual = 'en_transito' THEN
            UPDATE public.camiones
            SET estado = 'disponible'
            WHERE id = v_camion_id;

            FOR v_item IN 
                SELECT producto_id, cantidad_despachada 
                FROM public.detalle_distribucion 
                WHERE orden_id = p_orden_id
            LOOP
                UPDATE public.inventario_movil
                SET cantidad_cargada = cantidad_cargada - v_item.cantidad_despachada,
                    updated_at = NOW()
                WHERE camion_id = v_camion_id AND producto_id = v_item.producto_id;

                UPDATE public.inventario_almacen
                SET stock_disponible = stock_disponible + v_item.cantidad_despachada,
                    updated_at = NOW()
                WHERE producto_id = v_item.producto_id;
            END LOOP;
        END IF;

        UPDATE public.ordenes_distribucion
        SET estado = 'anulada'
        WHERE id = p_orden_id;
    END IF;

END;
$$;

-- 3. actualiza_orden_distribucion_segun_correlativo
CREATE OR REPLACE FUNCTION public.actualiza_orden_distribucion_segun_correlativo(
    p_correlativo INT,
    p_header JSONB,
    p_detalle JSONB
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_orden_id UUID;
    v_estado_actual TEXT;
    v_creado_por UUID;
    v_user_id UUID := auth.uid();
    
    v_cliente_id UUID;
    v_camion_id UUID;
    v_fecha_despacho TIMESTAMPTZ;
    v_factura_origen TEXT;
    v_fecha_tasa DATE;
    v_tasa_cambio NUMERIC(14,4);
    
    v_peso_total NUMERIC(14,2) := 0.00;
    v_total_bs NUMERIC(14,2) := 0.00;
    v_total_usd NUMERIC(14,2) := 0.00;
    
    v_item JSONB;
    v_secuencia INT := 1;
    v_producto_id UUID;
    v_cantidad INT;
    v_val_recaudar_bs NUMERIC(14,2);
    v_val_usd NUMERIC(14,2);
    v_subtotal_bs NUMERIC(14,2);
    v_subtotal_usd NUMERIC(14,2);
    v_peso_unitario NUMERIC(14,2);
BEGIN
    IF p_correlativo IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El correlativo de la orden es requerido.',
                'details', NULL
            )
        );
    END IF;

    SELECT id, estado, creado_por
    INTO v_orden_id, v_estado_actual, v_creado_por
    FROM public.ordenes_distribucion
    WHERE correlativo = p_correlativo;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ORDEN_NO_ENCONTRADA',
                'message', 'No se encontró la orden con correlativo ' || p_correlativo::text,
                'details', NULL
            )
        );
    END IF;

    IF v_estado_actual NOT IN ('borrador') THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo se pueden actualizar órdenes en estado borrador. Estado actual: ' || v_estado_actual,
                'details', NULL
            )
        );
    END IF;

    IF public.user_has_role(ARRAY['vendedor']) AND NOT public.user_has_role(ARRAY['admin', 'gerente', 'despachador']) THEN
        IF v_user_id IS NOT NULL AND v_creado_por IS DISTINCT FROM v_user_id THEN
            RETURN json_build_object(
                'success', false,
                'data', NULL,
                'error', json_build_object(
                    'code', 'ACCESO_DENEGADO',
                    'message', 'Un vendedor solo puede actualizar las órdenes que él mismo ha registrado.',
                    'details', NULL
                )
            );
        END IF;
    END IF;

    v_cliente_id := (p_header->>'cliente_id')::UUID;
    v_camion_id := (p_header->>'camion_id')::UUID;
    v_fecha_despacho := (p_header->>'fecha_despacho')::TIMESTAMPTZ;
    v_factura_origen := p_header->>'factura_origen_numero';
    v_fecha_tasa := COALESCE(v_fecha_despacho::date, CURRENT_DATE);

    SELECT tasa_cambio INTO v_tasa_cambio
    FROM public.tasa_cambio
    WHERE fecha_tasa = v_fecha_tasa;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'EXCEPCION_TASA_NO_ENCONTRADA',
                'message', 'No existe tasa de cambio registrada para la fecha ' || v_fecha_tasa::text,
                'details', NULL
            )
        );
    END IF;

    IF p_detalle IS NOT NULL AND jsonb_array_length(p_detalle) > 0 THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(p_detalle) LOOP
            v_producto_id := (v_item->>'producto_id')::UUID;
            v_cantidad := (v_item->>'cantidad_solicitada')::INT;
            v_val_recaudar_bs := (v_item->>'valor_unitario_recaudar')::NUMERIC;
            v_val_usd := (v_item->>'valor_unitario_usd')::NUMERIC;

            IF v_val_usd IS NULL OR v_val_usd = 0 THEN
                v_val_usd := ROUND(v_val_recaudar_bs / v_tasa_cambio, 2);
            END IF;

            v_subtotal_bs := v_cantidad * v_val_recaudar_bs;
            v_subtotal_usd := v_cantidad * v_val_usd;

            v_total_bs := v_total_bs + v_subtotal_bs;
            v_total_usd := v_total_usd + v_subtotal_usd;

            SELECT COALESCE(peso_unitario_kg, 0) INTO v_peso_unitario
            FROM public.productos WHERE id = v_producto_id;

            v_peso_total := v_peso_total + (v_peso_unitario * v_cantidad);
        END LOOP;
    END IF;

    UPDATE public.ordenes_distribucion
    SET cliente_id = COALESCE(v_cliente_id, cliente_id),
        camion_id = COALESCE(v_camion_id, camion_id),
        fecha_despacho = COALESCE(v_fecha_despacho, fecha_despacho),
        factura_origen_numero = COALESCE(v_factura_origen, factura_origen_numero),
        tasa_cambio = v_tasa_cambio,
        peso_total_calculado = v_peso_total,
        total_recaudar_bs = v_total_bs,
        total_recaudar_usd = v_total_usd
    WHERE id = v_orden_id;

    IF p_detalle IS NOT NULL AND jsonb_array_length(p_detalle) > 0 THEN
        DELETE FROM public.detalle_distribucion WHERE orden_id = v_orden_id;

        FOR v_item IN SELECT * FROM jsonb_array_elements(p_detalle) LOOP
            v_producto_id := (v_item->>'producto_id')::UUID;
            v_cantidad := (v_item->>'cantidad_solicitada')::INT;
            v_val_recaudar_bs := (v_item->>'valor_unitario_recaudar')::NUMERIC;
            v_val_usd := (v_item->>'valor_unitario_usd')::NUMERIC;

            IF v_val_usd IS NULL OR v_val_usd = 0 THEN
                v_val_usd := ROUND(v_val_recaudar_bs / v_tasa_cambio, 2);
            END IF;

            v_subtotal_bs := v_cantidad * v_val_recaudar_bs;
            v_subtotal_usd := v_cantidad * v_val_usd;

            INSERT INTO public.detalle_distribucion (
                id,
                orden_id,
                producto_id,
                cantidad_solicitada,
                cantidad_despachada,
                valor_unitario_recaudar,
                subtotal_recaudar,
                valor_unitario_usd,
                subtotal_recaudar_usd,
                secuencia_entrega,
                estado_entrega
            ) VALUES (
                gen_random_uuid(),
                v_orden_id,
                v_producto_id,
                v_cantidad,
                0,
                v_val_recaudar_bs,
                v_subtotal_bs,
                v_val_usd,
                v_subtotal_usd,
                v_secuencia,
                'pendiente'
            );

            v_secuencia := v_secuencia + 1;
        END LOOP;
    END IF;

    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'correlativo', p_correlativo,
            'orden_id', v_orden_id,
            'tasa_cambio', v_tasa_cambio,
            'total_recaudar_bs', v_total_bs,
            'total_recaudar_usd', v_total_usd
        ),
        'error', NULL
    );

EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object(
        'success', false,
        'data', NULL,
        'error', json_build_object(
            'code', 'SQL_ERROR',
            'message', SQLERRM,
            'details', NULL
        )
    );
END;
$$;

-- 4. retorna_ordenes_distribucion_segun_estado
CREATE OR REPLACE FUNCTION public.retorna_ordenes_distribucion_segun_estado(
    p_estado TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_is_vendedor BOOLEAN := FALSE;
    v_is_gerente_admin BOOLEAN := FALSE;
    v_ordenes JSON;
BEGIN
    IF p_estado IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El estado de la orden es requerido.',
                'details', NULL
            )
        );
    END IF;

    v_is_gerente_admin := public.user_has_role(ARRAY['admin', 'gerente', 'despachador']);
    v_is_vendedor := public.user_has_role(ARRAY['vendedor']);

    SELECT COALESCE(json_agg(
        json_build_object(
            'id', o.id,
            'correlativo', o.correlativo,
            'cliente_id', o.cliente_id,
            'cliente_razon_social', c.razon_social,
            'cliente_vendedor_id', c.vendedor_id,
            'camion_id', o.camion_id,
            'estado', o.estado,
            'fecha_despacho', o.fecha_despacho,
            'peso_total_calculado', o.peso_total_calculado,
            'factura_origen_numero', o.factura_origen_numero,
            'tasa_cambio', o.tasa_cambio,
            'total_recaudar_bs', o.total_recaudar_bs,
            'total_recaudar_usd', o.total_recaudar_usd,
            'creado_por', o.creado_por,
            'created_at', o.created_at
        ) ORDER BY o.correlativo DESC
    ), '[]'::json)
    INTO v_ordenes
    FROM public.ordenes_distribucion o
    LEFT JOIN public.clientes c ON c.id = o.cliente_id
    WHERE o.estado = p_estado
      AND (
          v_is_gerente_admin 
          OR (v_is_vendedor AND (c.vendedor_id = v_user_id OR o.creado_por = v_user_id))
      );

    RETURN json_build_object(
        'success', true,
        'data', v_ordenes,
        'error', NULL
    );

EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object(
        'success', false,
        'data', NULL,
        'error', json_build_object(
            'code', 'SQL_ERROR',
            'message', SQLERRM,
            'details', NULL
        )
    );
END;
$$;

-- 5. registra_nuevo_usuario
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
    IF p_email IS NULL OR p_email = '' THEN
        RETURN jsonb_build_object('success', false, 'message', 'El correo electrónico es requerido.');
    END IF;

    IF p_password IS NULL OR p_password = '' THEN
        RETURN jsonb_build_object('success', false, 'message', 'La contraseña es requerida.');
    END IF;

    IF p_nombre_completo IS NULL OR p_nombre_completo = '' THEN
        RETURN jsonb_build_object('success', false, 'message', 'El nombre completo es requerido.');
    END IF;

    IF EXISTS (SELECT 1 FROM auth.users WHERE email = p_email) THEN
        RETURN jsonb_build_object('success', false, 'message', 'El correo electrónico ya está registrado.');
    END IF;

    v_rol_normalizado := LOWER(TRIM(p_rol_nombre));

    SELECT id INTO v_rol_id FROM public.roles WHERE nombre = v_rol_normalizado;
    IF v_rol_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El rol ' || p_rol_nombre || ' no existe en el sistema.');
    END IF;

    v_user_id := gen_random_uuid();
    v_identity_id := gen_random_uuid();

    INSERT INTO auth.users (
        id, instance_id, email, encrypted_password, email_confirmed_at,
        created_at, updated_at, raw_app_meta_data, raw_user_meta_data,
        aud, role, is_anonymous, confirmation_token, recovery_token,
        email_change_token_new, email_change_token_current, phone_change_token, reauthentication_token
    ) VALUES (
        v_user_id, '00000000-0000-0000-0000-000000000000', p_email, crypt(p_password, gen_salt('bf')), NOW(),
        NOW(), NOW(), jsonb_build_object('provider', 'email', 'providers', array_to_json(array['email'])),
        jsonb_build_object('full_name', p_nombre_completo), 'authenticated', 'authenticated', FALSE,
        '', '', '', '', '', ''
    );

    INSERT INTO auth.identities (
        id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at
    ) VALUES (
        v_identity_id, v_user_id, jsonb_build_object('sub', v_user_id::text, 'email', p_email, 'email_verified', true, 'phone_verified', false),
        'email', v_user_id::text, NOW(), NOW(), NOW()
    );

    INSERT INTO public.perfiles_usuario (
        id, rol_id, nombre_completo, telefono, activo, updated_at
    ) VALUES (
        v_user_id, v_rol_id, p_nombre_completo, p_telefono, TRUE, NOW()
    )
    ON CONFLICT (id) DO UPDATE 
    SET rol_id = EXCLUDED.rol_id, nombre_completo = EXCLUDED.nombre_completo, telefono = EXCLUDED.telefono, updated_at = NOW();

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

-- 6. Actualización de RLS
DROP POLICY IF EXISTS select_ordenes_distribucion ON public.ordenes_distribucion;
CREATE POLICY select_ordenes_distribucion ON public.ordenes_distribucion
FOR SELECT
USING (
    public.user_has_role(ARRAY['admin', 'gerente', 'despachador'])
);
