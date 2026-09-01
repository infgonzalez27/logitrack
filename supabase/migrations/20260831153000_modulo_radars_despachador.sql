-- Migración para el Módulo de Control de Radares por Despachador (Sección 4 de PROPOSICION-CAMBIOS-DB.md)

-- 1. Tabla Maestra de Radares (public.radars)
CREATE TABLE IF NOT EXISTS public.radars (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    correlativo SERIAL UNIQUE,
    despachador_id UUID NOT NULL REFERENCES public.perfiles_usuario(id) ON DELETE RESTRICT,
    fecha_despacho DATE NOT NULL DEFAULT CURRENT_DATE,
    total_cantidad_solicitada NUMERIC(10,0) DEFAULT 0,
    total_cantidad_despachada NUMERIC(10,0) DEFAULT 0,
    total_contenedores_retirados NUMERIC(10,0) DEFAULT 0,
    status_radar BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Índices de optimización para la tabla radars
CREATE INDEX IF NOT EXISTS idx_radars_despachador_fecha ON public.radars(despachador_id, fecha_despacho);
CREATE INDEX IF NOT EXISTS idx_radars_status ON public.radars(status_radar);

-- 2. Relación en Cabecera de Orden (ordenes_distribucion.radar_id)
ALTER TABLE public.ordenes_distribucion
ADD COLUMN IF NOT EXISTS radar_id UUID REFERENCES public.radars(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_ordenes_distribucion_radar_id ON public.ordenes_distribucion(radar_id);

-- 3. Habilitar RLS en public.radars
ALTER TABLE public.radars ENABLE ROW LEVEL SECURITY;

-- Políticas RLS para public.radars
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'radars' AND policyname = 'Permitir lectura de radares a usuarios autenticados'
    ) THEN
        CREATE POLICY "Permitir lectura de radares a usuarios autenticados" 
        ON public.radars FOR SELECT 
        TO authenticated 
        USING (true);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'radars' AND policyname = 'Permitir insercion y actualizacion de radares a usuarios autenticados'
    ) THEN
        CREATE POLICY "Permitir insercion y actualizacion de radares a usuarios autenticados" 
        ON public.radars FOR ALL 
        TO authenticated 
        USING (true) 
        WITH CHECK (true);
    END IF;
END $$;


-- =============================================================================
-- 4. PROCEDIMIENTOS ALMACENADOS (RPC)
-- =============================================================================

-- 4.1 RPC: crear_o_obtener_radar
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

    -- Asociar las órdenes del despachador de esa fecha al radar (si no tienen radar asignado)
    UPDATE public.ordenes_distribucion o
    SET radar_id = v_radar_id
    FROM public.clientes c
    WHERE o.cliente_id = c.id
      AND c.despachador_id = v_despachador_id
      AND o.fecha_despacho::date = p_fecha_despacho
      AND o.estado IN ('aprobada', 'en_transito', 'por_liquidar', 'liquidada')
      AND (o.radar_id IS NULL OR o.radar_id = v_radar_id);

    -- Recalcular totales del radar
    SELECT 
        COALESCE(SUM(d.cantidad_solicitada), 0),
        COALESCE(SUM(d.cantidad_despachada), 0),
        COALESCE(SUM(d.contenedores_retirados), 0),
        COUNT(DISTINCT o.id)
    INTO v_tot_solicitada, v_tot_despachada, v_tot_retirados, v_total_ordenes
    FROM public.ordenes_distribucion o
    JOIN public.detalle_distribucion d ON d.orden_id = o.id
    WHERE o.radar_id = v_radar_id;

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


-- 4.2 RPC: retorna_radar_detalle_reporte
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

    -- 3. Consolidado de productos solicitados/despachados en este radar (Reporte global de carga)
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'producto_id', p.id,
                'codigo_producto', p.codigo_producto,
                'nombre_producto', p.nombre,
                'imagen_path', p.imagen_path,
                'cantidad_solicitada', SUM(d.cantidad_solicitada),
                'cantidad_despachada', SUM(COALESCE(d.cantidad_despachada, 0))
            )
        ),
        '[]'::jsonb
    )
    INTO v_resumen_productos
    FROM public.ordenes_distribucion o
    JOIN public.detalle_distribucion d ON d.orden_id = o.id
    JOIN public.productos p ON d.producto_id = p.id
    WHERE o.radar_id = p_radar_id
    GROUP BY p.id, p.codigo_producto, p.nombre, p.imagen_path;

    -- 4. Detalle orden por orden
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
            )
        ),
        '[]'::jsonb
    )
    INTO v_ordenes
    FROM public.ordenes_distribucion o
    JOIN public.clientes c ON o.cliente_id = c.id
    LEFT JOIN public.rutas rut ON c.id_ruta = rut.id_ruta
    WHERE o.radar_id = p_radar_id;

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
            'ordenes', v_ordenes
        )
    ) INTO v_resultado;

    RETURN v_resultado;
END;
$$;


-- 4.3 RPC: reasignar_orden_a_radar
CREATE OR REPLACE FUNCTION public.reasignar_orden_a_radar(
    p_orden_id UUID,
    p_nuevo_radar_id UUID DEFAULT NULL,
    p_nueva_fecha DATE DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_radar_anterior_id UUID;
    v_estado_orden TEXT;
BEGIN
    SELECT radar_id, estado INTO v_radar_anterior_id, v_estado_orden
    FROM public.ordenes_distribucion
    WHERE id = p_orden_id;

    IF v_radar_anterior_id IS NULL AND v_estado_orden IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'ORDEN_INEXISTENTE',
                'message', 'La orden especificada no existe.'
            )
        );
    END IF;

    IF v_estado_orden = 'liquidada' THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'ORDEN_LIQUIDADA',
                'message', 'No se puede reasignar una orden que ya ha sido liquidada.'
            )
        );
    END IF;

    -- Actualizar la orden
    UPDATE public.ordenes_distribucion
    SET radar_id = p_nuevo_radar_id,
        fecha_despacho = COALESCE(p_nueva_fecha::timestamptz, fecha_despacho)
    WHERE id = p_orden_id;

    -- Recalcular totales en el radar anterior si existía
    IF v_radar_anterior_id IS NOT NULL THEN
        UPDATE public.radars
        SET total_cantidad_solicitada = (
                SELECT COALESCE(SUM(d.cantidad_solicitada), 0)
                FROM public.ordenes_distribucion o
                JOIN public.detalle_distribucion d ON d.orden_id = o.id
                WHERE o.radar_id = v_radar_anterior_id
            ),
            total_cantidad_despachada = (
                SELECT COALESCE(SUM(d.cantidad_despachada), 0)
                FROM public.ordenes_distribucion o
                JOIN public.detalle_distribucion d ON d.orden_id = o.id
                WHERE o.radar_id = v_radar_anterior_id
            ),
            total_contenedores_retirados = (
                SELECT COALESCE(SUM(d.contenedores_retirados), 0)
                FROM public.ordenes_distribucion o
                JOIN public.detalle_distribucion d ON d.orden_id = o.id
                WHERE o.radar_id = v_radar_anterior_id
            )
        WHERE id = v_radar_anterior_id;
    END IF;

    -- Recalcular totales en el nuevo radar si existe
    IF p_nuevo_radar_id IS NOT NULL THEN
        UPDATE public.radars
        SET total_cantidad_solicitada = (
                SELECT COALESCE(SUM(d.cantidad_solicitada), 0)
                FROM public.ordenes_distribucion o
                JOIN public.detalle_distribucion d ON d.orden_id = o.id
                WHERE o.radar_id = p_nuevo_radar_id
            ),
            total_cantidad_despachada = (
                SELECT COALESCE(SUM(d.cantidad_despachada), 0)
                FROM public.ordenes_distribucion o
                JOIN public.detalle_distribucion d ON d.orden_id = o.id
                WHERE o.radar_id = p_nuevo_radar_id
            ),
            total_contenedores_retirados = (
                SELECT COALESCE(SUM(d.contenedores_retirados), 0)
                FROM public.ordenes_distribucion o
                JOIN public.detalle_distribucion d ON d.orden_id = o.id
                WHERE o.radar_id = p_nuevo_radar_id
            )
        WHERE id = p_nuevo_radar_id;
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Orden reasignada exitosamente.',
        'data', jsonb_build_object(
            'orden_id', p_orden_id,
            'radar_id', p_nuevo_radar_id,
            'fecha_despacho', p_nueva_fecha
        )
    );
END;
$$;


-- 4.4 RPC: guardar_resultado_despacho_radar
CREATE OR REPLACE FUNCTION public.guardar_resultado_despacho_radar(
    p_radar_id UUID,
    p_despacho_json JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_orden RECORD;
    v_detalle RECORD;
    v_cliente_id UUID;
    v_contenedor_id UUID;
    v_cant_entregada INT;
    v_cant_retirada INT;
    v_tot_solicitada NUMERIC(10,0);
    v_tot_despachada NUMERIC(10,0);
    v_tot_retirados NUMERIC(10,0);
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.radars WHERE id = p_radar_id) THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'RADAR_INEXISTENTE',
                'message', 'El radar especificado no existe.'
            )
        );
    END IF;

    -- Procesar cada orden entregada en el JSON
    FOR v_orden IN SELECT * FROM jsonb_to_recordset(p_despacho_json->'ordenes') AS x(orden_id UUID, detalles JSONB)
    LOOP
        -- Obtener el cliente de la orden
        SELECT cliente_id INTO v_cliente_id
        FROM public.ordenes_distribucion
        WHERE id = v_orden.orden_id;

        IF v_cliente_id IS NOT NULL THEN
            -- Recorrer detalles de la orden
            FOR v_detalle IN SELECT * FROM jsonb_to_recordset(v_orden.detalles) AS d(
                detalle_id UUID,
                cantidad_despachada NUMERIC,
                estado_entrega TEXT,
                motivo_rechazo TEXT,
                contenedores_retirados INT,
                contenedor_id UUID
            )
            LOOP
                -- Actualizar el renglón en detalle_distribucion
                UPDATE public.detalle_distribucion
                SET cantidad_despachada = COALESCE(v_detalle.cantidad_despachada, 0),
                    estado_entrega = COALESCE(v_detalle.estado_entrega, 'entregado'),
                    motivo_rechazo = v_detalle.motivo_rechazo,
                    contenedores_retirados = COALESCE(v_detalle.contenedores_retirados, 0),
                    contenedor_id = v_detalle.contenedor_id
                WHERE id = v_detalle.detalle_id;

                -- Identificar contenedor asociado al producto si no vino explícito
                v_contenedor_id := v_detalle.contenedor_id;
                IF v_contenedor_id IS NULL THEN
                    SELECT p.contenedor_id INTO v_contenedor_id
                    FROM public.detalle_distribucion dd
                    JOIN public.productos p ON dd.producto_id = p.id
                    WHERE dd.id = v_detalle.detalle_id;
                END IF;

                -- Calcular movimiento de contenedores
                IF v_contenedor_id IS NOT NULL THEN
                    v_cant_entregada := COALESCE(v_detalle.cantidad_despachada, 0)::INT;
                    v_cant_retirada := COALESCE(v_detalle.contenedores_retirados, 0);

                    IF v_cant_entregada > 0 OR v_cant_retirada > 0 THEN
                        INSERT INTO public.movimientos_contenedores (
                            cliente_id, orden_id, contenedor_id, cantidad_entregada, cantidad_retirada, creado_por
                        ) VALUES (
                            v_cliente_id, v_orden.orden_id, v_contenedor_id, v_cant_entregada, v_cant_retirada, auth.uid()
                        );
                    END IF;
                END IF;
            END LOOP;

            -- Actualizar estado de la orden a 'por_liquidar'
            UPDATE public.ordenes_distribucion
            SET estado = 'por_liquidar'
            WHERE id = v_orden.orden_id
              AND estado IN ('en_transito', 'aprobada');
        END IF;
    END LOOP;

    -- Actualizar totales globales del Radar y marcar status_radar = TRUE (.T.)
    SELECT 
        COALESCE(SUM(d.cantidad_solicitada), 0),
        COALESCE(SUM(d.cantidad_despachada), 0),
        COALESCE(SUM(d.contenedores_retirados), 0)
    INTO v_tot_solicitada, v_tot_despachada, v_tot_retirados
    FROM public.ordenes_distribucion o
    JOIN public.detalle_distribucion d ON d.orden_id = o.id
    WHERE o.radar_id = p_radar_id;

    UPDATE public.radars
    SET total_cantidad_solicitada = v_tot_solicitada,
        total_cantidad_despachada = v_tot_despachada,
        total_contenedores_retirados = v_tot_retirados,
        status_radar = TRUE
    WHERE id = p_radar_id;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Resultado del despacho registrado en el radar exitosamente.',
        'data', jsonb_build_object(
            'radar_id', p_radar_id,
            'status_radar', TRUE,
            'total_cantidad_solicitada', v_tot_solicitada,
            'total_cantidad_despachada', v_tot_despachada,
            'total_contenedores_retirados', v_tot_retirados
        )
    );
END;
$$;

-- Permisos de ejecución
GRANT EXECUTE ON FUNCTION public.crear_o_obtener_radar TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.retorna_radar_detalle_reporte TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.reasignar_orden_a_radar TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.guardar_resultado_despacho_radar TO authenticated, service_role;
