-- Función RPC: public.registrar_movimiento_contenedores_a_clientes
-- Registra retiros (o entregas/ajustes) de contenedores directamente a un cliente
-- sin necesidad de crear una Orden de Distribución (orden_id = NULL).

CREATE OR REPLACE FUNCTION public.registrar_movimiento_contenedores_a_clientes(
    p_cliente_id UUID,
    p_movimientos JSONB DEFAULT '[]'::jsonb,
    p_observaciones TEXT DEFAULT NULL,
    p_creado_por UUID DEFAULT NULL
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

    v_usuario_id := COALESCE(p_creado_por, auth.uid());
    v_obs := NULLIF(TRIM(COALESCE(p_observaciones, '')), '');

    v_movimientos_norm := COALESCE(p_movimientos, '[]'::jsonb);
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

        v_saldo_ant := NULL;
        SELECT saldo_pendiente
        INTO v_saldo_ant
        FROM public.saldo_contenedores_clientes
        WHERE cliente_id = p_cliente_id
          AND contenedor_id = v_rec.contenedor_id
        FOR UPDATE;

        v_saldo_ant := COALESCE(v_saldo_ant, 0);
        v_saldo_act := v_saldo_ant + v_rec.entregados - v_rec.retirados;

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
