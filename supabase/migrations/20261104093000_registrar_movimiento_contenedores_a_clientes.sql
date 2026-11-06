-- ==============================================================================
-- Parche Idempotente: Módulo de Retiro / Movimiento de Contenedores a Clientes
--                     sin Orden de Distribución
-- Fecha: 2026-11-04 09:30:00
-- Descripción:
--   1. Asegura las columnas `observaciones`, `saldo_anterior` y `saldo_actual`
--      en `public.movimientos_contenedores` y elimina restricciones que impidan
--      saldos a favor del cliente (< 0).
--   2. Crea la función RPC `public.registrar_movimiento_contenedores_a_clientes`
--      para registrar retiros (y ajustes/entregas) de contenedores directamente
--      a un cliente sin requerir una Orden de Distribución (`orden_id = NULL`).
--   3. Actualiza `public.retorna_movimientos_contenedores_segun_cliente_id_rango_fechas`
--      para exponer `observaciones`, `saldo_anterior`, `saldo_actual` y el
--      indicador `es_movimiento_directo` (`orden_id IS NULL`).
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Asegurar columnas y flexibilidad de saldos en tablas de contenedores
-- ------------------------------------------------------------------------------
ALTER TABLE public.movimientos_contenedores
    ADD COLUMN IF NOT EXISTS saldo_anterior INT,
    ADD COLUMN IF NOT EXISTS saldo_actual INT,
    ADD COLUMN IF NOT EXISTS observaciones TEXT;

ALTER TABLE public.saldo_contenedores_clientes
    DROP CONSTRAINT IF EXISTS saldo_contenedores_clientes_saldo_pendiente_check;

ALTER TABLE public.movimientos_contenedores
    DROP CONSTRAINT IF EXISTS movimientos_contenedores_cantidad_entregada_check;

ALTER TABLE public.movimientos_contenedores
    DROP CONSTRAINT IF EXISTS movimientos_contenedores_cantidad_retirada_check;

COMMENT ON COLUMN public.movimientos_contenedores.observaciones IS
    'Observación o nota del movimiento de contenedores (especialmente útil en retiros directos sin orden de distribución).';

-- ------------------------------------------------------------------------------
-- 2. Función RPC: public.registrar_movimiento_contenedores_a_clientes
-- ------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.registrar_movimiento_contenedores_a_clientes(UUID, JSONB, TEXT, UUID);
DROP FUNCTION IF EXISTS public.registrar_movimiento_contenedores_a_clientes(UUID, JSONB, TEXT, UUID, JSONB, UUID);

CREATE OR REPLACE FUNCTION public.registrar_movimiento_contenedores_a_clientes(
    p_cliente_id UUID,
    p_movimientos JSONB DEFAULT NULL,
    p_observaciones TEXT DEFAULT NULL,
    p_creado_por UUID DEFAULT NULL,
    p_items JSONB DEFAULT NULL,
    p_usuario_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_cliente RECORD;
    v_usuario_id UUID;
    v_movimientos_norm JSONB;
    v_obs TEXT;
    v_rec RECORD;
    v_saldo_ant INT;
    v_saldo_act INT;
    v_movimiento_id UUID;
    v_total_entregados INT := 0;
    v_total_retirados INT := 0;
    v_resumen JSONB := '[]'::jsonb;
BEGIN
    -- 1. Validar cliente obligatorio y existencia
    IF p_cliente_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El identificador del cliente (p_cliente_id) es obligatorio.'
            )
        );
    END IF;

    SELECT id, rif_nit, razon_social
    INTO v_cliente
    FROM public.clientes
    WHERE id = p_cliente_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'CLIENTE_INEXISTENTE',
                'message', 'El cliente especificado no existe.'
            )
        );
    END IF;

    -- 2. Resolver usuario ejecutor y observación
    v_usuario_id := COALESCE(p_creado_por, p_usuario_id, auth.uid());
    v_obs := NULLIF(TRIM(COALESCE(p_observaciones, '')), '');

    -- 3. Normalizar p_movimientos (acepta array JSONB u objeto único JSONB)
    v_movimientos_norm := COALESCE(p_movimientos, p_items, '[]'::jsonb);
    IF jsonb_typeof(v_movimientos_norm) = 'object' THEN
        v_movimientos_norm := jsonb_build_array(v_movimientos_norm);
    END IF;

    IF jsonb_typeof(v_movimientos_norm) <> 'array' OR jsonb_array_length(v_movimientos_norm) = 0 THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'Debe enviar al menos un contenedor en p_movimientos.'
            )
        );
    END IF;

    -- 4. Validar formato y valores enteros >= 0 en cada elemento
    IF EXISTS (
        SELECT 1
        FROM jsonb_array_elements(v_movimientos_norm) e
        WHERE NULLIF(TRIM(COALESCE(e->>'contenedor_id', '')), '') IS NULL
           OR COALESCE(
                NULLIF(TRIM(COALESCE(e->>'cantidad_retirada', e->>'retirados', e->>'cantidad', '')), '')::numeric,
                0
              ) < 0
           OR COALESCE(
                NULLIF(TRIM(COALESCE(e->>'cantidad_retirada', e->>'retirados', e->>'cantidad', '')), '')::numeric,
                0
              ) <> trunc(COALESCE(
                NULLIF(TRIM(COALESCE(e->>'cantidad_retirada', e->>'retirados', e->>'cantidad', '')), '')::numeric,
                0
              ))
           OR COALESCE(
                NULLIF(TRIM(COALESCE(e->>'cantidad_entregada', e->>'entregados', '')), '')::numeric,
                0
              ) < 0
           OR COALESCE(
                NULLIF(TRIM(COALESCE(e->>'cantidad_entregada', e->>'entregados', '')), '')::numeric,
                0
              ) <> trunc(COALESCE(
                NULLIF(TRIM(COALESCE(e->>'cantidad_entregada', e->>'entregados', '')), '')::numeric,
                0
              ))
    ) THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'CONTENEDORES_INVALIDOS',
                'message', 'Cada elemento debe incluir un contenedor_id válido y cantidades enteras mayores o iguales a 0.'
            )
        );
    END IF;

    -- 5. Procesar movimientos agrupados por tipo de contenedor
    FOR v_rec IN
        WITH parsed AS (
            SELECT
                (NULLIF(TRIM(e->>'contenedor_id'), ''))::UUID AS contenedor_id,
                SUM(
                    COALESCE(
                        NULLIF(TRIM(COALESCE(e->>'cantidad_entregada', e->>'entregados', '')), '')::numeric,
                        0
                    )
                )::INT AS entregados,
                SUM(
                    COALESCE(
                        NULLIF(TRIM(COALESCE(e->>'cantidad_retirada', e->>'retirados', e->>'cantidad', '')), '')::numeric,
                        0
                    )
                )::INT AS retirados
            FROM jsonb_array_elements(v_movimientos_norm) e
            GROUP BY 1
        )
        SELECT
            p.contenedor_id,
            p.entregados,
            p.retirados,
            t.codigo,
            t.nombre
        FROM parsed p
        LEFT JOIN public.tipos_contenedores t ON t.id = p.contenedor_id
        WHERE p.entregados > 0 OR p.retirados > 0
        ORDER BY t.nombre NULLS LAST, p.contenedor_id
    LOOP
        IF v_rec.nombre IS NULL THEN
            RAISE EXCEPTION 'El tipo de contenedor % no existe en tipos_contenedores.', v_rec.contenedor_id
                USING ERRCODE = 'P0001';
        END IF;

        -- Bloquear fila de saldo actual del cliente para este contenedor
        v_saldo_ant := NULL;
        SELECT saldo_pendiente
        INTO v_saldo_ant
        FROM public.saldo_contenedores_clientes
        WHERE cliente_id = p_cliente_id
          AND contenedor_id = v_rec.contenedor_id
        FOR UPDATE;

        v_saldo_ant := COALESCE(v_saldo_ant, 0);

        -- Calcular nuevo saldo (permite saldo < 0 a favor del cliente si retira más de lo que debía)
        v_saldo_act := v_saldo_ant + v_rec.entregados - v_rec.retirados;

        -- Insertar movimiento directo sin orden de distribución (orden_id = NULL)
        INSERT INTO public.movimientos_contenedores (
            cliente_id,
            orden_id,
            contenedor_id,
            cantidad_entregada,
            cantidad_retirada,
            creado_por,
            saldo_anterior,
            saldo_actual,
            observaciones,
            created_at
        ) VALUES (
            p_cliente_id,
            NULL,
            v_rec.contenedor_id,
            v_rec.entregados,
            v_rec.retirados,
            v_usuario_id,
            v_saldo_ant,
            v_saldo_act,
            v_obs,
            NOW()
        )
        RETURNING id INTO v_movimiento_id;

        -- Actualizar o crear el saldo acumulado del cliente
        INSERT INTO public.saldo_contenedores_clientes (
            cliente_id,
            contenedor_id,
            saldo_pendiente,
            updated_at
        ) VALUES (
            p_cliente_id,
            v_rec.contenedor_id,
            v_saldo_act,
            NOW()
        )
        ON CONFLICT (cliente_id, contenedor_id)
        DO UPDATE SET
            saldo_pendiente = EXCLUDED.saldo_pendiente,
            updated_at = NOW();

        v_total_entregados := v_total_entregados + v_rec.entregados;
        v_total_retirados := v_total_retirados + v_rec.retirados;

        v_resumen := v_resumen || jsonb_build_array(jsonb_build_object(
            'movimiento_id', v_movimiento_id,
            'contenedor_id', v_rec.contenedor_id,
            'codigo', v_rec.codigo,
            'nombre', v_rec.nombre,
            'saldo_anterior', v_saldo_ant,
            'entregados', v_rec.entregados,
            'retirados', v_rec.retirados,
            'saldo_actual', v_saldo_act
        ));
    END LOOP;

    IF jsonb_array_length(v_resumen) = 0 THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'CANTIDADES_CERO',
                'message', 'Debe indicar al menos una cantidad retirada o entregada mayor a 0.'
            )
        );
    END IF;

    -- Registrar en logs_auditoria si existe la tabla
    IF to_regclass('public.logs_auditoria') IS NOT NULL THEN
        INSERT INTO public.logs_auditoria (
            tabla_afectada,
            accion,
            registro_id,
            usuario_id,
            valores_anteriores,
            valores_nuevos
        ) VALUES (
            'movimientos_contenedores',
            'MOVIMIENTO_DIRECTO_CONTENEDORES',
            p_cliente_id,
            v_usuario_id,
            NULL,
            jsonb_build_object(
                'cliente_id', p_cliente_id,
                'razon_social', v_cliente.razon_social,
                'total_entregados', v_total_entregados,
                'total_retirados', v_total_retirados,
                'observaciones', v_obs,
                'contenedores', v_resumen
            )
        );
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Movimiento de contenedores registrado exitosamente.',
        'data', jsonb_build_object(
            'cliente_id', v_cliente.id,
            'rif_nit', v_cliente.rif_nit,
            'razon_social', v_cliente.razon_social,
            'total_entregados', v_total_entregados,
            'total_retirados', v_total_retirados,
            'observaciones', v_obs,
            'fecha_movimiento', NOW(),
            'contenedores', v_resumen
        ),
        'error', NULL
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', FALSE,
        'data', NULL,
        'error', jsonb_build_object(
            'code', 'ERROR_INTERNO',
            'message', SQLERRM
        )
    );
END;
$$;

COMMENT ON FUNCTION public.registrar_movimiento_contenedores_a_clientes(UUID, JSONB, TEXT, UUID, JSONB, UUID) IS
    'Registra retiros (o entregas/ajustes) de contenedores directamente a un cliente sin necesidad de crear una Orden de Distribución (orden_id = NULL). Actualiza saldo_contenedores_clientes e inserta el historial en movimientos_contenedores.';

GRANT EXECUTE ON FUNCTION public.registrar_movimiento_contenedores_a_clientes(UUID, JSONB, TEXT, UUID, JSONB, UUID)
    TO anon, authenticated, service_role;

-- ------------------------------------------------------------------------------
-- 3. Actualizar retorna_movimientos_contenedores_segun_cliente_id_rango_fechas
--    para incluir observaciones, saldo_anterior, saldo_actual y es_movimiento_directo
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.retorna_movimientos_contenedores_segun_cliente_id_rango_fechas(
    p_cliente_id UUID,
    p_fecha_inicial DATE DEFAULT NULL,
    p_fecha_limite DATE DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_cliente RECORD;
    v_saldo_anterior INT := 0;
    v_total_entregados INT := 0;
    v_total_retirados INT := 0;
    v_saldo_final INT := 0;
    v_movimientos JSONB := '[]'::jsonb;
    v_result JSONB;
BEGIN
    IF p_cliente_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El parámetro p_cliente_id es obligatorio.'
            )
        );
    END IF;

    SELECT id, rif_nit, razon_social INTO v_cliente
    FROM public.clientes
    WHERE id = p_cliente_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'CLIENTE_INEXISTENTE',
                'message', 'El cliente especificado no existe.'
            )
        );
    END IF;

    IF p_fecha_inicial IS NULL THEN
        p_fecha_inicial := CURRENT_DATE - INTERVAL '30 days';
    END IF;

    IF p_fecha_limite IS NULL THEN
        p_fecha_limite := CURRENT_DATE;
    END IF;

    -- 1. Calcular Saldo Anterior acumulado antes de p_fecha_inicial
    SELECT COALESCE(SUM(cantidad_entregada - cantidad_retirada), 0)
    INTO v_saldo_anterior
    FROM public.movimientos_contenedores
    WHERE cliente_id = p_cliente_id
      AND created_at::DATE < p_fecha_inicial;

    -- 2. Calcular Totales entregados y retirados dentro del rango
    SELECT 
        COALESCE(SUM(cantidad_entregada), 0),
        COALESCE(SUM(cantidad_retirada), 0)
    INTO v_total_entregados, v_total_retirados
    FROM public.movimientos_contenedores
    WHERE cliente_id = p_cliente_id
      AND created_at::DATE BETWEEN p_fecha_inicial AND p_fecha_limite;

    v_saldo_final := v_saldo_anterior + v_total_entregados - v_total_retirados;

    -- 3. Extraer Detalle de Movimientos en el Rango
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', m.id,
            'fecha_movimiento', m.created_at,
            'orden_id', m.orden_id,
            'correlativo_orden', o.correlativo,
            'factura_origen_numero', o.factura_origen_numero,
            'es_movimiento_directo', (m.orden_id IS NULL),
            'contenedor_id', m.contenedor_id,
            'codigo_contenedor', t.codigo,
            'nombre_contenedor', t.nombre,
            'cantidad_entregada', m.cantidad_entregada,
            'cantidad_retirada', m.cantidad_retirada,
            'saldo_anterior', m.saldo_anterior,
            'saldo_actual', m.saldo_actual,
            'observaciones', m.observaciones
        ) ORDER BY m.created_at ASC
    ), '[]'::jsonb)
    INTO v_movimientos
    FROM public.movimientos_contenedores m
    LEFT JOIN public.ordenes_distribucion o ON m.orden_id = o.id
    LEFT JOIN public.tipos_contenedores t ON m.contenedor_id = t.id
    WHERE m.cliente_id = p_cliente_id
      AND m.created_at::DATE BETWEEN p_fecha_inicial AND p_fecha_limite;

    SELECT jsonb_build_object(
        'success', TRUE,
        'data', jsonb_build_object(
            'cliente_id', v_cliente.id,
            'rif_nit', v_cliente.rif_nit,
            'razon_social', v_cliente.razon_social,
            'fecha_inicial', p_fecha_inicial,
            'fecha_limite', p_fecha_limite,
            'saldo_anterior', v_saldo_anterior,
            'total_entregados', v_total_entregados,
            'total_retirados', v_total_retirados,
            'saldo_final', v_saldo_final,
            'movimientos', v_movimientos
        ),
        'error', NULL
    ) INTO v_result;

    RETURN v_result;
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', FALSE,
        'data', NULL,
        'error', jsonb_build_object(
            'code', 'SQL_ERROR',
            'message', SQLERRM
        )
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.retorna_movimientos_contenedores_segun_cliente_id_rango_fechas(UUID, DATE, DATE)
    TO anon, authenticated, service_role;
