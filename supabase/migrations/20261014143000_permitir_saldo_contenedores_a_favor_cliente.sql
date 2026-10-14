-- ==============================================================================
-- Migración: Permitir saldo de contenedores a favor del cliente (< 0)
-- y corregir anular/editar orden de distribución
-- Fecha: 2026-10-14 14:30:00
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Quitar restricciones CHECK que prohíben valores < 0
-- ------------------------------------------------------------------------------
ALTER TABLE public.saldo_contenedores_clientes
    DROP CONSTRAINT IF EXISTS saldo_contenedores_clientes_saldo_pendiente_check;

ALTER TABLE public.movimientos_contenedores
    DROP CONSTRAINT IF EXISTS movimientos_contenedores_cantidad_entregada_check;

ALTER TABLE public.movimientos_contenedores
    DROP CONSTRAINT IF EXISTS movimientos_contenedores_cantidad_retirada_check;

ALTER TABLE public.ordenes_distribucion
    ADD COLUMN IF NOT EXISTS observaciones TEXT;

-- ------------------------------------------------------------------------------
-- 2. lt_asentar_contenedores_orden (Permitiendo saldo actual < 0)
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

        -- Permite saldos negativos si se retiran más de los que debía (saldo a favor del cliente)
        v_saldo_act := v_saldo_ant + v_rec.entregados - v_rec.retirados;

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
-- 3. anular_orden_distribucion (Reversión transaccional limpia)
-- ------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.anular_orden_distribucion(uuid);
DROP FUNCTION IF EXISTS public.anular_orden_distribucion(uuid, text);

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
-- 4. editar_orden_distribucion (Preservando saldos a favor)
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
    v_item JSONB;
    v_producto_id UUID;
    v_cantidad INT;
    v_stock_disponible INT;
    v_val_usd NUMERIC(14,2);
    v_val_usd_prod NUMERIC(14,2);
    v_subtotal_usd NUMERIC(14,2);
    v_total_usd NUMERIC(14,2) := 0.00;
    v_total_bs NUMERIC(14,2) := 0.00;
    v_peso_unitario NUMERIC(10,2);
    v_peso_total NUMERIC(10,2) := 0.00;
    v_secuencia INT := 1;
    v_contenedores_resumen JSONB := '[]'::jsonb;
    v_rendicion_activa RECORD;
    v_desc_rec RECORD;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', NULL,
            'error', jsonb_build_object('code', 'NO_AUTENTICADO', 'message', 'Debes iniciar sesión para editar una orden.')
        );
    END IF;

    IF p_orden_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', NULL,
            'error', jsonb_build_object('code', 'PARAMETRO_INVALIDO', 'message', 'El ID de la orden es requerido.')
        );
    END IF;

    IF p_productos_json IS NULL OR jsonb_array_length(p_productos_json) = 0 THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', NULL,
            'error', jsonb_build_object('code', 'PARAMETRO_INVALIDO', 'message', 'Debe incluir al menos un producto en la orden.')
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
            'error', jsonb_build_object('code', 'ORDEN_ANULADA', 'message', 'No se puede editar una orden que ya ha sido anulada.')
        );
    END IF;

    IF v_orden.estado = 'liquidada' THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', NULL,
            'error', jsonb_build_object('code', 'ORDEN_LIQUIDADA', 'message', 'No se puede editar una orden que ya ha sido liquidada.')
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
                'message', 'No se puede editar la orden porque tiene una rendición de cuentas asociada activa (ID: ' || COALESCE(SUBSTRING(v_rendicion_activa.rendicion_id::text, 1, 8), '') || ', Estado: ' || v_rendicion_activa.estado_rendicion || '). Debe reversar la rendición antes de editar la orden.'
            )
        );
    END IF;

    -- 1. Reversar inventario de las líneas actuales
    IF COALESCE(v_orden.es_autoventa, false) = true AND v_orden.camion_id IS NOT NULL THEN
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
        FOR v_det IN
            SELECT producto_id, COALESCE(cantidad_despachada, cantidad_solicitada, 0) AS cantidad
            FROM public.detalle_distribucion
            WHERE orden_id = p_orden_id
        LOOP
            UPDATE public.inventario_almacen
            SET stock_disponible = stock_disponible + v_det.cantidad
            WHERE producto_id = v_det.producto_id;
        END LOOP;
    END IF;

    -- 2. Reversar movimientos y saldos de contenedores previos
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

    -- 3. Validar stock disponible para las nuevas líneas
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;

        IF v_cantidad IS NULL OR v_cantidad <= 0 THEN
            RETURN jsonb_build_object(
                'success', false,
                'data', NULL,
                'error', jsonb_build_object('code', 'CANTIDAD_INVALIDA', 'message', 'La cantidad para cada producto debe ser mayor a cero.')
            );
        END IF;

        IF COALESCE(v_orden.es_autoventa, false) = true AND v_orden.camion_id IS NOT NULL THEN
            SELECT (COALESCE(cantidad_cargada, 0) - COALESCE(cantidad_entregada, 0))
            INTO v_stock_disponible
            FROM public.inventario_movil
            WHERE camion_id = v_orden.camion_id AND producto_id = v_producto_id;

            IF v_stock_disponible IS NULL OR v_stock_disponible < v_cantidad THEN
                RETURN jsonb_build_object(
                    'success', false,
                    'data', NULL,
                    'error', jsonb_build_object(
                        'code', 'STOCK_INSUFICIENTE_MOVIL',
                        'message', 'Stock insuficiente en camión para el producto seleccionado (Disponible: ' || COALESCE(v_stock_disponible, 0) || ', Solicitado: ' || v_cantidad || ').'
                    )
                );
            END IF;

        ELSIF v_orden.origen_venta = 'ALMACEN' OR v_orden.camion_id IS NULL THEN
            SELECT stock_disponible INTO v_stock_disponible
            FROM public.inventario_almacen
            WHERE producto_id = v_producto_id;

            IF v_stock_disponible IS NULL OR v_stock_disponible < v_cantidad THEN
                RETURN jsonb_build_object(
                    'success', false,
                    'data', NULL,
                    'error', jsonb_build_object(
                        'code', 'STOCK_INSUFICIENTE_ALMACEN',
                        'message', 'Stock insuficiente en almacén para el producto seleccionado (Disponible: ' || COALESCE(v_stock_disponible, 0) || ', Solicitado: ' || v_cantidad || ').'
                    )
                );
            END IF;
        END IF;
    END LOOP;

    -- 4. Reemplazar líneas en detalle_distribucion
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

-- ------------------------------------------------------------------------------
-- 5. registrar_venta_en_ruta_autoventa (Preservando saldos a favor)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.registrar_venta_en_ruta_autoventa(
    p_vendedor_id UUID,
    p_cliente_id UUID,
    p_camion_id UUID,
    p_productos_json JSONB DEFAULT '[]'::jsonb,
    p_contenedores_json JSONB DEFAULT '[]'::jsonb,
    p_observaciones TEXT DEFAULT NULL,
    p_tasa_cambio NUMERIC DEFAULT NULL,
    p_es_cortesia BOOLEAN DEFAULT FALSE
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
    
    v_desc_rec RECORD;
    v_pct_desc NUMERIC(5,2);
    v_monto_desc_unit NUMERIC(14,2);
    
    v_cont_item JSONB;
    v_cont_id UUID;
    v_cant_entregada INT;
    v_cant_retirada INT;
    v_saldo_ant INT;
    v_saldo_act INT;
BEGIN
    -- Validaciones de parámetros
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

    -- Validar existencia del camión y estado ('en_ruta' o 'asignado')
    SELECT estado INTO v_camion_estado
    FROM public.camiones
    WHERE id = p_camion_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'message', 'El camión especificado no existe.');
    END IF;

    IF v_camion_estado NOT IN ('en_ruta', 'asignado') THEN
        RETURN jsonb_build_object('success', false, 'message', 'El camión debe estar en ruta para registrar AutoVentas. Estado actual: ' || v_camion_estado);
    END IF;

    -- Obtener datos del cliente (vendedor, despachador, ruta)
    SELECT c.vendedor_id, c.despachador_id, c.id_ruta
    INTO v_vendedor_id, v_despachador_id, v_id_ruta
    FROM public.clientes c
    WHERE c.id = p_cliente_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'message', 'El cliente especificado no existe.');
    END IF;

    v_vendedor_id := COALESCE(p_vendedor_id, v_vendedor_id);

    -- Determinar tasa de cambio
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

    -- 1. Validar disponibilidad de stock en inventario_movil para cada producto
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;

        IF v_cantidad IS NULL OR v_cantidad <= 0 THEN
            RETURN jsonb_build_object('success', false, 'message', 'La cantidad solicitada para cada producto debe ser mayor a cero.');
        END IF;

        -- Consultar disponibilidad real en inventario_movil (cargado - entregado)
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

    -- 2. Generar correlativo e ID de orden
    v_correlativo := nextval('public.ordenes_distribucion_correlativo_seq');
    v_factura_origen := 'AV-' || LPAD(v_correlativo::text, 6, '0');
    v_orden_id := gen_random_uuid();

    -- 3. Calcular montos y pesos
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;

        SELECT COALESCE(precio_lista1, 0.00), COALESCE(peso_unitario_kg, 0.00) 
        INTO v_val_usd_prod, v_peso_unitario
        FROM public.productos
        WHERE id = v_producto_id;

        -- Buscar descuento específico del cliente
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
        v_peso_total := v_peso_total + (COALESCE(v_peso_unitario, 0.00) * v_cantidad);
        v_total_recaudar_usd := v_total_recaudar_usd + v_subtotal_usd;
    END LOOP;

    v_total_recaudar_bs := ROUND(v_total_recaudar_usd * v_tasa_cambio, 2);

    -- 4. Insertar la orden en ordenes_distribucion (estado = 'por_liquidar', es_autoventa = TRUE, radar_id = NULL)
    INSERT INTO public.ordenes_distribucion (
        id,
        correlativo,
        cliente_id,
        camion_id,
        vendedor_id,
        despachador_id,
        id_ruta,
        estado,
        es_autoventa,
        radar_id,
        fecha_despacho,
        peso_total_calculado,
        factura_origen_numero,
        creado_por,
        created_at,
        tasa_cambio,
        total_recaudar_usd,
        total_recaudar_bs,
        es_cortesia
    ) VALUES (
        v_orden_id,
        v_correlativo,
        p_cliente_id,
        p_camion_id,
        v_vendedor_id,
        v_despachador_id,
        v_id_ruta,
        'por_liquidar',
        TRUE,
        NULL,
        CURRENT_DATE,
        v_peso_total,
        v_factura_origen,
        auth.uid(),
        NOW(),
        v_tasa_cambio,
        v_total_recaudar_usd,
        v_total_recaudar_bs,
        p_es_cortesia
    );

    -- 5. Insertar líneas en detalle_distribucion y actualizar inventario móvil
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;

        SELECT COALESCE(precio_lista1, 0.00) INTO v_val_usd_prod FROM public.productos WHERE id = v_producto_id;
        
        -- Buscar descuento específico del cliente
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
            valor_unitario_usd,
            subtotal_recaudar_usd,
            secuencia_entrega,
            precio_lista_usd,
            porcentaje_descuento,
            monto_descuento_usd
        ) VALUES (
            gen_random_uuid(),
            v_orden_id,
            v_producto_id,
            v_cantidad,
            v_cantidad,
            v_val_usd,
            v_subtotal_usd,
            v_secuencia,
            v_val_usd_prod,
            v_pct_desc,
            v_monto_desc_unit
        );

        v_secuencia := v_secuencia + 1;

        -- Incrementar cantidad_entregada en el inventario móvil del camión
        UPDATE public.inventario_movil
        SET cantidad_entregada = cantidad_entregada + v_cantidad,
            updated_at = NOW()
        WHERE camion_id = p_camion_id AND producto_id = v_producto_id;
    END LOOP;

    -- 6. Procesar movimiento de envases / contenedores si fueron suministrados
    IF p_contenedores_json IS NOT NULL AND jsonb_array_length(p_contenedores_json) > 0 THEN
        FOR v_cont_item IN SELECT * FROM jsonb_array_elements(p_contenedores_json) LOOP
            v_cont_id := (v_cont_item->>'contenedor_id')::UUID;
            v_cant_entregada := COALESCE((v_cont_item->>'cantidad_entregada')::INT, 0);
            v_cant_retirada := COALESCE((v_cont_item->>'cantidad_retirada')::INT, 0);

            IF v_cont_id IS NOT NULL AND (v_cant_entregada > 0 OR v_cant_retirada > 0) THEN
                SELECT saldo_pendiente INTO v_saldo_ant
                FROM public.saldo_contenedores_clientes
                WHERE cliente_id = p_cliente_id AND contenedor_id = v_cont_id
                FOR UPDATE;
                v_saldo_ant := COALESCE(v_saldo_ant, 0);

                -- Permite saldos negativos si retira más de lo que debía
                v_saldo_act := v_saldo_ant + v_cant_entregada - v_cant_retirada;

                -- Registro histórico del movimiento con saldo previo y actual
                INSERT INTO public.movimientos_contenedores (
                    cliente_id,
                    orden_id,
                    contenedor_id,
                    cantidad_entregada,
                    cantidad_retirada,
                    saldo_anterior,
                    saldo_actual,
                    created_at
                ) VALUES (
                    p_cliente_id,
                    v_orden_id,
                    v_cont_id,
                    v_cant_entregada,
                    v_cant_retirada,
                    v_saldo_ant,
                    v_saldo_act,
                    NOW()
                );

                -- Actualización del saldo acumulado del cliente
                INSERT INTO public.saldo_contenedores_clientes (
                    cliente_id,
                    contenedor_id,
                    saldo_pendiente,
                    updated_at
                ) VALUES (
                    p_cliente_id,
                    v_cont_id,
                    v_saldo_act,
                    NOW()
                )
                ON CONFLICT (cliente_id, contenedor_id)
                DO UPDATE SET
                    saldo_pendiente = EXCLUDED.saldo_pendiente,
                    updated_at = NOW();
            END IF;
        END LOOP;
    END IF;

    -- 7. Respuesta exitosa
    RETURN jsonb_build_object(
        'success', true,
        'message', 'Venta en ruta (AutoVenta) registrada exitosamente con descuentos aplicados.',
        'data', jsonb_build_object(
            'orden_id', v_orden_id,
            'correlativo', v_correlativo,
            'factura_origen_numero', v_factura_origen,
            'cliente_id', p_cliente_id,
            'camion_id', p_camion_id,
            'total_recaudar_usd', v_total_recaudar_usd,
            'total_recaudar_bs', v_total_recaudar_bs,
            'tasa_cambio', v_tasa_cambio,
            'peso_total_kg', v_peso_total,
            'estado', 'por_liquidar'
        )
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'Error interno al registrar la AutoVenta: ' || SQLERRM,
            'error_detail', SQLSTATE
        );
END;
$$;

GRANT EXECUTE ON FUNCTION public.registrar_venta_en_ruta_autoventa(UUID, UUID, UUID, JSONB, JSONB, TEXT, NUMERIC, BOOLEAN) TO authenticated, service_role;

-- ------------------------------------------------------------------------------
-- 6. registrar_despacho_cliente_radar (Preservando saldos a favor)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.registrar_despacho_cliente_radar(
    p_orden_id UUID,
    p_detalles_json JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_estado_orden TEXT;
    v_camion_id UUID;
    v_radar_id UUID;
    v_status_radar BOOLEAN;
    v_item JSONB;
    v_detalle_id UUID;
    v_cantidad_despachada INT;
    v_estado_entrega TEXT;
    v_motivo_rechazo TEXT;
    v_contenedores_retirados INT;
    v_contenedor_id UUID;
    v_producto_id UUID;
    v_cantidad_solicitada INT;
    v_devolucion INT;
    v_pendientes_count INT;
    v_total_despachado INT := 0;
    v_cliente_id UUID;
    v_despacho_permitido BOOLEAN;
    v_excepcion_gerencia BOOLEAN;
    v_nuevo_estado_orden TEXT;

    -- Variables para procesamiento y resumen de saldos de contenedores
    v_rec_prev RECORD;
    v_rec_cont RECORD;
    v_saldo_previo INT;
    v_saldo_nuevo INT;
    v_cant_entregada INT;
    v_cant_retirada INT;
    v_contenedores_resumen JSONB := '[]'::JSONB;
BEGIN
    IF p_orden_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El parámetro p_orden_id es obligatorio.'
            )
        );
    END IF;

    -- Obtener información de la orden, cliente y radar asociado
    SELECT o.estado, o.camion_id, o.cliente_id, o.radar_id,
           COALESCE(c.excepcion_despacho_gerencia, FALSE),
           TRUE
    INTO v_estado_orden, v_camion_id, v_cliente_id, v_radar_id, v_excepcion_gerencia, v_despacho_permitido
    FROM public.ordenes_distribucion o
    JOIN public.clientes c ON o.cliente_id = c.id
    WHERE o.id = p_orden_id;

    v_despacho_permitido := TRUE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'ORDEN_INEXISTENTE',
                'message', 'No se encontró la orden especificada.'
            )
        );
    END IF;

    IF v_radar_id IS NOT NULL THEN
        SELECT COALESCE(status_radar, FALSE)
        INTO v_status_radar
        FROM public.radars
        WHERE id = v_radar_id;

        IF v_status_radar = TRUE THEN
            RETURN jsonb_build_object(
                'success', FALSE,
                'error', jsonb_build_object(
                    'code', 'RADAR_APROBADO_BLOQUEADO',
                    'message', 'El radar correspondiente ya ha sido aprobado por la Gerencia y se encuentra bloqueado para modificaciones.'
                )
            );
        END IF;
    END IF;

    IF NOT v_despacho_permitido THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'DESPACHO_BLOQUEADO_CREDITO',
                'message', 'El despacho no está permitido debido a restricciones de crédito del cliente.'
            )
        );
    END IF;

    IF v_estado_orden NOT IN ('en_transito', 'despachada', 'por_liquidar') THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo se pueden registrar despachos para órdenes en tránsito, despachadas o por liquidar.',
                'details', 'Estado actual: ' || v_estado_orden
            )
        );
    END IF;

    -- Actualizar detalle de la orden e inventario móvil
    IF p_detalles_json IS NOT NULL THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(p_detalles_json)
        LOOP
            v_detalle_id := (v_item->>'detalle_id')::UUID;
            v_cantidad_despachada := (v_item->>'cantidad_despachada')::INT;
            v_estado_entrega := v_item->>'estado_entrega';
            v_motivo_rechazo := v_item->>'motivo_rechazo';
            v_contenedores_retirados := COALESCE((v_item->>'contenedores_retirados')::INT, 0);
            v_contenedor_id := (v_item->>'contenedor_id')::UUID;

            SELECT producto_id, cantidad_solicitada INTO v_producto_id, v_cantidad_solicitada
            FROM public.detalle_distribucion
            WHERE id = v_detalle_id AND orden_id = p_orden_id;

            IF FOUND THEN
                v_devolucion := GREATEST(0, v_cantidad_solicitada - v_cantidad_despachada);

                IF v_camion_id IS NOT NULL THEN
                    UPDATE public.inventario_movil
                    SET cantidad_entregada = cantidad_entregada + v_cantidad_despachada,
                        cantidad_devolucion = cantidad_devolucion + v_devolucion,
                        updated_at = NOW()
                    WHERE camion_id = v_camion_id AND producto_id = v_producto_id;
                END IF;

                UPDATE public.detalle_distribucion
                SET cantidad_despachada = v_cantidad_despachada,
                    estado_entrega = COALESCE(v_estado_entrega, CASE WHEN v_cantidad_despachada > 0 THEN 'entregado' ELSE 'rechazado' END),
                    motivo_rechazo = v_motivo_rechazo,
                    contenedores_retirados = v_contenedores_retirados,
                    contenedor_id = v_contenedor_id
                WHERE id = v_detalle_id;
            END IF;
        END LOOP;
    END IF;

    -- ASIENTO DE SALDOS DE CONTENEDORES
    -- 1. Reversar movimientos previos registrados para esta orden
    FOR v_rec_prev IN
        SELECT contenedor_id, cantidad_entregada, cantidad_retirada
        FROM public.movimientos_contenedores
        WHERE orden_id = p_orden_id
    LOOP
        UPDATE public.saldo_contenedores_clientes
        SET saldo_pendiente = saldo_pendiente - v_rec_prev.cantidad_entregada + v_rec_prev.cantidad_retirada,
            updated_at = NOW()
        WHERE cliente_id = v_cliente_id AND contenedor_id = v_rec_prev.contenedor_id;
    END LOOP;

    DELETE FROM public.movimientos_contenedores WHERE orden_id = p_orden_id;

    -- 2. Calcular entregas y retiros por tipo de contenedor asignado
    FOR v_rec_cont IN
        SELECT 
            COALESCE(d.contenedor_id, p.contenedor_id) AS contenedor_id,
            SUM(
                CASE 
                    WHEN COALESCE(d.contenedor_id, p.contenedor_id) IS NOT NULL AND COALESCE(d.cantidad_despachada, 0) > 0 THEN
                        CEIL(COALESCE(d.cantidad_despachada, 0)::numeric / GREATEST(COALESCE(p.unidades_por_contenedor, 1)::numeric, 1))
                    ELSE 0
                END
            )::INT AS total_entregados,
            SUM(COALESCE(d.contenedores_retirados, 0))::INT AS total_retirados
        FROM public.detalle_distribucion d
        LEFT JOIN public.productos p ON p.id = d.producto_id
        WHERE d.orden_id = p_orden_id
          AND COALESCE(d.contenedor_id, p.contenedor_id) IS NOT NULL
        GROUP BY COALESCE(d.contenedor_id, p.contenedor_id)
    LOOP
        v_cant_entregada := v_rec_cont.total_entregados;
        v_cant_retirada := v_rec_cont.total_retirados;

        IF v_cant_entregada > 0 OR v_cant_retirada > 0 THEN
            SELECT COALESCE(saldo_pendiente, 0)
            INTO v_saldo_previo
            FROM public.saldo_contenedores_clientes
            WHERE cliente_id = v_cliente_id AND contenedor_id = v_rec_cont.contenedor_id;

            IF NOT FOUND THEN
                v_saldo_previo := 0;
            END IF;

            -- Permite saldos negativos sin GREATEST(0, ...)
            v_saldo_nuevo := v_saldo_previo + v_cant_entregada - v_cant_retirada;

            -- Registrar movimiento individual
            INSERT INTO public.movimientos_contenedores (
                cliente_id, orden_id, contenedor_id, cantidad_entregada, cantidad_retirada, creado_por, saldo_anterior, saldo_actual
            ) VALUES (
                v_cliente_id, p_orden_id, v_rec_cont.contenedor_id, v_cant_entregada, v_cant_retirada, auth.uid(), v_saldo_previo, v_saldo_nuevo
            );

            -- Upsert del saldo del cliente
            INSERT INTO public.saldo_contenedores_clientes (
                cliente_id, contenedor_id, saldo_pendiente, updated_at
            ) VALUES (
                v_cliente_id, v_rec_cont.contenedor_id, v_saldo_nuevo, NOW()
            )
            ON CONFLICT (cliente_id, contenedor_id)
            DO UPDATE SET
                saldo_pendiente = EXCLUDED.saldo_pendiente,
                updated_at = NOW();

            -- Construir resumen para el Frontend
            v_contenedores_resumen := v_contenedores_resumen || jsonb_build_object(
                'contenedor_id', v_rec_cont.contenedor_id,
                'saldo_anterior', v_saldo_previo,
                'cantidad_entregada', v_cant_entregada,
                'cantidad_retirada', v_cant_retirada,
                'saldo_actualizado', v_saldo_nuevo
            );
        END IF;
    END LOOP;

    -- Validar si quedan ítems pendientes en la orden
    SELECT COUNT(*) INTO v_pendientes_count
    FROM public.detalle_distribucion
    WHERE orden_id = p_orden_id AND (estado_entrega IS NULL OR estado_entrega = 'pendiente');

    IF v_pendientes_count = 0 THEN
        SELECT COALESCE(SUM(cantidad_despachada), 0) INTO v_total_despachado
        FROM public.detalle_distribucion
        WHERE orden_id = p_orden_id;

        IF v_total_despachado = 0 THEN
            v_nuevo_estado_orden := 'devuelta';
        ELSE
            v_nuevo_estado_orden := 'por_liquidar';
        END IF;

        UPDATE public.ordenes_distribucion
        SET estado = v_nuevo_estado_orden
        WHERE id = p_orden_id;

        IF v_excepcion_gerencia THEN
            UPDATE public.clientes
            SET excepcion_despacho_gerencia = FALSE
            WHERE id = v_cliente_id;
        END IF;
    ELSE
        v_nuevo_estado_orden := v_estado_orden;
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Despacho registrado en radar exitosamente.',
        'data', jsonb_build_object(
            'orden_id', p_orden_id,
            'nuevo_estado', v_nuevo_estado_orden,
            'total_despachado', v_total_despachado,
            'contenedores_resumen', v_contenedores_resumen
        ),
        'error', NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', SQLSTATE,
                'message', SQLERRM
            )
        );
END;
$$;

ALTER FUNCTION public.registrar_despacho_cliente_radar(UUID, JSONB) OWNER TO postgres;
GRANT ALL ON FUNCTION public.registrar_despacho_cliente_radar(UUID, JSONB) TO authenticated, service_role;

-- ------------------------------------------------------------------------------
-- 7. retorna_saldo_contenedores_segun_clientes (Listar saldos <> 0)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.retorna_saldo_contenedores_segun_clientes(
    p_cliente_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSONB;
BEGIN
    IF p_cliente_id IS NULL THEN
        -- Retornar todos los clientes que poseen saldo pendiente o saldo a favor (<> 0)
        SELECT jsonb_build_object(
            'success', TRUE,
            'data', COALESCE(jsonb_agg(
                jsonb_build_object(
                    'cliente_id', s.cliente_id,
                    'rif_nit', c.rif_nit,
                    'razon_social', c.razon_social,
                    'contenedor_id', s.contenedor_id,
                    'codigo_contenedor', t.codigo,
                    'nombre_contenedor', t.nombre,
                    'saldo_pendiente', s.saldo_pendiente,
                    'updated_at', s.updated_at
                ) ORDER BY c.razon_social, t.nombre
            ), '[]'::jsonb),
            'error', NULL
        ) INTO v_result
        FROM public.saldo_contenedores_clientes s
        JOIN public.clientes c ON s.cliente_id = c.id
        JOIN public.tipos_contenedores t ON s.contenedor_id = t.id
        WHERE s.saldo_pendiente <> 0;
    ELSE
        -- Retornar el saldo del cliente especificado
        IF EXISTS (
            SELECT 1 FROM public.saldo_contenedores_clientes WHERE cliente_id = p_cliente_id
        ) THEN
            SELECT jsonb_build_object(
                'success', TRUE,
                'data', COALESCE(jsonb_agg(
                    jsonb_build_object(
                        'cliente_id', s.cliente_id,
                        'rif_nit', c.rif_nit,
                        'razon_social', c.razon_social,
                        'contenedor_id', s.contenedor_id,
                        'codigo_contenedor', t.codigo,
                        'nombre_contenedor', t.nombre,
                        'saldo_pendiente', s.saldo_pendiente,
                        'updated_at', s.updated_at
                    ) ORDER BY t.nombre
                ), '[]'::jsonb),
                'error', NULL
            ) INTO v_result
            FROM public.saldo_contenedores_clientes s
            JOIN public.clientes c ON s.cliente_id = c.id
            JOIN public.tipos_contenedores t ON s.contenedor_id = t.id
            WHERE s.cliente_id = p_cliente_id;
        ELSE
            SELECT jsonb_build_object(
                'success', TRUE,
                'data', COALESCE(jsonb_agg(
                    jsonb_build_object(
                        'cliente_id', p_cliente_id,
                        'rif_nit', (SELECT rif_nit FROM public.clientes WHERE id = p_cliente_id),
                        'razon_social', (SELECT razon_social FROM public.clientes WHERE id = p_cliente_id),
                        'contenedor_id', t.id,
                        'codigo_contenedor', t.codigo,
                        'nombre_contenedor', t.nombre,
                        'saldo_pendiente', 0,
                        'updated_at', NULL
                    ) ORDER BY t.nombre
                ), '[]'::jsonb),
                'error', NULL
            ) INTO v_result
            FROM public.tipos_contenedores t;
        END IF;
    END IF;

    RETURN v_result;
END;
$$;
