-- ==============================================================================
-- PARCHE IDEMPOTENTE: RESERVA INMEDIATA DE STOCK EN ALMACÉN PARA ÓRDENES DE DISTRIBUCIÓN
-- Fecha: 2026-11-24 16:00:00
-- Descripción:
--   Implementa el Esquema 1 (reserva inmediata en inventario_almacen):
--   1. Agrega `public.ordenes_distribucion.stock_reservado BOOLEAN NOT NULL DEFAULT FALSE`
--      para distinguir con precisión órdenes que mantienen stock comprometido en almacén
--      frente a órdenes históricas previas al parche, reversadas o reprogramadas.
--   2. `public.crear_orden_distribucion`:
--      - Bloquea `inventario_almacen` con `FOR UPDATE` en orden determinístico por `producto_id`.
--      - Valida que `stock_disponible >= cantidad_solicitada` (rechaza con `STOCK_INSUFICIENTE_ALMACEN`).
--      - Mueve atómicamente `stock_disponible -> stock_comprometido` y marca `stock_reservado = TRUE`.
--   3. `public.actualiza_orden_distribucion_segun_correlativo`:
--      - Bloquea los SKU involucrados con `FOR UPDATE`.
--      - Calcula delta neto (si `stock_reservado = TRUE`) o cantidad total (si `stock_reservado = FALSE`).
--      - Rechaza con `STOCK_INSUFICIENTE_ALMACEN` si el incremento supera `stock_disponible`.
--      - Ajusta `stock_disponible` y `stock_comprometido`, marcando `stock_reservado = TRUE`.
--   4. `public.anular_orden_distribucion`:
--      - Si la orden está en `borrador`/`aprobada` con `stock_reservado = TRUE`, libera
--        `stock_comprometido -> stock_disponible` y marca `stock_reservado = FALSE`.
--   5. `public.generar_despacho_orden_almacen`:
--      - Si `stock_reservado = TRUE`, consume primero `stock_comprometido` (evitando doble descuento)
--        y valida/descuenta cualquier remanente de `stock_disponible`, marcando `stock_reservado = FALSE`.
--   6. `public.solicita_cargar_inventario_movil_desde_almacen`:
--      - Elimina el bug de stock fantasma (`GREATEST(0, ...)`): bloquea `inventario_almacen FOR UPDATE`,
--        consume `stock_comprometido` únicamente hasta el monto reservado por las órdenes del Radar
--        (0 para AutoVentas) y rechaza estrictamente con `STOCK_INSUFICIENTE_ALMACEN` si no alcanza
--        `stock_disponible`. Limpia `stock_reservado = FALSE` al pasar órdenes del Radar a `en_transito`.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 0. Columna idempotente de control de reserva en ordenes_distribucion
-- ------------------------------------------------------------------------------
ALTER TABLE IF EXISTS public.ordenes_distribucion
    ADD COLUMN IF NOT EXISTS stock_reservado BOOLEAN NOT NULL DEFAULT FALSE;

UPDATE public.inventario_almacen
SET stock_comprometido = 0,
    updated_at = NOW()
WHERE stock_comprometido < 0;


-- ------------------------------------------------------------------------------
-- 1. crear_orden_distribucion (con bloqueo FOR UPDATE y reserva inmediata)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.crear_orden_distribucion(
    p_vendedor_id UUID,
    p_cliente_id UUID,
    p_camion_id UUID DEFAULT NULL,
    p_tasa_cambio NUMERIC DEFAULT NULL,
    p_productos_json JSONB DEFAULT '[]'::jsonb,
    p_despachador_id UUID DEFAULT NULL,
    p_id_ruta UUID DEFAULT NULL,
    p_es_cortesia BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
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
    v_req RECORD;
    v_secuencia INT := 1;
    v_producto_id UUID;
    v_cantidad INT;
    v_prod_nombre TEXT;
    v_stock_disponible INT;

    v_val_usd_prod NUMERIC(14,2);
    v_val_usd NUMERIC(14,2);
    v_pct_desc NUMERIC(5,2) := 0.00;
    v_monto_desc_unit NUMERIC(14,2) := 0.00;
    v_subtotal_usd NUMERIC(14,2);
    v_peso_unitario NUMERIC(10,2);

    v_desc_rec RECORD;
    v_err_msg TEXT;
BEGIN
    -- Validaciones básicas
    IF p_vendedor_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del vendedor es requerido.');
    END IF;

    IF p_cliente_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del cliente es requerido.');
    END IF;

    IF p_productos_json IS NULL OR jsonb_typeof(p_productos_json) <> 'array' OR jsonb_array_length(p_productos_json) = 0 THEN
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

    IF p_camion_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.camiones WHERE id = p_camion_id) THEN
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

    -- Validar productos y calcular totales exclusivamente en USD y peso total
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;

        IF v_producto_id IS NULL THEN
            RETURN jsonb_build_object('success', false, 'message', 'Cada producto debe especificar un producto_id válido.');
        END IF;

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

        -- Buscar descuento específico del cliente para este producto
        SELECT * INTO v_desc_rec
        FROM public.descuentos_cliente_producto
        WHERE cliente_id = p_cliente_id AND producto_id = v_producto_id AND activo = true;

        -- Resolver precio unitario en USD
        IF p_es_cortesia = TRUE THEN
            v_val_usd := 0.00;
        ELSIF (v_item->>'valor_unitario_usd') IS NOT NULL THEN
            v_val_usd := (v_item->>'valor_unitario_usd')::NUMERIC;
        ELSIF (v_item->>'precio_unitario') IS NOT NULL THEN
            v_val_usd := (v_item->>'precio_unitario')::NUMERIC;
        ELSIF v_desc_rec.id IS NOT NULL THEN
            IF v_desc_rec.precio_pactado_usd IS NOT NULL THEN
                v_val_usd := v_desc_rec.precio_pactado_usd;
            ELSIF v_desc_rec.porcentaje_descuento > 0 THEN
                v_val_usd := ROUND(v_val_usd_prod * (1.00 - (v_desc_rec.porcentaje_descuento / 100.00)), 2);
            ELSE
                v_val_usd := v_val_usd_prod;
            END IF;
        ELSE
            v_val_usd := v_val_usd_prod;
        END IF;

        IF p_es_cortesia = FALSE AND (v_val_usd <= 0 OR (v_val_usd < 1.00 AND v_val_usd_prod >= 1.00)) THEN
            v_val_usd := v_val_usd_prod;
        END IF;

        v_subtotal_usd := ROUND(v_cantidad * v_val_usd, 2);

        v_peso_total := v_peso_total + (COALESCE(v_peso_unitario, 0.00) * v_cantidad);
        v_total_recaudar_usd := v_total_recaudar_usd + v_subtotal_usd;
    END LOOP;

    -- Bloquear inventario_almacen FOR UPDATE en orden determinístico y validar stock disponible
    FOR v_req IN
        SELECT
            (elem->>'producto_id')::UUID AS producto_id,
            SUM((elem->>'cantidad')::INT)::INT AS cantidad_total,
            COUNT(*)::INT AS repeticiones
        FROM jsonb_array_elements(p_productos_json) AS elem
        GROUP BY (elem->>'producto_id')::UUID
        ORDER BY (elem->>'producto_id')::UUID
    LOOP
        SELECT nombre INTO v_prod_nombre
        FROM public.productos
        WHERE id = v_req.producto_id;

        IF v_req.repeticiones > 1 THEN
            v_err_msg := format(
                'El producto %s está duplicado en la orden. Consolide la cantidad en una sola línea.',
                COALESCE(v_prod_nombre, v_req.producto_id::text)
            );
            RETURN jsonb_build_object(
                'success', false,
                'message', v_err_msg,
                'error', jsonb_build_object('code', 'PRODUCTO_DUPLICADO', 'message', v_err_msg)
            );
        END IF;

        SELECT stock_disponible
        INTO v_stock_disponible
        FROM public.inventario_almacen
        WHERE producto_id = v_req.producto_id
        FOR UPDATE;

        IF NOT FOUND OR COALESCE(v_stock_disponible, 0) < v_req.cantidad_total THEN
            v_err_msg := format(
                'Stock insuficiente en almacén para el producto %s (Disponible: %s, Solicitado: %s).',
                COALESCE(v_prod_nombre, v_req.producto_id::text),
                COALESCE(v_stock_disponible, 0),
                v_req.cantidad_total
            );
            RETURN jsonb_build_object(
                'success', false,
                'message', v_err_msg,
                'error', jsonb_build_object(
                    'code', 'STOCK_INSUFICIENTE_ALMACEN',
                    'message', v_err_msg
                )
            );
        END IF;
    END LOOP;

    -- Generar correlativo y número de factura de origen únicamente tras validar stock
    v_correlativo := nextval('public.ordenes_distribucion_correlativo_seq');
    v_factura_origen := 'FAC-' || LPAD(v_correlativo::text, 6, '0');
    v_orden_id := gen_random_uuid();

    -- Reservar stock en almacén (stock_disponible -> stock_comprometido)
    FOR v_req IN
        SELECT
            (elem->>'producto_id')::UUID AS producto_id,
            SUM((elem->>'cantidad')::INT)::INT AS cantidad_total
        FROM jsonb_array_elements(p_productos_json) AS elem
        GROUP BY (elem->>'producto_id')::UUID
        ORDER BY (elem->>'producto_id')::UUID
    LOOP
        UPDATE public.inventario_almacen
        SET stock_disponible = stock_disponible - v_req.cantidad_total,
            stock_comprometido = COALESCE(stock_comprometido, 0) + v_req.cantidad_total,
            updated_at = NOW()
        WHERE producto_id = v_req.producto_id;
    END LOOP;

    -- Insertar Cabecera de la Orden con estado 'aprobada' y stock_reservado = TRUE
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
        total_recaudar_usd,
        es_cortesia,
        stock_reservado
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
        v_total_recaudar_usd,
        p_es_cortesia,
        TRUE
    );

    -- Insertar Detalles de la Orden
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;

        SELECT COALESCE(precio_lista1, 0.00) INTO v_val_usd_prod
        FROM public.productos
        WHERE id = v_producto_id;

        SELECT * INTO v_desc_rec
        FROM public.descuentos_cliente_producto
        WHERE cliente_id = p_cliente_id AND producto_id = v_producto_id AND activo = true;

        IF p_es_cortesia = TRUE THEN
            v_pct_desc := 0.00;
            v_monto_desc_unit := 0.00;
            v_val_usd := 0.00;
        ELSIF v_desc_rec.id IS NOT NULL THEN
            v_pct_desc := COALESCE(v_desc_rec.porcentaje_descuento, 0.00);
            IF v_desc_rec.precio_pactado_usd IS NOT NULL THEN
                v_val_usd := v_desc_rec.precio_pactado_usd;
                v_monto_desc_unit := GREATEST(0.00, v_val_usd_prod - v_val_usd);
            ELSIF v_desc_rec.porcentaje_descuento > 0 THEN
                v_val_usd := ROUND(v_val_usd_prod * (1.00 - (v_pct_desc / 100.00)), 2);
                v_monto_desc_unit := v_val_usd_prod - v_val_usd;
            ELSE
                v_val_usd := v_val_usd_prod;
                v_monto_desc_unit := 0.00;
            END IF;
        ELSE
            v_pct_desc := 0.00;
            v_monto_desc_unit := 0.00;
            v_val_usd := COALESCE((v_item->>'valor_unitario_usd')::NUMERIC, (v_item->>'precio_unitario')::NUMERIC, v_val_usd_prod);
        END IF;

        IF p_es_cortesia = FALSE AND (v_val_usd <= 0 OR (v_val_usd < 1.00 AND v_val_usd_prod >= 1.00)) THEN
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
            subtotal_recaudar_usd,
            precio_lista_usd,
            porcentaje_descuento,
            monto_descuento_usd
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
            v_subtotal_usd,
            v_val_usd_prod,
            v_pct_desc,
            v_monto_desc_unit * v_cantidad
        );

        v_secuencia := v_secuencia + 1;
    END LOOP;

    RETURN jsonb_build_object(
        'success', true,
        'message', 'Orden de distribución creada exitosamente y stock reservado en almacén.',
        'orden_id', v_orden_id,
        'data', jsonb_build_object(
            'orden_id', v_orden_id,
            'correlativo', v_correlativo,
            'tasa_cambio', v_tasa_cambio,
            'total_recaudar_bs', NULL,
            'total_recaudar_usd', v_total_recaudar_usd,
            'peso_total_calculado', v_peso_total,
            'stock_reservado', TRUE
        )
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false,
        'message', 'Error al crear la orden: ' || SQLERRM
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.crear_orden_distribucion(UUID, UUID, UUID, NUMERIC, JSONB, UUID, UUID, BOOLEAN) TO authenticated, service_role;


-- ------------------------------------------------------------------------------
-- 2. actualiza_orden_distribucion_segun_correlativo (ajuste atómico de reserva)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.actualiza_orden_distribucion_segun_correlativo(
    p_correlativo INT,
    p_header JSONB,
    p_detalle JSONB
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_orden RECORD;
    v_user_id UUID := auth.uid();
    v_rol TEXT;
    v_es_gerencia BOOLEAN := FALSE;
    v_tiene_abonos BOOLEAN := FALSE;
    v_stock_reservado_final BOOLEAN;

    v_cliente_id UUID;
    v_camion_id UUID;
    v_fecha_despacho TIMESTAMPTZ;
    v_factura_origen TEXT;
    v_fecha_tasa DATE;
    v_tasa_cambio NUMERIC(14,4);

    v_peso_total NUMERIC(14,2) := 0.00;
    v_total_usd NUMERIC(14,2) := 0.00;
    v_total_bs NUMERIC(14,2) := 0.00;

    v_item JSONB;
    v_sku RECORD;
    v_secuencia INT := 1;
    v_producto_id UUID;
    v_cantidad INT;
    v_prod_nombre TEXT;
    v_stock_disponible INT;
    v_stock_comprometido INT;
    v_delta INT;
    v_release INT;
    v_err_msg TEXT;

    v_val_usd NUMERIC(14,2);
    v_val_usd_prod NUMERIC(14,2);
    v_subtotal_usd NUMERIC(14,2);
    v_val_bs NUMERIC(14,2);
    v_subtotal_bs NUMERIC(12,2);
    v_peso_unitario NUMERIC(14,2);
    v_precio_lista_usd NUMERIC(14,2);
    v_pct_descuento NUMERIC(5,2);
    v_monto_descuento_usd NUMERIC(14,2);
    v_contenedores_retirados_prev INT;
    v_contenedor_id_prev UUID;

    v_detalles_previos JSONB;
    v_detalles_nuevos JSONB;
    v_mapa_retirados JSONB := '{}'::jsonb;
    v_valores_anteriores JSONB;
    v_valores_nuevos JSONB;
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

    -- 2. Obtener y bloquear orden actual
    SELECT *
    INTO v_orden
    FROM public.ordenes_distribucion
    WHERE correlativo = p_correlativo
    FOR UPDATE;

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

    v_stock_reservado_final := COALESCE(v_orden.stock_reservado, FALSE);

    -- 3. Validar que la orden esté en estado borrador o aprobada para modificación
    IF v_orden.estado NOT IN ('borrador', 'aprobada') THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo se pueden actualizar órdenes en estado borrador o aprobada. Si la orden está por liquidar, primero anule el despacho. Estado actual: ' || v_orden.estado,
                'details', NULL
            )
        );
    END IF;

    -- 4. Validar permisos por rol
    v_rol := public.lt_current_user_rol();
    v_es_gerencia := COALESCE(public.user_has_role(ARRAY['admin', 'gerente']), FALSE)
                     OR COALESCE(v_rol, '') IN ('admin', 'gerente');

    SELECT EXISTS (
        SELECT 1
        FROM public.detalle_rendicion_ordenes dro
        JOIN public.rendiciones_cuentas rc ON rc.id = dro.rendicion_id
        WHERE dro.orden_distribucion_id = v_orden.id
          AND rc.estado <> 'reversada'
    ) INTO v_tiene_abonos;

    IF (v_orden.radar_id IS NOT NULL OR v_tiene_abonos OR COALESCE(v_orden.observaciones, '') LIKE '%DESPACHO ANULADO%')
       AND NOT v_es_gerencia THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ACCESO_DENEGADO',
                'message', 'Solo la Gerencia o Administración puede modificar una orden con despacho previo o abonos.',
                'details', NULL
            )
        );
    END IF;

    IF public.user_has_role(ARRAY['vendedor']) AND NOT v_es_gerencia AND NOT public.user_has_role(ARRAY['despachador']) THEN
        IF v_user_id IS NOT NULL AND v_orden.creado_por IS DISTINCT FROM v_user_id THEN
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

    -- 5. Capturar estado anterior y mapa de envases retirados previos
    SELECT COALESCE(jsonb_agg(to_jsonb(d)), '[]'::jsonb)
    INTO v_detalles_previos
    FROM public.detalle_distribucion d
    WHERE d.orden_id = v_orden.id;

    SELECT COALESCE(
        jsonb_object_agg(
            d.producto_id::text,
            jsonb_build_object(
                'contenedores_retirados', COALESCE(d.contenedores_retirados, 0),
                'contenedor_id', d.contenedor_id
            )
        ),
        '{}'::jsonb
    )
    INTO v_mapa_retirados
    FROM public.detalle_distribucion d
    WHERE d.orden_id = v_orden.id
      AND d.producto_id IS NOT NULL;

    v_valores_anteriores := jsonb_build_object(
        'correlativo', v_orden.correlativo,
        'estado', v_orden.estado,
        'cliente_id', v_orden.cliente_id,
        'camion_id', v_orden.camion_id,
        'fecha_despacho', v_orden.fecha_despacho,
        'factura_origen_numero', v_orden.factura_origen_numero,
        'tasa_cambio', v_orden.tasa_cambio,
        'total_recaudar_usd', v_orden.total_recaudar_usd,
        'total_recaudar_bs', v_orden.total_recaudar_bs,
        'peso_total_calculado', v_orden.peso_total_calculado,
        'stock_reservado', COALESCE(v_orden.stock_reservado, FALSE),
        'detalles', v_detalles_previos
    );

    -- 6. Extraer cabecera y resolver tasa de cambio
    v_cliente_id := COALESCE((p_header->>'cliente_id')::UUID, v_orden.cliente_id);
    v_camion_id := COALESCE(NULLIF(p_header->>'camion_id', '')::UUID, v_orden.camion_id);
    v_fecha_despacho := COALESCE(NULLIF(p_header->>'fecha_despacho', '')::TIMESTAMPTZ, v_orden.fecha_despacho);
    v_factura_origen := COALESCE(NULLIF(TRIM(p_header->>'factura_origen_numero'), ''), v_orden.factura_origen_numero);
    v_fecha_tasa := COALESCE(v_fecha_despacho::date, CURRENT_DATE);

    SELECT tasa_cambio INTO v_tasa_cambio
    FROM public.tasa_cambio
    WHERE fecha_tasa = v_fecha_tasa;

    IF NOT FOUND OR v_tasa_cambio IS NULL THEN
        IF v_orden.tasa_cambio IS NOT NULL AND v_orden.tasa_cambio > 0 THEN
            v_tasa_cambio := v_orden.tasa_cambio;
        ELSE
            SELECT tasa_cambio INTO v_tasa_cambio
            FROM public.tasa_cambio
            ORDER BY fecha_tasa DESC
            LIMIT 1;
        END IF;
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

    -- 7. Validar stock en almacén y ajustar reserva antes de modificar detalle
    IF p_detalle IS NOT NULL AND jsonb_typeof(p_detalle) = 'array' AND jsonb_array_length(p_detalle) > 0 THEN
        -- Validación básica de líneas entrantes
        FOR v_item IN SELECT * FROM jsonb_array_elements(p_detalle) LOOP
            v_producto_id := (v_item->>'producto_id')::UUID;
            v_cantidad := COALESCE((v_item->>'cantidad_solicitada')::INT, (v_item->>'cantidad')::INT, 0);

            IF v_producto_id IS NULL THEN
                RETURN json_build_object(
                    'success', false,
                    'data', NULL,
                    'error', json_build_object('code', 'PARAMETRO_INVALIDO', 'message', 'Cada producto debe especificar un producto_id válido.', 'details', NULL)
                );
            END IF;

            IF v_cantidad <= 0 THEN
                RETURN json_build_object(
                    'success', false,
                    'data', NULL,
                    'error', json_build_object('code', 'PARAMETRO_INVALIDO', 'message', 'La cantidad solicitada para cada producto debe ser mayor a cero.', 'details', NULL)
                );
            END IF;
        END LOOP;

        -- Fase A: Bloquear inventario_almacen FOR UPDATE en orden determinístico y validar disponibilidad
        FOR v_sku IN
            WITH old_det AS (
                SELECT producto_id, SUM(COALESCE(cantidad_solicitada, 0))::INT AS old_qty
                FROM public.detalle_distribucion
                WHERE orden_id = v_orden.id
                GROUP BY producto_id
            ),
            new_det AS (
                SELECT
                    (elem->>'producto_id')::UUID AS producto_id,
                    SUM(COALESCE((elem->>'cantidad_solicitada')::INT, (elem->>'cantidad')::INT, 0))::INT AS new_qty,
                    COUNT(*)::INT AS repeticiones
                FROM jsonb_array_elements(p_detalle) AS elem
                GROUP BY (elem->>'producto_id')::UUID
            )
            SELECT
                COALESCE(n.producto_id, o.producto_id) AS producto_id,
                COALESCE(o.old_qty, 0) AS old_qty,
                COALESCE(n.new_qty, 0) AS new_qty,
                COALESCE(n.repeticiones, 0) AS repeticiones
            FROM old_det o
            FULL OUTER JOIN new_det n ON n.producto_id = o.producto_id
            ORDER BY COALESCE(n.producto_id, o.producto_id)
        LOOP
            SELECT nombre INTO v_prod_nombre
            FROM public.productos
            WHERE id = v_sku.producto_id;

            IF v_sku.repeticiones > 1 THEN
                v_err_msg := format(
                    'El producto %s está duplicado en la orden. Consolide la cantidad en una sola línea.',
                    COALESCE(v_prod_nombre, v_sku.producto_id::text)
                );
                RETURN json_build_object(
                    'success', false,
                    'data', NULL,
                    'error', json_build_object('code', 'PRODUCTO_DUPLICADO', 'message', v_err_msg, 'details', NULL)
                );
            END IF;

            IF COALESCE(v_orden.stock_reservado, FALSE) = TRUE THEN
                v_delta := v_sku.new_qty - v_sku.old_qty;
            ELSE
                v_delta := v_sku.new_qty;
            END IF;

            IF v_delta <> 0 THEN
                SELECT stock_disponible, stock_comprometido
                INTO v_stock_disponible, v_stock_comprometido
                FROM public.inventario_almacen
                WHERE producto_id = v_sku.producto_id
                FOR UPDATE;

                IF v_delta > 0 AND (NOT FOUND OR COALESCE(v_stock_disponible, 0) < v_delta) THEN
                    v_err_msg := format(
                        'Stock insuficiente en almacén para el producto %s (Disponible adicional: %s, Incremento requerido: %s, Solicitado total: %s).',
                        COALESCE(v_prod_nombre, v_sku.producto_id::text),
                        COALESCE(v_stock_disponible, 0),
                        v_delta,
                        v_sku.new_qty
                    );
                    RETURN json_build_object(
                        'success', false,
                        'data', NULL,
                        'error', json_build_object(
                            'code', 'STOCK_INSUFICIENTE_ALMACEN',
                            'message', v_err_msg,
                            'details', NULL
                        )
                    );
                END IF;
            END IF;
        END LOOP;

        -- Fase B: Aplicar ajustes de stock_disponible y stock_comprometido
        FOR v_sku IN
            WITH old_det AS (
                SELECT producto_id, SUM(COALESCE(cantidad_solicitada, 0))::INT AS old_qty
                FROM public.detalle_distribucion
                WHERE orden_id = v_orden.id
                GROUP BY producto_id
            ),
            new_det AS (
                SELECT
                    (elem->>'producto_id')::UUID AS producto_id,
                    SUM(COALESCE((elem->>'cantidad_solicitada')::INT, (elem->>'cantidad')::INT, 0))::INT AS new_qty
                FROM jsonb_array_elements(p_detalle) AS elem
                GROUP BY (elem->>'producto_id')::UUID
            )
            SELECT
                COALESCE(n.producto_id, o.producto_id) AS producto_id,
                COALESCE(o.old_qty, 0) AS old_qty,
                COALESCE(n.new_qty, 0) AS new_qty
            FROM old_det o
            FULL OUTER JOIN new_det n ON n.producto_id = o.producto_id
            ORDER BY COALESCE(n.producto_id, o.producto_id)
        LOOP
            IF COALESCE(v_orden.stock_reservado, FALSE) = TRUE THEN
                v_delta := v_sku.new_qty - v_sku.old_qty;
            ELSE
                v_delta := v_sku.new_qty;
            END IF;

            IF v_delta > 0 THEN
                UPDATE public.inventario_almacen
                SET stock_disponible = stock_disponible - v_delta,
                    stock_comprometido = COALESCE(stock_comprometido, 0) + v_delta,
                    updated_at = NOW()
                WHERE producto_id = v_sku.producto_id;
            ELSIF v_delta < 0 THEN
                SELECT stock_comprometido
                INTO v_stock_comprometido
                FROM public.inventario_almacen
                WHERE producto_id = v_sku.producto_id;

                IF FOUND THEN
                    v_release := LEAST(COALESCE(v_stock_comprometido, 0), ABS(v_delta));
                    IF v_release > 0 THEN
                        UPDATE public.inventario_almacen
                        SET stock_comprometido = COALESCE(stock_comprometido, 0) - v_release,
                            stock_disponible = stock_disponible + v_release,
                            updated_at = NOW()
                        WHERE producto_id = v_sku.producto_id;
                    END IF;
                END IF;
            END IF;
        END LOOP;

        v_stock_reservado_final := TRUE;

        -- Fase C: Reemplazar detalle y recalcular totales con los nuevos precios y cantidades
        DELETE FROM public.detalle_distribucion WHERE orden_id = v_orden.id;

        FOR v_item IN SELECT * FROM jsonb_array_elements(p_detalle) LOOP
            v_producto_id := (v_item->>'producto_id')::UUID;
            v_cantidad := COALESCE((v_item->>'cantidad_solicitada')::INT, (v_item->>'cantidad')::INT, 0);

            SELECT COALESCE(precio_lista1, 0.00), COALESCE(peso_unitario_kg, 0.00), contenedor_id
            INTO v_val_usd_prod, v_peso_unitario, v_contenedor_id_prev
            FROM public.productos
            WHERE id = v_producto_id;

            IF COALESCE(v_orden.es_cortesia, FALSE) = TRUE THEN
                v_val_usd := 0.00;
            ELSE
                v_val_usd := COALESCE(
                    NULLIF(v_item->>'valor_unitario_usd', '')::NUMERIC,
                    NULLIF(v_item->>'precio_unitario', '')::NUMERIC,
                    v_val_usd_prod
                );
                IF v_val_usd <= 0 THEN
                    v_val_usd := v_val_usd_prod;
                END IF;
            END IF;

            v_precio_lista_usd := v_val_usd_prod;
            IF v_precio_lista_usd > 0 AND v_val_usd < v_precio_lista_usd THEN
                v_monto_descuento_usd := ROUND(v_precio_lista_usd - v_val_usd, 4);
                v_pct_descuento := ROUND(((v_precio_lista_usd - v_val_usd) / v_precio_lista_usd) * 100.00, 2);
            ELSE
                v_monto_descuento_usd := 0.00;
                v_pct_descuento := 0.00;
            END IF;

            v_subtotal_usd := ROUND(v_cantidad * v_val_usd, 2);
            v_val_bs := ROUND(v_val_usd * v_tasa_cambio, 2);
            v_subtotal_bs := ROUND(v_subtotal_usd * v_tasa_cambio, 2);

            v_total_usd := v_total_usd + v_subtotal_usd;
            v_peso_total := v_peso_total + (v_peso_unitario * v_cantidad);

            v_contenedores_retirados_prev := COALESCE(
                (v_mapa_retirados->(v_producto_id::text)->>'contenedores_retirados')::INT,
                0
            );
            IF (v_mapa_retirados->(v_producto_id::text)->>'contenedor_id') IS NOT NULL THEN
                v_contenedor_id_prev := (v_mapa_retirados->(v_producto_id::text)->>'contenedor_id')::UUID;
            END IF;

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
                precio_lista_usd,
                porcentaje_descuento,
                monto_descuento_usd,
                contenedores_retirados,
                contenedor_id,
                secuencia_entrega,
                estado_entrega
            ) VALUES (
                gen_random_uuid(),
                v_orden.id,
                v_producto_id,
                v_cantidad,
                0,
                v_val_bs,
                v_subtotal_bs,
                v_val_usd,
                v_subtotal_usd,
                v_precio_lista_usd,
                v_pct_descuento,
                v_monto_descuento_usd,
                v_contenedores_retirados_prev,
                v_contenedor_id_prev,
                v_secuencia,
                'pendiente'
            );

            v_secuencia := v_secuencia + 1;
        END LOOP;
    ELSE
        v_total_usd := COALESCE(v_orden.total_recaudar_usd, 0.00);
        v_peso_total := COALESCE(v_orden.peso_total_calculado, 0.00);
    END IF;

    v_total_bs := ROUND(v_total_usd * v_tasa_cambio, 2);

    -- 8. Actualizar cabecera de la orden con los nuevos totales recalculados
    UPDATE public.ordenes_distribucion
    SET cliente_id = v_cliente_id,
        camion_id = v_camion_id,
        fecha_despacho = v_fecha_despacho,
        factura_origen_numero = v_factura_origen,
        tasa_cambio = v_tasa_cambio,
        peso_total_calculado = v_peso_total,
        total_recaudar_bs = v_total_bs,
        total_recaudar_usd = v_total_usd,
        stock_reservado = v_stock_reservado_final,
        observaciones = COALESCE(observaciones, '') ||
                        ' [EDITADA el ' || TO_CHAR(NOW(), 'YYYY-MM-DD HH24:MI:SS') || ']'
    WHERE id = v_orden.id;

    -- 9. Si la orden pertenece a un radar, sincronizar cantidad solicitada del radar
    IF v_orden.radar_id IS NOT NULL THEN
        UPDATE public.radars r
        SET total_cantidad_solicitada = COALESCE((
            SELECT SUM(d.cantidad_solicitada)
            FROM public.ordenes_distribucion o
            JOIN public.detalle_distribucion d ON d.orden_id = o.id
            WHERE o.radar_id = v_orden.radar_id
              AND o.estado <> 'anulada'
        ), 0)
        WHERE r.id = v_orden.radar_id;
    END IF;

    -- 10. Registrar auditoría en public.logs_auditoria
    SELECT COALESCE(jsonb_agg(to_jsonb(d)), '[]'::jsonb)
    INTO v_detalles_nuevos
    FROM public.detalle_distribucion d
    WHERE d.orden_id = v_orden.id;

    v_valores_nuevos := jsonb_build_object(
        'correlativo', p_correlativo,
        'estado', v_orden.estado,
        'cliente_id', v_cliente_id,
        'camion_id', v_camion_id,
        'fecha_despacho', v_fecha_despacho,
        'factura_origen_numero', v_factura_origen,
        'tasa_cambio', v_tasa_cambio,
        'total_recaudar_usd', v_total_usd,
        'total_recaudar_bs', v_total_bs,
        'peso_total_calculado', v_peso_total,
        'stock_reservado', v_stock_reservado_final,
        'detalles', v_detalles_nuevos,
        'ejecutado_por', v_user_id,
        'rol_ejecutor', v_rol
    );

    INSERT INTO public.logs_auditoria (
        usuario_id,
        tabla_afectada,
        accion,
        registro_id,
        valores_anteriores,
        valores_nuevos,
        fecha_registro
    ) VALUES (
        v_user_id,
        'ordenes_distribucion',
        'EDITAR_ORDEN',
        v_orden.id,
        v_valores_anteriores,
        v_valores_nuevos,
        NOW()
    );

    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'correlativo', p_correlativo,
            'orden_id', v_orden.id,
            'tasa_cambio', v_tasa_cambio,
            'total_recaudar_bs', v_total_bs,
            'total_recaudar_usd', v_total_usd,
            'stock_reservado', v_stock_reservado_final
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

GRANT EXECUTE ON FUNCTION public.actualiza_orden_distribucion_segun_correlativo(INT, JSONB, JSONB) TO authenticated, service_role;


-- ------------------------------------------------------------------------------
-- 3. anular_orden_distribucion (libera stock_comprometido si estaba reservado)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.anular_orden_distribucion(
    p_orden_id UUID,
    p_motivo TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_orden RECORD;
    v_det RECORD;
    v_mov_cont RECORD;
    v_saldo_act INT;
    v_nuevo_saldo INT;
    v_stock_comprometido INT;
    v_release INT;
    v_rendicion_activa RECORD;
    v_radar_pendiente BOOLEAN := FALSE;
    v_tot_solicitada NUMERIC(10,0);
    v_tot_despachada NUMERIC(10,0);
    v_tot_retirados NUMERIC(10,0);
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', NULL,
            'error', jsonb_build_object('code', 'NO_AUTENTICADO', 'message', 'Debes iniciar sesión para anular una orden.')
        );
    END IF;

    IF p_orden_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', NULL,
            'error', jsonb_build_object('code', 'PARAMETRO_INVALIDO', 'message', 'El ID de la orden es requerido.')
        );
    END IF;

    SELECT * INTO v_orden
    FROM public.ordenes_distribucion
    WHERE id = p_orden_id
    FOR UPDATE;

    IF v_orden.id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', NULL,
            'error', jsonb_build_object('code', 'ORDEN_NO_ENCONTRADA', 'message', 'La orden de distribución no existe.')
        );
    END IF;

    IF v_orden.estado = 'anulada' THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', NULL,
            'error', jsonb_build_object('code', 'ORDEN_YA_ANULADA', 'message', 'La orden ya se encuentra anulada.')
        );
    END IF;

    -- REGLA CRÍTICA: Bloquear si tiene rendición de cuentas activa
    SELECT dro.id, rc.id AS rendicion_id, rc.estado AS estado_rendicion
    INTO v_rendicion_activa
    FROM public.detalle_rendicion_ordenes dro
    JOIN public.rendiciones_cuentas rc ON dro.rendicion_id = rc.id
    WHERE dro.orden_distribucion_id = p_orden_id
      AND rc.estado <> 'reversada'
    LIMIT 1;

    IF v_rendicion_activa.id IS NOT NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'ORDEN_CON_RENDICION',
                'message', 'No se puede anular la orden porque tiene una rendición de cuentas asociada activa (ID: ' || COALESCE(SUBSTRING(v_rendicion_activa.rendicion_id::text, 1, 8), '') || ', Estado: ' || v_rendicion_activa.estado_rendicion || '). Debe reversar la rendición antes de anular la orden.'
            )
        );
    END IF;

    -- Liberar reserva inmediata si la orden aún no había sido despachada/cargada
    IF v_orden.estado IN ('borrador', 'aprobada') AND COALESCE(v_orden.stock_reservado, FALSE) = TRUE THEN
        FOR v_det IN
            SELECT producto_id, SUM(COALESCE(cantidad_solicitada, 0))::INT AS cantidad
            FROM public.detalle_distribucion
            WHERE orden_id = p_orden_id
            GROUP BY producto_id
            ORDER BY producto_id
        LOOP
            IF v_det.cantidad > 0 THEN
                SELECT stock_comprometido
                INTO v_stock_comprometido
                FROM public.inventario_almacen
                WHERE producto_id = v_det.producto_id
                FOR UPDATE;

                IF FOUND THEN
                    v_release := LEAST(COALESCE(v_stock_comprometido, 0), v_det.cantidad);
                    IF v_release > 0 THEN
                        UPDATE public.inventario_almacen
                        SET stock_disponible = stock_disponible + v_release,
                            stock_comprometido = COALESCE(stock_comprometido, 0) - v_release,
                            updated_at = NOW()
                        WHERE producto_id = v_det.producto_id;
                    END IF;
                END IF;
            END IF;
        END LOOP;
    END IF;

    -- Reversión de inventario según modalidad y solo si la entrega sigue asentada
    IF COALESCE(v_orden.es_autoventa, false) = true AND v_orden.camion_id IS NOT NULL THEN
        IF v_orden.estado IN ('por_liquidar', 'despachada') THEN
            FOR v_det IN
                SELECT producto_id, COALESCE(cantidad_despachada, cantidad_solicitada, 0) AS cantidad
                FROM public.detalle_distribucion
                WHERE orden_id = p_orden_id
            LOOP
                UPDATE public.inventario_movil
                SET cantidad_entregada = GREATEST(0, COALESCE(cantidad_entregada, 0) - v_det.cantidad),
                    updated_at = NOW()
                WHERE camion_id = v_orden.camion_id AND producto_id = v_det.producto_id;
            END LOOP;
        END IF;

    ELSIF v_orden.origen_venta = 'ALMACEN' OR v_orden.camion_id IS NULL THEN
        IF v_orden.estado IN ('por_liquidar', 'despachada') THEN
            FOR v_det IN
                SELECT producto_id, COALESCE(cantidad_despachada, cantidad_solicitada, 0) AS cantidad
                FROM public.detalle_distribucion
                WHERE orden_id = p_orden_id
            LOOP
                UPDATE public.inventario_almacen
                SET stock_disponible = stock_disponible + v_det.cantidad,
                    updated_at = NOW()
                WHERE producto_id = v_det.producto_id;
            END LOOP;
        END IF;

    ELSE
        IF v_orden.camion_id IS NOT NULL AND v_orden.estado IN ('en_ruta', 'despachada', 'por_liquidar') THEN
            FOR v_det IN
                SELECT producto_id,
                       COALESCE(cantidad_solicitada, 0) AS cant_sol,
                       COALESCE(cantidad_despachada, cantidad_solicitada, 0) AS cant_desp
                FROM public.detalle_distribucion
                WHERE orden_id = p_orden_id
            LOOP
                UPDATE public.inventario_movil
                SET cantidad_entregada = GREATEST(0, COALESCE(cantidad_entregada, 0) - v_det.cant_desp),
                    cantidad_devolucion = GREATEST(0, COALESCE(cantidad_devolucion, 0) - GREATEST(0, v_det.cant_sol - v_det.cant_desp)),
                    updated_at = NOW()
                WHERE camion_id = v_orden.camion_id AND producto_id = v_det.producto_id;
            END LOOP;
        END IF;
    END IF;

    -- Reversión de envases (permitiendo saldos a favor < 0 y eliminando movimientos de la orden)
    IF v_orden.cliente_id IS NOT NULL THEN
        FOR v_mov_cont IN
            SELECT contenedor_id,
                   SUM(COALESCE(cantidad_entregada, 0))::INT AS total_entregados,
                   SUM(COALESCE(cantidad_retirada, 0))::INT AS total_retirados
            FROM public.movimientos_contenedores
            WHERE orden_id = p_orden_id
            GROUP BY contenedor_id
        LOOP
            SELECT saldo_pendiente INTO v_saldo_act
            FROM public.saldo_contenedores_clientes
            WHERE cliente_id = v_orden.cliente_id AND contenedor_id = v_mov_cont.contenedor_id
            FOR UPDATE;

            v_saldo_act := COALESCE(v_saldo_act, 0);
            v_nuevo_saldo := v_saldo_act - v_mov_cont.total_entregados + v_mov_cont.total_retirados;

            UPDATE public.saldo_contenedores_clientes
            SET saldo_pendiente = v_nuevo_saldo,
                updated_at = NOW()
            WHERE cliente_id = v_orden.cliente_id AND contenedor_id = v_mov_cont.contenedor_id;
        END LOOP;

        DELETE FROM public.movimientos_contenedores WHERE orden_id = p_orden_id;
    END IF;

    -- Verificar si pertenece a un radar pendiente para desvincularla y recalcular
    IF v_orden.radar_id IS NOT NULL THEN
        SELECT (COALESCE(status_radar, FALSE) = FALSE)
        INTO v_radar_pendiente
        FROM public.radars
        WHERE id = v_orden.radar_id;
    END IF;

    -- Actualizar estado de la orden a 'anulada' y limpiar stock_reservado
    UPDATE public.ordenes_distribucion
    SET estado = 'anulada',
        stock_reservado = FALSE,
        radar_id = CASE WHEN COALESCE(v_radar_pendiente, FALSE) = TRUE THEN NULL ELSE radar_id END,
        observaciones = COALESCE(observaciones, '') ||
                        ' [ANULADA el ' || TO_CHAR(NOW(), 'YYYY-MM-DD HH24:MI:SS') ||
                        CASE WHEN p_motivo IS NOT NULL AND TRIM(p_motivo) <> '' THEN ' - Motivo: ' || TRIM(p_motivo) ELSE '' END || ']'
    WHERE id = p_orden_id;

    -- Recalcular totales del radar si la orden tenía un radar asignado
    IF v_orden.radar_id IS NOT NULL THEN
        SELECT
            COALESCE(SUM(d.cantidad_solicitada), 0),
            COALESCE(SUM(d.cantidad_despachada), 0),
            COALESCE(SUM(d.contenedores_retirados), 0)
        INTO v_tot_solicitada, v_tot_despachada, v_tot_retirados
        FROM public.ordenes_distribucion o
        JOIN public.detalle_distribucion d ON d.orden_id = o.id
        WHERE o.radar_id = v_orden.radar_id
          AND o.estado <> 'anulada';

        UPDATE public.radars
        SET total_cantidad_solicitada = v_tot_solicitada,
            total_cantidad_despachada = v_tot_despachada,
            total_contenedores_retirados = v_tot_retirados
        WHERE id = v_orden.radar_id;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'message', 'Orden de distribución anulada exitosamente y saldos revertidos.',
        'data', jsonb_build_object(
            'orden_id', p_orden_id,
            'correlativo', v_orden.correlativo,
            'estado_anterior', v_orden.estado,
            'estado_nuevo', 'anulada'
        ),
        'error', NULL
    );
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false,
        'data', NULL,
        'error', jsonb_build_object('code', 'SQL_ERROR', 'message', SQLERRM, 'details', 'SQLSTATE: ' || SQLSTATE)
    );
END;
$$;

REVOKE ALL ON FUNCTION public.anular_orden_distribucion(UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.anular_orden_distribucion(UUID, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.anular_orden_distribucion(UUID, TEXT) TO authenticated, service_role;


-- ------------------------------------------------------------------------------
-- 4. generar_despacho_orden_almacen (respeta stock_reservado sin doble descuento)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.generar_despacho_orden_almacen(
    p_orden_id UUID,
    p_observaciones TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_usuario_id UUID := auth.uid();
    v_rol TEXT;
    v_es_gerencia BOOLEAN := FALSE;
    v_orden RECORD;
    v_det RECORD;
    v_stock_disponible INT;
    v_stock_comprometido INT;
    v_usar_comprometido INT;
    v_usar_disponible INT;
    v_lineas_count INT := 0;
    v_retirados_json JSONB := '[]'::jsonb;
    v_contenedores_resumen JSONB := '[]'::jsonb;
    v_mercancia_despachada JSONB := '[]'::jsonb;
    v_estado_final TEXT := 'por_liquidar';
    v_total_abonos NUMERIC(14,2) := 0.00;
    v_tot_solicitada NUMERIC(10,0);
    v_tot_despachada NUMERIC(10,0);
    v_tot_retirados NUMERIC(10,0);
    v_detalles_previos JSONB;
    v_detalles_nuevos JSONB;
    v_valores_anteriores JSONB;
    v_valores_nuevos JSONB;
BEGIN
    IF v_usuario_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', NULL,
            'error', jsonb_build_object('code', 'NO_AUTENTICADO', 'message', 'Debes iniciar sesión para generar el despacho.')
        );
    END IF;

    v_rol := public.lt_current_user_rol();
    v_es_gerencia := COALESCE(public.user_has_role(ARRAY['admin', 'gerente']), FALSE)
                     OR COALESCE(v_rol, '') IN ('admin', 'gerente');

    IF NOT v_es_gerencia THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', NULL,
            'error', jsonb_build_object('code', 'ACCESO_DENEGADO', 'message', 'Permiso denegado: solo la Gerencia o Administración puede generar el despacho directo desde almacén.')
        );
    END IF;

    IF p_orden_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', NULL,
            'error', jsonb_build_object('code', 'PARAMETRO_INVALIDO', 'message', 'El ID de la orden es obligatorio.')
        );
    END IF;

    SELECT * INTO v_orden
    FROM public.ordenes_distribucion
    WHERE id = p_orden_id
    FOR UPDATE;

    IF v_orden.id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', NULL,
            'error', jsonb_build_object('code', 'ORDEN_NO_ENCONTRADA', 'message', 'La orden de distribución especificada no existe.')
        );
    END IF;

    IF v_orden.estado = 'liquidada' THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', NULL,
            'error', jsonb_build_object('code', 'ORDEN_LIQUIDADA', 'message', 'La orden ya se encuentra liquidada.')
        );
    END IF;

    IF v_orden.estado <> 'aprobada' THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', NULL,
            'error', jsonb_build_object('code', 'ESTADO_INVALIDO', 'message', 'La orden debe estar en estado aprobada para generar su despacho desde almacén. Estado actual: ' || COALESCE(v_orden.estado, 'desconocido'))
        );
    END IF;

    SELECT COUNT(*) INTO v_lineas_count
    FROM public.detalle_distribucion
    WHERE orden_id = p_orden_id;

    IF v_lineas_count = 0 THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', NULL,
            'error', jsonb_build_object('code', 'ORDEN_SIN_PRODUCTOS', 'message', 'La orden no tiene líneas de productos para despachar.')
        );
    END IF;

    SELECT COALESCE(jsonb_agg(to_jsonb(d)), '[]'::jsonb)
    INTO v_detalles_previos
    FROM public.detalle_distribucion d
    WHERE d.orden_id = p_orden_id;

    v_valores_anteriores := jsonb_build_object(
        'correlativo', v_orden.correlativo,
        'estado_orden', v_orden.estado,
        'radar_id', v_orden.radar_id,
        'stock_reservado', COALESCE(v_orden.stock_reservado, FALSE),
        'total_recaudar_usd', v_orden.total_recaudar_usd,
        'total_recaudar_bs', v_orden.total_recaudar_bs,
        'detalles', v_detalles_previos
    );

    -- Validar stock en inventario_almacen respetando stock_reservado en orden determinístico
    FOR v_det IN
        SELECT d.id,
               d.producto_id,
               d.cantidad_solicitada,
               p.nombre AS producto_nombre,
               p.contenedor_id AS prod_contenedor_id
        FROM public.detalle_distribucion d
        JOIN public.productos p ON p.id = d.producto_id
        WHERE d.orden_id = p_orden_id
        ORDER BY d.producto_id
    LOOP
        SELECT stock_disponible, stock_comprometido
        INTO v_stock_disponible, v_stock_comprometido
        FROM public.inventario_almacen
        WHERE producto_id = v_det.producto_id
        FOR UPDATE;

        IF COALESCE(v_orden.stock_reservado, FALSE) = TRUE THEN
            v_usar_comprometido := LEAST(COALESCE(v_stock_comprometido, 0), v_det.cantidad_solicitada);
        ELSE
            v_usar_comprometido := 0;
        END IF;
        v_usar_disponible := v_det.cantidad_solicitada - v_usar_comprometido;

        IF NOT FOUND OR COALESCE(v_stock_disponible, 0) < v_usar_disponible THEN
            RETURN jsonb_build_object(
                'success', false,
                'data', NULL,
                'error', jsonb_build_object(
                    'code', 'STOCK_INSUFICIENTE_ALMACEN',
                    'message', 'Stock insuficiente en almacén para el producto ' || COALESCE(v_det.producto_nombre, '') || ' (Disponible: ' || (COALESCE(v_stock_disponible, 0) + v_usar_comprometido) || ', A despachar: ' || v_det.cantidad_solicitada || ').'
                )
            );
        END IF;
    END LOOP;

    -- Descontar de inventario_almacen (consumiendo primero lo reservado por esta orden)
    FOR v_det IN
        SELECT d.id,
               d.producto_id,
               d.cantidad_solicitada,
               p.nombre AS producto_nombre,
               p.contenedor_id AS prod_contenedor_id
        FROM public.detalle_distribucion d
        JOIN public.productos p ON p.id = d.producto_id
        WHERE d.orden_id = p_orden_id
        ORDER BY d.producto_id
    LOOP
        SELECT stock_disponible, stock_comprometido
        INTO v_stock_disponible, v_stock_comprometido
        FROM public.inventario_almacen
        WHERE producto_id = v_det.producto_id;

        IF COALESCE(v_orden.stock_reservado, FALSE) = TRUE THEN
            v_usar_comprometido := LEAST(COALESCE(v_stock_comprometido, 0), v_det.cantidad_solicitada);
        ELSE
            v_usar_comprometido := 0;
        END IF;
        v_usar_disponible := v_det.cantidad_solicitada - v_usar_comprometido;

        UPDATE public.inventario_almacen
        SET stock_disponible = stock_disponible - v_usar_disponible,
            stock_comprometido = COALESCE(stock_comprometido, 0) - v_usar_comprometido,
            updated_at = NOW()
        WHERE producto_id = v_det.producto_id;

        UPDATE public.detalle_distribucion
        SET cantidad_despachada = v_det.cantidad_solicitada,
            estado_entrega = 'entregado',
            motivo_rechazo = NULL,
            contenedor_id = COALESCE(contenedor_id, v_det.prod_contenedor_id)
        WHERE id = v_det.id;

        v_mercancia_despachada := v_mercancia_despachada || jsonb_build_array(
            jsonb_build_object(
                'producto_id', v_det.producto_id,
                'producto_nombre', v_det.producto_nombre,
                'cantidad_despachada_almacen', v_det.cantidad_solicitada
            )
        );
    END LOOP;

    -- Asentar movimientos y saldos de contenedores
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'contenedor_id', sub.contenedor_id,
                'cantidad_retirada', sub.total_retirados
            )
        ),
        '[]'::jsonb
    )
    INTO v_retirados_json
    FROM (
        SELECT COALESCE(d.contenedor_id, p.contenedor_id) AS contenedor_id,
               SUM(COALESCE(d.contenedores_retirados, 0))::INT AS total_retirados
        FROM public.detalle_distribucion d
        JOIN public.productos p ON p.id = d.producto_id
        WHERE d.orden_id = p_orden_id
          AND COALESCE(d.contenedor_id, p.contenedor_id) IS NOT NULL
          AND COALESCE(d.contenedores_retirados, 0) > 0
        GROUP BY COALESCE(d.contenedor_id, p.contenedor_id)
    ) sub;

    DELETE FROM public.movimientos_contenedores WHERE orden_id = p_orden_id;
    v_contenedores_resumen := public.lt_asentar_contenedores_orden(p_orden_id, v_retirados_json);

    -- Pasar la orden a 'por_liquidar', limpiar stock_reservado y reevaluar con abonos previos
    UPDATE public.ordenes_distribucion
    SET estado = 'por_liquidar',
        stock_reservado = FALSE,
        fecha_despacho = COALESCE(fecha_despacho, NOW()),
        observaciones = COALESCE(observaciones, '') ||
                        ' [DESPACHO GENERADO DESDE ALMACÉN el ' || TO_CHAR(NOW(), 'YYYY-MM-DD HH24:MI:SS') ||
                        CASE WHEN p_observaciones IS NOT NULL AND TRIM(p_observaciones) <> '' THEN ' - Nota: ' || TRIM(p_observaciones) ELSE '' END || ']'
    WHERE id = p_orden_id;

    PERFORM public.liquidar_orden_distribucion(p_orden_id);

    SELECT estado INTO v_estado_final
    FROM public.ordenes_distribucion
    WHERE id = p_orden_id;

    SELECT COALESCE(SUM(dro.recaudado), 0.00)
    INTO v_total_abonos
    FROM public.detalle_rendicion_ordenes dro
    JOIN public.rendiciones_cuentas rc ON dro.rendicion_id = rc.id
    WHERE dro.orden_distribucion_id = p_orden_id
      AND rc.estado = 'aprobada';

    IF v_orden.radar_id IS NOT NULL THEN
        SELECT
            COALESCE(SUM(d.cantidad_solicitada), 0),
            COALESCE(SUM(CASE WHEN COALESCE(d.estado_entrega, 'pendiente') <> 'pendiente' THEN COALESCE(d.cantidad_despachada, 0) ELSE 0 END), 0),
            COALESCE(SUM(d.contenedores_retirados), 0)
        INTO v_tot_solicitada, v_tot_despachada, v_tot_retirados
        FROM public.ordenes_distribucion o
        JOIN public.detalle_distribucion d ON d.orden_id = o.id
        WHERE o.radar_id = v_orden.radar_id
          AND o.estado <> 'anulada';

        UPDATE public.radars
        SET total_cantidad_solicitada = v_tot_solicitada,
            total_cantidad_despachada = v_tot_despachada,
            total_contenedores_retirados = v_tot_retirados
        WHERE id = v_orden.radar_id;
    END IF;

    SELECT COALESCE(jsonb_agg(to_jsonb(d)), '[]'::jsonb)
    INTO v_detalles_nuevos
    FROM public.detalle_distribucion d
    WHERE d.orden_id = p_orden_id;

    v_valores_nuevos := jsonb_build_object(
        'correlativo', v_orden.correlativo,
        'estado_orden', v_estado_final,
        'radar_id', v_orden.radar_id,
        'stock_reservado', FALSE,
        'total_recaudar_usd', v_orden.total_recaudar_usd,
        'total_recaudar_bs', v_orden.total_recaudar_bs,
        'abonos_aprobados_conservados_usd', v_total_abonos,
        'mercancia_despachada_almacen', v_mercancia_despachada,
        'contenedores', v_contenedores_resumen,
        'detalles', v_detalles_nuevos,
        'observaciones', NULLIF(TRIM(COALESCE(p_observaciones, '')), ''),
        'ejecutado_por', v_usuario_id,
        'rol_ejecutor', v_rol,
        'fecha_despacho_generado', NOW()
    );

    INSERT INTO public.logs_auditoria (
        usuario_id,
        tabla_afectada,
        accion,
        registro_id,
        valores_anteriores,
        valores_nuevos,
        fecha_registro
    ) VALUES (
        v_usuario_id,
        'ordenes_distribucion',
        'GENERAR_DESPACHO_ALMACEN',
        p_orden_id,
        v_valores_anteriores,
        v_valores_nuevos,
        NOW()
    );

    RETURN jsonb_build_object(
        'success', true,
        'message', CASE
            WHEN v_estado_final = 'liquidada' THEN 'Despacho generado desde almacén exitosamente. Con los abonos previos registrados, la orden quedó liquidada.'
            ELSE 'Despacho generado desde almacén exitosamente. La mercancía salió del inventario de almacén y la orden pasó a estado por liquidar.'
        END,
        'data', jsonb_build_object(
            'orden_id', p_orden_id,
            'correlativo', v_orden.correlativo,
            'estado_anterior', 'aprobada',
            'estado_nuevo', v_estado_final,
            'total_recaudar_usd', v_orden.total_recaudar_usd,
            'total_recaudar_bs', v_orden.total_recaudar_bs,
            'abonos_conservados_usd', v_total_abonos,
            'mercancia_despachada_almacen', v_mercancia_despachada,
            'contenedores', v_contenedores_resumen
        ),
        'error', NULL
    );

EXCEPTION WHEN OTHERS THEN
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

REVOKE ALL ON FUNCTION public.generar_despacho_orden_almacen(UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.generar_despacho_orden_almacen(UUID, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.generar_despacho_orden_almacen(UUID, TEXT) TO authenticated, service_role;


-- ------------------------------------------------------------------------------
-- 5. solicita_cargar_inventario_movil_desde_almacen (sin stock fantasma)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.solicita_cargar_inventario_movil_desde_almacen(
    p_camion_id UUID,
    p_resumen_productos JSONB,
    p_radar_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_items_array JSONB;
    v_req RECORD;
    v_prod_nombre TEXT;
    v_stock_disponible INT;
    v_stock_comprometido INT;
    v_inv_found BOOLEAN;
    v_reservado_radar INT;
    v_usar_comprometido INT;
    v_usar_disponible INT;
    v_total_productos_cargados INT := 0;
    v_unidades_totales INT := 0;
    v_camion_existe BOOLEAN;
    v_ordenes_actualizadas INT := 0;
    v_radar_id UUID;
    v_stock_movil_previo INT := 0;
BEGIN
    IF p_camion_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID del camión es requerido.'
            )
        );
    END IF;

    SELECT EXISTS(SELECT 1 FROM public.camiones WHERE id = p_camion_id) INTO v_camion_existe;
    IF NOT v_camion_existe THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'CAMION_INEXISTENTE',
                'message', 'El camión especificado no existe.'
            )
        );
    END IF;

    v_radar_id := p_radar_id;

    -- Purgar filas agotadas (disponible = 0) que hayan podido quedar en inventario_movil
    DELETE FROM public.inventario_movil
    WHERE camion_id = p_camion_id
      AND GREATEST(0, COALESCE(cantidad_cargada, 0) - COALESCE(cantidad_entregada, 0)) = 0;

    -- REGLA CRÍTICA DE NEGOCIO:
    -- A un camión que ya posee inventario móvil disponible NO se le puede cargar un Radar.
    IF v_radar_id IS NOT NULL THEN
        SELECT COALESCE(SUM(GREATEST(0, COALESCE(cantidad_cargada, 0) - COALESCE(cantidad_entregada, 0))), 0)::INT
        INTO v_stock_movil_previo
        FROM public.inventario_movil
        WHERE camion_id = p_camion_id;

        IF v_stock_movil_previo > 0 THEN
            RETURN jsonb_build_object(
                'success', FALSE,
                'data', NULL,
                'error', jsonb_build_object(
                    'code', 'CAMION_CON_INVENTARIO_MOVIL',
                    'message', format(
                        'No se puede cargar un Radar en este camión porque actualmente posee inventario móvil disponible (%s unidades de AutoVentas). Primero debe descargar el camión al almacén o asignar otro camión.',
                        v_stock_movil_previo
                    )
                )
            );
        END IF;
    END IF;

    IF jsonb_typeof(p_resumen_productos) = 'array' THEN
        v_items_array := p_resumen_productos;
    ELSIF jsonb_typeof(p_resumen_productos) = 'object' AND p_resumen_productos ? 'resumen_productos' THEN
        v_items_array := p_resumen_productos->'resumen_productos';
    ELSE
        v_items_array := '[]'::jsonb;
    END IF;

    IF v_items_array IS NULL OR jsonb_array_length(v_items_array) = 0 THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'DATOS_VACIOS',
                'message', 'El resumen de productos a cargar no contiene elementos válidos.'
            )
        );
    END IF;

    -- Fase 1: Bloquear inventario_almacen FOR UPDATE en orden determinístico y validar stock estricto
    FOR v_req IN
        SELECT
            (elem->>'producto_id')::UUID AS producto_id,
            SUM(COALESCE((elem->>'cantidad_solicitada')::INT, 0))::INT AS cantidad_solicitada
        FROM jsonb_array_elements(v_items_array) AS elem
        WHERE (elem->>'producto_id') IS NOT NULL
          AND COALESCE((elem->>'cantidad_solicitada')::INT, 0) > 0
        GROUP BY (elem->>'producto_id')::UUID
        ORDER BY (elem->>'producto_id')::UUID
    LOOP
        SELECT nombre INTO v_prod_nombre
        FROM public.productos
        WHERE id = v_req.producto_id;

        SELECT stock_disponible, stock_comprometido
        INTO v_stock_disponible, v_stock_comprometido
        FROM public.inventario_almacen
        WHERE producto_id = v_req.producto_id
        FOR UPDATE;
        v_inv_found := FOUND;

        -- Solo una carga de Radar puede consumir stock_comprometido (y solo hasta lo reservado por sus órdenes)
        IF v_radar_id IS NOT NULL THEN
            SELECT COALESCE(SUM(d.cantidad_solicitada), 0)::INT
            INTO v_reservado_radar
            FROM public.ordenes_distribucion o
            JOIN public.detalle_distribucion d ON d.orden_id = o.id
            WHERE o.radar_id = v_radar_id
              AND o.estado = 'aprobada'
              AND COALESCE(o.stock_reservado, FALSE) = TRUE
              AND d.producto_id = v_req.producto_id;
        ELSE
            v_reservado_radar := 0;
        END IF;

        v_usar_comprometido := LEAST(COALESCE(v_stock_comprometido, 0), v_reservado_radar, v_req.cantidad_solicitada);
        v_usar_disponible := v_req.cantidad_solicitada - v_usar_comprometido;

        IF NOT v_inv_found OR COALESCE(v_stock_disponible, 0) < v_usar_disponible THEN
            RETURN jsonb_build_object(
                'success', FALSE,
                'data', NULL,
                'error', jsonb_build_object(
                    'code', 'STOCK_INSUFICIENTE_ALMACEN',
                    'message', format(
                        'Stock insuficiente en almacén para cargar %s (Disponible para esta carga: %s, Solicitado: %s).',
                        COALESCE(v_prod_nombre, v_req.producto_id::text),
                        COALESCE(v_stock_disponible, 0) + v_usar_comprometido,
                        v_req.cantidad_solicitada
                    )
                )
            );
        END IF;
    END LOOP;

    -- Fase 2: Descontar exactamente de inventario_almacen y acreditar inventario_movil
    FOR v_req IN
        SELECT
            (elem->>'producto_id')::UUID AS producto_id,
            SUM(COALESCE((elem->>'cantidad_solicitada')::INT, 0))::INT AS cantidad_solicitada
        FROM jsonb_array_elements(v_items_array) AS elem
        WHERE (elem->>'producto_id') IS NOT NULL
          AND COALESCE((elem->>'cantidad_solicitada')::INT, 0) > 0
        GROUP BY (elem->>'producto_id')::UUID
        ORDER BY (elem->>'producto_id')::UUID
    LOOP
        SELECT stock_disponible, stock_comprometido
        INTO v_stock_disponible, v_stock_comprometido
        FROM public.inventario_almacen
        WHERE producto_id = v_req.producto_id;

        IF v_radar_id IS NOT NULL THEN
            SELECT COALESCE(SUM(d.cantidad_solicitada), 0)::INT
            INTO v_reservado_radar
            FROM public.ordenes_distribucion o
            JOIN public.detalle_distribucion d ON d.orden_id = o.id
            WHERE o.radar_id = v_radar_id
              AND o.estado = 'aprobada'
              AND COALESCE(o.stock_reservado, FALSE) = TRUE
              AND d.producto_id = v_req.producto_id;
        ELSE
            v_reservado_radar := 0;
        END IF;

        v_usar_comprometido := LEAST(COALESCE(v_stock_comprometido, 0), v_reservado_radar, v_req.cantidad_solicitada);
        v_usar_disponible := v_req.cantidad_solicitada - v_usar_comprometido;

        UPDATE public.inventario_almacen
        SET stock_comprometido = COALESCE(stock_comprometido, 0) - v_usar_comprometido,
            stock_disponible = stock_disponible - v_usar_disponible,
            updated_at = NOW()
        WHERE producto_id = v_req.producto_id;

        INSERT INTO public.inventario_movil (
            camion_id,
            producto_id,
            cantidad_cargada,
            cantidad_entregada,
            cantidad_devolucion,
            updated_at
        ) VALUES (
            p_camion_id,
            v_req.producto_id,
            v_req.cantidad_solicitada,
            0,
            0,
            NOW()
        )
        ON CONFLICT (camion_id, producto_id)
        DO UPDATE SET
            cantidad_cargada = public.inventario_movil.cantidad_cargada + v_req.cantidad_solicitada,
            updated_at = NOW();

        v_total_productos_cargados := v_total_productos_cargados + 1;
        v_unidades_totales := v_unidades_totales + v_req.cantidad_solicitada;
    END LOOP;

    UPDATE public.camiones
    SET estado = 'en_ruta'
    WHERE id = p_camion_id;

    -- Solo si es una carga de Radar se actualizan las órdenes del radar y se libera la bandera stock_reservado
    IF v_radar_id IS NOT NULL THEN
        UPDATE public.ordenes_distribucion
        SET estado = 'en_transito',
            stock_reservado = FALSE
        WHERE radar_id = v_radar_id AND estado = 'aprobada';

        GET DIAGNOSTICS v_ordenes_actualizadas = ROW_COUNT;

        UPDATE public.detalle_distribucion dd
        SET cantidad_despachada = dd.cantidad_solicitada
        FROM public.ordenes_distribucion od
        WHERE dd.orden_id = od.id
          AND od.radar_id = v_radar_id
          AND od.estado = 'en_transito'
          AND COALESCE(dd.estado_entrega, 'pendiente') = 'pendiente';

        UPDATE public.radars
        SET carga_inventario_movil = TRUE
        WHERE id = v_radar_id;
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Carga a inventario móvil procesada exitosamente desde el almacén.',
        'data', jsonb_build_object(
            'camion_id', p_camion_id,
            'radar_id', v_radar_id,
            'carga_inventario_movil', (v_radar_id IS NOT NULL),
            'total_productos_cargados', v_total_productos_cargados,
            'unidades_totales', v_unidades_totales,
            'ordenes_despachadas', v_ordenes_actualizadas
        ),
        'error', NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'SQL_ERROR',
                'message', SQLERRM,
                'details', 'SQLSTATE: ' || SQLSTATE
            )
        );
END;
$$;

ALTER FUNCTION public.solicita_cargar_inventario_movil_desde_almacen(UUID, JSONB, UUID) OWNER TO postgres;
GRANT EXECUTE ON FUNCTION public.solicita_cargar_inventario_movil_desde_almacen(UUID, JSONB, UUID) TO authenticated, service_role;
