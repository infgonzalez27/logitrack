-- ==============================================================================
-- PARCHE IDEMPOTENTE: CAMION SE ASIGNA AL ARMAR EL RADAR (NO AL CREAR LA ORDEN)
-- Fecha: 2026-11-12 17:00:00
-- Descripcion:
--   1. public.radars.camion_id (FK camiones) + backfill desde ordenes vinculadas.
--   2. ordenes_distribucion.camion_id admite NULL; crear_orden_distribucion recibe
--      p_camion_id opcional (DEFAULT NULL).
--   3. Trigger en ordenes_distribucion: al vincular una orden a un radar hereda el
--      camion del radar; al liberarla (radar_id -> NULL, estado aprobada) vuelve a NULL.
--   4. Trigger en radars: si cambia camion_id se propaga a sus ordenes.
--   5. public.lt_validar_camion_para_radar: solo camiones 'disponible' (informa si esta
--      en ruta / mantenimiento / inactivo).
--   6. crear_o_obtener_radar(p_despachador_id, p_fecha_despacho, p_camion_id).
--   7. Nueva RPC asignar_camion_radar(p_radar_id, p_camion_id).
-- ==============================================================================

ALTER TABLE IF EXISTS public.radars
    ADD COLUMN IF NOT EXISTS camion_id UUID REFERENCES public.camiones(id);

ALTER TABLE IF EXISTS public.ordenes_distribucion
    ALTER COLUMN camion_id DROP NOT NULL;

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
-- 1. crear_orden_distribucion con camion opcional
-- ------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.crear_orden_distribucion(UUID, UUID, UUID, NUMERIC, JSONB, UUID, UUID, BOOLEAN);
CREATE OR REPLACE FUNCTION public.crear_orden_distribucion(
    p_vendedor_id UUID,
    p_cliente_id UUID,
    p_camion_id UUID DEFAULT NULL,
    p_tasa_cambio NUMERIC DEFAULT NULL,
    p_productos_json JSONB DEFAULT '[]'::jsonb,
    p_despachador_id UUID DEFAULT NULL,
    p_id_ruta UUID DEFAULT NULL,
    p_es_cortesia BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_orden_id UUID;
    v_correlativo INT;
    v_factura_origen VARCHAR(30);
    v_tasa_cambio NUMERIC(14,4);
    
    v_vendedor_id UUID;
    v_despachador_id UUID;
    v_id_ruta UUID;
    
    v_peso_total NUMERIC(10,2) := 0.00;
    v_total_recaudar_usd NUMERIC(14,2) := 0.00;
    
    v_item JSONB;
    v_secuencia INT := 1;
    v_producto_id UUID;
    v_cantidad INT;
    
    v_val_usd_prod NUMERIC(14,2);
    v_val_usd NUMERIC(14,2);
    v_pct_desc NUMERIC(5,2) := 0.00;
    v_monto_desc_unit NUMERIC(14,2) := 0.00;
    v_subtotal_usd NUMERIC(14,2);
    v_peso_unitario NUMERIC(10,2);

    v_desc_rec RECORD;
BEGIN
    -- Validaciones bÃ¡sicas
    IF p_vendedor_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del vendedor es requerido.');
    END IF;

    IF p_cliente_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del cliente es requerido.');
    END IF;

IF p_productos_json IS NULL OR jsonb_array_length(p_productos_json) = 0 THEN
        RETURN jsonb_build_object('success', false, 'message', 'Debe incluir al menos un producto en la orden.');
    END IF;

    -- Obtener informaciÃ³n del cliente (vendedor_id, despachador_id, id_ruta)
    SELECT c.vendedor_id, c.despachador_id, c.id_ruta
    INTO v_vendedor_id, v_despachador_id, v_id_ruta
    FROM public.clientes c
    WHERE c.id = p_cliente_id;

    -- Priorizar parÃ¡metros explÃ­citos si fueron proporcionados
    v_vendedor_id := COALESCE(p_vendedor_id, v_vendedor_id);
    v_despachador_id := COALESCE(p_despachador_id, v_despachador_id);
    v_id_ruta := COALESCE(p_id_ruta, v_id_ruta);

    -- Validar existencia de entidades
    IF NOT EXISTS (SELECT 1 FROM public.perfiles_usuario WHERE id = p_vendedor_id) THEN
        RETURN jsonb_build_object('success', false, 'message', 'El vendedor especificado no existe.');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.clientes WHERE id = p_cliente_id) THEN
        RETURN jsonb_build_object('success', false, 'message', 'El cliente especificado no existe.');
    END IF;

    IF p_camion_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.camiones WHERE id = p_camion_id) THEN
        RETURN jsonb_build_object('success', false, 'message', 'El camiÃ³n especificado no existe.');
    END IF;

    -- Determinar / validar la tasa de cambio
    IF p_tasa_cambio IS NOT NULL AND p_tasa_cambio > 0 THEN
        v_tasa_cambio := p_tasa_cambio;
    ELSE
        SELECT tasa_cambio INTO v_tasa_cambio
        FROM public.tasa_cambio
        WHERE fecha_tasa = CURRENT_DATE;

        IF v_tasa_cambio IS NULL THEN
            SELECT tasa_cambio INTO v_tasa_cambio
            FROM public.tasa_cambio
            ORDER BY fecha_tasa DESC
            LIMIT 1;
        END IF;

        IF v_tasa_cambio IS NULL THEN
            RETURN jsonb_build_object(
                'success', false, 
                'message', 'No hay tasa de cambio registrada. Debe proporcionar p_tasa_cambio o registrar una tasa oficial en el sistema.'
            );
        END IF;
    END IF;

    -- Generar correlativo y nÃºmero de factura de origen automÃ¡ticamente
    v_correlativo := nextval('public.ordenes_distribucion_correlativo_seq');
    v_factura_origen := 'FAC-' || LPAD(v_correlativo::text, 6, '0');
    v_orden_id := gen_random_uuid();

    -- Validar productos y calcular totales exclusivamente en USD y peso total
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;
        
        IF v_cantidad IS NULL OR v_cantidad <= 0 THEN
            RETURN jsonb_build_object('success', false, 'message', 'La cantidad del producto debe ser mayor a cero.');
        END IF;

        SELECT COALESCE(precio_lista1, 0.00), COALESCE(peso_unitario_kg, 0.00) 
        INTO v_val_usd_prod, v_peso_unitario
        FROM public.productos
        WHERE id = v_producto_id;

        IF NOT FOUND THEN
            RETURN jsonb_build_object('success', false, 'message', 'El producto con ID ' || v_producto_id::text || ' no existe.');
        END IF;

        -- Buscar descuento especÃ­fico del cliente para este producto
        SELECT * INTO v_desc_rec
        FROM public.descuentos_cliente_producto
        WHERE cliente_id = p_cliente_id AND producto_id = v_producto_id AND activo = true;

        -- Resolver precio unitario en USD
        IF p_es_cortesia = TRUE THEN
            v_val_usd := 0.00;
        ELSIF (v_item->>'valor_unitario_usd') IS NOT NULL THEN
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

        IF p_es_cortesia = FALSE AND (v_val_usd <= 0 OR (v_val_usd < 1.00 AND v_val_usd_prod >= 1.00)) THEN
            v_val_usd := v_val_usd_prod;
        END IF;

        v_subtotal_usd := ROUND(v_cantidad * v_val_usd, 2);

        v_peso_total := v_peso_total + (COALESCE(v_peso_unitario, 0.00) * v_cantidad);
        v_total_recaudar_usd := v_total_recaudar_usd + v_subtotal_usd;
    END LOOP;

    -- Insertar Cabecera de la Orden con estado 'aprobada'
    INSERT INTO public.ordenes_distribucion (
        id,
        correlativo,
        cliente_id,
        camion_id,
        vendedor_id,
        despachador_id,
        id_ruta,
        estado,
        fecha_despacho,
        peso_total_calculado,
        factura_origen_numero,
        creado_por,
        created_at,
        tasa_cambio,
        total_recaudar_bs,
        total_recaudar_usd,
        es_cortesia
    ) VALUES (
        v_orden_id,
        v_correlativo,
        p_cliente_id,
        p_camion_id,
        v_vendedor_id,
        v_despachador_id,
        v_id_ruta,
        'aprobada',
        NULL,
        v_peso_total,
        v_factura_origen,
        p_vendedor_id,
        NOW(),
        v_tasa_cambio,
        NULL,
        v_total_recaudar_usd,
        p_es_cortesia
    );

    -- Insertar Detalles de la Orden
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;
        
        SELECT COALESCE(precio_lista1, 0.00) INTO v_val_usd_prod
        FROM public.productos
        WHERE id = v_producto_id;

        -- Buscar descuento especÃ­fico del cliente
        SELECT * INTO v_desc_rec
        FROM public.descuentos_cliente_producto
        WHERE cliente_id = p_cliente_id AND producto_id = v_producto_id AND activo = true;

        IF p_es_cortesia = TRUE THEN
            v_pct_desc := 0.00;
            v_monto_desc_unit := 0.00;
            v_val_usd := 0.00;
        ELSIF v_desc_rec.id IS NOT NULL THEN
            v_pct_desc := COALESCE(v_desc_rec.porcentaje_descuento, 0.00);
            IF v_desc_rec.precio_pactado_usd IS NOT NULL THEN
                v_val_usd := v_desc_rec.precio_pactado_usd;
                v_monto_desc_unit := GREATEST(0.00, v_val_usd_prod - v_val_usd);
            ELSIF v_desc_rec.porcentaje_descuento > 0 THEN
                v_val_usd := ROUND(v_val_usd_prod * (1.00 - (v_pct_desc / 100.00)), 2);
                v_monto_desc_unit := v_val_usd_prod - v_val_usd;
            ELSE
                v_val_usd := v_val_usd_prod;
                v_monto_desc_unit := 0.00;
            END IF;
        ELSE
            v_pct_desc := 0.00;
            v_monto_desc_unit := 0.00;
            v_val_usd := COALESCE((v_item->>'valor_unitario_usd')::NUMERIC, (v_item->>'precio_unitario')::NUMERIC, v_val_usd_prod);
        END IF;

        IF p_es_cortesia = FALSE AND (v_val_usd <= 0 OR (v_val_usd < 1.00 AND v_val_usd_prod >= 1.00)) THEN
            v_val_usd := v_val_usd_prod;
        END IF;

        v_subtotal_usd := ROUND(v_cantidad * v_val_usd, 2);

        INSERT INTO public.detalle_distribucion (
            id,
            orden_id,
            producto_id,
            cantidad_solicitada,
            cantidad_despachada,
            valor_unitario_recaudar,
            subtotal_recaudar,
            secuencia_entrega,
            estado_entrega,
            motivo_rechazo,
            valor_unitario_usd,
            subtotal_recaudar_usd,
            precio_lista_usd,
            porcentaje_descuento,
            monto_descuento_usd
        ) VALUES (
            gen_random_uuid(),
            v_orden_id,
            v_producto_id,
            v_cantidad,
            0,
            NULL,
            NULL,
            v_secuencia,
            'pendiente',
            NULL,
            v_val_usd,
            v_subtotal_usd,
            v_val_usd_prod,
            v_pct_desc,
            v_monto_desc_unit * v_cantidad
        );
        
        v_secuencia := v_secuencia + 1;
    END LOOP;

    RETURN jsonb_build_object(
        'success', true, 
        'message', 'Orden de distribuciÃ³n creada exitosamente.', 
        'orden_id', v_orden_id,
        'data', jsonb_build_object(
            'orden_id', v_orden_id,
            'correlativo', v_correlativo,
            'tasa_cambio', v_tasa_cambio,
            'total_recaudar_bs', NULL,
            'total_recaudar_usd', v_total_recaudar_usd,
            'peso_total_calculado', v_peso_total
        )
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false, 
        'message', 'Error al crear la orden: ' || SQLERRM
    );
END;
$$;
GRANT EXECUTE ON FUNCTION public.crear_orden_distribucion(UUID, UUID, UUID, NUMERIC, JSONB, UUID, UUID, BOOLEAN) TO authenticated, service_role;


-- ------------------------------------------------------------------------------
-- 2. Validador de camion para radar (solo 'disponible')
--    Devuelve NULL si es valido o un JSONB de error listo para retornar.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.lt_validar_camion_para_radar(p_camion_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
    v_placa TEXT;
    v_estado TEXT;
BEGIN
    SELECT placa, estado INTO v_placa, v_estado
    FROM public.camiones
    WHERE id = p_camion_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'CAMION_INEXISTENTE',
                'message', 'El camión especificado no existe.'
            )
        );
    END IF;

    IF v_estado IS DISTINCT FROM 'disponible' THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'CAMION_NO_DISPONIBLE',
                'message', CASE v_estado
                    WHEN 'en_ruta' THEN format('El camión %s está en ruta y no puede asignarse a un nuevo Radar. Selecciona un camión disponible.', v_placa)
                    WHEN 'mantenimiento' THEN format('El camión %s está en mantenimiento y no puede asignarse a un Radar.', v_placa)
                    WHEN 'inactivo' THEN format('El camión %s está inactivo y no puede asignarse a un Radar.', v_placa)
                    ELSE format('El camión %s no está disponible (estado: %s).', v_placa, COALESCE(v_estado, 'desconocido'))
                END,
                'estado_camion', v_estado
            )
        );
    END IF;

    RETURN NULL;
END;
$$;

GRANT EXECUTE ON FUNCTION public.lt_validar_camion_para_radar(UUID) TO authenticated, service_role;


-- ------------------------------------------------------------------------------
-- 3. Trigger en ordenes_distribucion: herencia / liberacion del camion del radar
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.lt_tg_orden_camion_segun_radar()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF COALESCE(NEW.es_autoventa, FALSE) = TRUE THEN
        RETURN NEW;
    END IF;

    IF NEW.radar_id IS NOT NULL AND NEW.radar_id IS DISTINCT FROM OLD.radar_id THEN
        -- Al vincularse a un radar, la orden hereda el camion del radar
        NEW.camion_id := (SELECT r.camion_id FROM public.radars r WHERE r.id = NEW.radar_id);
    ELSIF NEW.radar_id IS NULL AND OLD.radar_id IS NOT NULL AND NEW.estado = 'aprobada' THEN
        -- Al liberarse del radar (queda aprobada) pierde el camion; el proximo radar asigna el suyo
        NEW.camion_id := NULL;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_orden_camion_segun_radar ON public.ordenes_distribucion;
CREATE TRIGGER trg_orden_camion_segun_radar
    BEFORE UPDATE OF radar_id ON public.ordenes_distribucion
    FOR EACH ROW
    EXECUTE FUNCTION public.lt_tg_orden_camion_segun_radar();


-- ------------------------------------------------------------------------------
-- 4. Trigger en radars: propagar cambio de camion a sus ordenes
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.lt_tg_radar_propaga_camion()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.camion_id IS DISTINCT FROM OLD.camion_id THEN
        UPDATE public.ordenes_distribucion
        SET camion_id = NEW.camion_id
        WHERE radar_id = NEW.id
          AND COALESCE(es_autoventa, FALSE) = FALSE
          AND estado <> 'anulada';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_radar_propaga_camion ON public.radars;
CREATE TRIGGER trg_radar_propaga_camion
    AFTER UPDATE OF camion_id ON public.radars
    FOR EACH ROW
    EXECUTE FUNCTION public.lt_tg_radar_propaga_camion();


-- ------------------------------------------------------------------------------
-- 5. crear_o_obtener_radar con p_camion_id
-- ------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.crear_o_obtener_radar(UUID, DATE);

CREATE OR REPLACE FUNCTION public.crear_o_obtener_radar(
    p_despachador_id UUID DEFAULT NULL,
    p_fecha_despacho DATE DEFAULT CURRENT_DATE,
    p_camion_id UUID DEFAULT NULL
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
    v_camion_actual UUID;
    v_ordenes_excluidas UUID[];
    v_tot_solicitada NUMERIC(10,0);
    v_tot_despachada NUMERIC(10,0);
    v_tot_retirados NUMERIC(10,0);
    v_total_ordenes INT;
    v_validacion JSONB;
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

    SELECT id, correlativo, COALESCE(status_radar, FALSE), COALESCE(carga_inventario_movil, FALSE),
           camion_id, COALESCE(ordenes_excluidas, '{}'::UUID[])
    INTO v_radar_id, v_correlativo, v_status_radar, v_carga_inventario, v_camion_actual, v_ordenes_excluidas
    FROM public.radars
    WHERE despachador_id = v_despachador_id
      AND fecha_despacho = p_fecha_despacho
    ORDER BY created_at DESC
    LIMIT 1;

    -- Validar el camion solicitado si cambia respecto al actual del radar
    IF p_camion_id IS NOT NULL
       AND (v_radar_id IS NULL OR (v_status_radar = FALSE AND v_carga_inventario = FALSE))
       AND p_camion_id IS DISTINCT FROM v_camion_actual THEN
        v_validacion := public.lt_validar_camion_para_radar(p_camion_id);
        IF v_validacion IS NOT NULL THEN
            RETURN v_validacion;
        END IF;
    END IF;

    IF v_radar_id IS NULL THEN
        INSERT INTO public.radars (despachador_id, fecha_despacho, status_radar, ordenes_excluidas, camion_id)
        VALUES (v_despachador_id, p_fecha_despacho, FALSE, '{}'::UUID[], p_camion_id)
        RETURNING id, correlativo, COALESCE(status_radar, FALSE), COALESCE(carga_inventario_movil, FALSE),
                  camion_id, COALESCE(ordenes_excluidas, '{}'::UUID[])
        INTO v_radar_id, v_correlativo, v_status_radar, v_carga_inventario, v_camion_actual, v_ordenes_excluidas;
    ELSIF p_camion_id IS NOT NULL
          AND v_status_radar = FALSE AND v_carga_inventario = FALSE
          AND p_camion_id IS DISTINCT FROM v_camion_actual THEN
        UPDATE public.radars SET camion_id = p_camion_id WHERE id = v_radar_id;
        v_camion_actual := p_camion_id;
    END IF;

    IF COALESCE(v_status_radar, FALSE) = FALSE THEN
        UPDATE public.ordenes_distribucion
        SET radar_id = NULL
        WHERE radar_id = v_radar_id
          AND (estado = 'anulada' OR id = ANY(v_ordenes_excluidas));
    END IF;

    IF COALESCE(v_status_radar, FALSE) = FALSE AND COALESCE(v_carga_inventario, FALSE) = FALSE THEN
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
            'camion_id', v_camion_actual,
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

GRANT EXECUTE ON FUNCTION public.crear_o_obtener_radar(UUID, DATE, UUID) TO authenticated, service_role;


-- ------------------------------------------------------------------------------
-- 6. Nueva RPC: asignar_camion_radar
--    Cambia el camion de un radar pendiente mientras el camion no haya sido cargado.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.asignar_camion_radar(
    p_radar_id UUID,
    p_camion_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_status BOOLEAN;
    v_carga BOOLEAN;
    v_camion_actual UUID;
    v_validacion JSONB;
    v_placa TEXT;
BEGIN
    IF p_radar_id IS NULL OR p_camion_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El radar y el camión son obligatorios.'
            )
        );
    END IF;

    SELECT COALESCE(status_radar, FALSE), COALESCE(carga_inventario_movil, FALSE), camion_id
    INTO v_status, v_carga, v_camion_actual
    FROM public.radars
    WHERE id = p_radar_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object('code', 'RADAR_INEXISTENTE', 'message', 'El radar especificado no existe.')
        );
    END IF;

    IF v_status THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object('code', 'RADAR_APROBADO_BLOQUEADO', 'message', 'El radar ya fue aprobado y no se puede modificar.')
        );
    END IF;

    IF v_carga THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'RADAR_INVENTARIO_CARGADO',
                'message', 'Para cambiar el camión debe reversar primero el inventario móvil al almacén.'
            )
        );
    END IF;

    IF p_camion_id IS DISTINCT FROM v_camion_actual THEN
        v_validacion := public.lt_validar_camion_para_radar(p_camion_id);
        IF v_validacion IS NOT NULL THEN
            RETURN v_validacion;
        END IF;

        UPDATE public.radars SET camion_id = p_camion_id WHERE id = p_radar_id;
    END IF;

    SELECT placa INTO v_placa FROM public.camiones WHERE id = p_camion_id;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', format('Camión %s asignado al radar.', v_placa),
        'data', jsonb_build_object(
            'radar_id', p_radar_id,
            'camion_id', p_camion_id,
            'placa', v_placa
        ),
        'error', NULL
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', FALSE,
        'data', NULL,
        'error', jsonb_build_object('code', 'SQL_ERROR', 'message', SQLERRM, 'details', 'SQLSTATE: ' || SQLSTATE)
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.asignar_camion_radar(UUID, UUID) TO authenticated, service_role;
