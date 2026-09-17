-- Migración: Funciones RPC de Saldo e Historial de Movimientos de Contenedores por Cliente

-- 1. Función: retorna_saldo_contenedores_segun_clientes
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
        -- Retornar todos los clientes que poseen saldo_pendiente > 0
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
        WHERE s.saldo_pendiente > 0;

    ELSE
        -- Retornar el saldo del cliente especificado.
        -- Si posee registros en saldo_contenedores_clientes, retornarlos todos.
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
            -- Verificar si el cliente existe
            IF NOT EXISTS (SELECT 1 FROM public.clientes WHERE id = p_cliente_id) THEN
                RETURN jsonb_build_object(
                    'success', FALSE,
                    'data', NULL,
                    'error', jsonb_build_object(
                        'code', 'CLIENTE_INEXISTENTE',
                        'message', 'El cliente especificado no existe.'
                    )
                );
            END IF;

            -- Retornar fila sintética con saldo_pendiente = 0 si el cliente no posee registros de saldo aún
            SELECT jsonb_build_object(
                'success', TRUE,
                'data', jsonb_build_array(
                    jsonb_build_object(
                        'cliente_id', c.id,
                        'rif_nit', c.rif_nit,
                        'razon_social', c.razon_social,
                        'contenedor_id', NULL,
                        'codigo_contenedor', NULL,
                        'nombre_contenedor', NULL,
                        'saldo_pendiente', 0,
                        'updated_at', c.created_at
                    )
                ),
                'error', NULL
            ) INTO v_result
            FROM public.clientes c
            WHERE c.id = p_cliente_id;
        END IF;
    END IF;

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

-- 2. Función: retorna_movimientos_contenedores_segun_cliente_id_rango_fechas
CREATE OR REPLACE FUNCTION public.retorna_movimientos_contenedores_segun_cliente_id_rango_fechas(
    p_cliente_id UUID,
    p_fecha_inicial DATE DEFAULT NULL,
    p_fecha_limite DATE DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
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
    -- Validar parámetro obligatorio p_cliente_id
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

    -- Validar que el cliente exista
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

    -- Si las fechas no vienen especificadas, asignar valores por defecto (últimos 30 días)
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
            'contenedor_id', m.contenedor_id,
            'codigo_contenedor', t.codigo,
            'nombre_contenedor', t.nombre,
            'cantidad_entregada', m.cantidad_entregada,
            'cantidad_retirada', m.cantidad_retirada
        ) ORDER BY m.created_at ASC
    ), '[]'::jsonb)
    INTO v_movimientos
    FROM public.movimientos_contenedores m
    LEFT JOIN public.ordenes_distribucion o ON m.orden_id = o.id
    LEFT JOIN public.tipos_contenedores t ON m.contenedor_id = t.id
    WHERE m.cliente_id = p_cliente_id
      AND m.created_at::DATE BETWEEN p_fecha_inicial AND p_fecha_limite;

    -- Construir respuesta JSON exitosa
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

-- Otorgar permisos de ejecución a los roles de Supabase
GRANT EXECUTE ON FUNCTION public.retorna_saldo_contenedores_segun_clientes(UUID) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.retorna_movimientos_contenedores_segun_cliente_id_rango_fechas(UUID, DATE, DATE) TO anon, authenticated, service_role;
