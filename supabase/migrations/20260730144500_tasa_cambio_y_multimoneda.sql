-- Migration: Tasa de Cambio, Multimoneda y Gestión por Vendedor (DB-013 a DB-018)

-- 1. Tabla tasa_cambio (DB-013)
CREATE TABLE IF NOT EXISTS public.tasa_cambio (
    fecha_tasa DATE PRIMARY KEY,
    tasa_cambio NUMERIC(14,4) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Habilitar RLS en tasa_cambio
ALTER TABLE public.tasa_cambio ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'tasa_cambio' AND policyname = 'Permitir lectura de tasa_cambio a usuarios autenticados'
    ) THEN
        CREATE POLICY "Permitir lectura de tasa_cambio a usuarios autenticados"
            ON public.tasa_cambio FOR SELECT TO authenticated USING (true);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'tasa_cambio' AND policyname = 'Permitir administracion de tasa_cambio a usuarios autorizados'
    ) THEN
        CREATE POLICY "Permitir administracion de tasa_cambio a usuarios autorizados"
            ON public.tasa_cambio FOR ALL TO authenticated
            USING (public.user_has_role(ARRAY['admin', 'gerente']));
    END IF;
END $$;

-- 2. RPC inserta_tasa_cambio
CREATE OR REPLACE FUNCTION public.inserta_tasa_cambio(
    p_fecha_tasa DATE,
    p_tasa NUMERIC
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF p_fecha_tasa IS NULL OR p_tasa IS NULL OR p_tasa <= 0 THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'La fecha y el monto de la tasa deben ser válidos y mayores a cero.',
                'details', NULL
            )
        );
    END IF;

    IF EXISTS (SELECT 1 FROM public.tasa_cambio WHERE fecha_tasa = p_fecha_tasa) THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'FECHA_TASA_DUPLICADA',
                'message', 'Ya existe una tasa registrada para la fecha ' || p_fecha_tasa::text || '. Para modificarla, elimínela primero.',
                'details', NULL
            )
        );
    END IF;

    INSERT INTO public.tasa_cambio (fecha_tasa, tasa_cambio)
    VALUES (p_fecha_tasa, p_tasa);

    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'fecha_tasa', p_fecha_tasa,
            'tasa_cambio', p_tasa
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

-- 3. RPC elimina_tasa_cambio
CREATE OR REPLACE FUNCTION public.elimina_tasa_cambio(
    p_fecha_tasa DATE
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF p_fecha_tasa IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'La fecha de la tasa es requerida.',
                'details', NULL
            )
        );
    END IF;

    DELETE FROM public.tasa_cambio WHERE fecha_tasa = p_fecha_tasa;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'TASA_NO_ENCONTRADA',
                'message', 'No se encontró ninguna tasa registrada para la fecha ' || p_fecha_tasa::text,
                'details', NULL
            )
        );
    END IF;

    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'fecha_tasa', p_fecha_tasa,
            'eliminado', true
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

-- 4. RPC retorna_ultima_tasa_cambio
CREATE OR REPLACE FUNCTION public.retorna_ultima_tasa_cambio()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result RECORD;
BEGIN
    SELECT fecha_tasa, tasa_cambio, created_at
    INTO v_result
    FROM public.tasa_cambio
    ORDER BY fecha_tasa DESC
    LIMIT 1;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', true,
            'data', NULL,
            'error', NULL
        );
    END IF;

    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'fecha_tasa', v_result.fecha_tasa,
            'tasa_cambio', v_result.tasa_cambio,
            'created_at', v_result.created_at
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

-- 5. RPC retorna_tasas_cambio_por_rango
CREATE OR REPLACE FUNCTION public.retorna_tasas_cambio_por_rango(
    p_fecha_desde DATE,
    p_fecha_hasta DATE
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_tasas JSON;
BEGIN
    IF p_fecha_desde IS NULL OR p_fecha_hasta IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'Las fechas de inicio y fin son requeridas.',
                'details', NULL
            )
        );
    END IF;

    SELECT COALESCE(json_agg(
        json_build_object(
            'fecha_tasa', fecha_tasa,
            'tasa_cambio', tasa_cambio,
            'created_at', created_at
        ) ORDER BY fecha_tasa DESC
    ), '[]'::json)
    INTO v_tasas
    FROM public.tasa_cambio
    WHERE fecha_tasa >= p_fecha_desde AND fecha_tasa <= p_fecha_hasta;

    RETURN json_build_object(
        'success', true,
        'data', v_tasas,
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

-- 6. Agregar vendedor_id a clientes (DB-014)
ALTER TABLE public.clientes
ADD COLUMN IF NOT EXISTS vendedor_id UUID REFERENCES public.perfiles_usuario(id) ON DELETE SET NULL;

-- 7. Agregar campos multimoneda (DB-015)
ALTER TABLE public.ordenes_distribucion
ADD COLUMN IF NOT EXISTS tasa_cambio NUMERIC(14,4),
ADD COLUMN IF NOT EXISTS total_recaudar_bs NUMERIC(14,2),
ADD COLUMN IF NOT EXISTS total_recaudar_usd NUMERIC(14,2);

ALTER TABLE public.detalle_distribucion
ADD COLUMN IF NOT EXISTS valor_unitario_usd NUMERIC(14,2),
ADD COLUMN IF NOT EXISTS subtotal_recaudar_usd NUMERIC(14,2);

-- 8. RPC actualiza_orden_distribucion_segun_correlativo (DB-017)
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
    v_chofer_id UUID;
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
    v_chofer_id := (p_header->>'chofer_id')::UUID;
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
        chofer_id = COALESCE(v_chofer_id, chofer_id),
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

-- 9. RPC retorna_ordenes_distribucion_segun_estado (DB-018)
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
            'chofer_id', o.chofer_id,
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
