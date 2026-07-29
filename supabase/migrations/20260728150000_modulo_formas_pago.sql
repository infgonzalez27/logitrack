-- Migration: Módulo de Formas de Pago (DB-009, DB-010, DB-011)

-- 1. Crear tabla fpagos si no existe (DB-009)
CREATE TABLE IF NOT EXISTS public.fpagos (
    fpago_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    fpago_concepto TEXT NOT NULL UNIQUE,
    fpago_info BOOLEAN NOT NULL DEFAULT FALSE
);

-- Habilitar RLS en fpagos
ALTER TABLE public.fpagos ENABLE ROW LEVEL SECURITY;

-- Política de lectura pública/autenticada para fpagos
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'fpagos' AND policyname = 'Permitir lectura autenticada de fpagos'
    ) THEN
        CREATE POLICY "Permitir lectura autenticada de fpagos" ON public.fpagos
            FOR SELECT TO authenticated USING (true);
    END IF;
END $$;

-- Insertar formas de pago base con UUIDs estáticos
INSERT INTO public.fpagos (fpago_id, fpago_concepto, fpago_info)
VALUES 
    ('1a5b84c8-47bc-4ee0-880c-7833215be11b', 'Pago movil', true),
    ('2b6c95d9-58cd-4ff1-991d-8944326cf22c', 'Transferencia', true),
    ('3c7da6ea-69de-4002-aa2e-9a55437d033d', 'Efectivo Bs', false),
    ('4d8eb7fb-7ade-4113-bb3f-ab66548e144e', 'Efectivo USD', false),
    ('5e9fc80c-8bef-4224-cc4f-bc77659f255f', 'ZELLE', true),
    ('6fa0d91d-9c00-4335-dd5f-cd88760a366a', 'BINANCE', true)
ON CONFLICT (fpago_concepto) DO UPDATE 
SET fpago_info = EXCLUDED.fpago_info;

-- 2. Modificar tabla detalle_rendicion_fpagos para incluir FK fpago_id (DB-010)
ALTER TABLE public.detalle_rendicion_fpagos 
ADD COLUMN IF NOT EXISTS fpago_id UUID REFERENCES public.fpagos(fpago_id) ON DELETE RESTRICT;

-- Mapear registros existentes si la columna metodo_pago existe
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'detalle_rendicion_fpagos' 
          AND column_name = 'metodo_pago'
    ) THEN
        UPDATE public.detalle_rendicion_fpagos d
        SET fpago_id = f.fpago_id
        FROM public.fpagos f
        WHERE d.fpago_id IS NULL AND (
            (d.metodo_pago IN ('pago_movil', 'Pago movil') AND f.fpago_concepto = 'Pago movil') OR
            (d.metodo_pago IN ('transferencia', 'Transferencia') AND f.fpago_concepto = 'Transferencia') OR
            (d.metodo_pago IN ('efectivo_bs', 'Efectivo Bs') AND f.fpago_concepto = 'Efectivo Bs') OR
            (d.metodo_pago IN ('efectivo_usd', 'Efectivo USD') AND f.fpago_concepto = 'Efectivo USD') OR
            (d.metodo_pago = 'ZELLE' AND f.fpago_concepto = 'ZELLE') OR
            (d.metodo_pago = 'BINANCE' AND f.fpago_concepto = 'BINANCE')
        );

        -- Eliminar la columna antigua metodo_pago
        ALTER TABLE public.detalle_rendicion_fpagos DROP COLUMN metodo_pago;
    END IF;
END $$;

-- 3. Actualizar función registrar_rendicion_cuentas
CREATE OR REPLACE FUNCTION public.registrar_rendicion_cuentas(
    p_cliente_id UUID,
    p_observaciones TEXT,
    p_creado_por UUID,
    p_ordenes JSONB,  -- Array de objetos: [{"orden_id": "...", "monto_recaudado": 150.00}]
    p_pagos JSONB      -- Array de objetos: [{"fpago_id": "...", "monto": 200.00, "referencia_bancaria": "...", "cuenta_bancaria": "...", "capture_url": "..."}]
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_rendicion_id UUID;
    v_total_ordenes NUMERIC(12, 2) := 0.00;
    v_total_pagos NUMERIC(12, 2) := 0.00;
    v_total_efectivo NUMERIC(12, 2) := 0.00;
    v_total_transferencias NUMERIC(12, 2) := 0.00;
    v_item RECORD;
    v_pago RECORD;
    v_exceso NUMERIC(12, 2) := 0.00;
    v_fpago_info BOOLEAN;
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

    -- Validar que el cliente exista
    IF NOT EXISTS (SELECT 1 FROM public.clientes WHERE id = p_cliente_id) THEN
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
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_ordenes) AS x(orden_id UUID, monto_recaudado NUMERIC(12,2)) LOOP
        v_total_ordenes := v_total_ordenes + v_item.monto_recaudado;
    END LOOP;

    -- 3. Calcular totales y clasificar según formas de pago (fpagos.fpago_info)
    FOR v_pago IN SELECT * FROM jsonb_to_recordset(p_pagos) AS y(fpago_id UUID, monto NUMERIC(12,2), referencia_bancaria TEXT, cuenta_bancaria TEXT, capture_url TEXT) LOOP
        v_total_pagos := v_total_pagos + v_pago.monto;
        
        -- Obtener fpago_info para saber si es transferencia/digital (true) o efectivo (false)
        SELECT fpago_info INTO v_fpago_info FROM public.fpagos WHERE fpago_id = v_pago.fpago_id;
        
        IF v_fpago_info IS NULL THEN
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

        IF v_fpago_info = FALSE THEN
            v_total_efectivo := v_total_efectivo + v_pago.monto;
        ELSE
            v_total_transferencias := v_total_transferencias + v_pago.monto;
        END IF;
    END LOOP;

    -- 4. Crear el registro principal (Cabecera) en rendiciones_cuentas
    INSERT INTO public.rendiciones_cuentas (
        cliente_id,
        fecha_rendicion,
        total_efectivo_recaudado,
        total_transferencias_recaudado,
        total_devoluciones_valoradas,
        estado,
        observaciones,
        auditado_por
    ) VALUES (
        p_cliente_id,
        NOW(),
        v_total_efectivo,
        v_total_transferencias,
        0.00,
        'revision',
        p_observaciones,
        NULL
    ) RETURNING id INTO v_rendicion_id;

    -- 5. Registrar detalle de órdenes asociadas
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_ordenes) AS x(orden_id UUID, monto_recaudado NUMERIC(12,2)) LOOP
        INSERT INTO public.detalle_rendicion_ordenes (
            rendicion_id,
            orden_distribucion_id,
            recaudado
        ) VALUES (
            v_rendicion_id,
            v_item.orden_id,
            v_item.monto_recaudado
        );
    END LOOP;

    -- 6. Registrar formas de pago (detalle_rendicion_fpagos)
    FOR v_pago IN SELECT * FROM jsonb_to_recordset(p_pagos) AS y(fpago_id UUID, monto NUMERIC(12,2), referencia_bancaria TEXT, cuenta_bancaria TEXT, capture_url TEXT) LOOP
        INSERT INTO public.detalle_rendicion_fpagos (
            rendicion_id,
            fpago_id,
            monto,
            referencia_bancaria,
            cuenta_bancaria,
            capture_url
        ) VALUES (
            v_rendicion_id,
            v_pago.fpago_id,
            v_pago.monto,
            v_pago.referencia_bancaria,
            v_pago.cuenta_bancaria,
            v_pago.capture_url
        );
    END LOOP;

    -- 7. Manejo de Crédito a Favor del Cliente
    IF v_total_pagos > v_total_ordenes THEN
        v_exceso := v_total_pagos - v_total_ordenes;

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

    -- 8. Retorno Exitoso
    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'rendicion_id', v_rendicion_id,
            'total_ordenes', v_total_ordenes,
            'total_pagos', v_total_pagos,
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

-- 4. Crear la función consulta_registros_formas_pago (DB-011)
CREATE OR REPLACE FUNCTION public.consulta_registros_formas_pago()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_data JSON;
BEGIN
    SELECT json_agg(
        json_build_object(
            'fpago_id', fpago_id,
            'fpago_concepto', fpago_concepto,
            'fpago_info', fpago_info
        ) ORDER BY fpago_concepto
    ) INTO v_data
    FROM public.fpagos;

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
