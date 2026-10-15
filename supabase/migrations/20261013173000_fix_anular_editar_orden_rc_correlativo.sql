-- ==============================================================================
-- Parche Idempotente: Fix column rc.correlativo y check constraint movimientos_contenedores
-- Fecha: 2026-10-13 18:05:00
-- Descripción: 1. public.rendiciones_cuentas no tiene columna correlativo (su PK es id uuid).
--              2. movimientos_contenedores tiene CHECK (cantidad_entregada >= 0 y cantidad_retirada >= 0).
--                 Se revierte el saldo de envases del cliente y se eliminan los movimientos de la orden anulada.
-- ==============================================================================
-- ------------------------------------------------------------------------------
-- 2. Anulación de Órdenes de Distribución (Reversión Transaccional)
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
    v_rendicion_activa RECORD;
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

    -- Reversión de inventario según modalidad
    IF COALESCE(v_orden.es_autoventa, false) = true AND v_orden.camion_id IS NOT NULL THEN
        -- Auto-Venta: descontó cantidad_entregada en inventario_movil
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

    ELSIF v_orden.origen_venta = 'ALMACEN' OR v_orden.camion_id IS NULL THEN
        -- Venta directa de almacén: descontó stock_disponible en inventario_almacen
        FOR v_det IN
            SELECT producto_id, COALESCE(cantidad_despachada, cantidad_solicitada, 0) AS cantidad
            FROM public.detalle_distribucion
            WHERE orden_id = p_orden_id
        LOOP
            UPDATE public.inventario_almacen
            SET stock_disponible = stock_disponible + v_det.cantidad
            WHERE producto_id = v_det.producto_id;
        END LOOP;

    ELSE
        -- Pre-venta en ruta: si ya había salido en carga móvil
        IF v_orden.camion_id IS NOT NULL AND v_orden.estado IN ('en_ruta', 'despachada', 'por_liquidar') THEN
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
    END IF;

    -- Reversión de envases/contenedores si se asentaron movimientos para esta orden
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
            -- Si la orden sumó entregados y restó retirados, la reversión resta entregados y suma retirados
            v_nuevo_saldo := GREATEST(0, v_saldo_act - v_mov_cont.total_entregados + v_mov_cont.total_retirados);

            UPDATE public.saldo_contenedores_clientes
            SET saldo_pendiente = v_nuevo_saldo,
                updated_at = NOW()
            WHERE cliente_id = v_orden.cliente_id AND contenedor_id = v_mov_cont.contenedor_id;
        END LOOP;

        DELETE FROM public.movimientos_contenedores WHERE orden_id = p_orden_id;
    END IF;

    -- Actualizar estado de la orden a 'anulada'
    UPDATE public.ordenes_distribucion
    SET estado = 'anulada',
        observaciones = COALESCE(observaciones, '') ||
                        ' [ANULADA el ' || TO_CHAR(NOW(), 'YYYY-MM-DD HH24:MI:SS') ||
                        CASE WHEN p_motivo IS NOT NULL AND TRIM(p_motivo) <> '' THEN ' - Motivo: ' || TRIM(p_motivo) ELSE '' END || ']'
    WHERE id = p_orden_id;

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
-- 3. Edición de Órdenes de Distribución (Actualización Transaccional)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.editar_orden_distribucion(
    p_orden_id UUID,
    p_productos_json JSONB,
    p_contenedores_json JSONB DEFAULT '[]'::jsonb,
    p_observaciones TEXT DEFAULT NULL
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
    v_rendicion_activa RECORD;

    v_item JSONB;
    v_producto_id UUID;
    v_cantidad INT;
    v_val_usd NUMERIC(14,2);
    v_val_usd_prod NUMERIC(14,2);
    v_peso_unitario NUMERIC(10,2);
    v_peso_total NUMERIC(10,2) := 0.00;
    v_subtotal_usd NUMERIC(14,2);
    v_total_usd NUMERIC(14,2) := 0.00;
    v_total_bs NUMERIC(14,2);
    v_secuencia INT := 1;
    v_desc_rec RECORD;
    v_stock_disponible INT;
    v_contenedores_resumen JSONB := '[]'::jsonb;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN jsonb_build_object('success', false, 'data', NULL, 'error', jsonb_build_object('code', 'NO_AUTENTICADO', 'message', 'Debes iniciar sesión para editar una orden.'));
    END IF;

    IF p_orden_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'data', NULL, 'error', jsonb_build_object('code', 'PARAMETRO_INVALIDO', 'message', 'El ID de la orden es requerido.'));
    END IF;

    IF p_productos_json IS NULL OR jsonb_typeof(p_productos_json) <> 'array' OR jsonb_array_length(p_productos_json) = 0 THEN
        RETURN jsonb_build_object('success', false, 'data', NULL, 'error', jsonb_build_object('code', 'PARAMETRO_INVALIDO', 'message', 'Debe incluir al menos un producto en la orden.'));
    END IF;

    SELECT * INTO v_orden
    FROM public.ordenes_distribucion
    WHERE id = p_orden_id
    FOR UPDATE;

    IF v_orden.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'data', NULL, 'error', jsonb_build_object('code', 'ORDEN_NO_ENCONTRADA', 'message', 'La orden de distribución no existe.'));
    END IF;

    IF v_orden.estado IN ('anulada', 'liquidada') THEN
        RETURN jsonb_build_object('success', false, 'data', NULL, 'error', jsonb_build_object('code', 'ORDEN_NO_EDITABLE', 'message', 'No se puede editar una orden en estado ' || v_orden.estado || '.'));
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
                'message', 'No se puede editar la orden porque ya tiene rendición de cuentas o cobranzas aplicadas (ID: ' || COALESCE(SUBSTRING(v_rendicion_activa.rendicion_id::text, 1, 8), '') || ', Estado: ' || v_rendicion_activa.estado_rendicion || ').'
            )
        );
    END IF;

    -- 1. Reversión temporal del inventario anterior
    IF COALESCE(v_orden.es_autoventa, false) = true AND v_orden.camion_id IS NOT NULL THEN
        FOR v_det IN SELECT producto_id, COALESCE(cantidad_despachada, cantidad_solicitada, 0) AS cantidad FROM public.detalle_distribucion WHERE orden_id = p_orden_id LOOP
            UPDATE public.inventario_movil
            SET cantidad_entregada = GREATEST(0, COALESCE(cantidad_entregada, 0) - v_det.cantidad),
                updated_at = NOW()
            WHERE camion_id = v_orden.camion_id AND producto_id = v_det.producto_id;
        END LOOP;

    ELSIF v_orden.origen_venta = 'ALMACEN' OR v_orden.camion_id IS NULL THEN
        FOR v_det IN SELECT producto_id, COALESCE(cantidad_despachada, cantidad_solicitada, 0) AS cantidad FROM public.detalle_distribucion WHERE orden_id = p_orden_id LOOP
            UPDATE public.inventario_almacen
            SET stock_disponible = stock_disponible + v_det.cantidad
            WHERE producto_id = v_det.producto_id;
        END LOOP;
    END IF;

    -- 2. Reversión temporal de envases anteriores del cliente
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
            v_nuevo_saldo := GREATEST(0, v_saldo_act - v_mov_cont.total_entregados + v_mov_cont.total_retirados);

            UPDATE public.saldo_contenedores_clientes
            SET saldo_pendiente = v_nuevo_saldo, updated_at = NOW()
            WHERE cliente_id = v_orden.cliente_id AND contenedor_id = v_mov_cont.contenedor_id;
        END LOOP;
        DELETE FROM public.movimientos_contenedores WHERE orden_id = p_orden_id;
    END IF;

    -- 3. Validar disponibilidad de stock para las NUEVAS cantidades solicitadas
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;

        IF v_cantidad IS NULL OR v_cantidad <= 0 THEN
            RAISE EXCEPTION 'La cantidad para cada producto debe ser un entero mayor a cero.' USING HINT = 'CANTIDAD_INVALIDA';
        END IF;

        IF COALESCE(v_orden.es_autoventa, false) = true AND v_orden.camion_id IS NOT NULL THEN
            SELECT GREATEST(0, COALESCE(cantidad_cargada, 0) - COALESCE(cantidad_entregada, 0))
            INTO v_stock_disponible
            FROM public.inventario_movil
            WHERE camion_id = v_orden.camion_id AND producto_id = v_producto_id;

            IF COALESCE(v_stock_disponible, 0) < v_cantidad THEN
                RAISE EXCEPTION 'Stock insuficiente en camión para el producto %. Disponible: %, Solicitado: %',
                    v_producto_id, COALESCE(v_stock_disponible, 0), v_cantidad USING HINT = 'STOCK_INSUFICIENTE';
            END IF;

        ELSIF v_orden.origen_venta = 'ALMACEN' OR v_orden.camion_id IS NULL THEN
            SELECT stock_disponible INTO v_stock_disponible
            FROM public.inventario_almacen
            WHERE producto_id = v_producto_id;

            IF COALESCE(v_stock_disponible, 0) < v_cantidad THEN
                RAISE EXCEPTION 'Stock insuficiente en almacén para el producto %. Disponible: %, Solicitado: %',
                    v_producto_id, COALESCE(v_stock_disponible, 0), v_cantidad USING HINT = 'STOCK_INSUFICIENTE';
            END IF;
        END IF;
    END LOOP;

    -- 4. Reemplazar líneas de detalle y asentar nuevo inventario
    DELETE FROM public.detalle_distribucion WHERE orden_id = p_orden_id;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;

        SELECT COALESCE(precio_lista1, 0.00), COALESCE(peso_unitario_kg, 0.00)
        INTO v_val_usd_prod, v_peso_unitario
        FROM public.productos WHERE id = v_producto_id;

        IF COALESCE(v_orden.es_cortesia, false) = true THEN
            v_val_usd := 0.00;
        ELSE
            SELECT * INTO v_desc_rec
            FROM public.descuentos_cliente_producto
            WHERE cliente_id = v_orden.cliente_id AND producto_id = v_producto_id AND activo = true;

            IF (v_item->>'valor_unitario_usd') IS NOT NULL THEN
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

            IF v_val_usd <= 0 THEN v_val_usd := v_val_usd_prod; END IF;
        END IF;

        v_subtotal_usd := ROUND(v_cantidad * v_val_usd, 2);
        v_total_usd := v_total_usd + v_subtotal_usd;
        v_peso_total := v_peso_total + (COALESCE(v_peso_unitario, 0.00) * v_cantidad);

        INSERT INTO public.detalle_distribucion (
            id, orden_id, producto_id, cantidad_solicitada, cantidad_despachada,
            valor_unitario_usd, subtotal_recaudar_usd, secuencia_entrega, estado_entrega
        ) VALUES (
            gen_random_uuid(), p_orden_id, v_producto_id, v_cantidad, v_cantidad,
            v_val_usd, v_subtotal_usd, v_secuencia, 'entregado'
        );
        v_secuencia := v_secuencia + 1;

        -- Aplicar nuevo descuento de inventario
        IF COALESCE(v_orden.es_autoventa, false) = true AND v_orden.camion_id IS NOT NULL THEN
            UPDATE public.inventario_movil
            SET cantidad_entregada = cantidad_entregada + v_cantidad, updated_at = NOW()
            WHERE camion_id = v_orden.camion_id AND producto_id = v_producto_id;
        ELSIF v_orden.origen_venta = 'ALMACEN' OR v_orden.camion_id IS NULL THEN
            UPDATE public.inventario_almacen
            SET stock_disponible = stock_disponible - v_cantidad
            WHERE producto_id = v_producto_id;
        END IF;
    END LOOP;

    -- 5. Recalcular y actualizar totales en la cabecera
    v_total_bs := ROUND(v_total_usd * COALESCE(v_orden.tasa_cambio, 1.00), 2);

    UPDATE public.ordenes_distribucion
    SET total_recaudar_usd = v_total_usd,
        total_recaudar_bs = v_total_bs,
        peso_total_calculado = v_peso_total,
        observaciones = CASE
            WHEN p_observaciones IS NOT NULL AND TRIM(p_observaciones) <> ''
            THEN TRIM(p_observaciones) || ' [EDITADA ' || TO_CHAR(NOW(), 'YYYY-MM-DD HH24:MI') || ']'
            ELSE COALESCE(observaciones, '') || ' [EDITADA ' || TO_CHAR(NOW(), 'YYYY-MM-DD HH24:MI') || ']'
        END
    WHERE id = p_orden_id;

    -- 6. Asentar nuevos envases llamando a lt_asentar_contenedores_orden
    IF p_contenedores_json IS NOT NULL THEN
        v_contenedores_resumen := public.lt_asentar_contenedores_orden(p_orden_id, p_contenedores_json);
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'message', 'Orden de distribución editada exitosamente.',
        'data', jsonb_build_object(
            'orden_id', p_orden_id,
            'correlativo', v_orden.correlativo,
            'total_recaudar_usd', v_total_usd,
            'total_recaudar_bs', v_total_bs,
            'peso_total_calculado', v_peso_total,
            'contenedores', v_contenedores_resumen
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

REVOKE ALL ON FUNCTION public.editar_orden_distribucion(UUID, JSONB, JSONB, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.editar_orden_distribucion(UUID, JSONB, JSONB, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.editar_orden_distribucion(UUID, JSONB, JSONB, TEXT) TO authenticated, service_role;
