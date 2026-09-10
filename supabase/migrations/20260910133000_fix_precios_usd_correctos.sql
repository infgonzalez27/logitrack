-- Migration: 20260910133000_fix_precios_usd_correctos.sql
-- Description: Fix unit price assignment in USD by prioritizing productos.precio_lista1 over corrupted fraction prices, recalculate order totals exclusively in USD, set Bs fields to NULL, and update all existing database records.

-- 1. Redefinir crear_orden_distribucion
CREATE OR REPLACE FUNCTION public.crear_orden_distribucion(
    p_vendedor_id UUID,
    p_cliente_id UUID,
    p_camion_id UUID,
    p_tasa_cambio NUMERIC DEFAULT NULL,
    p_productos_json JSONB DEFAULT '[]'::jsonb,
    p_despachador_id UUID DEFAULT NULL,
    p_id_ruta UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_orden_id UUID;
    v_correlativo INT;
    v_factura_origen VARCHAR(30);
    v_tasa_cambio NUMERIC(14,4);
    
    v_vendedor_id UUID;
    v_despachador_id UUID;
    v_id_ruta UUID;
    
    v_peso_total NUMERIC(10,2) := 0.00;
    v_total_recaudar_usd NUMERIC(14,2) := 0.00;
    
    v_item JSONB;
    v_secuencia INT := 1;
    v_producto_id UUID;
    v_cantidad INT;
    v_val_usd NUMERIC(14,2);
    v_val_usd_prod NUMERIC(14,2);
    v_subtotal_usd NUMERIC(14,2);
    v_peso_unitario NUMERIC(10,2);
BEGIN
    -- Validaciones básicas
    IF p_vendedor_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del vendedor es requerido.');
    END IF;

    IF p_cliente_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del cliente es requerido.');
    END IF;

    IF p_camion_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del camión es requerido.');
    END IF;

    IF p_productos_json IS NULL OR jsonb_array_length(p_productos_json) = 0 THEN
        RETURN jsonb_build_object('success', false, 'message', 'Debe incluir al menos un producto en la orden.');
    END IF;

    -- Obtener información del cliente (vendedor_id, despachador_id, id_ruta)
    SELECT c.vendedor_id, c.despachador_id, c.id_ruta
    INTO v_vendedor_id, v_despachador_id, v_id_ruta
    FROM public.clientes c
    WHERE c.id = p_cliente_id;

    -- Priorizar parámetros explícitos si fueron proporcionados
    v_vendedor_id := COALESCE(p_vendedor_id, v_vendedor_id);
    v_despachador_id := COALESCE(p_despachador_id, v_despachador_id);
    v_id_ruta := COALESCE(p_id_ruta, v_id_ruta);

    -- Validar existencia de entidades
    IF NOT EXISTS (SELECT 1 FROM public.perfiles_usuario WHERE id = p_vendedor_id) THEN
        RETURN jsonb_build_object('success', false, 'message', 'El vendedor especificado no existe.');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.clientes WHERE id = p_cliente_id) THEN
        RETURN jsonb_build_object('success', false, 'message', 'El cliente especificado no existe.');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.camiones WHERE id = p_camion_id) THEN
        RETURN jsonb_build_object('success', false, 'message', 'El camión especificado no existe.');
    END IF;

    -- Determinar / validar la tasa de cambio
    IF p_tasa_cambio IS NOT NULL AND p_tasa_cambio > 0 THEN
        v_tasa_cambio := p_tasa_cambio;
    ELSE
        SELECT tasa_cambio INTO v_tasa_cambio
        FROM public.tasa_cambio
        WHERE fecha_tasa = CURRENT_DATE;

        IF v_tasa_cambio IS NULL THEN
            SELECT tasa_cambio INTO v_tasa_cambio
            FROM public.tasa_cambio
            ORDER BY fecha_tasa DESC
            LIMIT 1;
        END IF;

        IF v_tasa_cambio IS NULL THEN
            RETURN jsonb_build_object(
                'success', false, 
                'message', 'No hay tasa de cambio registrada. Debe proporcionar p_tasa_cambio o registrar una tasa oficial en el sistema.'
            );
        END IF;
    END IF;

    -- Generar correlativo y número de factura de origen automáticamente
    v_correlativo := nextval('public.ordenes_distribucion_correlativo_seq');
    v_factura_origen := 'FAC-' || LPAD(v_correlativo::text, 6, '0');
    v_orden_id := gen_random_uuid();

    -- Validar productos y calcular totales exclusivamente en USD y peso total
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;
        
        IF v_cantidad IS NULL OR v_cantidad <= 0 THEN
            RETURN jsonb_build_object('success', false, 'message', 'La cantidad del producto debe ser mayor a cero.');
        END IF;

        SELECT COALESCE(precio_lista1, 0.00), COALESCE(peso_unitario_kg, 0.00) 
        INTO v_val_usd_prod, v_peso_unitario
        FROM public.productos
        WHERE id = v_producto_id;

        IF NOT FOUND THEN
            RETURN jsonb_build_object('success', false, 'message', 'El producto con ID ' || v_producto_id::text || ' no existe.');
        END IF;

        -- Resolver precio unitario en USD priorizando precio de lista del producto
        v_val_usd := COALESCE((v_item->>'valor_unitario_usd')::NUMERIC, (v_item->>'precio_unitario')::NUMERIC, v_val_usd_prod);
        IF v_val_usd <= 0 OR (v_val_usd < 1.00 AND v_val_usd_prod >= 1.00) THEN
            v_val_usd := v_val_usd_prod;
        END IF;

        v_subtotal_usd := ROUND(v_cantidad * v_val_usd, 2);

        v_peso_total := v_peso_total + (COALESCE(v_peso_unitario, 0.00) * v_cantidad);
        v_total_recaudar_usd := v_total_recaudar_usd + v_subtotal_usd;
    END LOOP;

    -- Insertar Cabecera de la Orden con estado 'aprobada' (total_recaudar_bs en NULL)
    INSERT INTO public.ordenes_distribucion (
        id,
        correlativo,
        cliente_id,
        camion_id,
        vendedor_id,
        despachador_id,
        id_ruta,
        estado,
        fecha_despacho,
        peso_total_calculado,
        factura_origen_numero,
        creado_por,
        created_at,
        tasa_cambio,
        total_recaudar_bs,
        total_recaudar_usd
    ) VALUES (
        v_orden_id,
        v_correlativo,
        p_cliente_id,
        p_camion_id,
        v_vendedor_id,
        v_despachador_id,
        v_id_ruta,
        'aprobada',
        NULL,
        v_peso_total,
        v_factura_origen,
        p_vendedor_id,
        NOW(),
        v_tasa_cambio,
        NULL,
        v_total_recaudar_usd
    );

    -- Insertar Detalles de la Orden (valor_unitario_recaudar y subtotal_recaudar en NULL)
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;
        
        SELECT COALESCE(precio_lista1, 0.00) INTO v_val_usd_prod
        FROM public.productos
        WHERE id = v_producto_id;

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
            secuencia_entrega,
            estado_entrega,
            motivo_rechazo,
            valor_unitario_usd,
            subtotal_recaudar_usd
        ) VALUES (
            gen_random_uuid(),
            v_orden_id,
            v_producto_id,
            v_cantidad,
            0,
            NULL,
            NULL,
            v_secuencia,
            'pendiente',
            NULL,
            v_val_usd,
            v_subtotal_usd
        );
        
        v_secuencia := v_secuencia + 1;
    END LOOP;

    RETURN jsonb_build_object(
        'success', true, 
        'message', 'Orden de distribución creada exitosamente.', 
        'orden_id', v_orden_id,
        'data', jsonb_build_object(
            'orden_id', v_orden_id,
            'correlativo', v_correlativo,
            'tasa_cambio', v_tasa_cambio,
            'total_recaudar_bs', NULL,
            'total_recaudar_usd', v_total_recaudar_usd,
            'peso_total_calculado', v_peso_total
        )
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false, 
        'message', 'Error al crear la orden: ' || SQLERRM
    );
END;
$$;

-- 2. Redefinir actualiza_orden_distribucion_segun_correlativo
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

    -- Validar que la orden esté en estado borrador para modificación
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

-- 3. Corrección Exhaustiva de Datos en la Base de Datos Remota
-- Restaurar el precio real en USD (productos.precio_lista1) en todas las filas de detalle_distribucion
UPDATE public.detalle_distribucion dd
SET 
    valor_unitario_usd = COALESCE(NULLIF(p.precio_lista1, 0.00), dd.valor_unitario_usd, 0.00),
    subtotal_recaudar_usd = ROUND(dd.cantidad_solicitada * COALESCE(NULLIF(p.precio_lista1, 0.00), dd.valor_unitario_usd, 0.00), 2),
    valor_unitario_recaudar = NULL,
    subtotal_recaudar = NULL
FROM public.productos p
WHERE dd.producto_id = p.id;

-- Recalcular total_recaudar_usd en ordenes_distribucion y blanquear total_recaudar_bs a NULL
UPDATE public.ordenes_distribucion od
SET 
    total_recaudar_usd = COALESCE(d.sum_usd, 0.00),
    total_recaudar_bs = NULL
FROM (
    SELECT 
        orden_id,
        SUM(subtotal_recaudar_usd) AS sum_usd
    FROM public.detalle_distribucion
    GROUP BY orden_id
) d
WHERE od.id = d.orden_id;
