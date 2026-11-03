-- ==============================================================================
-- Parche Idempotente: Configuración de Días de Visita en Clientes y
--                     Reversión de Entrega en Despacho de Órdenes de Distribución
-- Fecha: 2026-11-03 12:45:00
-- Descripción:
--   TAREA 1 (Días de Visita y Filtro en Cartera APK):
--   1. Añade columnas `dias_visita TEXT[]` (máx. 2 días) y `visita_cualquier_dia BOOLEAN`
--      a `public.clientes`, con constraints CHECK y trigger normalizador.
--   2. Crea función auxiliar `public.lt_dia_semana_actual_texto(DATE)` y actualiza
--      `public.retorna_ordenes_por_liquidar()` para exponer `dias_visita`,
--      `visita_cualquier_dia` y `vendedor_id`.
--
--   TAREA 2 (Reversión de Entrega en Despacho sin anular la Orden):
--   3. Crea RPC `public.reversar_entrega_orden_distribucion(p_orden_id UUID, p_motivo TEXT)`
--      que reversa transaccionalmente la entrega de una orden completa:
--      - Regresa estado a 'en_transito' (Radar / Ruta / Auto-Venta) o 'aprobada' (Venta Directa Almacén).
--      - Devuelve mercancía a `inventario_movil` o `inventario_almacen` según origen.
--      - Revierte envases en `saldo_contenedores_clientes` y `movimientos_contenedores`.
--      - Registra auditoría detallada en `public.logs_auditoria` (`accion = 'REVERSAR_ENTREGA'`).
--   4. Actualiza `retorna_radar_despachador()` y `retorna_ordenes_distribucion_segun_idradar()`
--      para que las paradas ya despachadas de un radar activo sigan visibles con su estado
--      y permitan accionar "Reversar Entrega" desde la UI.
--   5. Sincroniza `anular_orden_distribucion`, `editar_orden_distribucion` y
--      `registrar_despacho_cliente_radar` para soportar órdenes con entrega reversada
--      sin duplicar movimientos de inventario.
-- ==============================================================================

-- ==============================================================================
-- PARTE 1: DÍAS DE VISITA EN PUBLIC.CLIENTES
-- ==============================================================================

ALTER TABLE public.clientes
    ADD COLUMN IF NOT EXISTS dias_visita TEXT[] NOT NULL DEFAULT '{}'::TEXT[];

ALTER TABLE public.clientes
    ADD COLUMN IF NOT EXISTS visita_cualquier_dia BOOLEAN NOT NULL DEFAULT TRUE;

COMMENT ON COLUMN public.clientes.dias_visita IS
    'Días de visita asignados al cliente (máximo 2): valores permitidos en minúsculas sin tilde (lunes, martes, miercoles, jueves, viernes, sabado, domingo).';

COMMENT ON COLUMN public.clientes.visita_cualquier_dia IS
    'Indica si el cliente puede ser visitado cualquier día de la semana (TRUE) o únicamente en los días definidos en dias_visita (FALSE).';

-- Función auxiliar para obtener el nombre canónico del día de la semana
CREATE OR REPLACE FUNCTION public.lt_dia_semana_actual_texto(p_fecha DATE DEFAULT CURRENT_DATE)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE EXTRACT(ISODOW FROM COALESCE(p_fecha, CURRENT_DATE))::INT
        WHEN 1 THEN 'lunes'
        WHEN 2 THEN 'martes'
        WHEN 3 THEN 'miercoles'
        WHEN 4 THEN 'jueves'
        WHEN 5 THEN 'viernes'
        WHEN 6 THEN 'sabado'
        WHEN 7 THEN 'domingo'
    END;
$$;

-- Trigger normalizador para dias_visita y visita_cualquier_dia en clientes
CREATE OR REPLACE FUNCTION public.lt_clientes_normalizar_dias_visita()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_dia TEXT;
    v_dias_limpios TEXT[] := '{}'::TEXT[];
BEGIN
    IF NEW.dias_visita IS NULL THEN
        NEW.dias_visita := '{}'::TEXT[];
    END IF;

    -- Normalizar cada día (minúsculas, sin tildes, sin duplicados)
    IF array_length(NEW.dias_visita, 1) IS NOT NULL THEN
        FOREACH v_dia IN ARRAY NEW.dias_visita LOOP
            v_dia := LOWER(TRIM(COALESCE(v_dia, '')));
            v_dia := TRANSLATE(v_dia, 'áéíóúÁÉÍÓÚ', 'aeiouaeiou');
            IF v_dia <> '' AND NOT (v_dia = ANY(v_dias_limpios)) THEN
                v_dias_limpios := array_append(v_dias_limpios, v_dia);
            END IF;
        END LOOP;
    END IF;

    NEW.dias_visita := v_dias_limpios;

    -- Si no tiene días específicos asignados, asegurar visita_cualquier_dia = TRUE
    IF COALESCE(array_length(NEW.dias_visita, 1), 0) = 0 THEN
        NEW.visita_cualquier_dia := TRUE;
    ELSIF NEW.visita_cualquier_dia IS NULL THEN
        NEW.visita_cualquier_dia := FALSE;
    END IF;

    -- Si explícitamente se marca visita_cualquier_dia = TRUE y no se enviaron cambios en dias_visita,
    -- se permite conservar o limpiar; si supera 2 días, se rechaza en el CHECK constraint.
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_clientes_normalizar_dias_visita ON public.clientes;
CREATE TRIGGER trg_clientes_normalizar_dias_visita
    BEFORE INSERT OR UPDATE OF dias_visita, visita_cualquier_dia ON public.clientes
    FOR EACH ROW
    EXECUTE FUNCTION public.lt_clientes_normalizar_dias_visita();

-- Normalizar filas existentes antes de aplicar constraints
UPDATE public.clientes
SET dias_visita = COALESCE(dias_visita, '{}'::TEXT[]),
    visita_cualquier_dia = COALESCE(visita_cualquier_dia, TRUE);

ALTER TABLE public.clientes
    DROP CONSTRAINT IF EXISTS clientes_dias_visita_max_check;

ALTER TABLE public.clientes
    ADD CONSTRAINT clientes_dias_visita_max_check
    CHECK (COALESCE(array_length(dias_visita, 1), 0) <= 2);

ALTER TABLE public.clientes
    DROP CONSTRAINT IF EXISTS clientes_dias_visita_valores_check;

ALTER TABLE public.clientes
    ADD CONSTRAINT clientes_dias_visita_valores_check
    CHECK (dias_visita <@ ARRAY['lunes', 'martes', 'miercoles', 'jueves', 'viernes', 'sabado', 'domingo']::TEXT[]);


-- Actualizar retorna_ordenes_por_liquidar para incluir dias_visita y visita_cualquier_dia
CREATE OR REPLACE FUNCTION public.retorna_ordenes_por_liquidar()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_data JSONB;
BEGIN
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'cliente_id', sub.cliente_id,
                'razon_social', sub.razon_social,
                'rif_nit', sub.rif_nit,
                'vendedor_id', sub.vendedor_id,
                'dias_visita', COALESCE(sub.dias_visita, '{}'::TEXT[]),
                'visita_cualquier_dia', COALESCE(sub.visita_cualquier_dia, TRUE),
                'dias_vencidos', sub.dias_vencidos,
                'cant_ordenes', sub.cant_ordenes,
                'monto_por_liquidar', sub.monto_por_liquidar
            )
            ORDER BY sub.dias_vencidos DESC
        ),
        '[]'::jsonb
    )
    INTO v_data
    FROM (
        SELECT
            c.id AS cliente_id,
            c.razon_social,
            c.rif_nit,
            c.vendedor_id,
            c.dias_visita,
            c.visita_cualquier_dia,
            (CURRENT_DATE - MIN(od.fecha_despacho::date))::INT AS dias_vencidos,
            COUNT(od.id)::INT AS cant_ordenes,
            SUM(
                COALESCE(od.total_recaudar_usd, 0.00)
                - COALESCE(abonos.total_recaudado_usd, 0.00)
            ) AS monto_por_liquidar
        FROM public.ordenes_distribucion od
        JOIN public.clientes c ON c.id = od.cliente_id
        LEFT JOIN LATERAL (
            SELECT SUM(COALESCE(dro.recaudado, 0.00)) AS total_recaudado_usd
            FROM public.detalle_rendicion_ordenes dro
            JOIN public.rendiciones_cuentas rc ON dro.rendicion_id = rc.id
            WHERE dro.orden_distribucion_id = od.id
              AND rc.estado = 'aprobada'
        ) abonos ON TRUE
        WHERE od.estado = 'por_liquidar'
          AND (od.es_cortesia IS NULL OR od.es_cortesia = FALSE)
        GROUP BY c.id, c.razon_social, c.rif_nit, c.vendedor_id, c.dias_visita, c.visita_cualquier_dia
    ) sub;

    RETURN jsonb_build_object(
        'success', TRUE,
        'dia_actual', public.lt_dia_semana_actual_texto(CURRENT_DATE),
        'data', v_data,
        'error', NULL
    );

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
$function$;

GRANT EXECUTE ON FUNCTION public.retorna_ordenes_por_liquidar() TO authenticated, service_role;


-- ==============================================================================
-- PARTE 2: REVERSIÓN DE ENTREGA EN DESPACHO (SIN ANULAR LA ORDEN)
-- ==============================================================================

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
    v_orden RECORD;
    v_det RECORD;
    v_mov_cont RECORD;
    v_rendicion_activa RECORD;
    v_status_radar BOOLEAN := FALSE;
    v_origen_orden TEXT;
    v_nuevo_estado TEXT;
    v_cant_desp INT;
    v_cant_dev INT;
    v_saldo_act INT;
    v_nuevo_saldo INT;
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
                'message', 'Debes iniciar sesión para reversar la entrega de una orden.'
            )
        );
    END IF;

    -- 2. Validar parámetro obligatorio
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

    -- 3. Bloquear orden a reversar
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

    -- 4. Bloquear si es registro de saldo inicial CxC
    IF COALESCE(v_orden.es_saldo_inicial, FALSE) = TRUE THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'ORDEN_SALDO_INICIAL',
                'message', 'No se puede reversar entrega sobre un registro de saldo inicial de cuentas por cobrar.'
            )
        );
    END IF;

    -- 5. Validar que la orden tenga una entrega procesada susceptible de reversión
    IF v_orden.estado NOT IN ('por_liquidar', 'despachada', 'devuelta') THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo se puede reversar la entrega de órdenes ya despachadas/entregadas (estados: por_liquidar, despachada o devuelta). Estado actual: ' || COALESCE(v_orden.estado, 'desconocido')
            )
        );
    END IF;

    -- 6. Bloquear si posee rendición de cuentas activa
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
                'message', 'No se puede reversar la entrega porque la orden tiene una rendición de cuentas activa (ID: ' || COALESCE(SUBSTRING(v_rendicion_activa.rendicion_id::text, 1, 8), '') || ', Estado: ' || v_rendicion_activa.estado_rendicion || '). Debe reversar la rendición primero.'
            )
        );
    END IF;

    -- 7. Si pertenece a un Radar, validar que el Radar no haya sido cerrado/aprobado por Gerencia
    IF v_orden.radar_id IS NOT NULL THEN
        SELECT COALESCE(status_radar, FALSE)
        INTO v_status_radar
        FROM public.radars
        WHERE id = v_orden.radar_id;

        IF v_status_radar = TRUE THEN
            RETURN jsonb_build_object(
                'success', false,
                'data', NULL,
                'error', jsonb_build_object(
                    'code', 'RADAR_APROBADO_BLOQUEADO',
                    'message', 'No se puede reversar la entrega porque el radar asociado ya fue aprobado y cerrado por la Gerencia.'
                )
            );
        END IF;
    END IF;

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
        'estado_orden', v_orden.estado,
        'origen_venta', v_orden.origen_venta,
        'es_autoventa', COALESCE(v_orden.es_autoventa, FALSE),
        'radar_id', v_orden.radar_id,
        'camion_id', v_orden.camion_id,
        'detalles', v_detalles_previos,
        'movimientos_contenedores', v_contenedores_previos
    );

    -- 9. Determinar origen de la orden, estado de retorno y reversar inventario
    IF v_orden.origen_venta = 'ALMACEN' OR (v_orden.camion_id IS NULL AND COALESCE(v_orden.es_autoventa, FALSE) = FALSE) THEN
        -- Caso A: Venta Directa desde Almacén -> regresa a 'aprobada' y devuelve stock a inventario_almacen
        v_origen_orden := 'VENTA_DIRECTA_ALMACEN';
        v_nuevo_estado := 'aprobada';

        FOR v_det IN
            SELECT producto_id, COALESCE(cantidad_despachada, cantidad_solicitada, 0) AS cantidad
            FROM public.detalle_distribucion
            WHERE orden_id = p_orden_id
        LOOP
            IF v_det.cantidad > 0 THEN
                UPDATE public.inventario_almacen
                SET stock_disponible = stock_disponible + v_det.cantidad,
                    updated_at = NOW()
                WHERE producto_id = v_det.producto_id;
            END IF;
        END LOOP;

        UPDATE public.detalle_distribucion
        SET cantidad_despachada = 0,
            estado_entrega = 'pendiente',
            motivo_rechazo = NULL,
            contenedores_retirados = 0
        WHERE orden_id = p_orden_id;

    ELSIF COALESCE(v_orden.es_autoventa, FALSE) = TRUE THEN
        -- Caso B: Auto-Venta en ruta -> regresa a 'en_transito' y devuelve stock a inventario_movil del camión
        v_origen_orden := 'AUTOVENTA';
        v_nuevo_estado := 'en_transito';

        IF v_orden.camion_id IS NOT NULL THEN
            FOR v_det IN
                SELECT producto_id,
                       COALESCE(cantidad_solicitada, 0) AS cant_sol,
                       COALESCE(cantidad_despachada, cantidad_solicitada, 0) AS cant_desp
                FROM public.detalle_distribucion
                WHERE orden_id = p_orden_id
            LOOP
                v_cant_desp := GREATEST(0, v_det.cant_desp);
                v_cant_dev := GREATEST(0, v_det.cant_sol - v_cant_desp);

                UPDATE public.inventario_movil
                SET cantidad_entregada = GREATEST(0, COALESCE(cantidad_entregada, 0) - v_cant_desp),
                    cantidad_devolucion = GREATEST(0, COALESCE(cantidad_devolucion, 0) - v_cant_dev),
                    updated_at = NOW()
                WHERE camion_id = v_orden.camion_id AND producto_id = v_det.producto_id;
            END LOOP;
        END IF;

        UPDATE public.detalle_distribucion
        SET cantidad_despachada = cantidad_solicitada,
            estado_entrega = 'pendiente',
            motivo_rechazo = NULL,
            contenedores_retirados = 0
        WHERE orden_id = p_orden_id;

    ELSE
        -- Caso C: Orden despachada por Radar / Ruta -> regresa a 'en_transito' y revierte entrega en inventario_movil
        v_origen_orden := CASE WHEN v_orden.radar_id IS NOT NULL THEN 'RADAR' ELSE 'RUTA' END;
        v_nuevo_estado := 'en_transito';

        IF v_orden.camion_id IS NOT NULL THEN
            FOR v_det IN
                SELECT producto_id,
                       COALESCE(cantidad_solicitada, 0) AS cant_sol,
                       COALESCE(cantidad_despachada, 0) AS cant_desp,
                       COALESCE(estado_entrega, 'pendiente') AS est_entrega
                FROM public.detalle_distribucion
                WHERE orden_id = p_orden_id
            LOOP
                -- Solo revertimos en inventario_movil las líneas cuya entrega fue procesada
                IF v_det.est_entrega <> 'pendiente' THEN
                    v_cant_desp := GREATEST(0, v_det.cant_desp);
                    v_cant_dev := GREATEST(0, v_det.cant_sol - v_cant_desp);

                    UPDATE public.inventario_movil
                    SET cantidad_entregada = GREATEST(0, COALESCE(cantidad_entregada, 0) - v_cant_desp),
                        cantidad_devolucion = GREATEST(0, COALESCE(cantidad_devolucion, 0) - v_cant_dev),
                        updated_at = NOW()
                    WHERE camion_id = v_orden.camion_id AND producto_id = v_det.producto_id;
                END IF;
            END LOOP;
        END IF;

        UPDATE public.detalle_distribucion
        SET cantidad_despachada = cantidad_solicitada,
            estado_entrega = 'pendiente',
            motivo_rechazo = NULL,
            contenedores_retirados = 0
        WHERE orden_id = p_orden_id;
    END IF;

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

    -- 11. Actualizar estado de la Orden de Distribución (NUNCA a 'anulada')
    UPDATE public.ordenes_distribucion
    SET estado = v_nuevo_estado,
        observaciones = COALESCE(observaciones, '') ||
                        ' [ENTREGA REVERSADA el ' || TO_CHAR(NOW(), 'YYYY-MM-DD HH24:MI:SS') ||
                        CASE WHEN p_motivo IS NOT NULL AND TRIM(p_motivo) <> '' THEN ' - Motivo: ' || TRIM(p_motivo) ELSE '' END || ']'
    WHERE id = p_orden_id;

    -- 12. Registrar evento explícito en public.logs_auditoria
    v_valores_nuevos := jsonb_build_object(
        'estado_orden', v_nuevo_estado,
        'origen_detectado', v_origen_orden,
        'motivo_reversion', NULLIF(TRIM(COALESCE(p_motivo, '')), ''),
        'ejecutado_por', v_usuario_id,
        'fecha_reversion', NOW()
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
        'REVERSAR_ENTREGA',
        p_orden_id,
        v_valores_anteriores,
        v_valores_nuevos,
        NOW()
    );

    RETURN jsonb_build_object(
        'success', true,
        'message', 'Entrega reversada exitosamente. La orden regresó a estado ' || v_nuevo_estado || ' y la mercancía fue devuelta al inventario correspondiente.',
        'data', jsonb_build_object(
            'orden_id', p_orden_id,
            'correlativo', v_orden.correlativo,
            'origen_orden', v_origen_orden,
            'estado_anterior', v_orden.estado,
            'estado_nuevo', v_nuevo_estado
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
    'Reversa la entrega de una orden de distribución sin anularla, regresando su estado a en_transito o aprobada según su origen (Radar/AutoVenta/Almacén), devolviendo el stock a inventario_movil o inventario_almacen, revirtiendo envases y dejando traza en logs_auditoria.';


-- ==============================================================================
-- PARTE 3: ACTUALIZAR CONSULTAS DE RADAR PARA MOSTRAR ENTREGAS PROCESADAS
--          DEL RADAR ACTIVO Y PERMITIR REVERSARLAS DESDE LA UI
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.retorna_radar_despachador()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_despachador_id UUID;
    v_resultado JSONB;
BEGIN
    v_despachador_id := auth.uid();

    IF v_despachador_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'NO_AUTENTICADO',
                'message', 'El usuario no está autenticado.'
            )
        );
    END IF;

    SELECT jsonb_build_object(
        'success', TRUE,
        'total_ordenes', COUNT(o.id),
        'data', COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'orden_id', o.id,
                    'correlativo', o.correlativo,
                    'estado', o.estado,
                    'radar_id', o.radar_id,
                    'es_autoventa', COALESCE(o.es_autoventa, FALSE),
                    'origen_venta', COALESCE(o.origen_venta, 'RUTA'),
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
                        'nombre_ruta', r.nombre_ruta,
                        'limite_credito', COALESCE(c.limite_credito, 0.00),
                        'max_facturas_vencidas', COALESCE(c.max_facturas_vencidas, 0),
                        'permiso_despacho_manual', COALESCE(c.permiso_despacho_manual, TRUE),
                        'excepcion_despacho_gerencia', COALESCE(c.excepcion_despacho_gerencia, FALSE),
                        'despacho_permitido', (
                            COALESCE(c.excepcion_despacho_gerencia, FALSE) = TRUE OR (
                                COALESCE(c.permiso_despacho_manual, TRUE) = TRUE
                                AND (COALESCE(c.limite_credito, 0.00) = 0.00 OR COALESCE(o.total_recaudar_bs, (COALESCE(o.total_recaudar_usd, 0.00) * COALESCE(o.tasa_cambio, 1.00)), 0.00) <= COALESCE(c.limite_credito, 0.00))
                            )
                        ),
                        'motivo_bloqueo', CASE
                            WHEN COALESCE(c.excepcion_despacho_gerencia, FALSE) = TRUE THEN NULL
                            WHEN COALESCE(c.permiso_despacho_manual, TRUE) = FALSE THEN 'Despacho bloqueado manualmente por política de crédito'
                            WHEN COALESCE(c.limite_credito, 0.00) > 0.00 AND COALESCE(o.total_recaudar_bs, (COALESCE(o.total_recaudar_usd, 0.00) * COALESCE(o.tasa_cambio, 1.00)), 0.00) > COALESCE(c.limite_credito, 0.00) THEN 'Monto de la orden supera el límite de crédito del cliente'
                            ELSE NULL
                        END
                    ),
                    'detalles', (
                        SELECT COALESCE(jsonb_agg(
                            jsonb_build_object(
                                'detalle_id', d.id,
                                'producto_id', p.id,
                                'codigo_producto', p.codigo_producto,
                                'nombre_producto', p.nombre,
                                'cantidad_solicitada', d.cantidad_solicitada,
                                'cantidad_despachada', COALESCE(d.cantidad_despachada, 0),
                                'valor_unitario_recaudar', d.valor_unitario_recaudar,
                                'subtotal_recaudar', d.subtotal_recaudar,
                                'valor_unitario_usd', d.valor_unitario_usd,
                                'subtotal_recaudar_usd', d.subtotal_recaudar_usd,
                                'precio_lista_usd', COALESCE(d.precio_lista_usd, d.valor_unitario_usd, 0.00),
                                'porcentaje_descuento', COALESCE(d.porcentaje_descuento, 0.00),
                                'monto_descuento_usd', COALESCE(d.monto_descuento_usd, 0.00),
                                'estado_entrega', COALESCE(d.estado_entrega, 'pendiente'),
                                'motivo_rechazo', d.motivo_rechazo,
                                'contenedores_retirados', COALESCE(d.contenedores_retirados, 0),
                                'contenedor_id', d.contenedor_id
                            )
                        ), '[]'::jsonb)
                        FROM public.detalle_distribucion d
                        JOIN public.productos p ON d.producto_id = p.id
                        WHERE d.orden_id = o.id
                    ),
                    'saldo_contenedores', (
                        SELECT COALESCE(jsonb_agg(
                            jsonb_build_object(
                                'contenedor_id', tc.id,
                                'nombre_contenedor', tc.nombre,
                                'saldo_pendiente', COALESCE(sc.saldo_pendiente, 0)
                            )
                        ), '[]'::jsonb)
                        FROM public.tipos_contenedores tc
                        LEFT JOIN public.saldo_contenedores_clientes sc ON sc.contenedor_id = tc.id AND sc.cliente_id = c.id
                    )
                ) ORDER BY o.correlativo ASC
            ),
            '[]'::jsonb
        )
    ) INTO v_resultado
    FROM public.ordenes_distribucion o
    JOIN public.clientes c ON o.cliente_id = c.id
    LEFT JOIN public.rutas r ON c.id_ruta = r.id_ruta
    LEFT JOIN public.radars rad ON o.radar_id = rad.id
    WHERE COALESCE(o.despachador_id, c.despachador_id) = v_despachador_id
      AND (
          o.estado IN ('en_transito', 'despachada')
          OR (
              o.radar_id IS NOT NULL
              AND COALESCE(rad.status_radar, FALSE) = FALSE
              AND o.estado IN ('por_liquidar', 'devuelta')
          )
      );

    RETURN v_resultado;
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
    WHERE o.radar_id = p_radar_id;

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


-- ==============================================================================
-- PARTE 4: SINCRONIZAR ANULAR, EDITAR Y REGISTRAR DESPACHO PARA EVITAR DOBLE
--          REVERSIÓN DE STOCK EN ÓRDENES CON ENTREGA REVERSADA
-- ==============================================================================

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
-- 4.2. editar_orden_distribucion (Soporte para órdenes con entrega reversada)
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
    v_estado_entrega_linea TEXT;
    v_cant_despachada_linea INT;
    v_nuevo_estado_orden TEXT;
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

    -- 1. Reversar inventario de las líneas actuales SOLO si la entrega estaba asentada (por_liquidar / despachada)
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

    -- 3. Validar stock disponible para las nuevas líneas (en AutoVenta o Venta Directa Almacén)
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

    -- Determinar estado de entrega de línea y estado de la orden tras editar
    IF COALESCE(v_orden.es_autoventa, false) = true OR v_orden.origen_venta = 'ALMACEN' OR v_orden.camion_id IS NULL THEN
        v_estado_entrega_linea := 'entregado';
        v_nuevo_estado_orden := 'por_liquidar';
    ELSIF v_orden.estado IN ('borrador', 'aprobada', 'en_transito') THEN
        v_estado_entrega_linea := 'pendiente';
        v_nuevo_estado_orden := v_orden.estado;
    ELSE
        v_estado_entrega_linea := 'entregado';
        v_nuevo_estado_orden := v_orden.estado;
    END IF;

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

        v_cant_despachada_linea := CASE
            WHEN v_nuevo_estado_orden IN ('borrador', 'aprobada') THEN 0
            ELSE v_cantidad
        END;

        INSERT INTO public.detalle_distribucion (
            id, orden_id, producto_id, cantidad_solicitada, cantidad_despachada,
            valor_unitario_usd, subtotal_recaudar_usd, secuencia_entrega, estado_entrega
        ) VALUES (
            gen_random_uuid(), p_orden_id, v_producto_id, v_cantidad, v_cant_despachada_linea,
            v_val_usd, v_subtotal_usd, v_secuencia, v_estado_entrega_linea
        );
        v_secuencia := v_secuencia + 1;

        -- Aplicar descuento de inventario en AutoVenta o Venta Directa Almacén
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
    SET estado = v_nuevo_estado_orden,
        total_recaudar_usd = v_total_usd,
        total_recaudar_bs = v_total_bs,
        peso_total_calculado = v_peso_total,
        observaciones = CASE
            WHEN p_observaciones IS NOT NULL AND TRIM(p_observaciones) <> ''
            THEN TRIM(p_observaciones) || ' [EDITADA ' || TO_CHAR(NOW(), 'YYYY-MM-DD HH24:MI') || ']'
            ELSE COALESCE(observaciones, '') || ' [EDITADA ' || TO_CHAR(NOW(), 'YYYY-MM-DD HH24:MI') || ']'
        END
    WHERE id = p_orden_id;

    -- 6. Asentar nuevos envases llamando a lt_asentar_contenedores_orden (si la orden queda entregada)
    IF p_contenedores_json IS NOT NULL AND v_nuevo_estado_orden = 'por_liquidar' THEN
        v_contenedores_resumen := public.lt_asentar_contenedores_orden(p_orden_id, p_contenedores_json);
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'message', 'Orden de distribución editada exitosamente.',
        'data', jsonb_build_object(
            'orden_id', p_orden_id,
            'correlativo', v_orden.correlativo,
            'estado', v_nuevo_estado_orden,
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
