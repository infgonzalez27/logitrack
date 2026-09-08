-- Migration: Módulo de Cuentas Bancarias de la Empresa y Multimoneda (USD/Bs) en Rendición de Cuentas

-- 1. Crear tabla maestra cuentas_bancarias_empresa
CREATE TABLE IF NOT EXISTS public.cuentas_bancarias_empresa (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    cuenta_bancaria VARCHAR(20) NOT NULL UNIQUE,
    entidad_bancaria VARCHAR(100) NOT NULL,
    status_cuenta BOOLEAN DEFAULT TRUE, -- TRUE = Activa (.T.), FALSE = Suspendida (.F.)
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Habilitar RLS
ALTER TABLE public.cuentas_bancarias_empresa ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'cuentas_bancarias_empresa' AND policyname = 'Permitir lectura autenticada de cuentas bancarias'
    ) THEN
        CREATE POLICY "Permitir lectura autenticada de cuentas bancarias" ON public.cuentas_bancarias_empresa
            FOR SELECT TO authenticated USING (true);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'cuentas_bancarias_empresa' AND policyname = 'Permitir edicion autenticada de cuentas bancarias'
    ) THEN
        CREATE POLICY "Permitir edicion autenticada de cuentas bancarias" ON public.cuentas_bancarias_empresa
            FOR ALL TO authenticated USING (true);
    END IF;
END $$;


-- 2. Alteraciones de columnas multimoneda y relaciones
ALTER TABLE public.rendiciones_cuentas 
ADD COLUMN IF NOT EXISTS tasa_cambio NUMERIC(10, 4) NOT NULL DEFAULT 1.0000,
ADD COLUMN IF NOT EXISTS total_recaudado_bs NUMERIC(12, 2) DEFAULT 0.00,
ADD COLUMN IF NOT EXISTS total_recaudado_usd NUMERIC(12, 2) DEFAULT 0.00;

ALTER TABLE public.detalle_rendicion_fpagos 
ADD COLUMN IF NOT EXISTS cuenta_bancaria_id UUID REFERENCES public.cuentas_bancarias_empresa(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS monto_bs NUMERIC(12, 2) DEFAULT 0.00,
ADD COLUMN IF NOT EXISTS monto_usd NUMERIC(12, 2) DEFAULT 0.00;

ALTER TABLE public.detalle_rendicion_ordenes 
ADD COLUMN IF NOT EXISTS recaudado_bs NUMERIC(12, 2) DEFAULT 0.00;


-- 3. Función crear_cuenta_bancaria_empresa
CREATE OR REPLACE FUNCTION public.crear_cuenta_bancaria_empresa(
    p_cuenta_bancaria TEXT,
    p_entidad_bancaria TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_id UUID;
BEGIN
    IF p_cuenta_bancaria IS NULL OR TRIM(p_cuenta_bancaria) = '' THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El número de cuenta bancaria es requerido.'
            )
        );
    END IF;

    IF p_entidad_bancaria IS NULL OR TRIM(p_entidad_bancaria) = '' THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'La entidad bancaria es requerida.'
            )
        );
    END IF;

    IF EXISTS (SELECT 1 FROM public.cuentas_bancarias_empresa WHERE cuenta_bancaria = TRIM(p_cuenta_bancaria)) THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'CUENTA_DUPLICADA',
                'message', 'La cuenta bancaria especificada ya está registrada.'
            )
        );
    END IF;

    INSERT INTO public.cuentas_bancarias_empresa (
        cuenta_bancaria,
        entidad_bancaria,
        status_cuenta
    ) VALUES (
        TRIM(p_cuenta_bancaria),
        TRIM(p_entidad_bancaria),
        TRUE
    ) RETURNING id INTO v_id;

    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'id', v_id,
            'cuenta_bancaria', TRIM(p_cuenta_bancaria),
            'entidad_bancaria', TRIM(p_entidad_bancaria),
            'status_cuenta', true
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


-- 4. Función actualizar_cuenta_bancaria_empresa
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


-- 5. Función cambiar_status_cuenta_bancaria_empresa
CREATE OR REPLACE FUNCTION public.cambiar_status_cuenta_bancaria_empresa(
    p_id UUID,
    p_status_cuenta BOOLEAN
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF p_id IS NULL OR p_status_cuenta IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID de la cuenta y el estatus son requeridos.'
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

    UPDATE public.cuentas_bancarias_empresa
    SET status_cuenta = p_status_cuenta
    WHERE id = p_id;

    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'id', p_id,
            'status_cuenta', p_status_cuenta
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


-- 6. Función retorna_cuentas_bancarias_empresa
CREATE OR REPLACE FUNCTION public.retorna_cuentas_bancarias_empresa(
    p_solo_activas BOOLEAN DEFAULT TRUE
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_data JSON;
BEGIN
    SELECT json_agg(
        json_build_object(
            'id', id,
            'cuenta_bancaria', cuenta_bancaria,
            'entidad_bancaria', entidad_bancaria,
            'status_cuenta', status_cuenta,
            'created_at', created_at
        ) ORDER BY entidad_bancaria ASC, cuenta_bancaria ASC
    ) INTO v_data
    FROM public.cuentas_bancarias_empresa
    WHERE (NOT p_solo_activas OR status_cuenta = TRUE);

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


-- 7. Función solicita_abonos_orden_distribucion (Multimoneda USD/Bs)
CREATE OR REPLACE FUNCTION public.solicita_abonos_orden_distribucion(
    p_cliente_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_saldo_favor NUMERIC(12, 2) := 0.00;
    v_tasa_oficial NUMERIC(10, 4) := 1.0000;
    v_ordenes JSON;
BEGIN
    -- Validar parámetro
    IF p_cliente_id IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID de cliente es requerido.'
            )
        );
    END IF;

    -- Validar que el cliente exista y obtener saldo a favor
    SELECT COALESCE(saldo_favor, 0.00) INTO v_saldo_favor
    FROM public.clientes
    WHERE id = p_cliente_id;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'CLIENTE_INEXISTENTE',
                'message', 'El cliente especificado no existe.'
            )
        );
    END IF;

    -- Obtener la última tasa de cambio oficial
    SELECT COALESCE(tasa_cambio, 1.0000) INTO v_tasa_oficial
    FROM public.tasa_cambio
    ORDER BY fecha_tasa DESC, created_at DESC
    LIMIT 1;

    -- Obtener ordenes por_liquidar con abonos acumulados en USD y Bs
    SELECT json_agg(
        json_build_object(
            'orden_id', od.id,
            'correlativo', od.correlativo,
            'fecha_despacho', od.fecha_despacho,
            'tasa_orden', COALESCE(od.tasa_cambio, v_tasa_oficial),
            'monto_total_orden', COALESCE(od.subtotal_recaudar, od.subtotal, 0.00),
            'monto_total_orden_bs', COALESCE(od.total_recaudar_bs, (COALESCE(od.subtotal_recaudar, od.subtotal, 0.00) * COALESCE(od.tasa_cambio, v_tasa_oficial)), 0.00),
            'abonos_acumulados', COALESCE(abonos.total_recaudado_usd, 0.00),
            'abonos_acumulados_bs', COALESCE(abonos.total_recaudado_bs, 0.00),
            'saldo_pendiente', COALESCE(od.subtotal_recaudar, od.subtotal, 0.00) - COALESCE(abonos.total_recaudado_usd, 0.00),
            'saldo_pendiente_bs', COALESCE(od.total_recaudar_bs, (COALESCE(od.subtotal_recaudar, od.subtotal, 0.00) * COALESCE(od.tasa_cambio, v_tasa_oficial)), 0.00) - COALESCE(abonos.total_recaudado_bs, 0.00)
        ) ORDER BY od.created_at ASC
    ) INTO v_ordenes
    FROM public.ordenes_distribucion od
    LEFT JOIN LATERAL (
        SELECT 
            SUM(COALESCE(dro.recaudado, 0.00)) AS total_recaudado_usd,
            SUM(COALESCE(dro.recaudado_bs, (COALESCE(dro.recaudado, 0.00) * COALESCE(rc.tasa_cambio, v_tasa_oficial)), 0.00)) AS total_recaudado_bs
        FROM public.detalle_rendicion_ordenes dro
        JOIN public.rendiciones_cuentas rc ON dro.rendicion_id = rc.id
        WHERE dro.orden_distribucion_id = od.id
          AND rc.estado = 'aprobada'
    ) abonos ON TRUE
    WHERE od.cliente_id = p_cliente_id
      AND od.estado = 'por_liquidar';

    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'cliente_id', p_cliente_id,
            'saldo_favor', v_saldo_favor,
            'saldo_favor_bs', (v_saldo_favor * v_tasa_oficial),
            'tasa_oficial_actual', v_tasa_oficial,
            'ordenes', COALESCE(v_ordenes, '[]'::json)
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


-- 8. Función registrar_rendicion_cuentas (Multimoneda USD/Bs y Cuentas Bancarias)
CREATE OR REPLACE FUNCTION public.registrar_rendicion_cuentas(
    p_cliente_id UUID,
    p_observaciones TEXT,
    p_creado_por UUID,
    p_ordenes JSONB,  -- Array: [{"orden_id": "...", "monto_recaudado": 150.00, "monto_recaudado_bs": 7500.00}]
    p_pagos JSONB,     -- Array: [{"fpago_id": "...", "monto": 200.00, "monto_bs": 10000.00, "monto_usd": 200.00, "cuenta_bancaria_id": "...", "referencia_bancaria": "...", "cuenta_bancaria": "...", "capture_url": "..."}]
    p_tasa_cambio NUMERIC DEFAULT NULL
)
RETURNS JSON
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

    -- 3. Validar y clasificar formas de pago (USD y Bs)
    FOR v_pago IN SELECT * FROM jsonb_to_recordset(p_pagos) AS y(fpago_id UUID, monto NUMERIC(12,2), monto_bs NUMERIC(12,2), monto_usd NUMERIC(12,2), cuenta_bancaria_id UUID, referencia_bancaria TEXT, cuenta_bancaria TEXT, capture_url TEXT) LOOP
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

    -- 4. Crear el registro principal (Cabecera) en rendiciones_cuentas
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
        'revision',
        p_observaciones,
        NULL
    ) RETURNING id INTO v_rendicion_id;

    -- 5. Registrar detalle de órdenes asociadas
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
    END LOOP;

    -- 6. Registrar formas de pago (detalle_rendicion_fpagos)
    FOR v_pago IN SELECT * FROM jsonb_to_recordset(p_pagos) AS y(fpago_id UUID, monto NUMERIC(12,2), monto_bs NUMERIC(12,2), monto_usd NUMERIC(12,2), cuenta_bancaria_id UUID, referencia_bancaria TEXT, cuenta_bancaria TEXT, capture_url TEXT) LOOP
        IF v_pago.monto_bs IS NOT NULL AND v_pago.monto_bs > 0 THEN
            v_item_bs := v_pago.monto_bs;
            v_item_usd := COALESCE(v_pago.monto_usd, v_item_bs / v_tasa_cambio);
        ELSE
            v_item_usd := COALESCE(v_pago.monto_usd, v_pago.monto, 0.00);
            v_item_bs := COALESCE(v_pago.monto_bs, v_item_usd * v_tasa_cambio);
        END IF;

        INSERT INTO public.detalle_rendicion_fpagos (
            rendicion_id,
            fpago_id,
            cuenta_bancaria_id,
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
            v_item_usd,
            v_item_bs,
            v_item_usd,
            v_pago.referencia_bancaria,
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
        v_exceso_bs := v_total_pagos_bs - v_total_ordenes_bs;

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
            'saldo_favor_generado', v_exceso
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


-- 9. Función reporte_recaudaciones_gerenciales (Multimoneda)
CREATE OR REPLACE FUNCTION public.reporte_recaudaciones_gerenciales(
    p_fecha_desde DATE DEFAULT NULL,
    p_fecha_hasta DATE DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_data JSON;
    v_desde TIMESTAMP WITH TIME ZONE;
    v_hasta TIMESTAMP WITH TIME ZONE;
BEGIN
    -- Configurar fechas por defecto si no son pasadas (mes actual)
    v_desde := COALESCE(p_fecha_desde::TIMESTAMP WITH TIME ZONE, date_trunc('month', CURRENT_DATE));
    v_hasta := COALESCE((p_fecha_hasta + INTERVAL '1 day - 1 microsecond')::TIMESTAMP WITH TIME ZONE, CURRENT_TIMESTAMP);

    SELECT json_agg(
        json_build_object(
            'rendicion_id', rc.id,
            'fecha_rendicion', rc.fecha_rendicion,
            'tasa_cambio', COALESCE(rc.tasa_cambio, 1.0000),
            'cliente_id', rc.cliente_id,
            'cliente_nombre', c.razon_social,
            'cliente_rif', c.rif_nit,
            'estado', rc.estado,
            'total_efectivo_recaudado', rc.total_efectivo_recaudado,
            'total_transferencias_recaudado', rc.total_transferencias_recaudado,
            'total_recaudado_usd', COALESCE(rc.total_recaudado_usd, 0.00),
            'total_recaudado_bs', COALESCE(rc.total_recaudado_bs, 0.00),
            'observaciones', rc.observaciones,
            'detalle_fpagos', COALESCE(fpagos_agg.fpagos, '[]'::json),
            'detalle_ordenes', COALESCE(ordenes_agg.ordenes, '[]'::json)
        ) ORDER BY rc.fecha_rendicion DESC
    ) INTO v_data
    FROM public.rendiciones_cuentas rc
    JOIN public.clientes c ON rc.cliente_id = c.id
    LEFT JOIN LATERAL (
        SELECT json_agg(
            json_build_object(
                'fpago_id', dfp.fpago_id,
                'concepto', fp.fpago_concepto,
                'monto', dfp.monto,
                'monto_bs', COALESCE(dfp.monto_bs, 0.00),
                'monto_usd', COALESCE(dfp.monto_usd, dfp.monto, 0.00),
                'cuenta_bancaria_id', dfp.cuenta_bancaria_id,
                'entidad_bancaria', cbe.entidad_bancaria,
                'cuenta_bancaria', COALESCE(cbe.cuenta_bancaria, dfp.cuenta_bancaria),
                'referencia_bancaria', dfp.referencia_bancaria,
                'capture_url', dfp.capture_url
            )
        ) AS fpagos
        FROM public.detalle_rendicion_fpagos dfp
        LEFT JOIN public.fpagos fp ON dfp.fpago_id = fp.fpago_id
        LEFT JOIN public.cuentas_bancarias_empresa cbe ON dfp.cuenta_bancaria_id = cbe.id
        WHERE dfp.rendicion_id = rc.id
    ) fpagos_agg ON TRUE
    LEFT JOIN LATERAL (
        SELECT json_agg(
            json_build_object(
                'orden_id', dro.orden_distribucion_id,
                'correlativo', od.correlativo,
                'recaudado', dro.recaudado,
                'recaudado_bs', COALESCE(dro.recaudado_bs, 0.00)
            )
        ) AS ordenes
        FROM public.detalle_rendicion_ordenes dro
        LEFT JOIN public.ordenes_distribucion od ON dro.orden_distribucion_id = od.id
        WHERE dro.rendicion_id = rc.id
    ) ordenes_agg ON TRUE
    WHERE rc.fecha_rendicion >= v_desde
      AND rc.fecha_rendicion <= v_hasta;

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
