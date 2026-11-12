-- ==============================================================================
-- PARCHE IDEMPOTENTE: ÓRDENES APROBADAS CON FECHAS ANTERIORES EN RADAR Y OPCIÓN DE QUITAR DEL RADAR
-- Fecha: 2026-11-12
-- Descripción:
--   1. Añade columna `ordenes_excluidas UUID[]` en `public.radars` para recordar
--      qué órdenes fueron retiradas manualmente de un radar específico (Comportamiento A:
--      si se regenera ese mismo radar no las vuelve a incluir, pero un nuevo radar sí).
--   2. `crear_o_obtener_radar`: Trae órdenes con `estado = 'aprobada'` cuya
--      `fecha_despacho::date <= p_fecha_despacho` (fecha del radar o anteriores)
--      que no estén vinculadas a otro radar ni excluidas de este radar.
--   3. `solicita_editar_o_sincronizar_radar`: Al regenerar el radar, trae órdenes
--      con `estado = 'aprobada'` y `fecha_despacho::date <= v_fecha_despacho`,
--      respetando las órdenes excluidas manualmente de ese radar (`ordenes_excluidas`).
--   4. Nueva RPC `quitar_orden_de_radar(p_radar_id, p_orden_id)`: Permite quitar una
--      orden en estado `'aprobada'` de un radar pendiente antes de cargar el camión
--      (`carga_inventario_movil = FALSE`), dejándola en `estado = 'aprobada'` y
--      `radar_id = NULL` para que un nuevo radar posterior la vuelva a traer.
--   5. `solicita_aprobar_radar`: Al aprobar/cerrar el radar y retornar el inventario
--      sobrante al almacén, las órdenes que no pudieron ser despachadas (`estado IN ('aprobada', 'en_transito')`
--      sin líneas entregadas) regresan automáticamente a `estado = 'aprobada'` y
--      `radar_id = NULL` para ser tomadas por el siguiente radar.
--   6. Actualiza `retorna_ordenes_distribucion_segun_idradar` (incluye `fecha_despacho`)
--      y `retorna_lista_radars_segun_rango_fechas` (incluye `carga_inventario_movil`).
--   7. Saneamiento de datos existentes: Libera órdenes no despachadas que hayan quedado
--      atrapadas en `'aprobada'` o `'en_transito'` dentro de radares ya aprobados.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 0. Columna ordenes_excluidas en public.radars
-- ------------------------------------------------------------------------------
ALTER TABLE IF EXISTS public.radars
ADD COLUMN IF NOT EXISTS ordenes_excluidas UUID[] NOT NULL DEFAULT '{}'::UUID[];


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
    v_carga_inventario BOOLEAN;
    v_ordenes_excluidas UUID[];
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
    SELECT id, correlativo, COALESCE(status_radar, FALSE), COALESCE(carga_inventario_movil, FALSE), COALESCE(ordenes_excluidas, '{}'::UUID[])
    INTO v_radar_id, v_correlativo, v_status_radar, v_carga_inventario, v_ordenes_excluidas
    FROM public.radars
    WHERE despachador_id = v_despachador_id
      AND fecha_despacho = p_fecha_despacho
    ORDER BY created_at DESC
    LIMIT 1;

    -- Si no existe, crearlo
    IF v_radar_id IS NULL THEN
        INSERT INTO public.radars (despachador_id, fecha_despacho, status_radar, ordenes_excluidas)
        VALUES (v_despachador_id, p_fecha_despacho, FALSE, '{}'::UUID[])
        RETURNING id, correlativo, COALESCE(status_radar, FALSE), COALESCE(carga_inventario_movil, FALSE), COALESCE(ordenes_excluidas, '{}'::UUID[])
        INTO v_radar_id, v_correlativo, v_status_radar, v_carga_inventario, v_ordenes_excluidas;
    END IF;

    -- Si el radar no está cerrado, limpiar órdenes que hayan sido anuladas o excluidas
    IF COALESCE(v_status_radar, FALSE) = FALSE THEN
        UPDATE public.ordenes_distribucion
        SET radar_id = NULL
        WHERE radar_id = v_radar_id
          AND (estado = 'anulada' OR id = ANY(v_ordenes_excluidas));
    END IF;

    -- Solo vincular nuevas órdenes si el radar sigue pendiente y sin camión cargado
    IF COALESCE(v_status_radar, FALSE) = FALSE AND COALESCE(v_carga_inventario, FALSE) = FALSE THEN
        -- Traer órdenes 'aprobada' de la fecha del radar o de fechas anteriores (<= p_fecha_despacho),
        -- así como órdenes en ruta/procesadas de la fecha del radar, excluyendo autoventas, anuladas y excluidas manualmente.
        UPDATE public.ordenes_distribucion o
        SET radar_id = v_radar_id
        FROM public.clientes c
        WHERE o.cliente_id = c.id
          AND COALESCE(o.despachador_id, c.despachador_id) = v_despachador_id
          AND (
              (o.estado = 'aprobada' AND o.fecha_despacho::date <= p_fecha_despacho)
              OR
              (o.estado IN ('en_transito', 'por_liquidar', 'liquidada', 'devuelta') AND o.fecha_despacho::date = p_fecha_despacho)
          )
          AND (o.radar_id IS NULL OR o.radar_id = v_radar_id)
          AND COALESCE(o.es_autoventa, FALSE) = FALSE
          AND NOT (o.id = ANY(v_ordenes_excluidas));
    END IF;

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
            'carga_inventario_movil', v_carga_inventario,
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
    v_ordenes_excluidas UUID[];
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
           COALESCE(status_radar, FALSE), COALESCE(carga_inventario_movil, FALSE),
           COALESCE(ordenes_excluidas, '{}'::UUID[])
    INTO v_despachador_id, v_fecha_despacho, v_correlativo, v_status_radar, v_carga_inventario, v_ordenes_excluidas
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

    -- Volver a vincular órdenes estándar activas (incluyendo 'aprobada' con fecha <= v_fecha_despacho)
    -- respetando las órdenes excluidas manualmente de este radar (Comportamiento A)
    UPDATE public.ordenes_distribucion o
    SET radar_id = p_radar_id
    FROM public.clientes c
    WHERE o.cliente_id = c.id
      AND COALESCE(o.despachador_id, c.despachador_id) = v_despachador_id
      AND (
          (o.estado = 'aprobada' AND o.fecha_despacho::date <= v_fecha_despacho)
          OR
          (o.estado IN ('en_transito', 'por_liquidar', 'liquidada', 'devuelta') AND o.fecha_despacho::date = v_fecha_despacho)
      )
      AND (o.radar_id IS NULL OR o.radar_id = p_radar_id)
      AND COALESCE(o.es_autoventa, FALSE) = FALSE
      AND NOT (o.id = ANY(v_ordenes_excluidas));

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
-- 3. Nueva función RPC: quitar_orden_de_radar
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.quitar_orden_de_radar(
    p_radar_id UUID,
    p_orden_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_status_radar BOOLEAN;
    v_carga_inventario BOOLEAN;
    v_correlativo_radar INT;
    v_orden RECORD;
    v_tot_solicitada NUMERIC(10,0);
    v_tot_despachada NUMERIC(10,0);
    v_tot_retirados NUMERIC(10,0);
    v_total_ordenes INT;
BEGIN
    IF p_radar_id IS NULL OR p_orden_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID del radar y el ID de la orden son obligatorios.'
            )
        );
    END IF;

    SELECT correlativo, COALESCE(status_radar, FALSE), COALESCE(carga_inventario_movil, FALSE)
    INTO v_correlativo_radar, v_status_radar, v_carga_inventario
    FROM public.radars
    WHERE id = p_radar_id
    FOR UPDATE;

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
                'message', 'El radar ya fue aprobado por la Gerencia y no se puede modificar.'
            )
        );
    END IF;

    IF v_carga_inventario = TRUE THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'RADAR_INVENTARIO_CARGADO',
                'message', 'Para quitar una orden del Radar debe primero reversar el inventario móvil al almacén.'
            )
        );
    END IF;

    SELECT id, correlativo, estado, radar_id
    INTO v_orden
    FROM public.ordenes_distribucion
    WHERE id = p_orden_id
    FOR UPDATE;

    IF v_orden.id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'ORDEN_INEXISTENTE',
                'message', 'La orden especificada no existe.'
            )
        );
    END IF;

    IF v_orden.radar_id IS DISTINCT FROM p_radar_id THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'ORDEN_NO_PERTENECE_AL_RADAR',
                'message', 'La orden especificada no se encuentra vinculada a este radar.'
            )
        );
    END IF;

    IF v_orden.estado <> 'aprobada' THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'ESTADO_ORDEN_INVALIDO',
                'message', 'Solo se pueden quitar del radar órdenes en estado aprobada que aún no hayan salido a despacho.'
            )
        );
    END IF;

    -- Desvincular la orden dejándola en estado 'aprobada' y reiniciando sus líneas a pendiente
    UPDATE public.ordenes_distribucion
    SET radar_id = NULL,
        estado = 'aprobada'
    WHERE id = p_orden_id;

    UPDATE public.detalle_distribucion
    SET cantidad_despachada = 0,
        estado_entrega = 'pendiente',
        motivo_rechazo = NULL
    WHERE orden_id = p_orden_id;

    -- Recalcular totales del radar
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

    -- Registrar la orden en ordenes_excluidas de este radar (Comportamiento A) y guardar totales
    UPDATE public.radars
    SET ordenes_excluidas = array_append(array_remove(COALESCE(ordenes_excluidas, '{}'::UUID[]), p_orden_id), p_orden_id),
        total_cantidad_solicitada = v_tot_solicitada,
        total_cantidad_despachada = v_tot_despachada,
        total_contenedores_retirados = v_tot_retirados
    WHERE id = p_radar_id;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', format('Orden #%s retirada del radar. Se mantiene aprobada para próximos radares.', v_orden.correlativo),
        'data', jsonb_build_object(
            'radar_id', p_radar_id,
            'orden_id', p_orden_id,
            'correlativo_orden', v_orden.correlativo,
            'estado_orden', 'aprobada',
            'ordenes_restantes', v_total_ordenes,
            'total_cantidad_solicitada', v_tot_solicitada,
            'total_cantidad_despachada', v_tot_despachada,
            'total_contenedores_retirados', v_tot_retirados
        ),
        'error', NULL
    );

EXCEPTION WHEN OTHERS THEN
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

GRANT EXECUTE ON FUNCTION public.quitar_orden_de_radar(UUID, UUID) TO authenticated, service_role;


-- ------------------------------------------------------------------------------
-- 4. solicita_aprobar_radar
--    Libera automáticamente a estado = 'aprobada' y radar_id = NULL las órdenes
--    que no pudieron ser despachadas en la ruta, una vez retornado su inventario.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.solicita_aprobar_radar(
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
    v_inv_res JSONB;
    v_ordenes_anuladas_count INT := 0;
    v_ordenes_reprogramadas_count INT := 0;
    v_contenedores_retirados_procesados INT := 0;
    v_contenedores_entregados_procesados INT := 0;
    v_clientes_deshabilitados_count INT := 0;
    v_tot_solicitada NUMERIC(10,0);
    v_tot_despachada NUMERIC(10,0);
    v_tot_retirados NUMERIC(10,0);
BEGIN
    IF p_radar_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID del radar es obligatorio.'
            )
        );
    END IF;

    -- Verificar existencia del radar y su estado actual
    SELECT despachador_id, fecha_despacho, COALESCE(status_radar, FALSE)
    INTO v_despachador_id, v_fecha_despacho, v_status_radar
    FROM public.radars
    WHERE id = p_radar_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'RADAR_INEXISTENTE',
                'message', 'El radar especificado no existe.'
            )
        );
    END IF;

    IF v_status_radar = TRUE THEN
        RETURN jsonb_build_object(
            'success', TRUE,
            'message', 'El radar ya se encuentra previamente aprobado.',
            'data', jsonb_build_object(
                'radar_id', p_radar_id,
                'status_radar', TRUE
            ),
            'error', NULL
        );
    END IF;

    -- 1. Marcar el radar como aprobado y cerrado (.T.) mediante status_radar = TRUE
    UPDATE public.radars
    SET status_radar = TRUE
    WHERE id = p_radar_id;

    -- El cálculo de contenedores entregados y retirados se realiza en registrar_despacho_cliente_radar
    v_contenedores_entregados_procesados := 0;
    v_contenedores_retirados_procesados := 0;

    -- 2. Devuelve el inventario no despachado del camión al almacén principal
    v_inv_res := public.retorna_inventario_no_despachado_para_almacen(p_radar_id);

    -- 3. Las órdenes en estado 'devuelta' pasan al estado final 'anulada'
    WITH ordenes_devueltas AS (
        UPDATE public.ordenes_distribucion
        SET estado = 'anulada'
        WHERE radar_id = p_radar_id AND estado = 'devuelta'
        RETURNING id
    )
    SELECT COUNT(*) INTO v_ordenes_anuladas_count FROM ordenes_devueltas;

    -- 4. Las órdenes que NO pudieron ser despachadas (quedaron en 'aprobada' o 'en_transito'
    --    con todas sus líneas pendientes) vuelven a estado 'aprobada' y se desvinculan (radar_id = NULL)
    --    para que el siguiente radar las tome automáticamente.
    UPDATE public.detalle_distribucion dd
    SET cantidad_despachada = 0,
        estado_entrega = 'pendiente',
        motivo_rechazo = NULL
    FROM public.ordenes_distribucion o
    WHERE dd.orden_id = o.id
      AND o.radar_id = p_radar_id
      AND o.estado IN ('aprobada', 'en_transito')
      AND NOT EXISTS (
          SELECT 1
          FROM public.detalle_distribucion dd2
          WHERE dd2.orden_id = o.id
            AND COALESCE(dd2.estado_entrega, 'pendiente') <> 'pendiente'
      );

    WITH ordenes_no_despachadas AS (
        UPDATE public.ordenes_distribucion o
        SET estado = 'aprobada',
            radar_id = NULL
        WHERE o.radar_id = p_radar_id
          AND o.estado IN ('aprobada', 'en_transito')
          AND NOT EXISTS (
              SELECT 1
              FROM public.detalle_distribucion dd2
              WHERE dd2.orden_id = o.id
                AND COALESCE(dd2.estado_entrega, 'pendiente') <> 'pendiente'
          )
        RETURNING o.id
    )
    SELECT COUNT(*) INTO v_ordenes_reprogramadas_count FROM ordenes_no_despachadas;

    -- 5. Recalcular totales finales del radar cerrado
    SELECT 
        COALESCE(SUM(d.cantidad_solicitada), 0),
        COALESCE(SUM(CASE WHEN COALESCE(d.estado_entrega, 'pendiente') <> 'pendiente' THEN COALESCE(d.cantidad_despachada, 0) ELSE 0 END), 0),
        COALESCE(SUM(d.contenedores_retirados), 0)
    INTO v_tot_solicitada, v_tot_despachada, v_tot_retirados
    FROM public.ordenes_distribucion o
    JOIN public.detalle_distribucion d ON d.orden_id = o.id
    WHERE o.radar_id = p_radar_id
      AND o.estado <> 'anulada';

    UPDATE public.radars
    SET total_cantidad_solicitada = v_tot_solicitada,
        total_cantidad_despachada = v_tot_despachada,
        total_contenedores_retirados = v_tot_retirados
    WHERE id = p_radar_id;

    -- 6. Políticas de crédito desactivadas temporalmente para mantener todos los clientes activos
    v_clientes_deshabilitados_count := 0;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Radar aprobado exitosamente. Inventario sobrante restituido al almacén, órdenes devueltas anuladas y órdenes no despachadas liberadas como aprobadas.',
        'data', jsonb_build_object(
            'radar_id', p_radar_id,
            'status_radar', TRUE,
            'contenedores_entregados_procesados', v_contenedores_entregados_procesados,
            'contenedores_retirados_procesados', v_contenedores_retirados_procesados,
            'clientes_deshabilitados_credito', v_clientes_deshabilitados_count,
            'ordenes_anuladas', v_ordenes_anuladas_count,
            'ordenes_reprogramadas', v_ordenes_reprogramadas_count,
            'inventario_reintegrado', COALESCE(v_inv_res->'data', '[]'::jsonb)
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

GRANT EXECUTE ON FUNCTION public.solicita_aprobar_radar(UUID) TO authenticated, service_role;


-- ------------------------------------------------------------------------------
-- 5. retorna_ordenes_distribucion_segun_idradar (Incluye fecha_despacho)
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
                    'fecha_despacho', o.fecha_despacho,
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
-- 6. retorna_lista_radars_segun_rango_fechas (Incluye carga_inventario_movil)
-- ------------------------------------------------------------------------------
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
-- 7. Saneamiento de datos existentes:
--    Liberar órdenes no despachadas ('aprobada' o 'en_transito' sin líneas entregadas)
--    que hayan quedado vinculadas a radares ya aprobados (status_radar = TRUE).
-- ------------------------------------------------------------------------------
DO $$
DECLARE
    v_rad RECORD;
BEGIN
    UPDATE public.detalle_distribucion dd
    SET cantidad_despachada = 0,
        estado_entrega = 'pendiente',
        motivo_rechazo = NULL
    FROM public.ordenes_distribucion o
    JOIN public.radars r ON o.radar_id = r.id
    WHERE dd.orden_id = o.id
      AND COALESCE(r.status_radar, FALSE) = TRUE
      AND o.estado IN ('aprobada', 'en_transito')
      AND NOT EXISTS (
          SELECT 1
          FROM public.detalle_distribucion dd2
          WHERE dd2.orden_id = o.id
            AND COALESCE(dd2.estado_entrega, 'pendiente') <> 'pendiente'
      );

    UPDATE public.ordenes_distribucion o
    SET estado = 'aprobada',
        radar_id = NULL
    FROM public.radars r
    WHERE o.radar_id = r.id
      AND COALESCE(r.status_radar, FALSE) = TRUE
      AND o.estado IN ('aprobada', 'en_transito')
      AND NOT EXISTS (
          SELECT 1
          FROM public.detalle_distribucion dd2
          WHERE dd2.orden_id = o.id
            AND COALESCE(dd2.estado_entrega, 'pendiente') <> 'pendiente'
      );

    FOR v_rad IN
        SELECT id FROM public.radars WHERE COALESCE(status_radar, FALSE) = TRUE
    LOOP
        UPDATE public.radars r
        SET total_cantidad_solicitada = COALESCE(sub.tot_sol, 0),
            total_cantidad_despachada = COALESCE(sub.tot_desp, 0),
            total_contenedores_retirados = COALESCE(sub.tot_ret, 0)
        FROM (
            SELECT 
                COALESCE(SUM(d.cantidad_solicitada), 0) AS tot_sol,
                COALESCE(SUM(CASE WHEN COALESCE(d.estado_entrega, 'pendiente') <> 'pendiente' THEN COALESCE(d.cantidad_despachada, 0) ELSE 0 END), 0) AS tot_desp,
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
