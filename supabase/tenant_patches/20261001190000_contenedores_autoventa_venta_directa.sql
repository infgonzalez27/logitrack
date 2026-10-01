-- ==============================================================================
-- Patch: Envases automáticos en AutoVenta y Venta directa (Task_20261001c)
-- Aplica después de 20260930180000_venta_directa_almacen_fix.sql. Idempotente.
--
--   1. movimientos_contenedores guarda saldo_anterior y saldo_actual del cliente
--      en cada movimiento (reimpresiones exactas del ticket).
--   2. lt_asentar_contenedores_orden(orden, retirados): calcula los envases
--      entregados desde el detalle de la orden con la misma fórmula del radar
--      (CEIL(cantidad / unidades_por_contenedor)), registra ENTREGA y RETIRO en
--      movimientos_contenedores, actualiza saldo_contenedores_clientes y
--      devuelve el resumen por tipo de envase.
--   3. registrar_venta_en_ruta_autoventa: misma firma. Los entregados se
--      calculan en la BD (se ignora cantidad_entregada de p_contenedores_json);
--      solo se toma cantidad_retirada. Devuelve data.contenedores. Exige sesión
--      y rol admin, gerente, vendedor o despachador.
--   4. crear_venta_directa_almacen: nuevo parámetro p_contenedores_json
--      ([{contenedor_id, cantidad_retirada}]). Devuelve data.contenedores.
-- ==============================================================================

ALTER TABLE public.movimientos_contenedores
  ADD COLUMN IF NOT EXISTS saldo_anterior INTEGER,
  ADD COLUMN IF NOT EXISTS saldo_actual INTEGER;

-- ------------------------------------------------------------------------------
-- 2. Asiento de envases de una orden
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.lt_asentar_contenedores_orden(
    p_orden_id UUID,
    p_retirados JSONB DEFAULT '[]'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_cliente_id UUID;
    v_retirados JSONB := COALESCE(p_retirados, '[]'::jsonb);
    v_rec RECORD;
    v_saldo_ant INT;
    v_saldo_act INT;
    v_resumen JSONB := '[]'::jsonb;
BEGIN
    SELECT cliente_id INTO v_cliente_id
    FROM public.ordenes_distribucion
    WHERE id = p_orden_id;

    IF v_cliente_id IS NULL THEN
        RAISE EXCEPTION 'La orden no existe o no tiene cliente.'
            USING HINT = 'ORDEN_INEXISTENTE';
    END IF;

    IF jsonb_typeof(v_retirados) <> 'array' THEN
        RAISE EXCEPTION 'Los envases retirados deben enviarse como lista.'
            USING HINT = 'PARAMETRO_INVALIDO';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM jsonb_array_elements(v_retirados) e
        WHERE COALESCE(NULLIF(e->>'cantidad_retirada', '')::numeric, 0) < 0
           OR COALESCE(NULLIF(e->>'cantidad_retirada', '')::numeric, 0)
              <> trunc(COALESCE(NULLIF(e->>'cantidad_retirada', '')::numeric, 0))
           OR (COALESCE(NULLIF(e->>'cantidad_retirada', '')::numeric, 0) > 0
               AND NULLIF(e->>'contenedor_id', '') IS NULL)
    ) THEN
        RAISE EXCEPTION 'Los envases retirados deben ser enteros mayores o iguales a 0, con su tipo de envase.'
            USING HINT = 'CONTENEDORES_INVALIDOS';
    END IF;

    FOR v_rec IN
        WITH ent AS (
            SELECT COALESCE(d.contenedor_id, p.contenedor_id) AS contenedor_id,
                   SUM(CEIL(
                       COALESCE(d.cantidad_despachada, 0)::numeric
                       / GREATEST(COALESCE(p.unidades_por_contenedor, 1)::numeric, 1)
                   ))::INT AS entregados
            FROM public.detalle_distribucion d
            JOIN public.productos p ON p.id = d.producto_id
            WHERE d.orden_id = p_orden_id
              AND COALESCE(d.contenedor_id, p.contenedor_id) IS NOT NULL
              AND COALESCE(d.cantidad_despachada, 0) > 0
            GROUP BY 1
        ),
        ret AS (
            SELECT (e->>'contenedor_id')::UUID AS contenedor_id,
                   SUM((e->>'cantidad_retirada')::numeric)::INT AS retirados
            FROM jsonb_array_elements(v_retirados) e
            WHERE COALESCE(NULLIF(e->>'cantidad_retirada', '')::numeric, 0) > 0
            GROUP BY 1
        )
        SELECT COALESCE(ent.contenedor_id, ret.contenedor_id) AS contenedor_id,
               COALESCE(ent.entregados, 0) AS entregados,
               COALESCE(ret.retirados, 0) AS retirados,
               t.codigo,
               t.nombre
        FROM ent
        FULL OUTER JOIN ret ON ret.contenedor_id = ent.contenedor_id
        LEFT JOIN public.tipos_contenedores t
               ON t.id = COALESCE(ent.contenedor_id, ret.contenedor_id)
        ORDER BY t.nombre
    LOOP
        IF v_rec.nombre IS NULL THEN
            RAISE EXCEPTION 'Uno de los tipos de envase indicados no existe.'
                USING HINT = 'CONTENEDOR_INEXISTENTE';
        END IF;

        CONTINUE WHEN v_rec.entregados = 0 AND v_rec.retirados = 0;

        v_saldo_ant := NULL;
        SELECT saldo_pendiente INTO v_saldo_ant
        FROM public.saldo_contenedores_clientes
        WHERE cliente_id = v_cliente_id AND contenedor_id = v_rec.contenedor_id
        FOR UPDATE;
        v_saldo_ant := COALESCE(v_saldo_ant, 0);

        -- saldo_pendiente tiene CHECK >= 0: un retiro mayor al saldo deja el saldo en 0.
        v_saldo_act := GREATEST(0, v_saldo_ant + v_rec.entregados - v_rec.retirados);

        INSERT INTO public.movimientos_contenedores (
            cliente_id, orden_id, contenedor_id, cantidad_entregada,
            cantidad_retirada, creado_por, saldo_anterior, saldo_actual
        ) VALUES (
            v_cliente_id, p_orden_id, v_rec.contenedor_id, v_rec.entregados,
            v_rec.retirados, auth.uid(), v_saldo_ant, v_saldo_act
        );

        INSERT INTO public.saldo_contenedores_clientes (
            cliente_id, contenedor_id, saldo_pendiente, updated_at
        ) VALUES (
            v_cliente_id, v_rec.contenedor_id, v_saldo_act, now()
        )
        ON CONFLICT (cliente_id, contenedor_id)
        DO UPDATE SET saldo_pendiente = EXCLUDED.saldo_pendiente,
                      updated_at = now();

        v_resumen := v_resumen || jsonb_build_array(jsonb_build_object(
            'contenedor_id', v_rec.contenedor_id,
            'codigo', v_rec.codigo,
            'nombre', v_rec.nombre,
            'saldo_anterior', v_saldo_ant,
            'entregados', v_rec.entregados,
            'retirados', v_rec.retirados,
            'saldo_actual', v_saldo_act
        ));
    END LOOP;

    RETURN v_resumen;
END;
$$;

REVOKE ALL ON FUNCTION public.lt_asentar_contenedores_orden(UUID, JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.lt_asentar_contenedores_orden(UUID, JSONB) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.lt_asentar_contenedores_orden(UUID, JSONB) TO service_role;

-- ------------------------------------------------------------------------------
-- 3. AutoVenta (venta en ruta)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.registrar_venta_en_ruta_autoventa(
    p_vendedor_id UUID,
    p_cliente_id UUID,
    p_camion_id UUID,
    p_productos_json JSONB DEFAULT '[]'::jsonb,
    p_contenedores_json JSONB DEFAULT '[]'::jsonb,
    p_observaciones TEXT DEFAULT NULL,
    p_tasa_cambio NUMERIC DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_rol TEXT;
    v_orden_id UUID;
    v_correlativo INT;
    v_factura_origen VARCHAR(30);
    v_tasa_cambio NUMERIC(14,4);

    v_vendedor_id UUID;
    v_despachador_id UUID;
    v_id_ruta UUID;
    v_camion_estado TEXT;

    v_peso_total NUMERIC(10,2) := 0.00;
    v_total_recaudar_usd NUMERIC(14,2) := 0.00;
    v_total_recaudar_bs NUMERIC(14,2) := 0.00;

    v_item JSONB;
    v_secuencia INT := 1;
    v_producto_id UUID;
    v_cantidad INT;
    v_stock_disponible_movil INT := 0;
    v_val_usd NUMERIC(14,2);
    v_val_usd_prod NUMERIC(14,2);
    v_subtotal_usd NUMERIC(14,2);
    v_peso_unitario NUMERIC(10,2);

    v_contenedores JSONB := '[]'::jsonb;
    v_err_msg TEXT;
    v_err_code TEXT;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'Debes iniciar sesión para registrar AutoVentas.');
    END IF;

    v_rol := public.lt_current_user_rol();
    IF v_rol IS NULL OR v_rol NOT IN ('admin', 'gerente', 'vendedor', 'despachador') THEN
        RETURN jsonb_build_object('success', false, 'message', 'No tienes permiso para registrar AutoVentas.');
    END IF;

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
        RETURN jsonb_build_object('success', false, 'message', 'Debe incluir al menos un producto en la orden de AutoVenta.');
    END IF;

    SELECT estado INTO v_camion_estado
    FROM public.camiones
    WHERE id = p_camion_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'message', 'El camión especificado no existe.');
    END IF;

    IF v_camion_estado NOT IN ('en_ruta', 'asignado') THEN
        RETURN jsonb_build_object('success', false, 'message', 'El camión debe estar en ruta para registrar AutoVentas. Estado actual: ' || v_camion_estado);
    END IF;

    SELECT c.vendedor_id, c.despachador_id, c.id_ruta
    INTO v_vendedor_id, v_despachador_id, v_id_ruta
    FROM public.clientes c
    WHERE c.id = p_cliente_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'message', 'El cliente especificado no existe.');
    END IF;

    v_vendedor_id := COALESCE(p_vendedor_id, v_vendedor_id);

    IF p_tasa_cambio IS NOT NULL AND p_tasa_cambio > 0 THEN
        v_tasa_cambio := p_tasa_cambio;
    ELSE
        SELECT tasa_cambio INTO v_tasa_cambio
        FROM public.tasa_cambio
        WHERE fecha_tasa = CURRENT_DATE;

        IF v_tasa_cambio IS NULL THEN
            SELECT tasa_cambio INTO v_tasa_cambio
            FROM public.tasa_cambio
            ORDER BY fecha_tasa DESC, created_at DESC
            LIMIT 1;
        END IF;

        IF v_tasa_cambio IS NULL THEN
            v_tasa_cambio := 1.0000;
        END IF;
    END IF;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;

        IF v_cantidad IS NULL OR v_cantidad <= 0 THEN
            RETURN jsonb_build_object('success', false, 'message', 'La cantidad solicitada para cada producto debe ser mayor a cero.');
        END IF;

        SELECT (COALESCE(cantidad_cargada, 0) - COALESCE(cantidad_entregada, 0))
        INTO v_stock_disponible_movil
        FROM public.inventario_movil
        WHERE camion_id = p_camion_id AND producto_id = v_producto_id;

        IF v_stock_disponible_movil IS NULL THEN
            v_stock_disponible_movil := 0;
        END IF;

        IF v_stock_disponible_movil < v_cantidad THEN
            RETURN jsonb_build_object(
                'success', false,
                'message', 'Stock insuficiente en el camión para el producto seleccionado. Disponible: ' || v_stock_disponible_movil || ', Solicitado: ' || v_cantidad
            );
        END IF;
    END LOOP;

    v_correlativo := nextval('public.ordenes_distribucion_correlativo_seq');
    v_factura_origen := 'AV-' || LPAD(v_correlativo::text, 6, '0');
    v_orden_id := gen_random_uuid();

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;

        SELECT COALESCE(precio_lista1, 0.00), COALESCE(peso_unitario_kg, 0.00)
        INTO v_val_usd_prod, v_peso_unitario
        FROM public.productos
        WHERE id = v_producto_id;

        v_val_usd := COALESCE((v_item->>'valor_unitario_usd')::NUMERIC, (v_item->>'precio_unitario')::NUMERIC, v_val_usd_prod);
        IF v_val_usd <= 0 THEN
            v_val_usd := v_val_usd_prod;
        END IF;

        v_subtotal_usd := ROUND(v_cantidad * v_val_usd, 2);
        v_peso_total := v_peso_total + (COALESCE(v_peso_unitario, 0.00) * v_cantidad);
        v_total_recaudar_usd := v_total_recaudar_usd + v_subtotal_usd;
    END LOOP;

    v_total_recaudar_bs := ROUND(v_total_recaudar_usd * v_tasa_cambio, 2);

    INSERT INTO public.ordenes_distribucion (
        id, correlativo, cliente_id, camion_id, vendedor_id, despachador_id,
        id_ruta, estado, es_autoventa, radar_id, fecha_despacho,
        peso_total_calculado, factura_origen_numero, creado_por, created_at,
        tasa_cambio, total_recaudar_usd, total_recaudar_bs
    ) VALUES (
        v_orden_id, v_correlativo, p_cliente_id, p_camion_id, v_vendedor_id, v_despachador_id,
        v_id_ruta, 'por_liquidar', TRUE, NULL, NOW(),
        v_peso_total, v_factura_origen, p_vendedor_id, NOW(),
        v_tasa_cambio, v_total_recaudar_usd, v_total_recaudar_bs
    );

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;

        SELECT COALESCE(precio_lista1, 0.00) INTO v_val_usd_prod FROM public.productos WHERE id = v_producto_id;
        v_val_usd := COALESCE((v_item->>'valor_unitario_usd')::NUMERIC, (v_item->>'precio_unitario')::NUMERIC, v_val_usd_prod);
        IF v_val_usd <= 0 THEN v_val_usd := v_val_usd_prod; END IF;
        v_subtotal_usd := ROUND(v_cantidad * v_val_usd, 2);

        INSERT INTO public.detalle_distribucion (
            id, orden_id, producto_id, cantidad_solicitada, cantidad_despachada,
            valor_unitario_usd, subtotal_recaudar_usd, secuencia_entrega, estado_entrega
        ) VALUES (
            gen_random_uuid(), v_orden_id, v_producto_id, v_cantidad, v_cantidad,
            v_val_usd, v_subtotal_usd, v_secuencia, 'entregado'
        );

        v_secuencia := v_secuencia + 1;

        UPDATE public.inventario_movil
        SET cantidad_entregada = cantidad_entregada + v_cantidad,
            updated_at = NOW()
        WHERE camion_id = p_camion_id AND producto_id = v_producto_id;
    END LOOP;

    v_contenedores := public.lt_asentar_contenedores_orden(v_orden_id, p_contenedores_json);

    RETURN jsonb_build_object(
        'success', true,
        'message', 'Venta en ruta (AutoVenta) registrada exitosamente.',
        'data', jsonb_build_object(
            'orden_id', v_orden_id,
            'correlativo', v_correlativo,
            'factura_origen_numero', v_factura_origen,
            'cliente_id', p_cliente_id,
            'camion_id', p_camion_id,
            'estado', 'por_liquidar',
            'es_autoventa', true,
            'total_recaudar_usd', v_total_recaudar_usd,
            'total_recaudar_bs', v_total_recaudar_bs,
            'tasa_cambio', v_tasa_cambio,
            'contenedores', v_contenedores
        ),
        'error', NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_err_msg = MESSAGE_TEXT,
            v_err_code = PG_EXCEPTION_HINT;
        RETURN jsonb_build_object(
            'success', false,
            'data', NULL,
            'error', jsonb_build_object(
                'code', COALESCE(NULLIF(v_err_code, ''), 'SQL_ERROR'),
                'message', v_err_msg,
                'details', 'SQLSTATE: ' || SQLSTATE
            )
        );
END;
$$;

REVOKE ALL ON FUNCTION public.registrar_venta_en_ruta_autoventa(UUID, UUID, UUID, JSONB, JSONB, TEXT, NUMERIC) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.registrar_venta_en_ruta_autoventa(UUID, UUID, UUID, JSONB, JSONB, TEXT, NUMERIC) FROM anon;
GRANT EXECUTE ON FUNCTION public.registrar_venta_en_ruta_autoventa(UUID, UUID, UUID, JSONB, JSONB, TEXT, NUMERIC) TO authenticated, service_role;

-- ------------------------------------------------------------------------------
-- 4. Venta directa en almacén (nueva firma con p_contenedores_json)
-- ------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.crear_venta_directa_almacen(UUID, UUID, TEXT, NUMERIC, JSONB);

CREATE OR REPLACE FUNCTION public.crear_venta_directa_almacen(
    p_cliente_id UUID,
    p_vendedor_id UUID,
    p_tipo_venta TEXT,
    p_tasa_cambio NUMERIC DEFAULT NULL,
    p_productos_json JSONB DEFAULT '[]'::jsonb,
    p_contenedores_json JSONB DEFAULT '[]'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_rol TEXT;
    v_vendedor_id UUID;
    v_tipo_venta TEXT := lower(btrim(COALESCE(p_tipo_venta, '')));

    v_orden_id UUID;
    v_correlativo INT;
    v_factura_origen VARCHAR(30);
    v_tasa_cambio NUMERIC(14,4);

    v_despachador_id UUID;
    v_id_ruta UUID;
    v_cliente_activo BOOLEAN;

    v_peso_total NUMERIC(10,2) := 0.00;
    v_total_usd NUMERIC(14,2) := 0.00;

    v_item JSONB;
    v_secuencia INT := 0;
    v_producto_id UUID;
    v_cantidad_num NUMERIC;
    v_cantidad INT;
    v_stock INT;
    v_nombre TEXT;
    v_lista NUMERIC(14,2);
    v_peso_unitario NUMERIC(10,2);

    v_desc_encontrado BOOLEAN;
    v_desc_pct NUMERIC;
    v_desc_pactado NUMERIC;
    v_precio_front NUMERIC;
    v_precio NUMERIC(14,2);
    v_monto_desc_unit NUMERIC(14,2);
    v_pct NUMERIC(5,2);
    v_subtotal NUMERIC(14,2);

    v_contenedores JSONB := '[]'::jsonb;
    v_err_msg TEXT;
    v_err_code TEXT;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Debes iniciar sesión para registrar una venta.'
            USING HINT = 'NO_AUTENTICADO';
    END IF;

    v_rol := public.lt_current_user_rol();
    IF v_rol IS NULL OR v_rol NOT IN ('admin', 'gerente', 'vendedor') THEN
        RAISE EXCEPTION 'No tienes permiso para registrar ventas directas.'
            USING HINT = 'PERMISO_DENEGADO';
    END IF;

    v_vendedor_id := COALESCE(p_vendedor_id, v_uid);
    IF v_rol = 'vendedor' AND v_vendedor_id <> v_uid THEN
        RAISE EXCEPTION 'Un vendedor solo puede registrar ventas a su nombre.'
            USING HINT = 'PERMISO_DENEGADO';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.perfiles_usuario WHERE id = v_vendedor_id) THEN
        RAISE EXCEPTION 'El vendedor especificado no existe.'
            USING HINT = 'VENDEDOR_INEXISTENTE';
    END IF;

    IF v_tipo_venta NOT IN ('credito', 'contado') THEN
        RAISE EXCEPTION 'El tipo de venta debe ser credito o contado.'
            USING HINT = 'PARAMETRO_INVALIDO';
    END IF;

    IF p_cliente_id IS NULL THEN
        RAISE EXCEPTION 'El cliente es requerido.'
            USING HINT = 'PARAMETRO_INVALIDO';
    END IF;

    IF p_productos_json IS NULL
       OR jsonb_typeof(p_productos_json) <> 'array'
       OR jsonb_array_length(p_productos_json) = 0 THEN
        RAISE EXCEPTION 'Debe incluir al menos un producto.'
            USING HINT = 'PARAMETRO_INVALIDO';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM jsonb_array_elements(p_productos_json) e
        GROUP BY e->>'producto_id'
        HAVING count(*) > 1
    ) THEN
        RAISE EXCEPTION 'Hay productos repetidos en la venta; agrupa las cantidades en una sola línea.'
            USING HINT = 'PRODUCTO_DUPLICADO';
    END IF;

    SELECT c.despachador_id, c.id_ruta, COALESCE(c.activo, true)
    INTO v_despachador_id, v_id_ruta, v_cliente_activo
    FROM public.clientes c
    WHERE c.id = p_cliente_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El cliente especificado no existe.'
            USING HINT = 'CLIENTE_INEXISTENTE';
    END IF;

    IF NOT v_cliente_activo THEN
        RAISE EXCEPTION 'El cliente está inactivo.'
            USING HINT = 'CLIENTE_INACTIVO';
    END IF;

    IF p_tasa_cambio IS NOT NULL AND p_tasa_cambio > 0 THEN
        v_tasa_cambio := p_tasa_cambio;
    ELSE
        SELECT tasa_cambio INTO v_tasa_cambio
        FROM public.tasa_cambio
        ORDER BY fecha_tasa DESC
        LIMIT 1;

        IF v_tasa_cambio IS NULL THEN
            RAISE EXCEPTION 'No hay tasa de cambio registrada. Regístrala en Tasas de cambio.'
                USING HINT = 'TASA_INEXISTENTE';
        END IF;
    END IF;

    v_correlativo := nextval('public.ordenes_distribucion_correlativo_seq');
    v_factura_origen := 'FAC-' || LPAD(v_correlativo::text, 6, '0');
    v_orden_id := gen_random_uuid();

    INSERT INTO public.ordenes_distribucion (
        id, correlativo, cliente_id, camion_id, vendedor_id, despachador_id,
        id_ruta, estado, fecha_despacho, peso_total_calculado,
        factura_origen_numero, creado_por, created_at, tasa_cambio,
        total_recaudar_bs, total_recaudar_usd, origen_venta, es_autoventa
    ) VALUES (
        v_orden_id, v_correlativo, p_cliente_id, NULL, v_vendedor_id, v_despachador_id,
        v_id_ruta, 'por_liquidar', now(), 0.00,
        v_factura_origen, v_uid, now(), v_tasa_cambio,
        NULL, 0.00, 'ALMACEN', false
    );

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_secuencia := v_secuencia + 1;
        v_producto_id := NULLIF(v_item->>'producto_id', '')::UUID;
        v_cantidad_num := NULLIF(v_item->>'cantidad', '')::NUMERIC;

        IF v_producto_id IS NULL THEN
            RAISE EXCEPTION 'Línea %: falta el producto.', v_secuencia
                USING HINT = 'PARAMETRO_INVALIDO';
        END IF;

        IF v_cantidad_num IS NULL OR v_cantidad_num <= 0 OR v_cantidad_num <> trunc(v_cantidad_num) THEN
            RAISE EXCEPTION 'Línea %: la cantidad debe ser un entero mayor a cero.', v_secuencia
                USING HINT = 'CANTIDAD_INVALIDA';
        END IF;
        v_cantidad := v_cantidad_num::INT;

        SELECT p.nombre, COALESCE(p.precio_lista1, 0.00), COALESCE(p.peso_unitario_kg, 0.00)
        INTO v_nombre, v_lista, v_peso_unitario
        FROM public.productos p
        WHERE p.id = v_producto_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Línea %: el producto no existe.', v_secuencia
                USING HINT = 'PRODUCTO_INEXISTENTE';
        END IF;

        SELECT ia.stock_disponible
        INTO v_stock
        FROM public.inventario_almacen ia
        WHERE ia.producto_id = v_producto_id
        FOR UPDATE;

        IF NOT FOUND OR COALESCE(v_stock, 0) < v_cantidad THEN
            RAISE EXCEPTION 'Stock insuficiente para «%». Disponible: %, solicitado: %.',
                v_nombre, COALESCE(v_stock, 0), v_cantidad
                USING HINT = 'STOCK_INSUFICIENTE';
        END IF;

        SELECT d.porcentaje_descuento, d.precio_pactado_usd
        INTO v_desc_pct, v_desc_pactado
        FROM public.descuentos_cliente_producto d
        WHERE d.cliente_id = p_cliente_id
          AND d.producto_id = v_producto_id
          AND d.activo = true
        LIMIT 1;
        v_desc_encontrado := FOUND;

        v_precio_front := COALESCE(
            NULLIF(v_item->>'valor_unitario_usd', '')::NUMERIC,
            NULLIF(v_item->>'precio_unitario', '')::NUMERIC
        );

        IF v_precio_front IS NOT NULL THEN
            v_precio := v_precio_front;
        ELSIF v_desc_encontrado AND v_desc_pactado IS NOT NULL THEN
            v_precio := v_desc_pactado;
        ELSIF v_desc_encontrado AND COALESCE(v_desc_pct, 0) > 0 THEN
            v_precio := ROUND(v_lista * (1.00 - (v_desc_pct / 100.00)), 2);
        ELSE
            v_precio := v_lista;
        END IF;

        -- Misma salvaguarda que crear_orden_distribucion.
        IF v_precio <= 0 OR (v_precio < 1.00 AND v_lista >= 1.00) THEN
            v_precio := v_lista;
        END IF;

        v_monto_desc_unit := GREATEST(0.00, v_lista - v_precio);
        v_pct := CASE WHEN v_lista > 0
                      THEN LEAST(100.00, ROUND(v_monto_desc_unit / v_lista * 100.00, 2))
                      ELSE 0.00 END;
        v_subtotal := ROUND(v_cantidad * v_precio, 2);

        UPDATE public.inventario_almacen
        SET stock_disponible = stock_disponible - v_cantidad
        WHERE producto_id = v_producto_id;

        INSERT INTO public.detalle_distribucion (
            orden_id, producto_id, cantidad_solicitada, cantidad_despachada,
            valor_unitario_recaudar, subtotal_recaudar, secuencia_entrega,
            estado_entrega, motivo_rechazo, valor_unitario_usd,
            subtotal_recaudar_usd, precio_lista_usd, porcentaje_descuento,
            monto_descuento_usd
        ) VALUES (
            v_orden_id, v_producto_id, v_cantidad, v_cantidad,
            NULL, NULL, v_secuencia,
            'entregado', NULL, v_precio,
            v_subtotal, v_lista, v_pct,
            v_monto_desc_unit * v_cantidad
        );

        v_total_usd := v_total_usd + v_subtotal;
        v_peso_total := v_peso_total + (v_peso_unitario * v_cantidad);
    END LOOP;

    UPDATE public.ordenes_distribucion
    SET total_recaudar_usd = v_total_usd,
        peso_total_calculado = v_peso_total
    WHERE id = v_orden_id;

    v_contenedores := public.lt_asentar_contenedores_orden(v_orden_id, p_contenedores_json);

    RETURN jsonb_build_object(
        'success', true,
        'message', 'Venta directa registrada. Queda por liquidar hasta registrar el cobro.',
        'orden_id', v_orden_id,
        'data', jsonb_build_object(
            'orden_id', v_orden_id,
            'correlativo', v_correlativo,
            'factura_origen_numero', v_factura_origen,
            'tasa_cambio', v_tasa_cambio,
            'tipo_venta', v_tipo_venta,
            'estado_orden', 'por_liquidar',
            'total_recaudar_bs', NULL,
            'total_recaudar_usd', v_total_usd,
            'peso_total_calculado', v_peso_total,
            'contenedores', v_contenedores
        ),
        'error', NULL
    );

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
        v_err_msg = MESSAGE_TEXT,
        v_err_code = PG_EXCEPTION_HINT;
    RETURN jsonb_build_object(
        'success', false,
        'data', NULL,
        'message', v_err_msg,
        'error', jsonb_build_object(
            'code', COALESCE(NULLIF(v_err_code, ''), 'SQL_ERROR'),
            'message', v_err_msg,
            'details', 'SQLSTATE: ' || SQLSTATE
        )
    );
END;
$$;

REVOKE ALL ON FUNCTION public.crear_venta_directa_almacen(UUID, UUID, TEXT, NUMERIC, JSONB, JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.crear_venta_directa_almacen(UUID, UUID, TEXT, NUMERIC, JSONB, JSONB) FROM anon;
GRANT EXECUTE ON FUNCTION public.crear_venta_directa_almacen(UUID, UUID, TEXT, NUMERIC, JSONB, JSONB) TO authenticated, service_role;

-- La función creada por Antigravity fuera de tenant_patches queda sin uso.
DROP FUNCTION IF EXISTS public.rpc_create_od_and_process_containers(UUID, UUID, UUID, NUMERIC, JSONB, UUID, UUID, INT);
