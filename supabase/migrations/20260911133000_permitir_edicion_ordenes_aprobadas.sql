-- Migration: 20260911133000_permitir_edicion_ordenes_aprobadas.sql
-- Description: Permitir la actualización y edición de órdenes de distribución que estén en estado 'aprobada' (además de 'borrador').

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
    v_total_usd NUMERIC(14,2) := 0.00;
    
    v_item JSONB;
    v_secuencia INT := 1;
    v_producto_id UUID;
    v_cantidad INT;
    v_val_usd NUMERIC(14,2);
    v_val_usd_prod NUMERIC(14,2);
    v_subtotal_usd NUMERIC(14,2);
    v_peso_unitario NUMERIC(14,2);
BEGIN
    -- 1. Validar parámetros principales
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

    -- Obtener orden actual
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

    -- Validar que la orden esté en estado borrador o aprobada para modificación
    IF v_estado_actual NOT IN ('borrador', 'aprobada') THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo se pueden actualizar órdenes en estado borrador o aprobada. Estado actual: ' || v_estado_actual,
                'details', NULL
            )
        );
    END IF;

    -- Validar permisos por rol
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

    -- Extract header values
    v_cliente_id := (p_header->>'cliente_id')::UUID;
    v_camion_id := (p_header->>'camion_id')::UUID;
    v_fecha_despacho := (p_header->>'fecha_despacho')::TIMESTAMPTZ;
    v_factura_origen := p_header->>'factura_origen_numero';
    v_fecha_tasa := COALESCE(v_fecha_despacho::date, CURRENT_DATE);

    -- Validar existencia de tasa de cambio para la fecha de la orden
    SELECT tasa_cambio INTO v_tasa_cambio
    FROM public.tasa_cambio
    WHERE fecha_tasa = v_fecha_tasa;

    IF NOT FOUND THEN
        SELECT tasa_cambio INTO v_tasa_cambio
        FROM public.tasa_cambio
        ORDER BY fecha_tasa DESC
        LIMIT 1;
    END IF;

    IF v_tasa_cambio IS NULL THEN
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

    -- Re-calcular totales recorriendo el detalle exclusivamente en USD
    IF p_detalle IS NOT NULL AND jsonb_array_length(p_detalle) > 0 THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(p_detalle) LOOP
            v_producto_id := (v_item->>'producto_id')::UUID;
            v_cantidad := (v_item->>'cantidad_solicitada')::INT;
            
            SELECT COALESCE(precio_lista1, 0.00), COALESCE(peso_unitario_kg, 0.00)
            INTO v_val_usd_prod, v_peso_unitario
            FROM public.productos WHERE id = v_producto_id;

            v_val_usd := COALESCE((v_item->>'valor_unitario_usd')::NUMERIC, (v_item->>'precio_unitario')::NUMERIC, v_val_usd_prod);
            IF v_val_usd <= 0 OR (v_val_usd < 1.00 AND v_val_usd_prod >= 1.00) THEN
                v_val_usd := v_val_usd_prod;
            END IF;

            v_subtotal_usd := ROUND(v_cantidad * v_val_usd, 2);

            v_total_usd := v_total_usd + v_subtotal_usd;
            v_peso_total := v_peso_total + (v_peso_unitario * v_cantidad);
        END LOOP;
    END IF;

    -- Actualizar Cabecera de la Orden (total_recaudar_bs en NULL)
    UPDATE public.ordenes_distribucion
    SET cliente_id = COALESCE(v_cliente_id, cliente_id),
        camion_id = COALESCE(v_camion_id, camion_id),
        fecha_despacho = COALESCE(v_fecha_despacho, fecha_despacho),
        factura_origen_numero = COALESCE(v_factura_origen, factura_origen_numero),
        tasa_cambio = v_tasa_cambio,
        peso_total_calculado = v_peso_total,
        total_recaudar_bs = NULL,
        total_recaudar_usd = v_total_usd
    WHERE id = v_orden_id;

    -- Reemplazar Detalle si fue provisto (valor_unitario_recaudar y subtotal_recaudar en NULL)
    IF p_detalle IS NOT NULL AND jsonb_array_length(p_detalle) > 0 THEN
        DELETE FROM public.detalle_distribucion WHERE orden_id = v_orden_id;

        FOR v_item IN SELECT * FROM jsonb_array_elements(p_detalle) LOOP
            v_producto_id := (v_item->>'producto_id')::UUID;
            v_cantidad := (v_item->>'cantidad_solicitada')::INT;
            
            SELECT COALESCE(precio_lista1, 0.00) INTO v_val_usd_prod
            FROM public.productos WHERE id = v_producto_id;

            v_val_usd := COALESCE((v_item->>'valor_unitario_usd')::NUMERIC, (v_item->>'precio_unitario')::NUMERIC, v_val_usd_prod);
            IF v_val_usd <= 0 OR (v_val_usd < 1.00 AND v_val_usd_prod >= 1.00) THEN
                v_val_usd := v_val_usd_prod;
            END IF;

            v_subtotal_usd := ROUND(v_cantidad * v_val_usd, 2);

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
                NULL,
                NULL,
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
            'total_recaudar_bs', NULL,
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

GRANT EXECUTE ON FUNCTION public.actualiza_orden_distribucion_segun_correlativo TO authenticated, service_role;
