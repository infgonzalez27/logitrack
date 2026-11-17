-- ==============================================================================
-- MIGRACIÓN / PARCHE: LIBERAR CAMIÓN ASOCIADO AL RADAR AL APROBAR
-- Fecha: 2026-11-17 18:30:00
-- Descripción:
--   1. Backfill de radars.camion_id desde ordenes vinculadas (si alguno es NULL).
--   2. Actualiza `retorna_inventario_no_despachado_para_almacen`:
--      - Obtiene el camion_id directamente de `radars.camion_id` (o de ordenes como fallback).
--      - Al retornar inventario, vacía `inventario_movil` y cambia `camiones.estado = 'disponible'`
--        verificando únicamente que el camión no esté asignado a otro radar activo pendiente
--        con carga de inventario (`status_radar = FALSE AND carga_inventario_movil = TRUE`).
--   3. Actualiza `solicita_aprobar_radar`:
--      - Si el radar ya fue previamente aprobado, verifica y libera a 'disponible' el camión
--        si este seguía en 'en_ruta' sin otros radares activos.
--      - Garantiza la liberación del camión asignado a 'disponible' al aprobar el radar.
--   4. Regularización idempotente inmediata de camiones que quedaron trabados en 'en_ruta'
--      en tenants donde todos los radares del camión ya fueron aprobados.
-- ==============================================================================

-- 1. Asegurar que todos los radares tengan su camion_id poblado desde sus órdenes
UPDATE public.radars r
SET camion_id = x.camion_id
FROM (
    SELECT DISTINCT ON (o.radar_id) o.radar_id, o.camion_id
    FROM public.ordenes_distribucion o
    WHERE o.radar_id IS NOT NULL AND o.camion_id IS NOT NULL
    ORDER BY o.radar_id, o.created_at DESC
) x
WHERE r.id = x.radar_id AND r.camion_id IS NULL;


-- ------------------------------------------------------------------------------
-- 2. Función: retorna_inventario_no_despachado_para_almacen
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.retorna_inventario_no_despachado_para_almacen(p_radar_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
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

    -- Obtener el camión asignado al radar directamente de radars.camion_id
    SELECT camion_id INTO v_camion_id
    FROM public.radars
    WHERE id = p_radar_id;

    -- Compatibilidad con radares anteriores donde el camión solo estaba en las órdenes vinculadas
    IF v_camion_id IS NULL THEN
        SELECT camion_id INTO v_camion_id
        FROM public.ordenes_distribucion
        WHERE radar_id = p_radar_id AND camion_id IS NOT NULL
        LIMIT 1;
    END IF;

    FOR v_rec IN
        SELECT 
            d.producto_id,
            p.codigo_producto,
            p.nombre AS nombre_producto,
            SUM(
                GREATEST(
                    0,
                    d.cantidad_solicitada - CASE
                        WHEN COALESCE(d.estado_entrega, 'pendiente') <> 'pendiente'
                        THEN COALESCE(d.cantidad_despachada, 0)
                        ELSE 0
                    END
                )
            ) AS total_devuelto,
            COALESCE(MIN(o.camion_id), v_camion_id) AS camion_id
        FROM public.ordenes_distribucion o
        JOIN public.detalle_distribucion d ON d.orden_id = o.id
        JOIN public.productos p ON p.id = d.producto_id
        WHERE o.radar_id = p_radar_id
          AND o.estado <> 'anulada'
        GROUP BY d.producto_id, p.codigo_producto, p.nombre
        HAVING SUM(
            GREATEST(
                0,
                d.cantidad_solicitada - CASE
                    WHEN COALESCE(d.estado_entrega, 'pendiente') <> 'pendiente'
                    THEN COALESCE(d.cantidad_despachada, 0)
                    ELSE 0
                END
            )
        ) > 0
    LOOP
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

    -- Si el radar tiene un camión asignado, se limpia su inventario móvil y se libera a 'disponible'
    -- siempre y cuando dicho camión no esté actualmente en otro radar activo con inventario cargado.
    IF v_camion_id IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1
            FROM public.radars r
            WHERE r.camion_id = v_camion_id
              AND r.id <> p_radar_id
              AND COALESCE(r.status_radar, FALSE) = FALSE
              AND COALESCE(r.carga_inventario_movil, FALSE) = TRUE
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
-- 3. Función: solicita_aprobar_radar
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.solicita_aprobar_radar(
    p_radar_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_despachador_id UUID;
    v_fecha_despacho DATE;
    v_status_radar BOOLEAN;
    v_camion_id UUID;
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
    SELECT despachador_id, fecha_despacho, COALESCE(status_radar, FALSE), camion_id
    INTO v_despachador_id, v_fecha_despacho, v_status_radar, v_camion_id
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

    IF v_camion_id IS NULL THEN
        SELECT camion_id INTO v_camion_id
        FROM public.ordenes_distribucion
        WHERE radar_id = p_radar_id AND camion_id IS NOT NULL
        LIMIT 1;
    END IF;

    IF v_status_radar = TRUE THEN
        -- Si el radar ya estaba previamente aprobado, garantizar que su camión se libere a 'disponible'
        -- siempre que no esté en otro radar activo con inventario cargado.
        IF v_camion_id IS NOT NULL THEN
            IF NOT EXISTS (
                SELECT 1
                FROM public.radars r
                WHERE r.camion_id = v_camion_id
                  AND r.id <> p_radar_id
                  AND COALESCE(r.status_radar, FALSE) = FALSE
                  AND COALESCE(r.carga_inventario_movil, FALSE) = TRUE
            ) THEN
                DELETE FROM public.inventario_movil WHERE camion_id = v_camion_id;

                UPDATE public.camiones
                SET estado = 'disponible'
                WHERE id = v_camion_id AND estado = 'en_ruta';
            END IF;
        END IF;

        RETURN jsonb_build_object(
            'success', TRUE,
            'message', 'El radar ya se encuentra previamente aprobado.',
            'data', jsonb_build_object(
                'radar_id', p_radar_id,
                'status_radar', TRUE,
                'camion_id', v_camion_id
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

    -- 2. Devuelve el inventario no despachado del camión al almacén principal y libera el camión a 'disponible'
    v_inv_res := public.retorna_inventario_no_despachado_para_almacen(p_radar_id);

    -- Garantizar explícitamente la liberación del camión a 'disponible' si no está en otro radar activo cargado
    IF v_camion_id IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1
            FROM public.radars r
            WHERE r.camion_id = v_camion_id
              AND r.id <> p_radar_id
              AND COALESCE(r.status_radar, FALSE) = FALSE
              AND COALESCE(r.carga_inventario_movil, FALSE) = TRUE
        ) THEN
            DELETE FROM public.inventario_movil WHERE camion_id = v_camion_id;

            UPDATE public.camiones
            SET estado = 'disponible'
            WHERE id = v_camion_id AND estado = 'en_ruta';
        END IF;
    END IF;

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
        'message', 'Radar aprobado exitosamente. Inventario sobrante restituido al almacén, órdenes devueltas anuladas, órdenes no despachadas liberadas como aprobadas y camión disponible.',
        'data', jsonb_build_object(
            'radar_id', p_radar_id,
            'camion_id', v_camion_id,
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
-- 4. Regularización idempotente de camiones trabados en 'en_ruta'
-- ------------------------------------------------------------------------------
-- Pasa a 'disponible' cualquier camión que haya quedado en 'en_ruta' cuando todos
-- sus radares ya estén aprobados o no posea radares activos en ruta.
UPDATE public.camiones c
SET estado = 'disponible'
WHERE c.estado = 'en_ruta'
  AND NOT EXISTS (
      SELECT 1
      FROM public.radars r
      WHERE r.camion_id = c.id
        AND COALESCE(r.status_radar, FALSE) = FALSE
        AND COALESCE(r.carga_inventario_movil, FALSE) = TRUE
  );

-- Limpiar inventario móvil de camiones que hayan quedado disponibles y no tengan radares pendientes activos
DELETE FROM public.inventario_movil im
WHERE EXISTS (
    SELECT 1 FROM public.camiones c
    WHERE c.id = im.camion_id
      AND c.estado = 'disponible'
)
AND NOT EXISTS (
    SELECT 1 FROM public.radars r
    WHERE r.camion_id = im.camion_id
      AND COALESCE(r.status_radar, FALSE) = FALSE
      AND COALESCE(r.carga_inventario_movil, FALSE) = TRUE
);
