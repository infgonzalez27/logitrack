-- ==============================================================================
-- Patch: Corrección de venta directa en almacén (crear_venta_directa_almacen)
-- Aplica después de 20260930170216_venta_directa_almacen.sql. Idempotente.
--
-- Cambios respecto a la versión anterior:
--   - Exige sesión (auth.uid()) y rol admin, gerente o vendedor.
--     Un vendedor solo puede vender a su nombre (p_vendedor_id = auth.uid()).
--   - creado_por = usuario que registra la venta (auditoría).
--   - Stock: bloquea la fila (FOR UPDATE) y rechaza si el producto no tiene
--     fila en inventario_almacen (antes se vendía sin descontar stock).
--   - Rechaza productos repetidos en p_productos_json.
--   - Precio calculado una sola vez: la cabecera coincide con la suma del detalle.
--   - Contado y crédito quedan en 'por_liquidar'; el cobro se registra con una
--     rendición como cualquier otra orden.
--   - fecha_despacho = now() (antes CURRENT_DATE, que en UTC podía caer el día anterior).
--   - Errores con el formato estándar {success, data, error:{code,message,details}}.
--   - search_path fijo, sin EXECUTE para PUBLIC/anon.
--   - origen_venta NOT NULL con CHECK ('RUTA','ALMACEN').
-- ==============================================================================

ALTER TABLE public.ordenes_distribucion
  ADD COLUMN IF NOT EXISTS origen_venta VARCHAR(20) DEFAULT 'RUTA';

UPDATE public.ordenes_distribucion
SET origen_venta = 'RUTA'
WHERE origen_venta IS NULL;

ALTER TABLE public.ordenes_distribucion
  ALTER COLUMN origen_venta SET DEFAULT 'RUTA',
  ALTER COLUMN origen_venta SET NOT NULL;

ALTER TABLE public.ordenes_distribucion
  DROP CONSTRAINT IF EXISTS ordenes_distribucion_origen_venta_check;

ALTER TABLE public.ordenes_distribucion
  ADD CONSTRAINT ordenes_distribucion_origen_venta_check
  CHECK (origen_venta IN ('RUTA', 'ALMACEN'));

ALTER TABLE public.ordenes_distribucion
  ALTER COLUMN camion_id DROP NOT NULL;

CREATE OR REPLACE FUNCTION public.crear_venta_directa_almacen(
    p_cliente_id UUID,
    p_vendedor_id UUID,
    p_tipo_venta TEXT,
    p_tasa_cambio NUMERIC DEFAULT NULL,
    p_productos_json JSONB DEFAULT '[]'::jsonb
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
            'peso_total_calculado', v_peso_total
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

REVOKE ALL ON FUNCTION public.crear_venta_directa_almacen(UUID, UUID, TEXT, NUMERIC, JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.crear_venta_directa_almacen(UUID, UUID, TEXT, NUMERIC, JSONB) FROM anon;
GRANT EXECUTE ON FUNCTION public.crear_venta_directa_almacen(UUID, UUID, TEXT, NUMERIC, JSONB) TO authenticated, service_role;
