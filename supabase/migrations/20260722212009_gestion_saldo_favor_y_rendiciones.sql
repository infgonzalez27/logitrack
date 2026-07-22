-- 1. Agregar columna saldo_favor a la tabla clientes
ALTER TABLE public.clientes ADD COLUMN IF NOT EXISTS saldo_favor NUMERIC(12, 2) DEFAULT 0.00 CHECK (saldo_favor >= 0.00);

-- 2. Crear tabla de auditoría para movimientos del saldo a favor de clientes
CREATE TABLE IF NOT EXISTS public.movimientos_saldo_favor (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    cliente_id UUID REFERENCES public.clientes(id) ON DELETE CASCADE,
    rendicion_id UUID REFERENCES public.rendiciones_cuentas(id) ON DELETE SET NULL,
    orden_id UUID REFERENCES public.ordenes_distribucion(id) ON DELETE SET NULL,
    monto NUMERIC(12, 2) NOT NULL, -- Positivo para abonos, negativo para cargos/descuentos
    tipo TEXT NOT NULL CHECK (tipo IN ('abono_recaudacion', 'cargo_pago_orden', 'devolucion_efectivo')),
    observaciones TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 3. Crear Stored Procedure registrar_rendicion_cuentas
CREATE OR REPLACE FUNCTION public.registrar_rendicion_cuentas(
    p_cliente_id UUID,
    p_observaciones TEXT,
    p_creado_por UUID,
    p_ordenes JSONB,
    p_pagos JSONB
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
BEGIN
    -- Validaciones básicas
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

    -- Calcular total recaudado de las órdenes
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_ordenes) AS x(orden_id UUID, monto_recaudado NUMERIC(12,2)) LOOP
        v_total_ordenes := v_total_ordenes + v_item.monto_recaudado;
    END LOOP;

    -- Calcular total y clasificar según formas de pago
    FOR v_pago IN SELECT * FROM jsonb_to_recordset(p_pagos) AS y(metodo_pago TEXT, monto NUMERIC(12,2), referencia_bancaria TEXT, cuenta_bancaria TEXT, capture_url TEXT) LOOP
        v_total_pagos := v_total_pagos + v_pago.monto;
        IF v_pago.metodo_pago IN ('efectivo_usd', 'efectivo_bs') THEN
            v_total_efectivo := v_total_efectivo + v_pago.monto;
        ELSIF v_pago.metodo_pago IN ('transferencia', 'pago_movil') THEN
            v_total_transferencias := v_total_transferencias + v_pago.monto;
        END IF;
    END LOOP;

    -- Crear cabecera
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

    -- Registrar órdenes
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

    -- Registrar formas de pago (detalle_rendicion_fpagos)
    FOR v_pago IN SELECT * FROM jsonb_to_recordset(p_pagos) AS y(metodo_pago TEXT, monto NUMERIC(12,2), referencia_bancaria TEXT, cuenta_bancaria TEXT, capture_url TEXT) LOOP
        INSERT INTO public.detalle_rendicion_fpagos (
            rendicion_id,
            metodo_pago,
            monto,
            referencia_bancaria,
            cuenta_bancaria,
            capture_url
        ) VALUES (
            v_rendicion_id,
            v_pago.metodo_pago,
            v_pago.monto,
            v_pago.referencia_bancaria,
            v_pago.cuenta_bancaria,
            v_pago.capture_url
        );
    END LOOP;

    -- Manejo de Crédito a Favor del Cliente
    IF v_total_pagos > v_total_ordenes THEN
        v_exceso := v_total_pagos - v_total_ordenes;

        -- Registrar abono histórico
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

        -- Actualizar saldo a favor en cliente
        UPDATE public.clientes
        SET saldo_favor = COALESCE(saldo_favor, 0.00) + v_exceso
        WHERE id = p_cliente_id;
    END IF;

    -- Retorno
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


-- 4. Crear Trigger automático para liquidar órdenes al aprobarse la recaudación
CREATE OR REPLACE FUNCTION public.on_rendicion_aprobada_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_item RECORD;
    v_res JSON;
BEGIN
    -- Solo actuar cuando el estado cambia a 'aprobada'
    IF NEW.estado = 'aprobada' AND (OLD.estado IS DISTINCT FROM 'aprobada') THEN
        -- Buscar todas las órdenes asociadas a esta rendición de cuentas
        FOR v_item IN 
            SELECT orden_distribucion_id 
            FROM public.detalle_rendicion_ordenes 
            WHERE rendicion_id = NEW.id
        LOOP
            -- Ejecutar liquidación de forma automática
            v_res := public.liquidar_orden_distribucion(v_item.orden_distribucion_id);
            
            -- Si falla, revertimos toda la transacción
            IF (v_res->>'success')::BOOLEAN = FALSE THEN
                RAISE EXCEPTION 'Fallo al liquidar automáticamente la orden %: %', 
                    v_item.orden_distribucion_id, v_res->'error'->>'message';
            END IF;
        END LOOP;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_liquidar_ordenes_on_aprobacion ON public.rendiciones_cuentas;
CREATE TRIGGER trigger_liquidar_ordenes_on_aprobacion
AFTER UPDATE ON public.rendiciones_cuentas
FOR EACH ROW
EXECUTE FUNCTION public.on_rendicion_aprobada_trigger();
