-- ==============================================================================
-- Parche Idempotente: Anular Despacho, Edición con Recálculo y Generar Despacho
--                     desde Almacén (Solo Gerencia/Admin) con Auditoría
-- Fecha: 2026-11-12 13:35:00
-- Descripción:
--   1. Actualiza `public.reversar_entrega_orden_distribucion(p_orden_id, p_motivo)`:
--      - Restringe su ejecución exclusivamente a roles `gerente` y `admin`.
--      - Permite anular el despacho incluso cuando el radar ya fue aprobado (`status_radar = TRUE`).
--      - Valida que la orden NO esté en estado `liquidada` (en cuyo caso exige reversar la cobranza),
--        pero NO exige reversar abonos parciales si la orden está en `por_liquidar`.
--      - La mercancía despachada reingresa directamente a `public.inventario_almacen` (`stock_disponible`).
--      - La orden regresa a estado `aprobada` para permitir su edición.
--      - Registra traza detallada en `public.logs_auditoria` (`accion = 'ANULAR_DESPACHO'`).
--   2. Actualiza `public.actualiza_orden_distribucion_segun_correlativo(p_correlativo, p_header, p_detalle)`:
--      - En órdenes con despacho previo/radar o abonos, restringe la edición solo a `gerente` y `admin`.
--      - Permite modificar libremente el precio unitario USD (> 0) y la cantidad a despachar,
--        recalculando descuentos, subtotales USD/Bs, `total_recaudar_usd`, `total_recaudar_bs` y peso.
--      - Preserva envases retirados previos de las líneas y registra auditoría en `public.logs_auditoria`
--        (`accion = 'EDITAR_ORDEN'`).
--   3. Crea `public.generar_despacho_orden_almacen(p_orden_id, p_observaciones)`:
--      - Exclusivo para `gerente` y `admin`.
--      - Toma una orden en estado `aprobada`, valida y descuenta de `public.inventario_almacen`
--        (`stock_disponible`) las cantidades a despachar.
--      - Marca las líneas como entregadas (`cantidad_despachada = cantidad_solicitada`, `estado_entrega = 'entregado'`).
--      - Asienta envases en `movimientos_contenedores` y `saldo_contenedores_clientes`.
--      - Pasa la orden a `por_liquidar` y ejecuta `liquidar_orden_distribucion` respetando abonos previos.
--      - Sincroniza totales del radar (incluso si ya estaba aprobado) y registra en `public.logs_auditoria`
--        (`accion = 'GENERAR_DESPACHO_ALMACEN'`).
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Función: public.reversar_entrega_orden_distribucion (Anular el Despacho)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reversar_entrega_orden_distribucion(
    p_orden_id UUID,
    p_motivo TEXT DEFAULT NULL
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
    v_mov_cont RECORD;
    v_status_radar BOOLEAN := FALSE;
    v_carga_inventario_radar BOOLEAN := FALSE;
    v_origen_orden TEXT;
    v_nuevo_estado TEXT := 'aprobada';
    v_cant_desp INT;
    v_cant_dev INT;
    v_saldo_act INT;
    v_nuevo_saldo INT;
    v_tot_solicitada NUMERIC(10,0);
    v_tot_despachada NUMERIC(10,0);
    v_tot_retirados NUMERIC(10,0);
    v_mercancia_reintegrada JSONB := '[]'::jsonb;
    v_valores_anteriores JSONB;
    v_valores_nuevos JSONB;
    v_detalles_previos JSONB;
    v_contenedores_previos JSONB;
BEGIN
    -- 1. Validar sesión activa
    IF v_usuario_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'NO_AUTENTICADO',
                'message', 'Debes iniciar sesión para anular el despacho de una orden.'
            )
        );
    END IF;

    -- 2. Validar rol: exclusivo para Gerencia y Administración
    v_rol := public.lt_current_user_rol();
    v_es_gerencia := COALESCE(public.user_has_role(ARRAY['admin', 'gerente']), FALSE)
                     OR COALESCE(v_rol, '') IN ('admin', 'gerente');

    IF NOT v_es_gerencia THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'ACCESO_DENEGADO',
                'message', 'Permiso denegado: solo la Gerencia o Administración puede anular el despacho de una orden.'
            )
        );
    END IF;

    -- 3. Validar parámetro obligatorio
    IF p_orden_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID de la orden es obligatorio.'
            )
        );
    END IF;

    -- 4. Bloquear orden a procesar
    SELECT * INTO v_orden
    FROM public.ordenes_distribucion
    WHERE id = p_orden_id
    FOR UPDATE;

    IF v_orden.id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'ORDEN_NO_ENCONTRADA',
                'message', 'La orden de distribución especificada no existe.'
            )
        );
    END IF;

    -- 5. Bloquear si es registro de saldo inicial CxC
    IF COALESCE(v_orden.es_saldo_inicial, FALSE) = TRUE THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'ORDEN_SALDO_INICIAL',
                'message', 'No se puede anular el despacho sobre un registro de saldo inicial de cuentas por cobrar.'
            )
        );
    END IF;

    -- 6. Bloquear si la orden ya se encuentra LIQUIDADA (debe reversar la cobranza primero)
    IF v_orden.estado = 'liquidada' THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'ORDEN_LIQUIDADA',
                'message', 'La orden se encuentra liquidada. Para poder anular su despacho y modificarla, primero debe reversar la cobranza asociada.'
            )
        );
    END IF;

    -- 7. Validar que la orden tenga un despacho procesado susceptible de anulación
    IF v_orden.estado NOT IN ('por_liquidar', 'despachada', 'devuelta') THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo se puede anular el despacho de órdenes entregadas (en estado por_liquidar, despachada o devuelta). Estado actual: ' || COALESCE(v_orden.estado, 'desconocido')
            )
        );
    END IF;

    -- NOTA DE NEGOCIO: Si la orden está en 'por_liquidar' y posee abonos parciales en
    -- detalle_rendicion_ordenes, NO hace falta reversar el abono; este se conserva intacto.
    -- Asimismo, se permite anular el despacho aunque el radar asociado ya esté aprobado (status_radar = TRUE).

    IF v_orden.radar_id IS NOT NULL THEN
        SELECT COALESCE(status_radar, FALSE), COALESCE(carga_inventario_movil, FALSE)
        INTO v_status_radar, v_carga_inventario_radar
        FROM public.radars
        WHERE id = v_orden.radar_id;
    END IF;

    v_origen_orden := CASE
        WHEN v_orden.origen_venta = 'ALMACEN' OR (v_orden.camion_id IS NULL AND COALESCE(v_orden.es_autoventa, FALSE) = FALSE) THEN 'VENTA_DIRECTA_ALMACEN'
        WHEN COALESCE(v_orden.es_autoventa, FALSE) = TRUE THEN 'AUTOVENTA'
        WHEN v_orden.radar_id IS NOT NULL THEN 'RADAR'
        ELSE 'RUTA'
    END;

    -- 8. Capturar estado previo para auditoría en logs_auditoria
    SELECT COALESCE(jsonb_agg(to_jsonb(d)), '[]'::jsonb)
    INTO v_detalles_previos
    FROM public.detalle_distribucion d
    WHERE d.orden_id = p_orden_id;

    SELECT COALESCE(jsonb_agg(to_jsonb(mc)), '[]'::jsonb)
    INTO v_contenedores_previos
    FROM public.movimientos_contenedores mc
    WHERE mc.orden_id = p_orden_id;

    v_valores_anteriores := jsonb_build_object(
        'correlativo', v_orden.correlativo,
        'estado_orden', v_orden.estado,
        'origen_venta', v_orden.origen_venta,
        'es_autoventa', COALESCE(v_orden.es_autoventa, FALSE),
        'radar_id', v_orden.radar_id,
        'status_radar', v_status_radar,
        'camion_id', v_orden.camion_id,
        'total_recaudar_usd', v_orden.total_recaudar_usd,
        'total_recaudar_bs', v_orden.total_recaudar_bs,
        'detalles', v_detalles_previos,
        'movimientos_contenedores', v_contenedores_previos
    );

    -- 9. Reintegrar la mercancía despachada directamente al inventario_almacen
    FOR v_det IN
        SELECT d.producto_id,
               p.nombre AS producto_nombre,
               COALESCE(d.cantidad_solicitada, 0) AS cant_sol,
               COALESCE(d.cantidad_despachada, d.cantidad_solicitada, 0) AS cant_desp,
               COALESCE(d.estado_entrega, 'pendiente') AS est_entrega
        FROM public.detalle_distribucion d
        LEFT JOIN public.productos p ON p.id = d.producto_id
        WHERE d.orden_id = p_orden_id
    LOOP
        v_cant_desp := CASE
            WHEN v_orden.origen_venta = 'ALMACEN' OR COALESCE(v_orden.es_autoventa, FALSE) = TRUE THEN GREATEST(0, v_det.cant_desp)
            WHEN v_det.est_entrega <> 'pendiente' THEN GREATEST(0, v_det.cant_desp)
            ELSE 0
        END;
        v_cant_dev := GREATEST(0, v_det.cant_sol - v_cant_desp);

        -- La mercancía despachada entra a inventario_almacen
        IF v_cant_desp > 0 THEN
            INSERT INTO public.inventario_almacen (
                producto_id,
                stock_disponible,
                stock_comprometido,
                updated_at
            ) VALUES (
                v_det.producto_id,
                v_cant_desp,
                0,
                NOW()
            )
            ON CONFLICT (producto_id)
            DO UPDATE SET
                stock_disponible = public.inventario_almacen.stock_disponible + EXCLUDED.stock_disponible,
                updated_at = NOW();

            v_mercancia_reintegrada := v_mercancia_reintegrada || jsonb_build_array(
                jsonb_build_object(
                    'producto_id', v_det.producto_id,
                    'producto_nombre', v_det.producto_nombre,
                    'cantidad_reintegrada_almacen', v_cant_desp
                )
            );
        END IF;

        -- Si el radar aún estaba abierto (no había retornado inventario_movil al almacén)
        -- o era una autoventa activa en camión, ajustar inventario_movil para evitar duplicidad al descargar camión
        IF v_orden.camion_id IS NOT NULL THEN
            IF COALESCE(v_orden.es_autoventa, FALSE) = TRUE THEN
                UPDATE public.inventario_movil
                SET cantidad_entregada = GREATEST(0, COALESCE(cantidad_entregada, 0) - v_cant_desp),
                    cantidad_cargada = GREATEST(0, COALESCE(cantidad_cargada, 0) - v_cant_desp),
                    updated_at = NOW()
                WHERE camion_id = v_orden.camion_id AND producto_id = v_det.producto_id;
            ELSIF v_orden.radar_id IS NOT NULL AND v_status_radar = FALSE AND v_carga_inventario_radar = TRUE THEN
                -- Si además había devolución parcial aún en el camión de un radar abierto, regresarla a almacén y descontar carga del camión
                IF v_cant_dev > 0 THEN
                    UPDATE public.inventario_almacen
                    SET stock_disponible = stock_disponible + v_cant_dev,
                        updated_at = NOW()
                    WHERE producto_id = v_det.producto_id;
                END IF;

                UPDATE public.inventario_movil
                SET cantidad_entregada = GREATEST(0, COALESCE(cantidad_entregada, 0) - v_cant_desp),
                    cantidad_devolucion = GREATEST(0, COALESCE(cantidad_devolucion, 0) - v_cant_dev),
                    cantidad_cargada = GREATEST(0, COALESCE(cantidad_cargada, 0) - v_det.cant_sol),
                    updated_at = NOW()
                WHERE camion_id = v_orden.camion_id AND producto_id = v_det.producto_id;
            END IF;
        END IF;
    END LOOP;

    -- Dejar las líneas en estado pendiente para edición (conservando contenedores_retirados y contenedor_id)
    UPDATE public.detalle_distribucion
    SET cantidad_despachada = 0,
        estado_entrega = 'pendiente',
        motivo_rechazo = NULL
    WHERE orden_id = p_orden_id;

    -- 10. Revertir movimientos y saldos de contenedores de la entrega
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

    -- 11. Actualizar estado de la Orden de Distribución a 'aprobada' para permitir su edición
    UPDATE public.ordenes_distribucion
    SET estado = v_nuevo_estado,
        observaciones = COALESCE(observaciones, '') ||
                        ' [DESPACHO ANULADO el ' || TO_CHAR(NOW(), 'YYYY-MM-DD HH24:MI:SS') ||
                        CASE WHEN p_motivo IS NOT NULL AND TRIM(p_motivo) <> '' THEN ' - Motivo: ' || TRIM(p_motivo) ELSE '' END || ']'
    WHERE id = p_orden_id;

    -- 12. Si pertenece a un radar, recalcular totales del radar
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

    -- 13. Registrar evento explícito en public.logs_auditoria
    v_valores_nuevos := jsonb_build_object(
        'correlativo', v_orden.correlativo,
        'estado_orden', v_nuevo_estado,
        'origen_detectado', v_origen_orden,
        'status_radar', v_status_radar,
        'mercancia_reintegrada_almacen', v_mercancia_reintegrada,
        'motivo_anulacion_despacho', NULLIF(TRIM(COALESCE(p_motivo, '')), ''),
        'ejecutado_por', v_usuario_id,
        'rol_ejecutor', v_rol,
        'fecha_anulacion_despacho', NOW()
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
        'ANULAR_DESPACHO',
        p_orden_id,
        v_valores_anteriores,
        v_valores_nuevos,
        NOW()
    );

    RETURN jsonb_build_object(
        'success', true,
        'message', 'Despacho anulado exitosamente. La mercancía ingresó al inventario de almacén y la orden pasó a estado aprobada para su edición.',
        'data', jsonb_build_object(
            'orden_id', p_orden_id,
            'correlativo', v_orden.correlativo,
            'origen_orden', v_origen_orden,
            'estado_anterior', v_orden.estado,
            'estado_nuevo', v_nuevo_estado,
            'mercancia_reintegrada_almacen', v_mercancia_reintegrada
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

REVOKE ALL ON FUNCTION public.reversar_entrega_orden_distribucion(UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reversar_entrega_orden_distribucion(UUID, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.reversar_entrega_orden_distribucion(UUID, TEXT) TO authenticated, service_role;

COMMENT ON FUNCTION public.reversar_entrega_orden_distribucion(UUID, TEXT) IS
    'Anula el despacho de una orden entregada (exclusivo Gerencia/Admin), reintegrando la mercancía a inventario_almacen, revirtiendo envases, conservando abonos parciales, regresando la orden a estado aprobada incluso con radar aprobado y dejando traza en logs_auditoria.';


-- ------------------------------------------------------------------------------
-- 2. Función: public.actualiza_orden_distribucion_segun_correlativo
--    Permite modificar precios unitarios y cantidades a despachar, recalcula
--    totales USD/Bs/descuentos, preserva envases retirados y registra auditoría.
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
    v_secuencia INT := 1;
    v_producto_id UUID;
    v_cantidad INT;
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

    -- Si la orden proviene de un radar, tuvo despacho anulado o tiene abonos, solo Gerencia/Admin puede editarla
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

    -- 7. Reemplazar detalle y recalcular totales con los nuevos precios y cantidades
    IF p_detalle IS NOT NULL AND jsonb_array_length(p_detalle) > 0 THEN
        DELETE FROM public.detalle_distribucion WHERE orden_id = v_orden.id;

        FOR v_item IN SELECT * FROM jsonb_array_elements(p_detalle) LOOP
            v_producto_id := (v_item->>'producto_id')::UUID;
            v_cantidad := COALESCE((v_item->>'cantidad_solicitada')::INT, (v_item->>'cantidad')::INT, 0);

            IF v_cantidad <= 0 THEN
                RAISE EXCEPTION 'La cantidad solicitada para cada producto debe ser mayor a cero.';
            END IF;

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

GRANT EXECUTE ON FUNCTION public.actualiza_orden_distribucion_segun_correlativo(INT, JSONB, JSONB) TO authenticated, service_role;


-- ------------------------------------------------------------------------------
-- 3. Función: public.generar_despacho_orden_almacen
--    Genera el despacho de una orden en estado 'aprobada' descontando la
--    mercancía directamente de inventario_almacen, asentando envases,
--    respetando abonos previos y registrando en logs_auditoria (Solo Gerencia/Admin).
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
    -- 1. Validar autenticación
    IF v_usuario_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'NO_AUTENTICADO',
                'message', 'Debes iniciar sesión para generar el despacho.'
            )
        );
    END IF;

    -- 2. Validar rol: exclusivo para Gerencia y Administración
    v_rol := public.lt_current_user_rol();
    v_es_gerencia := COALESCE(public.user_has_role(ARRAY['admin', 'gerente']), FALSE)
                     OR COALESCE(v_rol, '') IN ('admin', 'gerente');

    IF NOT v_es_gerencia THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'ACCESO_DENEGADO',
                'message', 'Permiso denegado: solo la Gerencia o Administración puede generar el despacho directo desde almacén.'
            )
        );
    END IF;

    -- 3. Validar parámetro obligatorio
    IF p_orden_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID de la orden es obligatorio.'
            )
        );
    END IF;

    -- 4. Obtener y bloquear la orden
    SELECT * INTO v_orden
    FROM public.ordenes_distribucion
    WHERE id = p_orden_id
    FOR UPDATE;

    IF v_orden.id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'ORDEN_NO_ENCONTRADA',
                'message', 'La orden de distribución especificada no existe.'
            )
        );
    END IF;

    IF v_orden.estado = 'liquidada' THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'ORDEN_LIQUIDADA',
                'message', 'La orden ya se encuentra liquidada.'
            )
        );
    END IF;

    IF v_orden.estado <> 'aprobada' THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'La orden debe estar en estado aprobada para generar su despacho desde almacén. Estado actual: ' || COALESCE(v_orden.estado, 'desconocido')
            )
        );
    END IF;

    SELECT COUNT(*) INTO v_lineas_count
    FROM public.detalle_distribucion
    WHERE orden_id = p_orden_id;

    IF v_lineas_count = 0 THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'ORDEN_SIN_PRODUCTOS',
                'message', 'La orden no tiene líneas de productos para despachar.'
            )
        );
    END IF;

    -- 5. Capturar estado previo para auditoría
    SELECT COALESCE(jsonb_agg(to_jsonb(d)), '[]'::jsonb)
    INTO v_detalles_previos
    FROM public.detalle_distribucion d
    WHERE d.orden_id = p_orden_id;

    v_valores_anteriores := jsonb_build_object(
        'correlativo', v_orden.correlativo,
        'estado_orden', v_orden.estado,
        'radar_id', v_orden.radar_id,
        'total_recaudar_usd', v_orden.total_recaudar_usd,
        'total_recaudar_bs', v_orden.total_recaudar_bs,
        'detalles', v_detalles_previos
    );

    -- 6. Validar stock disponible en inventario_almacen para todas las líneas
    FOR v_det IN
        SELECT d.id,
               d.producto_id,
               d.cantidad_solicitada,
               p.nombre AS producto_nombre,
               p.contenedor_id AS prod_contenedor_id
        FROM public.detalle_distribucion d
        JOIN public.productos p ON p.id = d.producto_id
        WHERE d.orden_id = p_orden_id
    LOOP
        SELECT stock_disponible
        INTO v_stock_disponible
        FROM public.inventario_almacen
        WHERE producto_id = v_det.producto_id
        FOR UPDATE;

        IF NOT FOUND OR COALESCE(v_stock_disponible, 0) < v_det.cantidad_solicitada THEN
            RETURN jsonb_build_object(
                'success', false,
                'data', NULL,
                'error', jsonb_build_object(
                    'code', 'STOCK_INSUFICIENTE_ALMACEN',
                    'message', 'Stock insuficiente en almacén para el producto ' || COALESCE(v_det.producto_nombre, '') || ' (Disponible: ' || COALESCE(v_stock_disponible, 0) || ', A despachar: ' || v_det.cantidad_solicitada || ').'
                )
            );
        END IF;
    END LOOP;

    -- 7. Descontar de inventario_almacen y marcar líneas como despachadas/entregadas
    FOR v_det IN
        SELECT d.id,
               d.producto_id,
               d.cantidad_solicitada,
               p.nombre AS producto_nombre,
               p.contenedor_id AS prod_contenedor_id
        FROM public.detalle_distribucion d
        JOIN public.productos p ON p.id = d.producto_id
        WHERE d.orden_id = p_orden_id
    LOOP
        UPDATE public.inventario_almacen
        SET stock_disponible = stock_disponible - v_det.cantidad_solicitada,
            stock_comprometido = GREATEST(0, COALESCE(stock_comprometido, 0) - v_det.cantidad_solicitada),
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

    -- 8. Asentar movimientos y saldos de contenedores (entregados y retirados)
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

    -- 9. Pasar la orden a 'por_liquidar' y reevaluar con abonos previos (si los tiene)
    UPDATE public.ordenes_distribucion
    SET estado = 'por_liquidar',
        fecha_despacho = COALESCE(fecha_despacho, NOW()),
        observaciones = COALESCE(observaciones, '') ||
                        ' [DESPACHO GENERADO DESDE ALMACÉN el ' || TO_CHAR(NOW(), 'YYYY-MM-DD HH24:MI:SS') ||
                        CASE WHEN p_observaciones IS NOT NULL AND TRIM(p_observaciones) <> '' THEN ' - Nota: ' || TRIM(p_observaciones) ELSE '' END || ']'
    WHERE id = p_orden_id;

    -- Evaluar abonos aprobados existentes sin necesidad de haberlos reversado
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

    -- 10. Si pertenece a un radar (incluso ya aprobado), actualizar totales del radar
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

    -- 11. Registrar evento explícito en public.logs_auditoria
    SELECT COALESCE(jsonb_agg(to_jsonb(d)), '[]'::jsonb)
    INTO v_detalles_nuevos
    FROM public.detalle_distribucion d
    WHERE d.orden_id = p_orden_id;

    v_valores_nuevos := jsonb_build_object(
        'correlativo', v_orden.correlativo,
        'estado_orden', v_estado_final,
        'radar_id', v_orden.radar_id,
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

COMMENT ON FUNCTION public.generar_despacho_orden_almacen(UUID, TEXT) IS
    'Genera el despacho directo desde inventario_almacen para una orden en estado aprobada (exclusivo Gerencia/Admin), descontando stock_disponible, asentando envases, pasando la orden a por_liquidar (respetando abonos previos) y registrando auditoría en logs_auditoria.';
