-- ==============================================================================
-- Parche Idempotente: Control estricto de estado de camiones (solo en carga y descarga)
-- Fecha: 2026-10-22 12:55:00
-- Descripción:
-- 1. liquidar_orden_distribucion: Se elimina el UPDATE public.camiones SET estado = 'disponible'
--    para evitar que la liquidación financiera de una orden libere prematuramente un camión
--    que sigue en ruta o aún tiene mercancía a bordo.
-- 2. actualizar_estado_orden_distribucion: Se elimina el UPDATE public.camiones SET estado = 'disponible'
--    en las transiciones a 'liquidada' y 'anulada'.
-- 3. retorna_inventario_no_despachado_para_almacen: Al descargar el inventario del radar y devolver
--    el sobrante al almacén principal, libera el inventario móvil del camión y pasa su estado
--    a 'disponible' (si no tiene otro radar activo en tránsito).
-- 4. solicita_reversar_carga_inventario_movil_a_almacen: Al reversar/descargar la carga del
--    camión al almacén, cambia el estado del camión a 'disponible' (en lugar de 'asignado',
--    valor que además no estaba permitido en camiones_estado_check).
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Función: liquidar_orden_distribucion (Sin liberar el camión al liquidar orden)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.liquidar_orden_distribucion(p_orden_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_estado_orden TEXT;
    v_cliente_id UUID;
    v_camion_id UUID;
    v_subtotal_recaudar NUMERIC(12, 2) := 0.00;
    v_total_abonos_aprobados NUMERIC(12, 2) := 0.00;
BEGIN
    IF p_orden_id IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID de la orden es requerido.'
            )
        );
    END IF;

    SELECT estado, cliente_id, camion_id, COALESCE(total_recaudar_usd, 0.00)
    INTO v_estado_orden, v_cliente_id, v_camion_id, v_subtotal_recaudar
    FROM public.ordenes_distribucion
    WHERE id = p_orden_id;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'ORDEN_INEXISTENTE',
                'message', 'La orden de distribución especificada no existe.'
            )
        );
    END IF;

    IF v_estado_orden != 'por_liquidar' THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo se pueden evaluar o liquidar financieramente órdenes en estado por_liquidar.'
            )
        );
    END IF;

    SELECT COALESCE(SUM(dro.recaudado), 0.00)
    INTO v_total_abonos_aprobados
    FROM public.detalle_rendicion_ordenes dro
    JOIN public.rendiciones_cuentas rc ON dro.rendicion_id = rc.id
    WHERE dro.orden_distribucion_id = p_orden_id
      AND rc.estado = 'aprobada';

    IF v_total_abonos_aprobados >= v_subtotal_recaudar THEN
        -- NOTA: El camión NO cambia a 'disponible' al liquidar una orden financieramente.
        -- Solo cambia de estado al cargar o descargar inventario del camión.
        UPDATE public.ordenes_distribucion 
        SET estado = 'liquidada' 
        WHERE id = p_orden_id;

        RETURN json_build_object(
            'success', true,
            'data', json_build_object(
                'orden_id', p_orden_id,
                'nuevo_estado', 'liquidada',
                'total_recaudado', v_total_abonos_aprobados,
                'subtotal_recaudar', v_subtotal_recaudar
            ),
            'error', NULL
        );
    ELSE
        RETURN json_build_object(
            'success', true,
            'data', json_build_object(
                'orden_id', p_orden_id,
                'nuevo_estado', 'por_liquidar',
                'total_recaudado', v_total_abonos_aprobados,
                'subtotal_recaudar', v_subtotal_recaudar,
                'saldo_pendiente', (v_subtotal_recaudar - v_total_abonos_aprobados)
            ),
            'error', NULL
        );
    END IF;

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

ALTER FUNCTION public.liquidar_orden_distribucion(uuid) OWNER TO postgres;
GRANT ALL ON FUNCTION public.liquidar_orden_distribucion(uuid) TO authenticated, service_role;


-- ------------------------------------------------------------------------------
-- 2. Función: actualizar_estado_orden_distribucion (Sin liberar camión en liquidada/anulada)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.actualizar_estado_orden_distribucion(p_orden_id uuid, p_estado text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_estado_actual TEXT;
    v_camion_id UUID;
    v_creado_por UUID;
    v_user_id UUID := auth.uid();
    v_item RECORD;
    v_producto_nombre TEXT;
    v_stock_disponible INT;
    v_stock_comprometido INT;
BEGIN
    IF p_orden_id IS NULL THEN
        RAISE EXCEPTION 'El ID de la orden es requerido.';
    END IF;

    IF p_estado IS NULL THEN
        RAISE EXCEPTION 'El estado de destino es requerido.';
    END IF;

    IF p_estado NOT IN ('borrador', 'lista_para_carga', 'en_transito', 'liquidada', 'anulada') THEN
        RAISE EXCEPTION 'El estado % no es un estado válido para la orden.', p_estado;
    END IF;

    SELECT estado, camion_id, creado_por 
    INTO v_estado_actual, v_camion_id, v_creado_por
    FROM public.ordenes_distribucion
    WHERE id = p_orden_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La orden de distribución con ID % no existe.', p_orden_id;
    END IF;

    IF public.user_has_role(ARRAY['vendedor']) AND NOT public.user_has_role(ARRAY['admin', 'gerente', 'despachador']) THEN
        IF v_user_id IS NOT NULL AND v_creado_por IS DISTINCT FROM v_user_id THEN
            RAISE EXCEPTION 'ACCESO_DENEGADO: Un vendedor solo puede modificar las órdenes que ha registrado.';
        END IF;
    END IF;

    IF v_estado_actual = p_estado THEN
        RETURN;
    END IF;

    IF v_estado_actual = 'borrador' AND p_estado NOT IN ('lista_para_carga', 'anulada') THEN
        RAISE EXCEPTION 'Transición no permitida: de % a %.', v_estado_actual, p_estado;
    ELSIF v_estado_actual = 'lista_para_carga' AND p_estado NOT IN ('en_transito', 'borrador', 'anulada') THEN
        RAISE EXCEPTION 'Transición no permitida: de % a %.', v_estado_actual, p_estado;
    ELSIF v_estado_actual = 'en_transito' AND p_estado NOT IN ('liquidada', 'anulada') THEN
        RAISE EXCEPTION 'Transición no permitida: de % a %.', v_estado_actual, p_estado;
    ELSIF v_estado_actual IN ('liquidada', 'anulada') THEN
        RAISE EXCEPTION 'No se pueden realizar cambios de estado en una orden %.', v_estado_actual;
    END IF;

    IF v_estado_actual = 'borrador' AND p_estado = 'lista_para_carga' THEN
        FOR v_item IN 
            SELECT producto_id, cantidad_solicitada 
            FROM public.detalle_distribucion 
            WHERE orden_id = p_orden_id
        LOOP
            SELECT stock_disponible, stock_comprometido 
            INTO v_stock_disponible, v_stock_comprometido
            FROM public.inventario_almacen
            WHERE producto_id = v_item.producto_id
            FOR UPDATE;

            IF NOT FOUND THEN
                SELECT nombre INTO v_producto_nombre FROM public.productos WHERE id = v_item.producto_id;
                RAISE EXCEPTION 'El producto % no tiene un registro de inventario en almacén.', COALESCE(v_producto_nombre, v_item.producto_id::text);
            END IF;

            IF v_stock_disponible < v_item.cantidad_solicitada THEN
                SELECT nombre INTO v_producto_nombre FROM public.productos WHERE id = v_item.producto_id;
                RAISE EXCEPTION 'Stock insuficiente en almacén para el producto % (Disponible: %, Requerido: %).', 
                    COALESCE(v_producto_nombre, v_item.producto_id::text), v_stock_disponible, v_item.cantidad_solicitada;
            END IF;

            UPDATE public.inventario_almacen
            SET stock_disponible = stock_disponible - v_item.cantidad_solicitada,
                stock_comprometido = stock_comprometido + v_item.cantidad_solicitada,
                updated_at = NOW()
            WHERE producto_id = v_item.producto_id;
        END LOOP;

        UPDATE public.ordenes_distribucion
        SET estado = 'lista_para_carga'
        WHERE id = p_orden_id;

    ELSIF v_estado_actual = 'lista_para_carga' AND p_estado = 'borrador' THEN
        FOR v_item IN 
            SELECT producto_id, cantidad_solicitada 
            FROM public.detalle_distribucion 
            WHERE orden_id = p_orden_id
        LOOP
            UPDATE public.inventario_almacen
            SET stock_disponible = stock_disponible + v_item.cantidad_solicitada,
                stock_comprometido = stock_comprometido - v_item.cantidad_solicitada,
                updated_at = NOW()
            WHERE producto_id = v_item.producto_id;
        END LOOP;

        UPDATE public.ordenes_distribucion
        SET estado = 'borrador'
        WHERE id = p_orden_id;

    ELSIF v_estado_actual = 'lista_para_carga' AND p_estado = 'en_transito' THEN
        IF v_camion_id IS NULL THEN
            RAISE EXCEPTION 'No se puede despachar la orden porque no tiene un camión asignado.';
        END IF;

        UPDATE public.camiones
        SET estado = 'en_ruta'
        WHERE id = v_camion_id;

        FOR v_item IN 
            SELECT producto_id, cantidad_solicitada 
            FROM public.detalle_distribucion 
            WHERE orden_id = p_orden_id
        LOOP
            UPDATE public.inventario_almacen
            SET stock_comprometido = stock_comprometido - v_item.cantidad_solicitada,
                updated_at = NOW()
            WHERE producto_id = v_item.producto_id;

            INSERT INTO public.inventario_movil (
                camion_id,
                producto_id,
                cantidad_cargada,
                cantidad_entregada,
                cantidad_devolucion,
                updated_at
            ) VALUES (
                v_camion_id,
                v_item.producto_id,
                v_item.cantidad_solicitada,
                0,
                0,
                NOW()
            )
            ON CONFLICT (camion_id, producto_id) 
            DO UPDATE SET 
                cantidad_cargada = inventario_movil.cantidad_cargada + v_item.cantidad_solicitada,
                updated_at = NOW();

            UPDATE public.detalle_distribucion
            SET cantidad_despachada = v_item.cantidad_solicitada
            WHERE orden_id = p_orden_id AND producto_id = v_item.producto_id;
        END LOOP;

        UPDATE public.ordenes_distribucion
        SET estado = 'en_transito',
            fecha_despacho = NOW()
        WHERE id = p_orden_id;

    ELSIF v_estado_actual = 'en_transito' AND p_estado = 'liquidada' THEN
        -- NOTA: No se cambia el estado del camión a 'disponible' al liquidar una orden individual.

        FOR v_item IN 
            SELECT producto_id, cantidad_despachada, COALESCE(estado_entrega, 'pendiente') as estado_entrega
            FROM public.detalle_distribucion 
            WHERE orden_id = p_orden_id
        LOOP
            IF v_item.estado_entrega IN ('entregado', 'pendiente', 'entregado_parcial') THEN
                UPDATE public.inventario_movil
                SET cantidad_cargada = cantidad_cargada - v_item.cantidad_despachada,
                    cantidad_entregada = cantidad_entregada + v_item.cantidad_despachada,
                    updated_at = NOW()
                WHERE camion_id = v_camion_id AND producto_id = v_item.producto_id;

            ELSIF v_item.estado_entrega = 'rechazado' THEN
                UPDATE public.inventario_movil
                SET cantidad_cargada = cantidad_cargada - v_item.cantidad_despachada,
                    cantidad_devolucion = cantidad_devolucion + v_item.cantidad_despachada,
                    updated_at = NOW()
                WHERE camion_id = v_camion_id AND producto_id = v_item.producto_id;

                UPDATE public.inventario_almacen
                SET stock_disponible = stock_disponible + v_item.cantidad_despachada,
                    updated_at = NOW()
                WHERE producto_id = v_item.producto_id;
            END IF;
        END LOOP;

        UPDATE public.ordenes_distribucion
        SET estado = 'liquidada'
        WHERE id = p_orden_id;

    ELSIF p_estado = 'anulada' THEN
        IF v_estado_actual = 'borrador' THEN
            NULL;

        ELSIF v_estado_actual = 'lista_para_carga' THEN
            FOR v_item IN 
                SELECT producto_id, cantidad_solicitada 
                FROM public.detalle_distribucion 
                WHERE orden_id = p_orden_id
            LOOP
                UPDATE public.inventario_almacen
                SET stock_disponible = stock_disponible + v_item.cantidad_solicitada,
                    stock_comprometido = stock_comprometido - v_item.cantidad_solicitada,
                    updated_at = NOW()
                WHERE producto_id = v_item.producto_id;
            END LOOP;

        ELSIF v_estado_actual = 'en_transito' THEN
            -- NOTA: No se cambia el estado del camión a 'disponible' al anular una orden individual.

            FOR v_item IN 
                SELECT producto_id, cantidad_despachada 
                FROM public.detalle_distribucion 
                WHERE orden_id = p_orden_id
            LOOP
                UPDATE public.inventario_movil
                SET cantidad_cargada = cantidad_cargada - v_item.cantidad_despachada,
                    updated_at = NOW()
                WHERE camion_id = v_camion_id AND producto_id = v_item.producto_id;

                UPDATE public.inventario_almacen
                SET stock_disponible = stock_disponible + v_item.cantidad_despachada,
                    updated_at = NOW()
                WHERE producto_id = v_item.producto_id;
            END LOOP;
        END IF;

        UPDATE public.ordenes_distribucion
        SET estado = 'anulada'
        WHERE id = p_orden_id;
    END IF;

END;
$$;

ALTER FUNCTION public.actualizar_estado_orden_distribucion(uuid, text) OWNER TO postgres;
GRANT ALL ON FUNCTION public.actualizar_estado_orden_distribucion(uuid, text) TO authenticated, service_role;


-- ------------------------------------------------------------------------------
-- 3. Función: retorna_inventario_no_despachado_para_almacen
--    (Descarga de inventario del radar a almacén y liberación del camión a 'disponible')
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.retorna_inventario_no_despachado_para_almacen(p_radar_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_rec RECORD;
    v_camion_id UUID;
    v_detalles JSONB := '[]'::jsonb;
BEGIN
    IF p_radar_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID del radar es requerido.'
            )
        );
    END IF;

    -- Identificar el camión asignado al radar
    SELECT camion_id INTO v_camion_id
    FROM public.ordenes_distribucion
    WHERE radar_id = p_radar_id AND camion_id IS NOT NULL
    LIMIT 1;

    FOR v_rec IN
        SELECT 
            d.producto_id,
            p.codigo_producto,
            p.nombre AS nombre_producto,
            SUM(GREATEST(0, d.cantidad_solicitada - COALESCE(d.cantidad_despachada, 0))) AS total_devuelto,
            MIN(o.camion_id) AS camion_id
        FROM public.ordenes_distribucion o
        JOIN public.detalle_distribucion d ON d.orden_id = o.id
        JOIN public.productos p ON p.id = d.producto_id
        WHERE o.radar_id = p_radar_id
        GROUP BY d.producto_id, p.codigo_producto, p.nombre
        HAVING SUM(GREATEST(0, d.cantidad_solicitada - COALESCE(d.cantidad_despachada, 0))) > 0
    LOOP
        -- 1. Reingresar el stock no despachado al almacén principal (inventario_almacen.stock_disponible)
        INSERT INTO public.inventario_almacen (producto_id, stock_disponible, stock_comprometido, updated_at)
        VALUES (v_rec.producto_id, v_rec.total_devuelto, 0, NOW())
        ON CONFLICT (producto_id)
        DO UPDATE SET 
            stock_disponible = public.inventario_almacen.stock_disponible + v_rec.total_devuelto,
            updated_at = NOW();

        BEGIN
            UPDATE public.productos
            SET stock_disponible = COALESCE(stock_disponible, 0) + v_rec.total_devuelto,
                updated_at = NOW()
            WHERE id = v_rec.producto_id;
        EXCEPTION WHEN OTHERS THEN
            NULL;
        END;

        -- 2. Descontar / rebajar del inventario móvil del camión la mercancía no entregada (devuelta)
        IF v_rec.camion_id IS NOT NULL THEN
            UPDATE public.inventario_movil
            SET cantidad_cargada = GREATEST(0, cantidad_cargada - v_rec.total_devuelto),
                updated_at = NOW()
            WHERE camion_id = v_rec.camion_id AND producto_id = v_rec.producto_id;
        END IF;

        v_detalles := v_detalles || jsonb_build_object(
            'producto_id', v_rec.producto_id,
            'codigo_producto', v_rec.codigo_producto,
            'nombre_producto', v_rec.nombre_producto,
            'cantidad_devuelta', v_rec.total_devuelto
        );
    END LOOP;

    -- 3. Liberar el camión a 'disponible' al finalizar la descarga de la ruta del radar,
    --    siempre que no tenga otro radar activo con órdenes en tránsito.
    IF v_camion_id IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1
            FROM public.ordenes_distribucion
            WHERE camion_id = v_camion_id
              AND radar_id IS DISTINCT FROM p_radar_id
              AND estado = 'en_transito'
        ) THEN
            DELETE FROM public.inventario_movil WHERE camion_id = v_camion_id;

            UPDATE public.camiones
            SET estado = 'disponible'
            WHERE id = v_camion_id AND estado = 'en_ruta';
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Inventario no despachado retornado exitosamente al almacén principal y camión liberado.',
        'data', v_detalles,
        'error', NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', SQLSTATE,
                'message', SQLERRM
            )
        );
END;
$$;

ALTER FUNCTION public.retorna_inventario_no_despachado_para_almacen(uuid) OWNER TO postgres;
GRANT ALL ON FUNCTION public.retorna_inventario_no_despachado_para_almacen(uuid) TO authenticated, service_role;


-- ------------------------------------------------------------------------------
-- 4. Función: solicita_reversar_carga_inventario_movil_a_almacen
--    (Al reversar/descargar la carga del camión al almacén, pasa a 'disponible')
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.solicita_reversar_carga_inventario_movil_a_almacen(
    p_camion_id uuid,
    p_resumen_productos jsonb DEFAULT NULL::jsonb,
    p_radar_id uuid DEFAULT NULL::uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_item JSONB;
    v_items_array JSONB := '[]'::jsonb;
    v_producto_id UUID;
    v_cantidad INT;
    v_total_productos_reversados INT := 0;
    v_unidades_totales INT := 0;
    v_camion_existe BOOLEAN;
    v_radar_id UUID;
    v_carga_inventario BOOLEAN;
    v_entregas_existentes INT := 0;
    v_ordenes_reversadas INT := 0;
    v_rec RECORD;
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
    IF v_radar_id IS NULL THEN
        SELECT radar_id INTO v_radar_id
        FROM public.ordenes_distribucion
        WHERE camion_id = p_camion_id AND radar_id IS NOT NULL
        ORDER BY created_at DESC
        LIMIT 1;
    END IF;

    IF v_radar_id IS NOT NULL THEN
        SELECT COALESCE(carga_inventario_movil, FALSE) INTO v_carga_inventario
        FROM public.radars
        WHERE id = v_radar_id;

        IF NOT v_carga_inventario THEN
            RETURN jsonb_build_object(
                'success', FALSE,
                'data', NULL,
                'error', jsonb_build_object(
                    'code', 'INVENTARIO_NO_CARGADO',
                    'message', 'El inventario móvil de este radar no ha sido cargado previamente o ya fue reversado.'
                )
            );
        END IF;

        SELECT COUNT(*) INTO v_entregas_existentes
        FROM public.ordenes_distribucion
        WHERE radar_id = v_radar_id AND estado IN ('despachada', 'por_liquidar', 'liquidada', 'devuelta');

        IF v_entregas_existentes > 0 THEN
            RETURN jsonb_build_object(
                'success', FALSE,
                'data', NULL,
                'error', jsonb_build_object(
                    'code', 'REVERSO_BLOQUEADO_POR_ENTREGAS',
                    'message', 'No se puede reversar la carga al almacén porque ya existen entregas o despachos registrados en esta ruta.'
                )
            );
        END IF;
    END IF;

    IF p_resumen_productos IS NOT NULL THEN
        IF jsonb_typeof(p_resumen_productos) = 'array' THEN
            v_items_array := p_resumen_productos;
        ELSIF jsonb_typeof(p_resumen_productos) = 'object' AND p_resumen_productos ? 'resumen_productos' THEN
            v_items_array := p_resumen_productos->'resumen_productos';
        END IF;
    END IF;

    IF jsonb_array_length(v_items_array) > 0 THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(v_items_array) LOOP
            v_producto_id := (v_item->>'producto_id')::UUID;
            v_cantidad := COALESCE((v_item->>'cantidad_solicitada')::INT, 0);

            IF v_producto_id IS NOT NULL AND v_cantidad > 0 THEN
                INSERT INTO public.inventario_almacen (producto_id, stock_disponible, stock_comprometido, updated_at)
                VALUES (v_producto_id, v_cantidad, 0, NOW())
                ON CONFLICT (producto_id)
                DO UPDATE SET
                    stock_disponible = public.inventario_almacen.stock_disponible + v_cantidad,
                    updated_at = NOW();

                UPDATE public.inventario_movil
                SET cantidad_cargada = GREATEST(0, cantidad_cargada - v_cantidad),
                    updated_at = NOW()
                WHERE camion_id = p_camion_id AND producto_id = v_producto_id;

                v_total_productos_reversados := v_total_productos_reversados + 1;
                v_unidades_totales := v_unidades_totales + v_cantidad;
            END IF;
        END LOOP;
    ELSE
        FOR v_rec IN 
            SELECT producto_id, cantidad_cargada
            FROM public.inventario_movil
            WHERE camion_id = p_camion_id AND cantidad_cargada > 0
        LOOP
            INSERT INTO public.inventario_almacen (producto_id, stock_disponible, stock_comprometido, updated_at)
            VALUES (v_rec.producto_id, v_rec.cantidad_cargada, 0, NOW())
            ON CONFLICT (producto_id)
            DO UPDATE SET
                stock_disponible = public.inventario_almacen.stock_disponible + v_rec.cantidad_cargada,
                updated_at = NOW();

            UPDATE public.inventario_movil
            SET cantidad_cargada = 0,
                updated_at = NOW()
            WHERE camion_id = p_camion_id AND producto_id = v_rec.producto_id;

            v_total_productos_reversados := v_total_productos_reversados + 1;
            v_unidades_totales := v_unidades_totales + v_rec.cantidad_cargada;
        END LOOP;
    END IF;

    IF v_radar_id IS NOT NULL THEN
        UPDATE public.ordenes_distribucion
        SET estado = 'aprobada'
        WHERE radar_id = v_radar_id AND estado = 'en_transito';

        GET DIAGNOSTICS v_ordenes_reversadas = ROW_COUNT;
    ELSE
        UPDATE public.ordenes_distribucion
        SET estado = 'aprobada'
        WHERE camion_id = p_camion_id AND estado = 'en_transito';

        GET DIAGNOSTICS v_ordenes_reversadas = ROW_COUNT;
    END IF;

    IF v_radar_id IS NOT NULL THEN
        UPDATE public.detalle_distribucion dd
        SET cantidad_despachada = 0
        FROM public.ordenes_distribucion od
        WHERE dd.orden_id = od.id AND od.radar_id = v_radar_id;
    ELSE
        UPDATE public.detalle_distribucion dd
        SET cantidad_despachada = 0
        FROM public.ordenes_distribucion od
        WHERE dd.orden_id = od.id AND od.camion_id = p_camion_id;
    END IF;

    -- El camión vuelve a 'disponible' al descargarse su inventario móvil
    UPDATE public.camiones
    SET estado = 'disponible'
    WHERE id = p_camion_id;

    -- Actualizar radars (sin updated_at)
    IF v_radar_id IS NOT NULL THEN
        UPDATE public.radars
        SET carga_inventario_movil = FALSE
        WHERE id = v_radar_id;
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Reverso de inventario móvil al almacén procesado exitosamente.',
        'data', jsonb_build_object(
            'camion_id', p_camion_id,
            'radar_id', v_radar_id,
            'carga_inventario_movil', FALSE,
            'total_productos_reversados', v_total_productos_reversados,
            'unidades_totales', v_unidades_totales,
            'ordenes_reversadas', v_ordenes_reversadas
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

ALTER FUNCTION public.solicita_reversar_carga_inventario_movil_a_almacen(uuid, jsonb, uuid) OWNER TO postgres;
GRANT ALL ON FUNCTION public.solicita_reversar_carga_inventario_movil_a_almacen(uuid, jsonb, uuid) TO authenticated, service_role;
