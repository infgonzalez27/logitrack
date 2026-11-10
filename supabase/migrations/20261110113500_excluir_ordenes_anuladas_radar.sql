-- ==============================================================================
-- PARCHE IDEMPOTENTE: EXCLUIR ÓRDENES ANULADAS AL CREAR, REGENERAR Y CONSULTAR RADAR
-- Fecha: 2026-11-10
-- Descripción:
--   1. `crear_o_obtener_radar`: Desvincula órdenes anuladas que pudieran haber quedado
--      en el radar, vincula solo órdenes activas y recalcula totales excluyendo 'anulada'.
--   2. `solicita_editar_o_sincronizar_radar`: Al regenerar/sincronizar el radar,
--      desvincula tanto órdenes en estado 'aprobada' como 'anulada' (`radar_id = NULL`),
--      y recalcula los totales excluyendo 'anulada'.
--   3. `anular_orden_distribucion`: Si la orden anulada pertenecía a un radar pendiente
--      (`status_radar = FALSE`), la desvincula (`radar_id = NULL`) y recalcula los
--      totales del radar inmediatamente.
--   4. `retorna_ordenes_distribucion_segun_idradar`: Excluye órdenes con `estado = 'anulada'`.
--   5. `retorna_radar_detalle_reporte`: Excluye órdenes con `estado = 'anulada'` en
--      resumen de productos, resumen de vacíos y listado de órdenes.
--   6. `retorna_lista_radars_pendiente_segun_rango_fechas`,
--      `retorna_lista_radars_aprobado_segun_rango_fechas` y
--      `retorna_lista_radars_segun_rango_fechas`: Excluyen órdenes anuladas en el
--      cálculo de `total_paradas`, `items` y `sku`.
--   7. Limpieza de datos existentes: Desvincula órdenes anuladas de radares pendientes
--      y recalcula sus totales.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. crear_o_obtener_radar
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.crear_o_obtener_radar(
    p_despachador_id UUID DEFAULT NULL,
    p_fecha_despacho DATE DEFAULT CURRENT_DATE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_despachador_id UUID;
    v_radar_id UUID;
    v_correlativo INT;
    v_status_radar BOOLEAN;
    v_tot_solicitada NUMERIC(10,0);
    v_tot_despachada NUMERIC(10,0);
    v_tot_retirados NUMERIC(10,0);
    v_total_ordenes INT;
    v_resultado JSONB;
BEGIN
    v_despachador_id := COALESCE(p_despachador_id, auth.uid());

    IF v_despachador_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_REQUERIDO',
                'message', 'Se requiere especificar un despachador_id o estar autenticado.'
            )
        );
    END IF;

    -- Verificar si existe un radar para este despachador y fecha
    SELECT id, correlativo, status_radar
    INTO v_radar_id, v_correlativo, v_status_radar
    FROM public.radars
    WHERE despachador_id = v_despachador_id
      AND fecha_despacho = p_fecha_despacho
    ORDER BY created_at DESC
    LIMIT 1;

    -- Si no existe, crearlo
    IF v_radar_id IS NULL THEN
        INSERT INTO public.radars (despachador_id, fecha_despacho, status_radar)
        VALUES (v_despachador_id, p_fecha_despacho, FALSE)
        RETURNING id, correlativo, status_radar INTO v_radar_id, v_correlativo, v_status_radar;
    END IF;

    -- Si el radar no está cerrado, limpiar órdenes que hayan sido anuladas
    IF COALESCE(v_status_radar, FALSE) = FALSE THEN
        UPDATE public.ordenes_distribucion
        SET radar_id = NULL
        WHERE radar_id = v_radar_id
          AND estado = 'anulada';
    END IF;

    -- EXCLUIR VENTA EN RUTA (es_autoventa = TRUE) y ÓRDENES ANULADAS
    UPDATE public.ordenes_distribucion o
    SET radar_id = v_radar_id
    FROM public.clientes c
    WHERE o.cliente_id = c.id
      AND COALESCE(o.despachador_id, c.despachador_id) = v_despachador_id
      AND o.fecha_despacho::date = p_fecha_despacho
      AND o.estado IN ('aprobada', 'en_transito', 'por_liquidar', 'liquidada', 'devuelta')
      AND (o.radar_id IS NULL OR o.radar_id = v_radar_id)
      AND COALESCE(o.es_autoventa, FALSE) = FALSE;

    -- Recalcular totales del radar (excluyendo cualquier orden anulada)
    SELECT 
        COALESCE(SUM(d.cantidad_solicitada), 0),
        COALESCE(SUM(d.cantidad_despachada), 0),
        COALESCE(SUM(d.contenedores_retirados), 0),
        COUNT(DISTINCT o.id)
    INTO v_tot_solicitada, v_tot_despachada, v_tot_retirados, v_total_ordenes
    FROM public.ordenes_distribucion o
    JOIN public.detalle_distribucion d ON d.orden_id = o.id
    WHERE o.radar_id = v_radar_id
      AND o.estado <> 'anulada';

    UPDATE public.radars
    SET total_cantidad_solicitada = v_tot_solicitada,
        total_cantidad_despachada = v_tot_despachada,
        total_contenedores_retirados = v_tot_retirados
    WHERE id = v_radar_id;

    SELECT jsonb_build_object(
        'success', TRUE,
        'message', 'Radar obtenido/creado exitosamente.',
        'data', jsonb_build_object(
            'id', v_radar_id,
            'correlativo', v_correlativo,
            'despachador_id', v_despachador_id,
            'fecha_despacho', p_fecha_despacho,
            'status_radar', v_status_radar,
            'total_cantidad_solicitada', v_tot_solicitada,
            'total_cantidad_despachada', v_tot_despachada,
            'total_contenedores_retirados', v_tot_retirados,
            'total_ordenes', v_total_ordenes
        )
    ) INTO v_resultado;

    RETURN v_resultado;
END;
$$;

GRANT EXECUTE ON FUNCTION public.crear_o_obtener_radar(UUID, DATE) TO authenticated, service_role;


-- ------------------------------------------------------------------------------
-- 2. solicita_editar_o_sincronizar_radar
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.solicita_editar_o_sincronizar_radar(
    p_radar_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_despachador_id UUID;
    v_fecha_despacho DATE;
    v_status_radar BOOLEAN;
    v_carga_inventario BOOLEAN;
    v_correlativo INT;
    v_tot_solicitada NUMERIC(10,0);
    v_tot_despachada NUMERIC(10,0);
    v_tot_retirados NUMERIC(10,0);
    v_total_ordenes INT;
    v_desvinculadas INT := 0;
    v_vinculadas INT := 0;
BEGIN
    IF p_radar_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID del radar es obligatorio.'
            )
        );
    END IF;

    SELECT despachador_id, fecha_despacho, correlativo,
           COALESCE(status_radar, FALSE), COALESCE(carga_inventario_movil, FALSE)
    INTO v_despachador_id, v_fecha_despacho, v_correlativo, v_status_radar, v_carga_inventario
    FROM public.radars
    WHERE id = p_radar_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'RADAR_INEXISTENTE',
                'message', 'El radar especificado no existe.'
            )
        );
    END IF;

    IF v_status_radar = TRUE THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'RADAR_APROBADO_BLOQUEADO',
                'message', 'El radar especificado ya ha sido aprobado por la Gerencia y no se puede modificar.'
            )
        );
    END IF;

    IF v_carga_inventario = TRUE THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'RADAR_INVENTARIO_CARGADO',
                'message', 'Para modificar el Radar debe reversar el inventario movil al almacén'
            )
        );
    END IF;

    -- Desvincular órdenes en estado 'aprobada' y también cualquier orden 'anulada'
    UPDATE public.ordenes_distribucion
    SET radar_id = NULL
    WHERE radar_id = p_radar_id
      AND estado IN ('aprobada', 'anulada');

    GET DIAGNOSTICS v_desvinculadas = ROW_COUNT;

    -- EXCLUIR VENTA EN RUTA (es_autoventa = TRUE) y ÓRDENES ANULADAS: Volver a vincular únicamente órdenes estándar activas
    UPDATE public.ordenes_distribucion o
    SET radar_id = p_radar_id
    FROM public.clientes c
    WHERE o.cliente_id = c.id
      AND COALESCE(o.despachador_id, c.despachador_id) = v_despachador_id
      AND o.fecha_despacho::date = v_fecha_despacho
      AND o.estado IN ('aprobada', 'en_transito', 'por_liquidar', 'liquidada', 'devuelta')
      AND (o.radar_id IS NULL OR o.radar_id = p_radar_id)
      AND COALESCE(o.es_autoventa, FALSE) = FALSE;

    GET DIAGNOSTICS v_vinculadas = ROW_COUNT;

    -- Recalcular totales consolidado del radar (excluyendo anuladas)
    SELECT 
        COALESCE(SUM(d.cantidad_solicitada), 0),
        COALESCE(SUM(d.cantidad_despachada), 0),
        COALESCE(SUM(d.contenedores_retirados), 0),
        COUNT(DISTINCT o.id)
    INTO v_tot_solicitada, v_tot_despachada, v_tot_retirados, v_total_ordenes
    FROM public.ordenes_distribucion o
    JOIN public.detalle_distribucion d ON d.orden_id = o.id
    WHERE o.radar_id = p_radar_id
      AND o.estado <> 'anulada';

    UPDATE public.radars
    SET total_cantidad_solicitada = v_tot_solicitada,
        total_cantidad_despachada = v_tot_despachada,
        total_contenedores_retirados = v_tot_retirados
    WHERE id = p_radar_id;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Radar re-sincronizado y actualizado exitosamente.',
        'data', jsonb_build_object(
            'radar_id', p_radar_id,
            'correlativo', v_correlativo,
            'despachador_id', v_despachador_id,
            'fecha_despacho', v_fecha_despacho,
            'ordenes_desvinculadas', v_desvinculadas,
            'ordenes_vinculadas', v_total_ordenes,
            'total_cantidad_solicitada', v_tot_solicitada,
            'total_cantidad_despachada', v_tot_despachada,
            'total_contenedores_retirados', v_tot_retirados
        ),
        'error', NULL
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.solicita_editar_o_sincronizar_radar(UUID) TO authenticated, service_role;


-- ------------------------------------------------------------------------------
-- 3. anular_orden_distribucion (Desvincula de radar pendiente y recalcula totales)
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
                SET stock_disponible = stock_disponible + v_det.cantidad
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

    -- Actualizar estado de la orden a 'anulada' (y desvincular si el radar sigue pendiente)
    UPDATE public.ordenes_distribucion
    SET estado = 'anulada',
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
-- 4. retorna_ordenes_distribucion_segun_idradar (Excluye órdenes anuladas)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.retorna_ordenes_distribucion_segun_idradar(p_radar_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_resultado JSONB;
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

    SELECT jsonb_build_object(
        'success', TRUE,
        'data', COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'id_orden_distribucion', o.id,
                    'correlativo', o.correlativo,
                    'estado', o.estado,
                    'ruta', COALESCE(rut.nombre_ruta, 'Sin Ruta'),
                    'razon_social', c.razon_social,
                    'direccion_fiscal', c.direccion_fiscal,
                    'items', COALESCE(det_stats.total_items, 0),
                    'sku', COALESCE(det_stats.total_sku, 0),
                    'contenedores_retirados', COALESCE(det_stats.total_contenedores_retirados, 0)
                ) ORDER BY o.correlativo ASC
            ),
            '[]'::jsonb
        ),
        'error', NULL
    ) INTO v_resultado
    FROM public.ordenes_distribucion o
    LEFT JOIN public.clientes c ON c.id = o.cliente_id
    LEFT JOIN public.rutas rut ON c.id_ruta = rut.id_ruta
    LEFT JOIN LATERAL (
        SELECT 
            SUM(COALESCE(d.cantidad_despachada, d.cantidad_solicitada, 0)) AS total_items,
            COUNT(DISTINCT d.producto_id) AS total_sku,
            SUM(COALESCE(d.contenedores_retirados, 0)) AS total_contenedores_retirados
        FROM public.detalle_distribucion d
        WHERE d.orden_id = o.id
    ) det_stats ON TRUE
    WHERE o.radar_id = p_radar_id
      AND o.estado <> 'anulada';

    RETURN v_resultado;

EXCEPTION WHEN OTHERS THEN
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

GRANT EXECUTE ON FUNCTION public.retorna_ordenes_distribucion_segun_idradar(UUID) TO authenticated, service_role;


-- ------------------------------------------------------------------------------
-- 5. retorna_radar_detalle_reporte (Excluye órdenes anuladas)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.retorna_radar_detalle_reporte(p_radar_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_radar RECORD;
    v_despachador RECORD;
    v_resumen_productos JSONB;
    v_resumen_vacios JSONB;
    v_ordenes JSONB;
    v_resultado JSONB;
BEGIN
    -- 1. Obtener la cabecera del radar
    SELECT r.id, r.correlativo, r.despachador_id, r.fecha_despacho,
           r.total_cantidad_solicitada, r.total_cantidad_despachada,
           r.total_contenedores_retirados, r.status_radar, r.created_at
    INTO v_radar
    FROM public.radars r
    WHERE r.id = p_radar_id;

    IF v_radar.id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'RADAR_INEXISTENTE',
                'message', 'No se encontró el radar especificado.'
            )
        );
    END IF;

    -- 2. Obtener datos del despachador
    SELECT pu.id, pu.nombre_completo, pu.telefono, u.email AS correo_e
    INTO v_despachador
    FROM public.perfiles_usuario pu
    LEFT JOIN auth.users u ON pu.id = u.id
    WHERE pu.id = v_radar.despachador_id;

    -- 3. Consolidado de productos solicitados/despachados en este radar (excluyendo anuladas)
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'producto_id', sub.producto_id,
                'codigo_producto', sub.codigo_producto,
                'nombre_producto', sub.nombre_producto,
                'imagen_path', sub.imagen_path,
                'cargado', sub.cantidad_solicitada,
                'despachado', sub.cantidad_despachada,
                'sobrante', (sub.cantidad_solicitada - sub.cantidad_despachada)
            )
        ),
        '[]'::jsonb
    )
    INTO v_resumen_productos
    FROM (
        SELECT p.id AS producto_id,
               p.codigo_producto,
               p.nombre AS nombre_producto,
               p.imagen_path,
               SUM(d.cantidad_solicitada) AS cantidad_solicitada,
               SUM(COALESCE(d.cantidad_despachada, 0)) AS cantidad_despachada
        FROM public.ordenes_distribucion o
        JOIN public.detalle_distribucion d ON d.orden_id = o.id
        JOIN public.productos p ON d.producto_id = p.id
        WHERE o.radar_id = p_radar_id
          AND o.estado <> 'anulada'
        GROUP BY p.id, p.codigo_producto, p.nombre, p.imagen_path
    ) sub;

    -- 3.5. Resumen de vacíos (contenedores) agrupados por cliente (excluyendo anuladas)
    WITH envases_entregados AS (
        SELECT o.cliente_id,
               p.contenedor_id,
               SUM(CEIL(d.cantidad_despachada::NUMERIC / COALESCE(p.unidades_por_contenedor, 1)))::INT AS entregados,
               0 AS retirados
        FROM public.ordenes_distribucion o
        JOIN public.detalle_distribucion d ON d.orden_id = o.id
        JOIN public.productos p ON p.id = d.producto_id
        WHERE o.radar_id = p_radar_id
          AND o.estado <> 'anulada'
          AND p.contenedor_id IS NOT NULL
        GROUP BY o.cliente_id, p.contenedor_id
    ),
    envases_retirados AS (
        SELECT o.cliente_id,
               d.contenedor_id,
               0 AS entregados,
               SUM(COALESCE(d.contenedores_retirados, 0)) AS retirados
        FROM public.ordenes_distribucion o
        JOIN public.detalle_distribucion d ON d.orden_id = o.id
        WHERE o.radar_id = p_radar_id
          AND o.estado <> 'anulada'
          AND d.contenedor_id IS NOT NULL
        GROUP BY o.cliente_id, d.contenedor_id
    ),
    envases_consolidados AS (
        SELECT cliente_id, contenedor_id, entregados, retirados FROM envases_entregados
        UNION ALL
        SELECT cliente_id, contenedor_id, entregados, retirados FROM envases_retirados
    ),
    resumen_agrupado AS (
        SELECT 
            ec.cliente_id,
            c.razon_social,
            c.rif_nit,
            ec.contenedor_id,
            p.codigo_producto,
            p.nombre AS nombre_producto,
            SUM(ec.entregados) AS entregado,
            SUM(ec.retirados) AS retirado
        FROM envases_consolidados ec
        JOIN public.clientes c ON c.id = ec.cliente_id
        JOIN public.productos p ON p.id = ec.contenedor_id
        GROUP BY ec.cliente_id, c.razon_social, c.rif_nit, ec.contenedor_id, p.codigo_producto, p.nombre
    )
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'cliente_id', ra.cliente_id,
                'razon_social', ra.razon_social,
                'rif_nit', ra.rif_nit,
                'detalles', (
                    SELECT jsonb_agg(
                        jsonb_build_object(
                            'contenedor_id', ra_inner.contenedor_id,
                            'codigo_producto', ra_inner.codigo_producto,
                            'nombre_producto', ra_inner.nombre_producto,
                            'entregado', ra_inner.entregado,
                            'retirado', ra_inner.retirado
                        )
                    )
                    FROM resumen_agrupado ra_inner
                    WHERE ra_inner.cliente_id = ra.cliente_id
                )
            )
        ),
        '[]'::jsonb
    )
    INTO v_resumen_vacios
    FROM (
        SELECT DISTINCT cliente_id, razon_social, rif_nit 
        FROM resumen_agrupado
    ) ra;

    -- 4. Detalle orden por orden (excluyendo anuladas)
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'orden_id', o.id,
                'correlativo', o.correlativo,
                'estado', o.estado,
                'fecha_despacho', o.fecha_despacho,
                'tasa_cambio', o.tasa_cambio,
                'total_recaudar_bs', o.total_recaudar_bs,
                'total_recaudar_usd', o.total_recaudar_usd,
                'cliente', jsonb_build_object(
                    'id', c.id,
                    'razon_social', c.razon_social,
                    'rif_nit', c.rif_nit,
                    'direccion_fiscal', c.direccion_fiscal,
                    'telefono', c.telefono,
                    'movil1', c.movil1,
                    'nombre_ruta', rut.nombre_ruta
                ),
                'detalles', (
                    SELECT COALESCE(jsonb_agg(
                        jsonb_build_object(
                            'detalle_id', d.id,
                            'producto_id', p.id,
                            'codigo_producto', p.codigo_producto,
                            'nombre_producto', p.nombre,
                            'imagen_path', p.imagen_path,
                            'cantidad_solicitada', d.cantidad_solicitada,
                            'cantidad_despachada', COALESCE(d.cantidad_despachada, 0),
                            'valor_unitario_recaudar', d.valor_unitario_recaudar,
                            'subtotal_recaudar', d.subtotal_recaudar,
                            'valor_unitario_usd', d.valor_unitario_usd,
                            'subtotal_recaudar_usd', d.subtotal_recaudar_usd,
                            'estado_entrega', COALESCE(d.estado_entrega, 'pendiente'),
                            'motivo_rechazo', d.motivo_rechazo,
                            'contenedores_retirados', COALESCE(d.contenedores_retirados, 0),
                            'contenedor_id', d.contenedor_id
                        )
                    ), '[]'::jsonb)
                    FROM public.detalle_distribucion d
                    JOIN public.productos p ON d.producto_id = p.id
                    WHERE d.orden_id = o.id
                )
            ) ORDER BY o.correlativo ASC
        ),
        '[]'::jsonb
    )
    INTO v_ordenes
    FROM public.ordenes_distribucion o
    JOIN public.clientes c ON o.cliente_id = c.id
    LEFT JOIN public.rutas rut ON c.id_ruta = rut.id_ruta
    WHERE o.radar_id = p_radar_id
      AND o.estado <> 'anulada';

    -- 5. Armado de la respuesta final
    SELECT jsonb_build_object(
        'success', TRUE,
        'data', jsonb_build_object(
            'radar', jsonb_build_object(
                'id', v_radar.id,
                'correlativo', v_radar.correlativo,
                'fecha_despacho', v_radar.fecha_despacho,
                'status_radar', v_radar.status_radar,
                'total_cantidad_solicitada', v_radar.total_cantidad_solicitada,
                'total_cantidad_despachada', v_radar.total_cantidad_despachada,
                'total_contenedores_retirados', v_radar.total_contenedores_retirados,
                'created_at', v_radar.created_at
            ),
            'despachador', jsonb_build_object(
                'id', v_despachador.id,
                'nombre_completo', v_despachador.nombre_completo,
                'telefono', v_despachador.telefono,
                'correo_e', v_despachador.correo_e
            ),
            'resumen_productos', v_resumen_productos,
            'resumen_vacios', v_resumen_vacios,
            'ordenes', v_ordenes
        )
    ) INTO v_resultado;

    RETURN v_resultado;
END;
$$;

GRANT EXECUTE ON FUNCTION public.retorna_radar_detalle_reporte(UUID) TO authenticated, service_role;


-- ------------------------------------------------------------------------------
-- 6. Funciones de listado de radares por rango de fechas (Excluyen órdenes anuladas en conteos)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.retorna_lista_radars_aprobado_segun_rango_fechas(
    p_despachador_id UUID DEFAULT NULL,
    p_fecha_inicial DATE DEFAULT NULL,
    p_fecha_limite DATE DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_despachador_id UUID;
    v_resultado JSONB;
BEGIN
    v_despachador_id := COALESCE(p_despachador_id, auth.uid());

    IF v_despachador_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'Se requiere el ID de despachador o estar autenticado.'
            )
        );
    END IF;

    SELECT jsonb_build_object(
        'success', TRUE,
        'data', COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'fecha_despacho', r.fecha_despacho,
                    'id_radar', r.id,
                    'correlativo', r.correlativo,
                    'total_paradas', COALESCE(ord_stats.total_paradas, 0),
                    'items', COALESCE(ord_stats.total_items, 0),
                    'sku', COALESCE(ord_stats.total_sku, 0),
                    'status_radar', COALESCE(r.status_radar, FALSE),
                    'carga_inventario_movil', COALESCE(r.carga_inventario_movil, FALSE)
                ) ORDER BY r.fecha_despacho DESC, r.correlativo DESC
            ),
            '[]'::jsonb
        ),
        'error', NULL
    ) INTO v_resultado
    FROM public.radars r
    LEFT JOIN LATERAL (
        SELECT 
            COUNT(DISTINCT o.id) AS total_paradas,
            SUM(COALESCE(d.cantidad_despachada, d.cantidad_solicitada, 0)) AS total_items,
            COUNT(DISTINCT d.producto_id) AS total_sku
        FROM public.ordenes_distribucion o
        LEFT JOIN public.detalle_distribucion d ON d.orden_id = o.id
        WHERE o.radar_id = r.id
          AND o.estado <> 'anulada'
    ) ord_stats ON TRUE
    WHERE r.despachador_id = v_despachador_id
      AND COALESCE(r.status_radar, FALSE) = TRUE
      AND (p_fecha_inicial IS NULL OR r.fecha_despacho >= p_fecha_inicial)
      AND (p_fecha_limite IS NULL OR r.fecha_despacho <= p_fecha_limite);

    RETURN v_resultado;

EXCEPTION WHEN OTHERS THEN
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

GRANT EXECUTE ON FUNCTION public.retorna_lista_radars_aprobado_segun_rango_fechas(UUID, DATE, DATE) TO authenticated, service_role;


CREATE OR REPLACE FUNCTION public.retorna_lista_radars_pendiente_segun_rango_fechas(
    p_despachador_id UUID DEFAULT NULL,
    p_fecha_inicial DATE DEFAULT NULL,
    p_fecha_limite DATE DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_despachador_id UUID;
    v_resultado JSONB;
BEGIN
    v_despachador_id := COALESCE(p_despachador_id, auth.uid());

    IF v_despachador_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'Se requiere el ID de despachador o estar autenticado.'
            )
        );
    END IF;

    SELECT jsonb_build_object(
        'success', TRUE,
        'data', COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'fecha_despacho', r.fecha_despacho,
                    'id_radar', r.id,
                    'correlativo', r.correlativo,
                    'total_paradas', COALESCE(ord_stats.total_paradas, 0),
                    'items', COALESCE(ord_stats.total_items, 0),
                    'sku', COALESCE(ord_stats.total_sku, 0),
                    'status_radar', COALESCE(r.status_radar, FALSE),
                    'carga_inventario_movil', COALESCE(r.carga_inventario_movil, FALSE)
                ) ORDER BY r.fecha_despacho DESC, r.correlativo DESC
            ),
            '[]'::jsonb
        ),
        'error', NULL
    ) INTO v_resultado
    FROM public.radars r
    LEFT JOIN LATERAL (
        SELECT 
            COUNT(DISTINCT o.id) AS total_paradas,
            SUM(COALESCE(d.cantidad_despachada, d.cantidad_solicitada, 0)) AS total_items,
            COUNT(DISTINCT d.producto_id) AS total_sku
        FROM public.ordenes_distribucion o
        LEFT JOIN public.detalle_distribucion d ON d.orden_id = o.id
        WHERE o.radar_id = r.id
          AND o.estado <> 'anulada'
    ) ord_stats ON TRUE
    WHERE r.despachador_id = v_despachador_id
      AND COALESCE(r.status_radar, FALSE) = FALSE
      AND (p_fecha_inicial IS NULL OR r.fecha_despacho >= p_fecha_inicial)
      AND (p_fecha_limite IS NULL OR r.fecha_despacho <= p_fecha_limite);

    RETURN v_resultado;

EXCEPTION WHEN OTHERS THEN
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

GRANT EXECUTE ON FUNCTION public.retorna_lista_radars_pendiente_segun_rango_fechas(UUID, DATE, DATE) TO authenticated, service_role;


CREATE OR REPLACE FUNCTION public.retorna_lista_radars_segun_rango_fechas(
    p_despachador_id UUID DEFAULT NULL,
    p_fecha_inicial DATE DEFAULT NULL,
    p_fecha_limite DATE DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_despachador_id UUID;
    v_resultado JSONB;
BEGIN
    v_despachador_id := COALESCE(p_despachador_id, auth.uid());

    IF v_despachador_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'Se requiere el ID de despachador o estar autenticado.'
            )
        );
    END IF;

    SELECT jsonb_build_object(
        'success', TRUE,
        'data', COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'fecha_despacho', r.fecha_despacho,
                    'id_radar', r.id,
                    'correlativo', r.correlativo,
                    'total_paradas', COALESCE(ord_stats.total_paradas, 0),
                    'items', COALESCE(ord_stats.total_items, 0),
                    'sku', COALESCE(ord_stats.total_sku, 0),
                    'status_radar', COALESCE(r.status_radar, FALSE)
                ) ORDER BY r.fecha_despacho DESC, r.correlativo DESC
            ),
            '[]'::jsonb
        ),
        'error', NULL
    ) INTO v_resultado
    FROM public.radars r
    LEFT JOIN LATERAL (
        SELECT 
            COUNT(DISTINCT o.id) AS total_paradas,
            SUM(COALESCE(d.cantidad_despachada, d.cantidad_solicitada, 0)) AS total_items,
            COUNT(DISTINCT d.producto_id) AS total_sku
        FROM public.ordenes_distribucion o
        LEFT JOIN public.detalle_distribucion d ON d.orden_id = o.id
        WHERE o.radar_id = r.id
          AND o.estado <> 'anulada'
    ) ord_stats ON TRUE
    WHERE r.despachador_id = v_despachador_id
      AND (p_fecha_inicial IS NULL OR r.fecha_despacho >= p_fecha_inicial)
      AND (p_fecha_limite IS NULL OR r.fecha_despacho <= p_fecha_limite);

    RETURN v_resultado;

EXCEPTION WHEN OTHERS THEN
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

GRANT EXECUTE ON FUNCTION public.retorna_lista_radars_segun_rango_fechas(UUID, DATE, DATE) TO authenticated, service_role;


-- ------------------------------------------------------------------------------
-- 7. Saneamiento inmediato de radares pendientes con órdenes anuladas vinculadas
-- ------------------------------------------------------------------------------
DO $$
DECLARE
    v_rad RECORD;
BEGIN
    -- Desvincular órdenes anuladas de radares aún no aprobados
    UPDATE public.ordenes_distribucion o
    SET radar_id = NULL
    FROM public.radars r
    WHERE o.radar_id = r.id
      AND COALESCE(r.status_radar, FALSE) = FALSE
      AND o.estado = 'anulada';

    -- Recalcular totales de todos los radares pendientes
    FOR v_rad IN
        SELECT id FROM public.radars WHERE COALESCE(status_radar, FALSE) = FALSE
    LOOP
        UPDATE public.radars r
        SET total_cantidad_solicitada = COALESCE(sub.tot_sol, 0),
            total_cantidad_despachada = COALESCE(sub.tot_desp, 0),
            total_contenedores_retirados = COALESCE(sub.tot_ret, 0)
        FROM (
            SELECT 
                COALESCE(SUM(d.cantidad_solicitada), 0) AS tot_sol,
                COALESCE(SUM(d.cantidad_despachada), 0) AS tot_desp,
                COALESCE(SUM(d.contenedores_retirados), 0) AS tot_ret
            FROM public.ordenes_distribucion o
            JOIN public.detalle_distribucion d ON d.orden_id = o.id
            WHERE o.radar_id = v_rad.id
              AND o.estado <> 'anulada'
        ) sub
        WHERE r.id = v_rad.id;
    END LOOP;
END;
$$;
