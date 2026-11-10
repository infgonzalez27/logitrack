-- ==============================================================================
-- PARCHE IDEMPOTENTE: AUTOVENTAS (CAMIÓN DISPONIBLE CON INVENTARIO MÓVIL),
--                     BLOQUEO DE RADAR EN CAMIÓN CON STOCK MÓVIL Y
--                     CORRECCIÓN DE REPORTES (SOBRANTE Y CONTENEDORES RETIRADOS)
-- Fecha: 2026-11-10 13:30:00
-- Descripción:
--   1. `descargar_camion_autoventa`: Agrega parámetro opcional `p_devolver_almacen BOOLEAN DEFAULT TRUE`.
--      - Si `p_devolver_almacen = TRUE`: Devuelve el sobrante a `inventario_almacen`, vacía
--        `inventario_movil` y cambia el camión a `'disponible'`.
--      - Si `p_devolver_almacen = FALSE`: NO devuelve el sobrante a `inventario_almacen`;
--        consolida en `inventario_movil` el stock disponible a bordo (`cantidad_cargada = disponible`,
--        `cantidad_entregada = 0`, `cantidad_devolucion = 0`, eliminando filas en 0) y cambia el
--        estado del camión a `'disponible'`.
--   2. `solicita_cargar_inventario_movil_desde_almacen`:
--      - Bloquea la carga de un Radar (`p_radar_id IS NOT NULL`) si el camión asignado posee
--        actualmente inventario móvil disponible (`cantidad_cargada - cantidad_entregada > 0`),
--        garantizando que el inventario móvil remanente sea exclusivo para AutoVentas.
--      - Evita arrastrar `radar_id` históricos cuando se invoca desde AutoVentas (`p_radar_id IS NULL`).
--      - Si existían filas agotadas (`disponible = 0`) con `cantidad_entregada > 0` de jornadas
--        previas cerradas, las reinicia limpiamente antes de sumar la nueva carga.
--   3. `solicita_reversar_carga_inventario_movil_a_almacen`:
--      - Al reversar la carga de un camión al almacén, limpia también `cantidad_entregada = 0`
--        y `cantidad_devolucion = 0` (eliminando filas en 0) para no dejar saldos fantasma.
--   4. `registrar_venta_en_ruta_autoventa`:
--      - Permite registrar ventas en AutoVentas si el camión se encuentra en `'disponible'`
--        (por haber cerrado jornada conservando su `inventario_movil`), pasándolo automáticamente
--        a `'en_ruta'`.
--   5. `retorna_radar_detalle_reporte` y `retorna_inventario_no_despachado_para_almacen`:
--      - Corrigen el cálculo de `despachado` y `sobrante` contabilizando `cantidad_despachada`
--        únicamente en líneas cuya entrega ya fue procesada (`COALESCE(estado_entrega, 'pendiente') <> 'pendiente'`),
--        evitando que al recién cargar el camión el reporte muestre `Cargado = 20, Despachado = 20, Sobrante = 0`.
--      - Corrigen `resumen_vacios` en `retorna_radar_detalle_reporte` cruzando contra
--        `public.tipos_contenedores` y leyendo de `public.movimientos_contenedores` (con respaldo
--        a `detalle_distribucion`), para que siempre se informen los contenedores entregados y retirados.
--   6. `retorna_reporte_autoventas_entregas_cliente` y `retorna_resumen_autoventas_jornada`:
--      - Incorporan el detalle de contenedores entregados y retirados por cliente/orden y el
--        consolidado general de contenedores retirados en la jornada de AutoVentas.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 0. Saneamiento preventivo de filas agotadas en inventario_movil
--    (Filas donde disponible <= 0 pero quedó cantidad_entregada > 0 de cierres antiguos)
-- ------------------------------------------------------------------------------
DELETE FROM public.inventario_movil
WHERE GREATEST(0, COALESCE(cantidad_cargada, 0) - COALESCE(cantidad_entregada, 0)) = 0;


-- ------------------------------------------------------------------------------
-- 1. Función: descargar_camion_autoventa
--    Soporta `p_devolver_almacen BOOLEAN DEFAULT TRUE`
-- ------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.descargar_camion_autoventa(uuid, jsonb);
DROP FUNCTION IF EXISTS public.descargar_camion_autoventa(uuid, jsonb, boolean);

CREATE OR REPLACE FUNCTION public.descargar_camion_autoventa(
    p_camion_id uuid,
    p_productos jsonb DEFAULT NULL,
    p_devolver_almacen boolean DEFAULT TRUE
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
    v_rol text;
    v_total boolean;
    v_devolver boolean := COALESCE(p_devolver_almacen, TRUE);
    v_pedido jsonb;
    v_disponible int;
    v_nombre text;
    v_rec record;
    v_detalle jsonb := '[]'::jsonb;
    v_productos int := 0;
    v_unidades int := 0;
BEGIN
    IF auth.uid() IS NOT NULL THEN
        v_rol := public.lt_current_user_rol();
        IF v_rol IS NULL OR v_rol NOT IN ('admin', 'gerente', 'vendedor', 'despachador') THEN
            RETURN jsonb_build_object(
                'success', false,
                'data', NULL,
                'error', jsonb_build_object(
                    'code', 'ACCESO_DENEGADO',
                    'message', 'No tienes permiso para descargar o liberar el camión.'
                )
            );
        END IF;
    END IF;

    IF p_camion_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.camiones WHERE id = p_camion_id) THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'CAMION_INEXISTENTE',
                'message', 'El camión especificado no existe.'
            )
        );
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.ordenes_distribucion
        WHERE camion_id = p_camion_id
          AND radar_id IS NOT NULL
          AND estado = 'en_transito'
    ) THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'RUTA_RADAR_ACTIVA',
                'message', 'El camión tiene una ruta de radar en tránsito. Debe gestionarse desde el módulo de Radar.'
            )
        );
    END IF;

    PERFORM 1 FROM public.inventario_movil WHERE camion_id = p_camion_id FOR UPDATE;

    -- ==========================================================================
    -- MODO A: Liberar camión a 'disponible' SIN devolver sobrante al almacén
    --         (Exclusivo AutoVentas: conserva el sobrante en inventario_movil)
    -- ==========================================================================
    IF NOT v_devolver THEN
        -- Eliminar productos que ya quedaron con disponible = 0
        DELETE FROM public.inventario_movil
        WHERE camion_id = p_camion_id
          AND GREATEST(0, COALESCE(cantidad_cargada, 0) - COALESCE(cantidad_entregada, 0)) = 0;

        -- Consolidar el sobrante neto como la nueva cantidad_cargada (reiniciando entregada = 0)
        FOR v_rec IN
            SELECT im.producto_id,
                   p.codigo_producto,
                   p.nombre,
                   GREATEST(0, COALESCE(im.cantidad_cargada, 0) - COALESCE(im.cantidad_entregada, 0)) AS disponible
            FROM public.inventario_movil im
            JOIN public.productos p ON p.id = im.producto_id
            WHERE im.camion_id = p_camion_id
            ORDER BY p.nombre
        LOOP
            IF v_rec.disponible > 0 THEN
                UPDATE public.inventario_movil
                SET cantidad_cargada = v_rec.disponible,
                    cantidad_entregada = 0,
                    cantidad_devolucion = 0,
                    updated_at = now()
                WHERE camion_id = p_camion_id
                  AND producto_id = v_rec.producto_id;

                v_detalle := v_detalle || jsonb_build_object(
                    'producto_id', v_rec.producto_id,
                    'codigo', v_rec.codigo_producto,
                    'nombre', v_rec.nombre,
                    'cantidad', v_rec.disponible
                );
                v_productos := v_productos + 1;
                v_unidades := v_unidades + v_rec.disponible;
            END IF;
        END LOOP;

        UPDATE public.camiones
        SET estado = 'disponible'
        WHERE id = p_camion_id;

        RETURN jsonb_build_object(
            'success', true,
            'message', CASE
                WHEN v_unidades = 0 THEN 'El camión pasó a estado disponible (no tenía sobrante en inventario móvil).'
                ELSE format(
                    'Camión disponible con inventario móvil: se conservaron %s unidad(es) de %s producto(s) a bordo sin devolver al almacén.',
                    v_unidades,
                    v_productos
                )
            END,
            'data', jsonb_build_object(
                'camion_id', p_camion_id,
                'estado_camion', 'disponible',
                'devuelto_almacen', false,
                'descarga_total', false,
                'productos_en_camion', v_productos,
                'unidades_en_camion', v_unidades,
                'productos_devueltos', 0,
                'unidades_devueltas', 0,
                'detalle', v_detalle
            ),
            'error', NULL
        );
    END IF;

    -- ==========================================================================
    -- MODO B: Comportamiento tradicional (Devolver sobrante a inventario_almacen)
    -- ==========================================================================
    v_total := p_productos IS NULL
        OR jsonb_typeof(p_productos) <> 'array'
        OR jsonb_array_length(p_productos) = 0;

    IF v_total THEN
        FOR v_rec IN
            SELECT im.producto_id,
                   p.codigo_producto,
                   p.nombre,
                   GREATEST(0, COALESCE(im.cantidad_cargada, 0) - COALESCE(im.cantidad_entregada, 0)) AS disponible
            FROM public.inventario_movil im
            JOIN public.productos p ON p.id = im.producto_id
            WHERE im.camion_id = p_camion_id
            ORDER BY p.nombre
        LOOP
            IF v_rec.disponible > 0 THEN
                INSERT INTO public.inventario_almacen (producto_id, stock_disponible, stock_comprometido, updated_at)
                VALUES (v_rec.producto_id, v_rec.disponible, 0, now())
                ON CONFLICT (producto_id) DO UPDATE
                    SET stock_disponible = public.inventario_almacen.stock_disponible + EXCLUDED.stock_disponible,
                        updated_at = now();

                v_detalle := v_detalle || jsonb_build_object(
                    'producto_id', v_rec.producto_id,
                    'codigo', v_rec.codigo_producto,
                    'nombre', v_rec.nombre,
                    'cantidad', v_rec.disponible
                );
                v_productos := v_productos + 1;
                v_unidades := v_unidades + v_rec.disponible;
            END IF;
        END LOOP;

        DELETE FROM public.inventario_movil WHERE camion_id = p_camion_id;
        UPDATE public.camiones SET estado = 'disponible' WHERE id = p_camion_id;
    ELSE
        SELECT COALESCE(jsonb_agg(jsonb_build_object('producto_id', pid, 'cantidad', cant)), '[]'::jsonb)
        INTO v_pedido
        FROM (
            SELECT (x->>'producto_id')::uuid AS pid,
                   SUM(COALESCE(NULLIF(x->>'cantidad', ''), NULLIF(x->>'cantidad_solicitada', ''), '0')::int) AS cant
            FROM jsonb_array_elements(p_productos) x
            WHERE NULLIF(x->>'producto_id', '') IS NOT NULL
            GROUP BY 1
        ) s
        WHERE cant > 0;

        FOR v_rec IN SELECT * FROM jsonb_to_recordset(v_pedido) AS t(producto_id uuid, cantidad int) LOOP
            v_disponible := NULL;
            v_nombre := NULL;
            SELECT GREATEST(0, COALESCE(im.cantidad_cargada, 0) - COALESCE(im.cantidad_entregada, 0)), p.nombre
            INTO v_disponible, v_nombre
            FROM public.inventario_movil im
            JOIN public.productos p ON p.id = im.producto_id
            WHERE im.camion_id = p_camion_id AND im.producto_id = v_rec.producto_id;

            IF COALESCE(v_disponible, 0) < v_rec.cantidad THEN
                RETURN jsonb_build_object(
                    'success', false,
                    'data', NULL,
                    'error', jsonb_build_object(
                        'code', 'CANTIDAD_EXCEDE_DISPONIBLE',
                        'message', format('%s: solo hay %s disponible(s) en el camión.', COALESCE(v_nombre, 'Producto'), COALESCE(v_disponible, 0))
                    )
                );
            END IF;
        END LOOP;

        FOR v_rec IN
            SELECT d.producto_id, d.cantidad, p.codigo_producto, p.nombre
            FROM jsonb_to_recordset(v_pedido) AS d(producto_id uuid, cantidad int)
            JOIN public.productos p ON p.id = d.producto_id
            ORDER BY p.nombre
        LOOP
            UPDATE public.inventario_movil
            SET cantidad_cargada = GREATEST(0, cantidad_cargada - v_rec.cantidad),
                updated_at = now()
            WHERE camion_id = p_camion_id AND producto_id = v_rec.producto_id;

            INSERT INTO public.inventario_almacen (producto_id, stock_disponible, stock_comprometido, updated_at)
            VALUES (v_rec.producto_id, v_rec.cantidad, 0, now())
            ON CONFLICT (producto_id) DO UPDATE
                SET stock_disponible = public.inventario_almacen.stock_disponible + EXCLUDED.stock_disponible,
                    updated_at = now();

            v_detalle := v_detalle || jsonb_build_object(
                'producto_id', v_rec.producto_id,
                'codigo', v_rec.codigo_producto,
                'nombre', v_rec.nombre,
                'cantidad', v_rec.cantidad
            );
            v_productos := v_productos + 1;
            v_unidades := v_unidades + v_rec.cantidad;
        END LOOP;

        -- Limpiar filas que hayan quedado con disponible = 0 y sin entregados pendientes
        DELETE FROM public.inventario_movil
        WHERE camion_id = p_camion_id
          AND GREATEST(0, COALESCE(cantidad_cargada, 0) - COALESCE(cantidad_entregada, 0)) = 0
          AND COALESCE(cantidad_entregada, 0) = 0;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'message', CASE
            WHEN v_unidades = 0 THEN 'El camión no tenía sobrante para devolver.'
            ELSE format('Se devolvieron %s unidad(es) de %s producto(s) al almacén.', v_unidades, v_productos)
        END,
        'data', jsonb_build_object(
            'camion_id', p_camion_id,
            'estado_camion', CASE WHEN v_total THEN 'disponible' ELSE NULL END,
            'devuelto_almacen', true,
            'descarga_total', v_total,
            'productos_devueltos', v_productos,
            'unidades_devueltas', v_unidades,
            'detalle', v_detalle
        ),
        'error', NULL
    );
END;
$function$;

ALTER FUNCTION public.descargar_camion_autoventa(uuid, jsonb, boolean) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.descargar_camion_autoventa(uuid, jsonb, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.descargar_camion_autoventa(uuid, jsonb, boolean) TO authenticated, service_role;


-- ------------------------------------------------------------------------------
-- 2. Función: solicita_cargar_inventario_movil_desde_almacen
--    - Bloquea cargar un Radar a un camión que tenga inventario_movil activo.
--    - No arrastra radar_id viejo cuando se llama desde AutoVentas (p_radar_id IS NULL).
--    - Limpia filas agotadas antes de cargar.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.solicita_cargar_inventario_movil_desde_almacen(
    p_camion_id UUID,
    p_resumen_productos JSONB,
    p_radar_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_item JSONB;
    v_items_array JSONB;
    v_producto_id UUID;
    v_cantidad_solicitada INT;
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

    -- Respetar estrictamente p_radar_id:
    -- Si viene NULL, es una carga de AutoVentas (no buscar radares históricos cerrados).
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

    FOR v_item IN SELECT * FROM jsonb_array_elements(v_items_array) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad_solicitada := COALESCE((v_item->>'cantidad_solicitada')::INT, 0);

        IF v_producto_id IS NOT NULL AND v_cantidad_solicitada > 0 THEN
            UPDATE public.inventario_almacen
            SET stock_comprometido = GREATEST(0, stock_comprometido - v_cantidad_solicitada),
                stock_disponible = CASE 
                    WHEN stock_comprometido < v_cantidad_solicitada 
                    THEN GREATEST(0, stock_disponible - (v_cantidad_solicitada - stock_comprometido))
                    ELSE stock_disponible 
                END,
                updated_at = NOW()
            WHERE producto_id = v_producto_id;

            INSERT INTO public.inventario_movil (
                camion_id,
                producto_id,
                cantidad_cargada,
                cantidad_entregada,
                cantidad_devolucion,
                updated_at
            ) VALUES (
                p_camion_id,
                v_producto_id,
                v_cantidad_solicitada,
                0,
                0,
                NOW()
            )
            ON CONFLICT (camion_id, producto_id)
            DO UPDATE SET
                cantidad_cargada = public.inventario_movil.cantidad_cargada + v_cantidad_solicitada,
                updated_at = NOW();

            v_total_productos_cargados := v_total_productos_cargados + 1;
            v_unidades_totales := v_unidades_totales + v_cantidad_solicitada;
        END IF;
    END LOOP;

    UPDATE public.camiones
    SET estado = 'en_ruta'
    WHERE id = p_camion_id;

    -- Solo si es una carga de Radar se actualizan las órdenes del radar y la bandera carga_inventario_movil
    IF v_radar_id IS NOT NULL THEN
        UPDATE public.ordenes_distribucion
        SET estado = 'en_transito'
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


-- ------------------------------------------------------------------------------
-- 3. Función: solicita_reversar_carga_inventario_movil_a_almacen
--    Limpia completamente inventario_movil al reversar la carga del radar
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.solicita_reversar_carga_inventario_movil_a_almacen(
    p_camion_id UUID,
    p_resumen_productos JSONB DEFAULT NULL,
    p_radar_id UUID DEFAULT NULL
)
RETURNS JSONB
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
        SELECT o.radar_id INTO v_radar_id
        FROM public.ordenes_distribucion o
        JOIN public.radars r ON r.id = o.radar_id
        WHERE o.camion_id = p_camion_id
          AND o.radar_id IS NOT NULL
          AND COALESCE(r.status_radar, FALSE) = FALSE
        ORDER BY o.created_at DESC
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

        DELETE FROM public.inventario_movil
        WHERE camion_id = p_camion_id
          AND GREATEST(0, COALESCE(cantidad_cargada, 0) - COALESCE(cantidad_entregada, 0)) = 0;
    ELSE
        FOR v_rec IN 
            SELECT producto_id, GREATEST(0, COALESCE(cantidad_cargada, 0) - COALESCE(cantidad_entregada, 0)) AS disponible
            FROM public.inventario_movil
            WHERE camion_id = p_camion_id
              AND GREATEST(0, COALESCE(cantidad_cargada, 0) - COALESCE(cantidad_entregada, 0)) > 0
        LOOP
            INSERT INTO public.inventario_almacen (producto_id, stock_disponible, stock_comprometido, updated_at)
            VALUES (v_rec.producto_id, v_rec.disponible, 0, NOW())
            ON CONFLICT (producto_id)
            DO UPDATE SET
                stock_disponible = public.inventario_almacen.stock_disponible + v_rec.disponible,
                updated_at = NOW();

            v_total_productos_reversados := v_total_productos_reversados + 1;
            v_unidades_totales := v_unidades_totales + v_rec.disponible;
        END LOOP;

        DELETE FROM public.inventario_movil WHERE camion_id = p_camion_id;
    END IF;

    IF v_radar_id IS NOT NULL THEN
        UPDATE public.ordenes_distribucion
        SET estado = 'aprobada'
        WHERE radar_id = v_radar_id AND estado = 'en_transito';

        GET DIAGNOSTICS v_ordenes_reversadas = ROW_COUNT;

        UPDATE public.detalle_distribucion dd
        SET cantidad_despachada = 0
        FROM public.ordenes_distribucion od
        WHERE dd.orden_id = od.id AND od.radar_id = v_radar_id;

        UPDATE public.radars
        SET carga_inventario_movil = FALSE
        WHERE id = v_radar_id;
    ELSE
        UPDATE public.ordenes_distribucion
        SET estado = 'aprobada'
        WHERE camion_id = p_camion_id AND estado = 'en_transito';

        GET DIAGNOSTICS v_ordenes_reversadas = ROW_COUNT;

        UPDATE public.detalle_distribucion dd
        SET cantidad_despachada = 0
        FROM public.ordenes_distribucion od
        WHERE dd.orden_id = od.id AND od.camion_id = p_camion_id AND od.estado = 'aprobada';
    END IF;

    UPDATE public.camiones
    SET estado = 'disponible'
    WHERE id = p_camion_id;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Inventario móvil reversado exitosamente al almacén.',
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

ALTER FUNCTION public.solicita_reversar_carga_inventario_movil_a_almacen(UUID, JSONB, UUID) OWNER TO postgres;
GRANT EXECUTE ON FUNCTION public.solicita_reversar_carga_inventario_movil_a_almacen(UUID, JSONB, UUID) TO authenticated, service_role;


-- ------------------------------------------------------------------------------
-- 4. Función: registrar_venta_en_ruta_autoventa
--    Permite vender desde un camión en estado 'disponible' que tenga inventario_movil,
--    cambiando su estado automáticamente a 'en_ruta'.
-- ------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.registrar_venta_en_ruta_autoventa(UUID, UUID, UUID, JSONB, JSONB, TEXT, NUMERIC);

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
    v_factura_numero VARCHAR(50);
    v_tasa_cambio NUMERIC(14,4);
    v_despachador_id UUID;
    v_id_ruta UUID;
    v_vendedor_id UUID;
    v_camion_estado TEXT;
    v_item JSONB;
    v_producto_id UUID;
    v_cantidad INT;
    v_precio_unitario NUMERIC(14,2);
    v_precio_lista_usd NUMERIC(14,2);
    v_porcentaje_descuento NUMERIC(5,2);
    v_monto_descuento_usd NUMERIC(14,2);
    v_peso_unitario NUMERIC(10,2);
    v_subtotal_usd NUMERIC(14,2);
    v_subtotal_bs NUMERIC(14,2);
    v_total_usd NUMERIC(14,2) := 0.00;
    v_total_bs NUMERIC(14,2) := 0.00;
    v_peso_total NUMERIC(10,2) := 0.00;
    v_stock_disponible INT;
    v_secuencia INT := 1;
    v_contenedores_resumen JSONB := '[]'::jsonb;
    v_desc_rec RECORD;
BEGIN
    IF p_cliente_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del cliente es requerido.');
    END IF;

    IF p_camion_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del camión es requerido.');
    END IF;

    IF p_productos_json IS NULL OR jsonb_array_length(p_productos_json) = 0 THEN
        RETURN jsonb_build_object('success', false, 'message', 'Debe incluir al menos un producto en la orden de AutoVenta.');
    END IF;

    -- Validar existencia del camión y estado ('en_ruta', 'asignado' o 'disponible' con inventario móvil)
    SELECT estado INTO v_camion_estado
    FROM public.camiones
    WHERE id = p_camion_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'message', 'El camión especificado no existe.');
    END IF;

    IF v_camion_estado NOT IN ('en_ruta', 'asignado', 'disponible') THEN
        RETURN jsonb_build_object('success', false, 'message', 'El camión no está disponible para registrar AutoVentas. Estado actual: ' || v_camion_estado);
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
        ORDER BY fecha_tasa DESC, created_at DESC
        LIMIT 1;

        IF v_tasa_cambio IS NULL OR v_tasa_cambio <= 0 THEN
            v_tasa_cambio := 1.0000;
        END IF;
    END IF;

    -- 1. Validar disponibilidad de stock en inventario_movil para cada producto
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;

        IF v_producto_id IS NULL OR v_cantidad IS NULL OR v_cantidad <= 0 THEN
            RETURN jsonb_build_object('success', false, 'message', 'Datos de producto o cantidad inválidos.');
        END IF;

        SELECT (COALESCE(cantidad_cargada, 0) - COALESCE(cantidad_entregada, 0))
        INTO v_stock_disponible
        FROM public.inventario_movil
        WHERE camion_id = p_camion_id AND producto_id = v_producto_id;

        IF NOT FOUND OR v_stock_disponible IS NULL OR v_stock_disponible < v_cantidad THEN
            RETURN jsonb_build_object(
                'success', false,
                'message', 'Stock insuficiente en el camión para el producto ID ' || v_producto_id || '. Disponible: ' || COALESCE(v_stock_disponible, 0) || ', Solicitado: ' || v_cantidad
            );
        END IF;
    END LOOP;

    -- Si el camión estaba en 'disponible' (conservando inventario móvil de una jornada previa),
    -- al registrar la primera venta en ruta pasa automáticamente a 'en_ruta'.
    IF v_camion_estado = 'disponible' THEN
        UPDATE public.camiones
        SET estado = 'en_ruta'
        WHERE id = p_camion_id;
    END IF;

    -- 2. Generar correlativo y número de factura/nota de autoventa antes del INSERT
    v_correlativo := nextval('public.ordenes_distribucion_correlativo_seq');
    v_factura_numero := 'AV-' || LPAD(v_correlativo::TEXT, 6, '0');
    v_orden_id := gen_random_uuid();

    INSERT INTO public.ordenes_distribucion (
        id,
        correlativo,
        factura_origen_numero,
        cliente_id,
        vendedor_id,
        despachador_id,
        camion_id,
        id_ruta,
        radar_id,
        es_autoventa,
        es_cortesia,
        estado,
        fecha_despacho,
        tasa_cambio,
        total_recaudar_usd,
        total_recaudar_bs,
        peso_total_calculado,
        observaciones,
        creado_por,
        created_at
    ) VALUES (
        v_orden_id,
        v_correlativo,
        v_factura_numero,
        p_cliente_id,
        v_vendedor_id,
        v_despachador_id,
        p_camion_id,
        v_id_ruta,
        NULL,
        TRUE,
        COALESCE(p_es_cortesia, FALSE),
        'por_liquidar',
        NOW(),
        v_tasa_cambio,
        0.00,
        0.00,
        0.00,
        p_observaciones,
        COALESCE(auth.uid(), v_vendedor_id),
        NOW()
    );

    -- 3. Insertar detalle de productos, calcular descuentos y descontar inventario móvil
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;

        SELECT COALESCE(precio_lista1, 0.00), COALESCE(peso_unitario_kg, 0.00)
        INTO v_precio_lista_usd, v_peso_unitario
        FROM public.productos
        WHERE id = v_producto_id;

        IF COALESCE(p_es_cortesia, FALSE) = TRUE THEN
            v_precio_unitario := 0.00;
            v_porcentaje_descuento := 0.00;
            v_monto_descuento_usd := 0.00;
        ELSE
            SELECT * INTO v_desc_rec
            FROM public.descuentos_cliente_producto
            WHERE cliente_id = p_cliente_id
              AND producto_id = v_producto_id
              AND activo = TRUE;

            IF FOUND THEN
                IF v_desc_rec.precio_pactado_usd IS NOT NULL AND v_desc_rec.precio_pactado_usd > 0 THEN
                    v_precio_unitario := v_desc_rec.precio_pactado_usd;
                    v_monto_descuento_usd := GREATEST(0.00, v_precio_lista_usd - v_precio_unitario);
                    IF v_precio_lista_usd > 0 THEN
                        v_porcentaje_descuento := ROUND((v_monto_descuento_usd / v_precio_lista_usd) * 100, 2);
                    ELSE
                        v_porcentaje_descuento := 0.00;
                    END IF;
                ELSIF v_desc_rec.porcentaje_descuento IS NOT NULL AND v_desc_rec.porcentaje_descuento > 0 THEN
                    v_porcentaje_descuento := v_desc_rec.porcentaje_descuento;
                    v_monto_descuento_usd := ROUND(v_precio_lista_usd * (v_porcentaje_descuento / 100.00), 2);
                    v_precio_unitario := GREATEST(0.00, v_precio_lista_usd - v_monto_descuento_usd);
                ELSE
                    v_precio_unitario := v_precio_lista_usd;
                    v_porcentaje_descuento := 0.00;
                    v_monto_descuento_usd := 0.00;
                END IF;
            ELSE
                v_precio_unitario := COALESCE((v_item->>'valor_unitario_usd')::NUMERIC, (v_item->>'precio_unitario')::NUMERIC, v_precio_lista_usd, 0.00);
                IF v_precio_unitario <= 0 THEN
                    v_precio_unitario := v_precio_lista_usd;
                END IF;
                v_porcentaje_descuento := 0.00;
                v_monto_descuento_usd := 0.00;
            END IF;
        END IF;

        v_subtotal_usd := ROUND(v_cantidad * v_precio_unitario, 2);
        v_subtotal_bs := ROUND(v_subtotal_usd * v_tasa_cambio, 2);

        v_total_usd := v_total_usd + v_subtotal_usd;
        v_total_bs := v_total_bs + v_subtotal_bs;
        v_peso_total := v_peso_total + (v_cantidad * COALESCE(v_peso_unitario, 0.00));

        INSERT INTO public.detalle_distribucion (
            id,
            orden_id,
            producto_id,
            cantidad_solicitada,
            cantidad_despachada,
            valor_unitario_usd,
            subtotal_recaudar_usd,
            valor_unitario_recaudar,
            subtotal_recaudar,
            precio_lista_usd,
            porcentaje_descuento,
            monto_descuento_usd,
            secuencia_entrega,
            estado_entrega
        ) VALUES (
            gen_random_uuid(),
            v_orden_id,
            v_producto_id,
            v_cantidad,
            v_cantidad,
            v_precio_unitario,
            v_subtotal_usd,
            ROUND(v_precio_unitario * v_tasa_cambio, 2),
            v_subtotal_bs,
            v_precio_lista_usd,
            v_porcentaje_descuento,
            v_monto_descuento_usd,
            v_secuencia,
            'entregado'
        );

        v_secuencia := v_secuencia + 1;

        UPDATE public.inventario_movil
        SET cantidad_entregada = COALESCE(cantidad_entregada, 0) + v_cantidad,
            updated_at = NOW()
        WHERE camion_id = p_camion_id AND producto_id = v_producto_id;
    END LOOP;

    -- 4. Actualizar totales en cabecera
    UPDATE public.ordenes_distribucion
    SET factura_origen_numero = v_factura_numero,
        total_recaudar_usd = v_total_usd,
        total_recaudar_bs = v_total_bs,
        peso_total_calculado = v_peso_total
    WHERE id = v_orden_id;

    -- 5. Asentar contenedores llamando a lt_asentar_contenedores_orden
    v_contenedores_resumen := public.lt_asentar_contenedores_orden(v_orden_id, COALESCE(p_contenedores_json, '[]'::jsonb));

    RETURN jsonb_build_object(
        'success', true,
        'message', 'Venta en ruta (AutoVenta) registrada exitosamente.',
        'data', jsonb_build_object(
            'orden_id', v_orden_id,
            'correlativo', v_correlativo,
            'factura_origen_numero', v_factura_numero,
            'es_autoventa', TRUE,
            'es_cortesia', COALESCE(p_es_cortesia, FALSE),
            'estado', 'por_liquidar',
            'total_recaudar_usd', v_total_usd,
            'total_recaudar_bs', v_total_bs,
            'tasa_cambio', v_tasa_cambio,
            'contenedores', v_contenedores_resumen
        ),
        'error', NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'Error al registrar AutoVenta: ' || SQLERRM,
            'error', jsonb_build_object('code', SQLSTATE, 'message', SQLERRM)
        );
END;
$$;

ALTER FUNCTION public.registrar_venta_en_ruta_autoventa(UUID, UUID, UUID, JSONB, JSONB, TEXT, NUMERIC, BOOLEAN) OWNER TO postgres;
GRANT EXECUTE ON FUNCTION public.registrar_venta_en_ruta_autoventa(UUID, UUID, UUID, JSONB, JSONB, TEXT, NUMERIC, BOOLEAN) TO authenticated, service_role;


-- ------------------------------------------------------------------------------
-- 5. Función: retorna_inventario_no_despachado_para_almacen
--    Contabiliza como despachadas únicamente las líneas con estado_entrega <> 'pendiente'
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

    SELECT camion_id INTO v_camion_id
    FROM public.ordenes_distribucion
    WHERE radar_id = p_radar_id AND camion_id IS NOT NULL
    LIMIT 1;

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
            MIN(o.camion_id) AS camion_id
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
-- 6. Función: retorna_radar_detalle_reporte
--    - Corrige `despachado` y `sobrante`: solo suma como despachado lo que ya
--      tiene `estado_entrega <> 'pendiente'` (evita que recién cargado el camión
--      aparezca Despachado = Cargado y Sobrante = 0).
--    - Corrige `resumen_vacios`: cruza contra `public.tipos_contenedores` y lee
--      los movimientos reales desde `public.movimientos_contenedores` (con respaldo
--      a `detalle_distribucion`), reportando todos los contenedores entregados y retirados.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.retorna_radar_detalle_reporte(
    p_radar_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_radar RECORD;
    v_despachador RECORD;
    v_resumen_productos JSONB;
    v_resumen_vacios JSONB;
    v_ordenes JSONB;
    v_tot_solicitada INT := 0;
    v_tot_despachada INT := 0;
    v_tot_retirados INT := 0;
    v_resultado JSONB;
BEGIN
    IF p_radar_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_REQUERIDO',
                'message', 'El parámetro p_radar_id es obligatorio.'
            )
        );
    END IF;

    -- 1. Obtener datos del radar
    SELECT id, correlativo, despachador_id, fecha_despacho, status_radar,
           total_cantidad_solicitada, total_cantidad_despachada, total_contenedores_retirados, created_at
    INTO v_radar
    FROM public.radars
    WHERE id = p_radar_id;

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

    -- 3. Consolidado de productos solicitados / despachados reales / sobrante (excluyendo anuladas)
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'producto_id', sub.producto_id,
                'codigo_producto', sub.codigo_producto,
                'nombre_producto', sub.nombre_producto,
                'imagen_path', sub.imagen_path,
                'cargado', sub.cantidad_solicitada,
                'despachado', sub.cantidad_despachada,
                'sobrante', GREATEST(0, sub.cantidad_solicitada - sub.cantidad_despachada)
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
               SUM(d.cantidad_solicitada)::INT AS cantidad_solicitada,
               SUM(
                   CASE
                       WHEN COALESCE(d.estado_entrega, 'pendiente') <> 'pendiente'
                       THEN COALESCE(d.cantidad_despachada, 0)
                       ELSE 0
                   END
               )::INT AS cantidad_despachada
        FROM public.ordenes_distribucion o
        JOIN public.detalle_distribucion d ON d.orden_id = o.id
        JOIN public.productos p ON d.producto_id = p.id
        WHERE o.radar_id = p_radar_id
          AND o.estado <> 'anulada'
        GROUP BY p.id, p.codigo_producto, p.nombre, p.imagen_path
        ORDER BY p.nombre ASC
    ) sub;

    -- 3.5. Resumen de vacíos (contenedores entregados y retirados) agrupados por cliente
    --      Toma primero los registros asentados en public.movimientos_contenedores
    --      y usa detalle_distribucion como respaldo para órdenes entregadas sin fila en movimientos_contenedores,
    --      cruzando contra public.tipos_contenedores.
    WITH movs_radar AS (
        SELECT o.cliente_id,
               mc.contenedor_id,
               COALESCE(mc.cantidad_entregada, 0)::INT AS entregados,
               COALESCE(mc.cantidad_retirada, 0)::INT AS retirados
        FROM public.ordenes_distribucion o
        JOIN public.movimientos_contenedores mc ON mc.orden_id = o.id
        WHERE o.radar_id = p_radar_id
          AND o.estado <> 'anulada'
          AND mc.contenedor_id IS NOT NULL
    ),
    fallback_detalle AS (
        SELECT o.cliente_id,
               COALESCE(d.contenedor_id, p.contenedor_id) AS contenedor_id,
               CASE
                   WHEN COALESCE(d.estado_entrega, 'pendiente') <> 'pendiente'
                        AND COALESCE(d.contenedor_id, p.contenedor_id) IS NOT NULL
                        AND COALESCE(d.cantidad_despachada, 0) > 0
                   THEN CEIL(COALESCE(d.cantidad_despachada, 0)::NUMERIC / GREATEST(COALESCE(p.unidades_por_contenedor, 1)::NUMERIC, 1))::INT
                   ELSE 0
               END AS entregados,
               CASE
                   WHEN COALESCE(d.estado_entrega, 'pendiente') <> 'pendiente'
                   THEN COALESCE(d.contenedores_retirados, 0)::INT
                   ELSE 0
               END AS retirados
        FROM public.ordenes_distribucion o
        JOIN public.detalle_distribucion d ON d.orden_id = o.id
        JOIN public.productos p ON p.id = d.producto_id
        WHERE o.radar_id = p_radar_id
          AND o.estado <> 'anulada'
          AND COALESCE(d.contenedor_id, p.contenedor_id) IS NOT NULL
          AND NOT EXISTS (
              SELECT 1 FROM public.movimientos_contenedores mc2 WHERE mc2.orden_id = o.id
          )
    ),
    envases_consolidados AS (
        SELECT cliente_id, contenedor_id, entregados, retirados FROM movs_radar
        UNION ALL
        SELECT cliente_id, contenedor_id, entregados, retirados FROM fallback_detalle
    ),
    resumen_agrupado AS (
        SELECT 
            ec.cliente_id,
            c.razon_social,
            c.rif_nit,
            ec.contenedor_id,
            COALESCE(tc.codigo, p_leg.codigo_producto, 'ENV') AS codigo_producto,
            COALESCE(tc.nombre, p_leg.nombre, 'Envase') AS nombre_producto,
            SUM(ec.entregados)::INT AS entregado,
            SUM(ec.retirados)::INT AS retirado
        FROM envases_consolidados ec
        JOIN public.clientes c ON c.id = ec.cliente_id
        LEFT JOIN public.tipos_contenedores tc ON tc.id = ec.contenedor_id
        LEFT JOIN public.productos p_leg ON p_leg.id = ec.contenedor_id
        GROUP BY ec.cliente_id, c.razon_social, c.rif_nit, ec.contenedor_id,
                 COALESCE(tc.codigo, p_leg.codigo_producto, 'ENV'),
                 COALESCE(tc.nombre, p_leg.nombre, 'Envase')
        HAVING SUM(ec.entregados) > 0 OR SUM(ec.retirados) > 0
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
                        ) ORDER BY ra_inner.nombre_producto ASC
                    )
                    FROM resumen_agrupado ra_inner
                    WHERE ra_inner.cliente_id = ra.cliente_id
                )
            ) ORDER BY ra.razon_social ASC
        ),
        '[]'::jsonb
    )
    INTO v_resumen_vacios
    FROM (
        SELECT DISTINCT cliente_id, razon_social, rif_nit 
        FROM resumen_agrupado
    ) ra;

    -- Totales reales del radar (solo despachado efectivo y total de contenedores retirados)
    SELECT
        COALESCE(SUM(d.cantidad_solicitada), 0)::INT,
        COALESCE(SUM(CASE WHEN COALESCE(d.estado_entrega, 'pendiente') <> 'pendiente' THEN COALESCE(d.cantidad_despachada, 0) ELSE 0 END), 0)::INT
    INTO v_tot_solicitada, v_tot_despachada
    FROM public.ordenes_distribucion o
    JOIN public.detalle_distribucion d ON d.orden_id = o.id
    WHERE o.radar_id = p_radar_id
      AND o.estado <> 'anulada';

    SELECT COALESCE(SUM(mc.cantidad_retirada), 0)::INT
    INTO v_tot_retirados
    FROM public.ordenes_distribucion o
    JOIN public.movimientos_contenedores mc ON mc.orden_id = o.id
    WHERE o.radar_id = p_radar_id
      AND o.estado <> 'anulada';

    IF v_tot_retirados = 0 THEN
        SELECT COALESCE(SUM(COALESCE(d.contenedores_retirados, 0)), 0)::INT
        INTO v_tot_retirados
        FROM public.ordenes_distribucion o
        JOIN public.detalle_distribucion d ON d.orden_id = o.id
        WHERE o.radar_id = p_radar_id
          AND o.estado <> 'anulada'
          AND COALESCE(d.estado_entrega, 'pendiente') <> 'pendiente';
    END IF;

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
                            'cantidad_despachada', CASE
                                WHEN COALESCE(d.estado_entrega, 'pendiente') <> 'pendiente'
                                THEN COALESCE(d.cantidad_despachada, 0)
                                ELSE 0
                            END,
                            'valor_unitario_recaudar', d.valor_unitario_recaudar,
                            'subtotal_recaudar', d.subtotal_recaudar,
                            'valor_unitario_usd', d.valor_unitario_usd,
                            'subtotal_recaudar_usd', d.subtotal_recaudar_usd,
                            'estado_entrega', COALESCE(d.estado_entrega, 'pendiente'),
                            'motivo_rechazo', d.motivo_rechazo,
                            'contenedores_retirados', COALESCE(d.contenedores_retirados, 0),
                            'contenedor_id', COALESCE(d.contenedor_id, p.contenedor_id)
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
                'total_cantidad_solicitada', v_tot_solicitada,
                'total_cantidad_despachada', v_tot_despachada,
                'total_contenedores_retirados', v_tot_retirados,
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

ALTER FUNCTION public.retorna_radar_detalle_reporte(UUID) OWNER TO postgres;
GRANT EXECUTE ON FUNCTION public.retorna_radar_detalle_reporte(UUID) TO authenticated, service_role;


-- ------------------------------------------------------------------------------
-- 7. Función: retorna_reporte_autoventas_entregas_cliente
--    Incluye los contenedores entregados y retirados por cliente/orden y el
--    resumen general de vacíos (`resumen_vacios` y `resumen_contenedores`).
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.retorna_reporte_autoventas_entregas_cliente(
    p_camion_id UUID,
    p_fecha DATE DEFAULT CURRENT_DATE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_fecha DATE := COALESCE(p_fecha, (CURRENT_TIMESTAMP AT TIME ZONE 'America/Caracas')::DATE);
    v_total_general_usd NUMERIC(14,2) := 0.00;
    v_total_contenedores_entregados INT := 0;
    v_total_contenedores_retirados INT := 0;
    v_entregas JSONB;
    v_inventario JSONB;
    v_resumen_vacios JSONB;
    v_resumen_contenedores JSONB;
BEGIN
    IF p_camion_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del camión es requerido.');
    END IF;

    -- 1. Total general facturado en USD del día para este camión
    SELECT COALESCE(SUM(od.total_recaudar_usd), 0.00)
    INTO v_total_general_usd
    FROM public.ordenes_distribucion od
    WHERE od.camion_id = p_camion_id
      AND od.es_autoventa = TRUE
      AND (od.fecha_despacho AT TIME ZONE 'America/Caracas')::DATE = v_fecha
      AND od.estado != 'anulada';

    -- 2. Inventario cargado, entregado y sobrante/devolución en el camión
    SELECT jsonb_agg(
        jsonb_build_object(
            'producto_id', p.id,
            'codigo', p.codigo_producto,
            'nombre', p.nombre,
            'cantidad_cargada', COALESCE(im.cantidad_cargada, 0),
            'cantidad_entregada', COALESCE(im.cantidad_entregada, 0),
            'devolucion', GREATEST(0, COALESCE(im.cantidad_cargada, 0) - COALESCE(im.cantidad_entregada, 0))
        ) ORDER BY p.nombre ASC
    ) INTO v_inventario
    FROM public.inventario_movil im
    JOIN public.productos p ON im.producto_id = p.id
    WHERE im.camion_id = p_camion_id;

    -- 3. Entregas detalladas por orden/cliente (incluyendo productos y contenedores retirados/entregados)
    SELECT jsonb_agg(
        jsonb_build_object(
            'cliente_id', t.cliente_id,
            'razon_social', t.razon_social,
            'rif_nit', t.rif_nit,
            'orden_id', t.orden_id,
            'correlativo', t.correlativo,
            'total_orden_usd', t.total_recaudar_usd,
            'productos', COALESCE(t.productos, '[]'::jsonb),
            'contenedores', COALESCE(t.contenedores, '[]'::jsonb),
            'total_contenedores_entregados', COALESCE(t.total_contenedores_entregados, 0),
            'total_contenedores_retirados', COALESCE(t.total_contenedores_retirados, 0)
        ) ORDER BY t.correlativo ASC
    ) INTO v_entregas
    FROM (
        SELECT 
            c.id AS cliente_id,
            c.razon_social,
            c.rif_nit,
            od.id AS orden_id,
            od.correlativo,
            od.total_recaudar_usd,
            (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'producto_id', p.id,
                        'codigo', p.codigo_producto,
                        'nombre', p.nombre,
                        'cantidad_cargada', odd.cantidad_solicitada,
                        'cantidad_entregada', odd.cantidad_despachada,
                        'devolucion', COALESCE(odd.cantidad_solicitada, 0) - COALESCE(odd.cantidad_despachada, 0),
                        'precio_unitario_usd', odd.valor_unitario_usd,
                        'subtotal_usd', odd.subtotal_recaudar_usd
                    ) ORDER BY p.nombre ASC
                )
                FROM public.detalle_distribucion odd
                JOIN public.productos p ON odd.producto_id = p.id
                WHERE odd.orden_id = od.id
            ) AS productos,
            (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'contenedor_id', mc.contenedor_id,
                        'codigo', COALESCE(tc.codigo, 'ENV'),
                        'nombre', COALESCE(tc.nombre, 'Envase'),
                        'cantidad_entregada', COALESCE(mc.cantidad_entregada, 0),
                        'cantidad_retirada', COALESCE(mc.cantidad_retirada, 0)
                    ) ORDER BY tc.nombre ASC
                )
                FROM public.movimientos_contenedores mc
                LEFT JOIN public.tipos_contenedores tc ON tc.id = mc.contenedor_id
                WHERE mc.orden_id = od.id
            ) AS contenedores,
            (
                SELECT COALESCE(SUM(mc.cantidad_entregada), 0)::INT
                FROM public.movimientos_contenedores mc
                WHERE mc.orden_id = od.id
            ) AS total_contenedores_entregados,
            (
                SELECT COALESCE(SUM(mc.cantidad_retirada), 0)::INT
                FROM public.movimientos_contenedores mc
                WHERE mc.orden_id = od.id
            ) AS total_contenedores_retirados
        FROM public.ordenes_distribucion od
        JOIN public.clientes c ON od.cliente_id = c.id
        WHERE od.camion_id = p_camion_id
          AND od.es_autoventa = TRUE
          AND (od.fecha_despacho AT TIME ZONE 'America/Caracas')::DATE = v_fecha
          AND od.estado != 'anulada'
    ) t;

    -- 4. Resumen de vacíos agrupado por cliente (misma estructura que retorna_radar_detalle_reporte)
    WITH resumen_agrupado AS (
        SELECT
            od.cliente_id,
            c.razon_social,
            c.rif_nit,
            mc.contenedor_id,
            COALESCE(tc.codigo, 'ENV') AS codigo_producto,
            COALESCE(tc.nombre, 'Envase') AS nombre_producto,
            SUM(COALESCE(mc.cantidad_entregada, 0))::INT AS entregado,
            SUM(COALESCE(mc.cantidad_retirada, 0))::INT AS retirado
        FROM public.ordenes_distribucion od
        JOIN public.movimientos_contenedores mc ON mc.orden_id = od.id
        JOIN public.clientes c ON c.id = od.cliente_id
        LEFT JOIN public.tipos_contenedores tc ON tc.id = mc.contenedor_id
        WHERE od.camion_id = p_camion_id
          AND od.es_autoventa = TRUE
          AND (od.fecha_despacho AT TIME ZONE 'America/Caracas')::DATE = v_fecha
          AND od.estado != 'anulada'
        GROUP BY od.cliente_id, c.razon_social, c.rif_nit, mc.contenedor_id, tc.codigo, tc.nombre
        HAVING SUM(COALESCE(mc.cantidad_entregada, 0)) > 0 OR SUM(COALESCE(mc.cantidad_retirada, 0)) > 0
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
                        ) ORDER BY ra_inner.nombre_producto ASC
                    )
                    FROM resumen_agrupado ra_inner
                    WHERE ra_inner.cliente_id = ra.cliente_id
                )
            ) ORDER BY ra.razon_social ASC
        ),
        '[]'::jsonb
    )
    INTO v_resumen_vacios
    FROM (
        SELECT DISTINCT cliente_id, razon_social, rif_nit
        FROM resumen_agrupado
    ) ra;

    -- 5. Resumen consolidado por tipo de contenedor y totales generales de la jornada
    SELECT
        COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'contenedor_id', sub.contenedor_id,
                    'codigo', sub.codigo,
                    'nombre', sub.nombre,
                    'total_entregado', sub.total_entregado,
                    'total_retirado', sub.total_retirado
                ) ORDER BY sub.nombre ASC
            ),
            '[]'::jsonb
        ),
        COALESCE(SUM(sub.total_entregado), 0)::INT,
        COALESCE(SUM(sub.total_retirado), 0)::INT
    INTO v_resumen_contenedores, v_total_contenedores_entregados, v_total_contenedores_retirados
    FROM (
        SELECT
            mc.contenedor_id,
            COALESCE(tc.codigo, 'ENV') AS codigo,
            COALESCE(tc.nombre, 'Envase') AS nombre,
            SUM(COALESCE(mc.cantidad_entregada, 0))::INT AS total_entregado,
            SUM(COALESCE(mc.cantidad_retirada, 0))::INT AS total_retirado
        FROM public.ordenes_distribucion od
        JOIN public.movimientos_contenedores mc ON mc.orden_id = od.id
        LEFT JOIN public.tipos_contenedores tc ON tc.id = mc.contenedor_id
        WHERE od.camion_id = p_camion_id
          AND od.es_autoventa = TRUE
          AND (od.fecha_despacho AT TIME ZONE 'America/Caracas')::DATE = v_fecha
          AND od.estado != 'anulada'
        GROUP BY mc.contenedor_id, tc.codigo, tc.nombre
        HAVING SUM(COALESCE(mc.cantidad_entregada, 0)) > 0 OR SUM(COALESCE(mc.cantidad_retirada, 0)) > 0
    ) sub;

    RETURN jsonb_build_object(
        'success', true,
        'data', jsonb_build_object(
            'camion_id', p_camion_id,
            'fecha', v_fecha,
            'total_general_usd', v_total_general_usd,
            'total_contenedores_entregados', v_total_contenedores_entregados,
            'total_contenedores_retirados', v_total_contenedores_retirados,
            'inventario', COALESCE(v_inventario, '[]'::jsonb),
            'entregas', COALESCE(v_entregas, '[]'::jsonb),
            'resumen_vacios', COALESCE(v_resumen_vacios, '[]'::jsonb),
            'resumen_contenedores', COALESCE(v_resumen_contenedores, '[]'::jsonb)
        ),
        'error', NULL
    );
END;
$$;

ALTER FUNCTION public.retorna_reporte_autoventas_entregas_cliente(UUID, DATE) OWNER TO postgres;
GRANT EXECUTE ON FUNCTION public.retorna_reporte_autoventas_entregas_cliente(UUID, DATE) TO authenticated, service_role;


-- ------------------------------------------------------------------------------
-- 8. Función: retorna_resumen_autoventas_jornada
--    Incluye también resumen_contenedores y total_contenedores_retirados del día
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.retorna_resumen_autoventas_jornada(
    p_camion_id uuid,
    p_fecha date DEFAULT CURRENT_DATE
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_fecha DATE := COALESCE(p_fecha, (CURRENT_TIMESTAMP AT TIME ZONE 'America/Caracas')::DATE);
    v_inventario_movil JSONB;
    v_ventas_jornada JSONB;
    v_resumen_contenedores JSONB;
    v_total_ordenes INT := 0;
    v_total_facturado_usd NUMERIC(14,2) := 0.00;
    v_total_facturado_bs NUMERIC(14,2) := 0.00;
    v_total_contenedores_entregados INT := 0;
    v_total_contenedores_retirados INT := 0;
BEGIN
    IF p_camion_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del camión es requerido.');
    END IF;

    SELECT jsonb_agg(
        jsonb_build_object(
            'producto_id', p.id,
            'codigo', p.codigo_producto,
            'nombre', p.nombre,
            'cantidad_cargada', COALESCE(im.cantidad_cargada, 0),
            'cantidad_entregada', COALESCE(im.cantidad_entregada, 0),
            'cantidad_disponible', GREATEST(0, COALESCE(im.cantidad_cargada, 0) - COALESCE(im.cantidad_entregada, 0))
        ) ORDER BY p.nombre ASC
    ) INTO v_inventario_movil
    FROM public.inventario_movil im
    JOIN public.productos p ON im.producto_id = p.id
    WHERE im.camion_id = p_camion_id;

    SELECT
        COUNT(*)::INT,
        COALESCE(SUM(total_recaudar_usd), 0.00),
        COALESCE(SUM(total_recaudar_bs), 0.00)
    INTO v_total_ordenes, v_total_facturado_usd, v_total_facturado_bs
    FROM public.ordenes_distribucion
    WHERE camion_id = p_camion_id
      AND es_autoventa = TRUE
      AND (created_at AT TIME ZONE 'America/Caracas')::DATE = v_fecha
      AND estado <> 'anulada';

    SELECT jsonb_agg(
        jsonb_build_object(
            'orden_id', od.id,
            'correlativo', od.correlativo,
            'factura_origen_numero', od.factura_origen_numero,
            'cliente_nombre', c.razon_social,
            'estado', od.estado,
            'total_recaudar_usd', od.total_recaudar_usd,
            'total_recaudar_bs', od.total_recaudar_bs,
            'created_at', od.created_at,
            'contenedores_retirados', COALESCE((
                SELECT SUM(mc.cantidad_retirada)::INT
                FROM public.movimientos_contenedores mc
                WHERE mc.orden_id = od.id
            ), 0)
        ) ORDER BY od.created_at DESC
    ) INTO v_ventas_jornada
    FROM public.ordenes_distribucion od
    JOIN public.clientes c ON od.cliente_id = c.id
    WHERE od.camion_id = p_camion_id
      AND od.es_autoventa = TRUE
      AND (od.created_at AT TIME ZONE 'America/Caracas')::DATE = v_fecha;

    SELECT
        COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'contenedor_id', sub.contenedor_id,
                    'codigo', sub.codigo,
                    'nombre', sub.nombre,
                    'total_entregado', sub.total_entregado,
                    'total_retirado', sub.total_retirado
                ) ORDER BY sub.nombre ASC
            ),
            '[]'::jsonb
        ),
        COALESCE(SUM(sub.total_entregado), 0)::INT,
        COALESCE(SUM(sub.total_retirado), 0)::INT
    INTO v_resumen_contenedores, v_total_contenedores_entregados, v_total_contenedores_retirados
    FROM (
        SELECT
            mc.contenedor_id,
            COALESCE(tc.codigo, 'ENV') AS codigo,
            COALESCE(tc.nombre, 'Envase') AS nombre,
            SUM(COALESCE(mc.cantidad_entregada, 0))::INT AS total_entregado,
            SUM(COALESCE(mc.cantidad_retirada, 0))::INT AS total_retirado
        FROM public.ordenes_distribucion od
        JOIN public.movimientos_contenedores mc ON mc.orden_id = od.id
        LEFT JOIN public.tipos_contenedores tc ON tc.id = mc.contenedor_id
        WHERE od.camion_id = p_camion_id
          AND od.es_autoventa = TRUE
          AND (od.created_at AT TIME ZONE 'America/Caracas')::DATE = v_fecha
          AND od.estado <> 'anulada'
        GROUP BY mc.contenedor_id, tc.codigo, tc.nombre
        HAVING SUM(COALESCE(mc.cantidad_entregada, 0)) > 0 OR SUM(COALESCE(mc.cantidad_retirada, 0)) > 0
    ) sub;

    RETURN jsonb_build_object(
        'success', true,
        'data', jsonb_build_object(
            'camion_id', p_camion_id,
            'fecha', v_fecha,
            'total_ordenes_autoventa', v_total_ordenes,
            'total_facturado_usd', v_total_facturado_usd,
            'total_facturado_bs', v_total_facturado_bs,
            'total_contenedores_entregados', v_total_contenedores_entregados,
            'total_contenedores_retirados', v_total_contenedores_retirados,
            'inventario_movil', COALESCE(v_inventario_movil, '[]'::jsonb),
            'resumen_contenedores', COALESCE(v_resumen_contenedores, '[]'::jsonb),
            'ventas', COALESCE(v_ventas_jornada, '[]'::jsonb)
        ),
        'error', NULL
    );
END;
$$;

ALTER FUNCTION public.retorna_resumen_autoventas_jornada(uuid, date) OWNER TO postgres;
GRANT EXECUTE ON FUNCTION public.retorna_resumen_autoventas_jornada(uuid, date) TO authenticated, service_role;
