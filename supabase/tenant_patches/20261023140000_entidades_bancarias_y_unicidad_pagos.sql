-- ==============================================================================
-- Parche Idempotente: Catálogo de Entidades Bancarias (BCV) y Control de Duplicidad de Referencias en Cobranzas
-- Fecha: 2026-10-23 14:00:00
-- Descripción:
-- 1. Crea la tabla `public.entidades_bancarias` con clave primaria natural `codigo_eb VARCHAR(4)`.
-- 2. Inserta las entidades bancarias activas en Venezuela según el BCV / SUDEBAN.
-- 3. Crea la función RPC `public.retorna_entidades_bancarias(p_solo_activas boolean)`.
-- 4. Agrega la columna `codigo_banco VARCHAR(4)` a `public.detalle_rendicion_fpagos`
--    (dejando los registros históricos en NULL - Opción A) y la restricción única
--    compuesta `CONSTRAINT uq_pago_banco_referencia UNIQUE (codigo_banco, referencia_bancaria)`.
-- 5. Actualiza `public.registrar_rendicion_cuentas` para recibir, validar y guardar
--    `codigo_banco`, verificando previamente la duplicidad `(codigo_banco, referencia_bancaria)`.
-- 6. Actualiza `public.reversa_rendicion_cuenta_segun_id_rendicion` para liberar `codigo_banco`
--    (poniéndolo en NULL) cuando una cobranza es reversada por gerencia.
-- 7. Actualiza `public.reporte_formas_pago_rendicion` y `public.reporte_recaudaciones_gerenciales`
--    para exponer `codigo_banco` y `nombre_banco`.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Tabla: public.entidades_bancarias
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.entidades_bancarias (
    codigo_eb VARCHAR(4) PRIMARY KEY,      -- '0102', '0134', '0105', etc.
    nombre_eb VARCHAR(120) NOT NULL,
    nombre_corto VARCHAR(50),
    rif_eb VARCHAR(15),
    activo BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.entidades_bancarias OWNER TO postgres;
ALTER TABLE public.entidades_bancarias ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Lectura publica de entidades_bancarias" ON public.entidades_bancarias;
CREATE POLICY "Lectura publica de entidades_bancarias"
    ON public.entidades_bancarias
    FOR SELECT
    TO anon, authenticated, service_role
    USING (true);

GRANT SELECT ON TABLE public.entidades_bancarias TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.entidades_bancarias TO service_role;

-- ------------------------------------------------------------------------------
-- 2. Semilla de Entidades Bancarias Activas en Venezuela (BCV / SUDEBAN)
-- ------------------------------------------------------------------------------
INSERT INTO public.entidades_bancarias (codigo_eb, nombre_eb, nombre_corto, rif_eb, activo)
VALUES
    ('0102', 'Banco de Venezuela, S.A. Banco Universal', 'Banco de Venezuela', 'G-20009997-6', true),
    ('0104', 'Venezolano de Crédito, S.A. Banco Universal', 'Venezolano de Crédito', 'J-00002970-9', true),
    ('0105', 'Mercantil, C.A. Banco Universal', 'Banco Mercantil', 'J-00002961-0', true),
    ('0108', 'BBVA Provincial, S.A. Banco Universal', 'BBVA Provincial', 'J-00002967-9', true),
    ('0114', 'Bancaribe, C.A. Banco Universal', 'Bancaribe', 'J-00002949-0', true),
    ('0115', 'Banco Exterior, C.A. Banco Universal', 'Banco Exterior', 'J-00002950-4', true),
    ('0128', 'Banco Caroní, C.A. Banco Universal', 'Banco Caroní', 'J-09504855-1', true),
    ('0134', 'Banesco Banco Universal, C.A.', 'Banesco', 'J-07013380-5', true),
    ('0137', 'Banco Sofitasa Banco Universal, C.A.', 'Sofitasa', 'J-09028384-6', true),
    ('0138', 'Banco Plaza, Banco Universal, C.A.', 'Banco Plaza', 'J-00297055-3', true),
    ('0146', 'Banco de la Gente Emprendedora (Bangente), C.A.', 'Bangente', 'J-30144204-0', true),
    ('0151', 'BFC Banco Fondo Común, C.A. Banco Universal', 'BFC Fondo Común', 'J-00072306-0', true),
    ('0156', '100% Banco, Banco Universal, C.A.', '100% Banco', 'J-08500776-8', true),
    ('0157', 'DelSur Banco Universal, C.A.', 'DelSur', 'J-00079723-4', true),
    ('0163', 'Banco del Tesoro, C.A. Banco Universal', 'Banco del Tesoro', 'G-20005187-6', true),
    ('0166', 'Banco Agrícola de Venezuela, C.A. Banco Universal', 'Banco Agrícola', 'G-20005795-5', true),
    ('0168', 'Bancrecer, S.A. Banco Microfinanciero', 'Bancrecer', 'J-31637417-3', true),
    ('0169', 'R4, Banco Microfinanciero, C.A.', 'R4 / Mi Banco', 'J-31594102-3', true),
    ('0171', 'Banco Activo, C.A. Banco Universal', 'Banco Activo', 'J-08006622-7', true),
    ('0172', 'Bancamiga Banco Universal, C.A.', 'Bancamiga', 'J-31628759-9', true),
    ('0173', 'Banco Internacional de Desarrollo, C.A. Banco Universal', 'BID', 'J-29464010-9', true),
    ('0174', 'Banplus Banco Universal, C.A.', 'Banplus', 'J-00042303-2', true),
    ('0175', 'Banco Digital de los Trabajadores, Banco Universal, C.A.', 'BDT / Bicentenario', 'G-20009148-7', true),
    ('0177', 'Banco de la Fuerza Armada Nacional Bolivariana, B.U.', 'BANFANB', 'G-20010657-3', true),
    ('0178', 'N58 Banco Digital, Banco Microfinanciero, S.A.', 'N58 Banco Digital', 'J-50358110-7', true),
    ('0191', 'Banco Nacional de Crédito, C.A. Banco Universal', 'BNC', 'J-30984132-7', true)
ON CONFLICT (codigo_eb) DO UPDATE
SET
    nombre_eb = EXCLUDED.nombre_eb,
    nombre_corto = EXCLUDED.nombre_corto,
    rif_eb = EXCLUDED.rif_eb,
    activo = EXCLUDED.activo;

-- ------------------------------------------------------------------------------
-- 3. Función RPC: public.retorna_entidades_bancarias
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.retorna_entidades_bancarias(p_solo_activas boolean DEFAULT true)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_data JSON;
BEGIN
    SELECT json_agg(
        json_build_object(
            'codigo_eb', eb.codigo_eb,
            'nombre_eb', eb.nombre_eb,
            'nombre_corto', eb.nombre_corto,
            'rif_eb', eb.rif_eb,
            'activo', eb.activo,
            'created_at', eb.created_at
        ) ORDER BY eb.codigo_eb ASC
    ) INTO v_data
    FROM public.entidades_bancarias eb
    WHERE (p_solo_activas = FALSE OR eb.activo = TRUE);

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

ALTER FUNCTION public.retorna_entidades_bancarias(boolean) OWNER TO postgres;
GRANT ALL ON FUNCTION public.retorna_entidades_bancarias(boolean) TO anon, authenticated, service_role;

-- ------------------------------------------------------------------------------
-- 4. Modificación de public.detalle_rendicion_fpagos (Columna y Restricción Única)
--    Opción A: Registros históricos quedan con codigo_banco = NULL.
-- ------------------------------------------------------------------------------
ALTER TABLE public.detalle_rendicion_fpagos
    ADD COLUMN IF NOT EXISTS codigo_banco VARCHAR(4);

ALTER TABLE public.detalle_rendicion_fpagos
    DROP CONSTRAINT IF EXISTS detalle_rendicion_fpagos_codigo_banco_fkey;

ALTER TABLE public.detalle_rendicion_fpagos
    ADD CONSTRAINT detalle_rendicion_fpagos_codigo_banco_fkey
    FOREIGN KEY (codigo_banco) REFERENCES public.entidades_bancarias(codigo_eb)
    ON DELETE RESTRICT;

ALTER TABLE public.detalle_rendicion_fpagos
    DROP CONSTRAINT IF EXISTS uq_pago_banco_referencia;

ALTER TABLE public.detalle_rendicion_fpagos
    ADD CONSTRAINT uq_pago_banco_referencia
    UNIQUE (codigo_banco, referencia_bancaria);

-- ------------------------------------------------------------------------------
-- 5. Actualización de public.registrar_rendicion_cuentas (5 y 6 parámetros)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.registrar_rendicion_cuentas(
    p_cliente_id uuid,
    p_observaciones text,
    p_creado_por uuid,
    p_ordenes jsonb,
    p_pagos jsonb,
    p_tasa_cambio numeric DEFAULT NULL::numeric
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_rendicion_id UUID;
    v_tasa_cambio NUMERIC(10, 4);
    v_total_ordenes NUMERIC(12, 2) := 0.00;
    v_total_ordenes_bs NUMERIC(12, 2) := 0.00;
    v_total_pagos NUMERIC(12, 2) := 0.00;
    v_total_pagos_bs NUMERIC(12, 2) := 0.00;
    v_total_efectivo NUMERIC(12, 2) := 0.00;
    v_total_transferencias NUMERIC(12, 2) := 0.00;
    v_saldo_favor_usado NUMERIC(12, 2) := 0.00;
    v_cliente_saldo_favor NUMERIC(12, 2) := 0.00;
    v_item RECORD;
    v_pago RECORD;
    v_exceso NUMERIC(12, 2) := 0.00;
    v_exceso_bs NUMERIC(12, 2) := 0.00;
    v_fpago_concepto TEXT;
    v_fpago_info BOOLEAN;
    v_item_usd NUMERIC(12, 2);
    v_item_bs NUMERIC(12, 2);
    v_rec_usd NUMERIC(12, 2);
    v_rec_bs NUMERIC(12, 2);
    v_codigo_banco VARCHAR(4);
    v_referencia TEXT;
    v_nombre_banco TEXT;
BEGIN
    -- 1. Validaciones básicas
    IF p_cliente_id IS NULL OR p_creado_por IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID de cliente y el usuario creador son requeridos.',
                'details', NULL
            )
        );
    END IF;

    -- Determinar tasa de cambio
    IF p_tasa_cambio IS NOT NULL AND p_tasa_cambio > 0 THEN
        v_tasa_cambio := p_tasa_cambio;
    ELSE
        SELECT COALESCE(tasa_cambio, 1.0000) INTO v_tasa_cambio
        FROM public.tasa_cambio
        ORDER BY fecha_tasa DESC, created_at DESC
        LIMIT 1;

        IF v_tasa_cambio IS NULL THEN
            v_tasa_cambio := 1.0000;
        END IF;
    END IF;

    -- Validar que el cliente exista y obtener saldo a favor actual
    SELECT COALESCE(saldo_favor, 0.00) 
    INTO v_cliente_saldo_favor 
    FROM public.clientes 
    WHERE id = p_cliente_id;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'CLIENTE_INEXISTENTE',
                'message', 'El cliente especificado no existe.',
                'details', NULL
            )
        );
    END IF;

    -- Validar que las listas hijas tengan al menos un elemento
    IF p_ordenes IS NULL OR jsonb_array_length(p_ordenes) = 0 THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'DETALLE_REQUISITO_FALTANTE',
                'message', 'Debe registrar al menos una orden en el detalle de la rendición.',
                'details', NULL
            )
        );
    END IF;

    IF p_pagos IS NULL OR jsonb_array_length(p_pagos) = 0 THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'DETALLE_REQUISITO_FALTANTE',
                'message', 'Debe registrar al menos una forma de pago en la rendición.',
                'details', NULL
            )
        );
    END IF;

    -- 2. Calcular totales de órdenes
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_ordenes) AS x(orden_id UUID, monto_recaudado NUMERIC(12,2), monto_recaudado_bs NUMERIC(12,2)) LOOP
        v_rec_usd := COALESCE(v_item.monto_recaudado, 0.00);
        v_rec_bs := COALESCE(v_item.monto_recaudado_bs, v_rec_usd * v_tasa_cambio);

        v_total_ordenes := v_total_ordenes + v_rec_usd;
        v_total_ordenes_bs := v_total_ordenes_bs + v_rec_bs;
    END LOOP;

    -- 3. Validar y clasificar formas de pago (USD y Bs) + validar banco y referencia
    FOR v_pago IN SELECT * FROM jsonb_to_recordset(p_pagos) AS y(
        fpago_id UUID,
        monto NUMERIC(12,2),
        monto_bs NUMERIC(12,2),
        monto_usd NUMERIC(12,2),
        cuenta_bancaria_id UUID,
        codigo_banco VARCHAR(4),
        referencia_bancaria TEXT,
        cuenta_bancaria TEXT,
        capture_url TEXT
    ) LOOP
        -- Calcular valores en ambas monedas
        IF v_pago.monto_bs IS NOT NULL AND v_pago.monto_bs > 0 THEN
            v_item_bs := v_pago.monto_bs;
            v_item_usd := COALESCE(v_pago.monto_usd, v_item_bs / v_tasa_cambio);
        ELSE
            v_item_usd := COALESCE(v_pago.monto_usd, v_pago.monto, 0.00);
            v_item_bs := COALESCE(v_pago.monto_bs, v_item_usd * v_tasa_cambio);
        END IF;

        v_total_pagos := v_total_pagos + v_item_usd;
        v_total_pagos_bs := v_total_pagos_bs + v_item_bs;
        
        -- Obtener información de la forma de pago
        SELECT fpago_concepto, fpago_info 
        INTO v_fpago_concepto, v_fpago_info 
        FROM public.fpagos 
        WHERE fpago_id = v_pago.fpago_id;
        
        IF v_fpago_concepto IS NULL THEN
            RETURN json_build_object(
                'success', false,
                'data', NULL,
                'error', json_build_object(
                    'code', 'FORMA_PAGO_INEXISTENTE',
                    'message', 'La forma de pago especificada no existe.',
                    'details', 'fpago_id: ' || v_pago.fpago_id
                )
            );
        END IF;

        v_codigo_banco := NULLIF(TRIM(COALESCE(v_pago.codigo_banco, '')), '');
        v_referencia := NULLIF(TRIM(COALESCE(v_pago.referencia_bancaria, '')), '');

        -- Validar entidad bancaria y duplicidad cuando se indica banco y referencia
        IF v_codigo_banco IS NOT NULL THEN
            SELECT COALESCE(nombre_corto, nombre_eb)
            INTO v_nombre_banco
            FROM public.entidades_bancarias
            WHERE codigo_eb = v_codigo_banco AND activo = TRUE;

            IF NOT FOUND THEN
                RETURN json_build_object(
                    'success', false,
                    'data', NULL,
                    'error', json_build_object(
                        'code', 'ENTIDAD_BANCARIA_INVALIDA',
                        'message', 'La entidad bancaria seleccionada (' || v_codigo_banco || ') no existe o está inactiva.',
                        'details', 'codigo_banco: ' || v_codigo_banco
                    )
                );
            END IF;

            IF v_referencia IS NOT NULL THEN
                IF EXISTS (
                    SELECT 1
                    FROM public.detalle_rendicion_fpagos dfp
                    WHERE dfp.codigo_banco = v_codigo_banco
                      AND dfp.referencia_bancaria = v_referencia
                ) THEN
                    RETURN json_build_object(
                        'success', false,
                        'data', NULL,
                        'error', json_build_object(
                            'code', 'REFERENCIA_DUPLICADA',
                            'message', 'La referencia bancaria ' || v_referencia || ' del banco ' || v_codigo_banco || ' (' || v_nombre_banco || ') ya fue registrada previamente en otra cobranza.',
                            'details', 'codigo_banco: ' || v_codigo_banco || ', referencia_bancaria: ' || v_referencia
                        )
                    );
                END IF;
            END IF;
        END IF;

        -- Verificar si es uso de Saldo a Favor
        IF v_fpago_concepto ILIKE '%saldo%favor%' THEN
            v_saldo_favor_usado := v_saldo_favor_usado + v_item_usd;
        ELSIF v_fpago_info = FALSE THEN
            v_total_efectivo := v_total_efectivo + v_item_usd;
        ELSE
            v_total_transferencias := v_total_transferencias + v_item_usd;
        END IF;
    END LOOP;

    -- Validar si el saldo a favor usado excede el disponible del cliente
    IF v_saldo_favor_usado > v_cliente_saldo_favor THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'SALDO_FAVOR_INSUFICIENTE',
                'message', 'El saldo a favor utilizado (' || v_saldo_favor_usado || ') supera el saldo a favor disponible del cliente (' || v_cliente_saldo_favor || ').',
                'details', NULL
            )
        );
    END IF;

    -- 4. Crear el registro principal (Cabecera) en rendiciones_cuentas con estado = 'aprobada'
    INSERT INTO public.rendiciones_cuentas (
        cliente_id,
        fecha_rendicion,
        tasa_cambio,
        total_efectivo_recaudado,
        total_transferencias_recaudado,
        total_recaudado_bs,
        total_recaudado_usd,
        total_devoluciones_valoradas,
        estado,
        observaciones,
        auditado_por
    ) VALUES (
        p_cliente_id,
        NOW(),
        v_tasa_cambio,
        v_total_efectivo,
        v_total_transferencias,
        v_total_pagos_bs,
        v_total_pagos,
        0.00,
        'aprobada',
        p_observaciones,
        NULL
    ) RETURNING id INTO v_rendicion_id;

    -- 5. Registrar detalle de órdenes asociadas y actualizar estado de las órdenes
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_ordenes) AS x(orden_id UUID, monto_recaudado NUMERIC(12,2), monto_recaudado_bs NUMERIC(12,2)) LOOP
        v_rec_usd := COALESCE(v_item.monto_recaudado, 0.00);
        v_rec_bs := COALESCE(v_item.monto_recaudado_bs, v_rec_usd * v_tasa_cambio);

        INSERT INTO public.detalle_rendicion_ordenes (
            rendicion_id,
            orden_distribucion_id,
            recaudado,
            recaudado_bs
        ) VALUES (
            v_rendicion_id,
            v_item.orden_id,
            v_rec_usd,
            v_rec_bs
        );

        -- Evaluar y liquidar financieramente la orden de distribución
        PERFORM public.liquidar_orden_distribucion(v_item.orden_id);
    END LOOP;

    -- 6. Registrar formas de pago (detalle_rendicion_fpagos)
    FOR v_pago IN SELECT * FROM jsonb_to_recordset(p_pagos) AS y(
        fpago_id UUID,
        monto NUMERIC(12,2),
        monto_bs NUMERIC(12,2),
        monto_usd NUMERIC(12,2),
        cuenta_bancaria_id UUID,
        codigo_banco VARCHAR(4),
        referencia_bancaria TEXT,
        cuenta_bancaria TEXT,
        capture_url TEXT
    ) LOOP
        IF v_pago.monto_bs IS NOT NULL AND v_pago.monto_bs > 0 THEN
            v_item_bs := v_pago.monto_bs;
            v_item_usd := COALESCE(v_pago.monto_usd, v_item_bs / v_tasa_cambio);
        ELSE
            v_item_usd := COALESCE(v_pago.monto_usd, v_pago.monto, 0.00);
            v_item_bs := COALESCE(v_pago.monto_bs, v_item_usd * v_tasa_cambio);
        END IF;

        v_codigo_banco := NULLIF(TRIM(COALESCE(v_pago.codigo_banco, '')), '');
        v_referencia := NULLIF(TRIM(COALESCE(v_pago.referencia_bancaria, '')), '');

        INSERT INTO public.detalle_rendicion_fpagos (
            rendicion_id,
            fpago_id,
            cuenta_bancaria_id,
            codigo_banco,
            monto,
            monto_bs,
            monto_usd,
            referencia_bancaria,
            cuenta_bancaria,
            capture_url
        ) VALUES (
            v_rendicion_id,
            v_pago.fpago_id,
            v_pago.cuenta_bancaria_id,
            v_codigo_banco,
            v_item_usd,
            v_item_bs,
            v_item_usd,
            v_referencia,
            v_pago.cuenta_bancaria,
            v_pago.capture_url
        );
    END LOOP;

    -- 7. Procesar uso de Saldo a Favor si aplica
    IF v_saldo_favor_usado > 0 THEN
        UPDATE public.clientes
        SET saldo_favor = saldo_favor - v_saldo_favor_usado
        WHERE id = p_cliente_id;

        INSERT INTO public.movimientos_saldo_favor (
            cliente_id,
            rendicion_id,
            orden_id,
            monto,
            tipo,
            observaciones,
            created_at
        ) VALUES (
            p_cliente_id,
            v_rendicion_id,
            NULL,
            -v_saldo_favor_usado,
            'cargo_pago_orden',
            'Uso de saldo a favor en rendición de cuentas ID: ' || v_rendicion_id,
            NOW()
        );
    END IF;

    -- 8. Manejo de Excedente de Pago (Crédito a Favor Generado)
    IF v_total_pagos > v_total_ordenes THEN
        v_exceso := v_total_pagos - v_total_ordenes;
        v_exceso_bs := v_exceso * v_tasa_cambio;

        INSERT INTO public.movimientos_saldo_favor (
            cliente_id,
            rendicion_id,
            orden_id,
            monto,
            tipo,
            observaciones,
            created_at
        ) VALUES (
            p_cliente_id,
            v_rendicion_id,
            NULL,
            v_exceso,
            'abono_recaudacion',
            'Excedente en formas de pago de rendición de cuentas ID: ' || v_rendicion_id,
            NOW()
        );

        UPDATE public.clientes
        SET saldo_favor = COALESCE(saldo_favor, 0.00) + v_exceso
        WHERE id = p_cliente_id;
    END IF;

    -- 9. Retorno Exitoso
    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'rendicion_id', v_rendicion_id,
            'tasa_cambio', v_tasa_cambio,
            'total_ordenes', v_total_ordenes,
            'total_ordenes_bs', v_total_ordenes_bs,
            'total_pagos', v_total_pagos,
            'total_pagos_bs', v_total_pagos_bs,
            'saldo_favor_usado', v_saldo_favor_usado,
            'saldo_favor_generado', v_exceso,
            'saldo_favor_generado_bs', v_exceso_bs
        ),
        'error', NULL
    );

EXCEPTION
    WHEN unique_violation THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'REFERENCIA_DUPLICADA',
                'message', 'La referencia bancaria indicada ya se encuentra registrada para ese mismo banco.',
                'details', 'SQLSTATE: ' || SQLSTATE || ' - ' || SQLERRM
            )
        );
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

ALTER FUNCTION public.registrar_rendicion_cuentas(uuid, text, uuid, jsonb, jsonb, numeric) OWNER TO postgres;
GRANT ALL ON FUNCTION public.registrar_rendicion_cuentas(uuid, text, uuid, jsonb, jsonb, numeric) TO anon, authenticated, service_role;

-- ------------------------------------------------------------------------------
-- 6. Actualización de public.reversa_rendicion_cuenta_segun_id_rendicion
--    Libera codigo_banco (a NULL) en detalle_rendicion_fpagos al reversar una cobranza.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reversa_rendicion_cuenta_segun_id_rendicion(p_id_rendicion uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_rol TEXT;
    v_estado_actual TEXT;
    v_cliente_id UUID;
    v_neto_saldo_favor NUMERIC(12, 2) := 0.00;
    v_saldo_cliente NUMERIC(12, 2) := 0.00;
    v_movimiento RECORD;
    v_orden RECORD;
    v_ordenes_liberadas INTEGER := 0;
BEGIN
    v_rol := public.lt_current_user_rol();
    IF v_rol IS DISTINCT FROM 'gerente' THEN
        RAISE EXCEPTION 'Permiso denegado: solo el gerente puede reversar cobranzas.';
    END IF;

    SELECT estado, cliente_id
    INTO v_estado_actual, v_cliente_id
    FROM public.rendiciones_cuentas
    WHERE id = p_id_rendicion
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La cobranza especificada no existe.';
    END IF;

    IF v_estado_actual = 'reversada' THEN
        RAISE EXCEPTION 'La cobranza ya está reversada.';
    END IF;

    IF v_estado_actual <> 'aprobada' THEN
        RAISE EXCEPTION 'Solo se pueden reversar cobranzas aprobadas (estado actual: %).', v_estado_actual;
    END IF;

    SELECT COALESCE(SUM(monto), 0.00)
    INTO v_neto_saldo_favor
    FROM public.movimientos_saldo_favor
    WHERE rendicion_id = p_id_rendicion;

    SELECT COALESCE(saldo_favor, 0.00)
    INTO v_saldo_cliente
    FROM public.clientes
    WHERE id = v_cliente_id
    FOR UPDATE;

    IF v_saldo_cliente - v_neto_saldo_favor < 0 THEN
        RAISE EXCEPTION 'El cliente ya usó % del saldo a favor que generó esta cobranza (saldo actual: %). Reversa primero la cobranza donde lo usó.',
            (v_neto_saldo_favor - v_saldo_cliente), v_saldo_cliente;
    END IF;

    -- 1. Cabecera: pasa a 'reversada'
    UPDATE public.rendiciones_cuentas
    SET estado = 'reversada',
        observaciones = TRIM(COALESCE(observaciones, '') || ' [REVERSADA por gerente el ' || TO_CHAR(NOW(), 'YYYY-MM-DD HH24:MI') || ']')
    WHERE id = p_id_rendicion;

    -- 1b. Liberar el bloqueo único (codigo_banco, referencia_bancaria) para permitir
    --     volver a registrar el pago si la cobranza fue reversada por error de carga.
    UPDATE public.detalle_rendicion_fpagos
    SET codigo_banco = NULL
    WHERE rendicion_id = p_id_rendicion;

    -- 2. Órdenes: vuelven a 'por_liquidar' y se reevalúan
    FOR v_orden IN
        SELECT DISTINCT orden_distribucion_id AS id
        FROM public.detalle_rendicion_ordenes
        WHERE rendicion_id = p_id_rendicion
    LOOP
        UPDATE public.ordenes_distribucion
        SET estado = 'por_liquidar'
        WHERE id = v_orden.id
          AND estado = 'liquidada';

        PERFORM public.liquidar_orden_distribucion(v_orden.id);
        v_ordenes_liberadas := v_ordenes_liberadas + 1;
    END LOOP;

    -- 3. Movimientos inversos de saldo a favor
    FOR v_movimiento IN
        SELECT id, monto, orden_id
        FROM public.movimientos_saldo_favor
        WHERE rendicion_id = p_id_rendicion
          AND tipo <> 'reverso_rendicion'
    LOOP
        INSERT INTO public.movimientos_saldo_favor (
            cliente_id, rendicion_id, orden_id, monto, tipo, observaciones, created_at
        ) VALUES (
            v_cliente_id,
            p_id_rendicion,
            v_movimiento.orden_id,
            -v_movimiento.monto,
            'reverso_rendicion',
            'Reverso del movimiento ID ' || v_movimiento.id,
            NOW()
        );
    END LOOP;

    IF v_neto_saldo_favor <> 0 THEN
        UPDATE public.clientes
        SET saldo_favor = COALESCE(saldo_favor, 0.00) - v_neto_saldo_favor
        WHERE id = v_cliente_id;
    END IF;

    RETURN json_build_object(
        'success', true,
        'message', 'Cobranza reversada. ' || v_ordenes_liberadas || ' orden(es) vuelven a por liquidar.',
        'data', json_build_object(
            'rendicion_id', p_id_rendicion,
            'estado_nuevo', 'reversada',
            'ordenes_liberadas', v_ordenes_liberadas,
            'saldo_favor_ajuste', -v_neto_saldo_favor
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

ALTER FUNCTION public.reversa_rendicion_cuenta_segun_id_rendicion(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.reversa_rendicion_cuenta_segun_id_rendicion(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reversa_rendicion_cuenta_segun_id_rendicion(uuid) TO authenticated, service_role;

-- ------------------------------------------------------------------------------
-- 7. Actualización de public.reporte_formas_pago_rendicion (expone codigo_banco y nombre_banco)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reporte_formas_pago_rendicion(
    p_fecha_desde date DEFAULT NULL::date,
    p_fecha_hasta date DEFAULT NULL::date,
    p_solo_bancarios boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_fecha_desde DATE;
    v_fecha_hasta DATE;
    v_movimientos JSONB;
    v_total_registros INT := 0;
    v_monto_total_bs NUMERIC(14,2) := 0.00;
    v_monto_total_usd NUMERIC(14,2) := 0.00;
BEGIN
    v_fecha_desde := COALESCE(p_fecha_desde, date_trunc('month', CURRENT_DATE)::date);
    v_fecha_hasta := COALESCE(p_fecha_hasta, CURRENT_DATE);

    SELECT
        COUNT(*)::INT,
        COALESCE(SUM(dfp.monto_bs), 0.00),
        COALESCE(SUM(dfp.monto_usd), 0.00)
    INTO v_total_registros, v_monto_total_bs, v_monto_total_usd
    FROM public.detalle_rendicion_fpagos dfp
    JOIN public.rendiciones_cuentas rc ON dfp.rendicion_id = rc.id
    JOIN public.fpagos fp ON dfp.fpago_id = fp.fpago_id
    WHERE rc.fecha_rendicion::date >= v_fecha_desde
      AND rc.fecha_rendicion::date <= v_fecha_hasta
      AND rc.estado = 'aprobada'
      AND (p_solo_bancarios = FALSE OR fp.es_bancario = TRUE);

    SELECT jsonb_agg(
        jsonb_build_object(
            'rendicion_id', rc.id,
            'fecha_rendicion', rc.fecha_rendicion,
            'tasa_cambio', rc.tasa_cambio,
            'cliente_id', c.id,
            'cliente_nombre', c.razon_social,
            'cliente_rif', c.rif_nit,
            'fpago_id', fp.fpago_id,
            'fpago_concepto', fp.fpago_concepto,
            'es_bancario', fp.es_bancario,
            'codigo_banco', dfp.codigo_banco,
            'nombre_banco', COALESCE(eb.nombre_corto, eb.nombre_eb),
            'referencia_bancaria', dfp.referencia_bancaria,
            'cuenta_bancaria', COALESCE(cbe.cuenta_bancaria, dfp.cuenta_bancaria),
            'capture_url', dfp.capture_url,
            'monto_bs', COALESCE(dfp.monto_bs, (dfp.monto_usd * COALESCE(rc.tasa_cambio, 0))),
            'monto_usd', dfp.monto_usd
        ) ORDER BY rc.fecha_rendicion DESC, dfp.id DESC
    ) INTO v_movimientos
    FROM public.detalle_rendicion_fpagos dfp
    JOIN public.rendiciones_cuentas rc ON dfp.rendicion_id = rc.id
    JOIN public.fpagos fp ON dfp.fpago_id = fp.fpago_id
    JOIN public.clientes c ON rc.cliente_id = c.id
    LEFT JOIN public.entidades_bancarias eb ON dfp.codigo_banco = eb.codigo_eb
    LEFT JOIN public.cuentas_bancarias_empresa cbe ON dfp.cuenta_bancaria_id = cbe.id
    WHERE rc.fecha_rendicion::date >= v_fecha_desde
      AND rc.fecha_rendicion::date <= v_fecha_hasta
      AND rc.estado = 'aprobada'
      AND (p_solo_bancarios = FALSE OR fp.es_bancario = TRUE);

    RETURN jsonb_build_object(
        'success', true,
        'data', jsonb_build_object(
            'fecha_desde', v_fecha_desde,
            'fecha_hasta', v_fecha_hasta,
            'solo_bancarios', p_solo_bancarios,
            'total_registros', v_total_registros,
            'monto_total_bs', v_monto_total_bs,
            'monto_total_usd', v_monto_total_usd,
            'movimientos', COALESCE(v_movimientos, '[]'::jsonb)
        ),
        'error', NULL
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'SQL_ERROR',
                'message', SQLERRM,
                'details', 'SQLSTATE: ' || SQLSTATE
            )
        );
END;
$$;

ALTER FUNCTION public.reporte_formas_pago_rendicion(date, date, boolean) OWNER TO postgres;
GRANT ALL ON FUNCTION public.reporte_formas_pago_rendicion(date, date, boolean) TO anon, authenticated, service_role;
