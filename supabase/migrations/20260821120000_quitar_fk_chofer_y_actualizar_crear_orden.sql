-- Migration: Quitar FK chofer_id y actualizar crear_orden_distribucion sin p_chofer_id

-- 1. Quitar restricciones FK y UNIQUE de chofer_id en ordenes_distribucion
ALTER TABLE public.ordenes_distribucion DROP CONSTRAINT IF EXISTS ordenes_distribucion_chofer_id_fkey;
ALTER TABLE public.ordenes_distribucion DROP CONSTRAINT IF EXISTS ordenes_distribucion_chofer_id_key;
DROP INDEX IF EXISTS public.ordenes_distribucion_chofer_id_key;
ALTER TABLE public.ordenes_distribucion ALTER COLUMN chofer_id DROP NOT NULL;

-- 2. Asegurar existencia de columnas y FKs para vendedor_id, despachador_id e id_ruta en ordenes_distribucion
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'ordenes_distribucion' AND column_name = 'vendedor_id'
    ) THEN
        ALTER TABLE public.ordenes_distribucion ADD COLUMN vendedor_id UUID REFERENCES public.perfiles_usuario(id) ON DELETE SET NULL;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'ordenes_distribucion' AND column_name = 'despachador_id'
    ) THEN
        ALTER TABLE public.ordenes_distribucion ADD COLUMN despachador_id UUID REFERENCES public.perfiles_usuario(id) ON DELETE SET NULL;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'ordenes_distribucion' AND column_name = 'id_ruta'
    ) THEN
        ALTER TABLE public.ordenes_distribucion ADD COLUMN id_ruta UUID REFERENCES public.rutas(id_ruta) ON DELETE SET NULL;
    END IF;
END $$;

-- 3. Eliminar firmas anteriores de la función crear_orden_distribucion
DROP FUNCTION IF EXISTS public.crear_orden_distribucion(UUID, UUID, UUID, UUID, NUMERIC, JSONB);
DROP FUNCTION IF EXISTS public.crear_orden_distribucion(UUID, UUID, UUID, NUMERIC, JSONB);

-- 4. Recrear función crear_orden_distribucion sin p_chofer_id
CREATE OR REPLACE FUNCTION public.crear_orden_distribucion(
    p_vendedor_id UUID,
    p_cliente_id UUID,
    p_camion_id UUID,
    p_tasa_cambio NUMERIC DEFAULT NULL,
    p_productos_json JSONB DEFAULT '[]'::jsonb,
    p_despachador_id UUID DEFAULT NULL,
    p_id_ruta UUID DEFAULT NULL
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
    v_total_recaudar_bs NUMERIC(14,2) := 0.00;
    v_total_recaudar_usd NUMERIC(14,2) := 0.00;
    
    v_item JSONB;
    v_secuencia INT := 1;
    v_producto_id UUID;
    v_cantidad INT;
    v_val_recaudar_bs NUMERIC(14,2);
    v_val_usd NUMERIC(14,2);
    v_subtotal_bs NUMERIC(14,2);
    v_subtotal_usd NUMERIC(14,2);
    v_peso_unitario NUMERIC(10,2);
BEGIN
    -- Validaciones básicas
    IF p_vendedor_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del vendedor es requerido.');
    END IF;

    IF p_cliente_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del cliente es requerido.');
    END IF;

    IF p_camion_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del camión es requerido.');
    END IF;

    IF p_productos_json IS NULL OR jsonb_array_length(p_productos_json) = 0 THEN
        RETURN jsonb_build_object('success', false, 'message', 'Debe incluir al menos un producto en la orden.');
    END IF;

    -- Obtener información del cliente (vendedor_id, despachador_id, id_ruta)
    SELECT c.vendedor_id, c.despachador_id, c.id_ruta
    INTO v_vendedor_id, v_despachador_id, v_id_ruta
    FROM public.clientes c
    WHERE c.id = p_cliente_id;

    -- Priorizar parámetros explícitos si fueron proporcionados
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

    IF NOT EXISTS (SELECT 1 FROM public.camiones WHERE id = p_camion_id) THEN
        RETURN jsonb_build_object('success', false, 'message', 'El camión especificado no existe.');
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

    -- Generar correlativo y número de factura de origen automáticamente
    v_correlativo := nextval('public.ordenes_distribucion_correlativo_seq');
    v_factura_origen := 'FAC-' || LPAD(v_correlativo::text, 6, '0');
    v_orden_id := gen_random_uuid();

    -- Validar productos y calcular totales multimoneda y peso total
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;
        
        IF v_cantidad IS NULL OR v_cantidad <= 0 THEN
            RETURN jsonb_build_object('success', false, 'message', 'La cantidad del producto debe ser mayor a cero.');
        END IF;

        SELECT peso_unitario_kg INTO v_peso_unitario
        FROM public.productos
        WHERE id = v_producto_id;

        IF NOT FOUND THEN
            RETURN jsonb_build_object('success', false, 'message', 'El producto con ID ' || v_producto_id::text || ' no existe.');
        END IF;

        v_val_recaudar_bs := COALESCE((v_item->>'valor_unitario_recaudar')::NUMERIC, (v_item->>'precio_unitario')::NUMERIC, 0.00);
        v_val_usd := COALESCE((v_item->>'valor_unitario_usd')::NUMERIC, 0.00);

        IF v_val_recaudar_bs > 0 AND (v_val_usd IS NULL OR v_val_usd = 0) THEN
            v_val_usd := ROUND(v_val_recaudar_bs / v_tasa_cambio, 2);
        ELSIF v_val_usd > 0 AND (v_val_recaudar_bs IS NULL OR v_val_recaudar_bs = 0) THEN
            v_val_recaudar_bs := ROUND(v_val_usd * v_tasa_cambio, 2);
        END IF;

        v_subtotal_bs := ROUND(v_cantidad * v_val_recaudar_bs, 2);
        v_subtotal_usd := ROUND(v_cantidad * v_val_usd, 2);

        v_peso_total := v_peso_total + (COALESCE(v_peso_unitario, 0.00) * v_cantidad);
        v_total_recaudar_bs := v_total_recaudar_bs + v_subtotal_bs;
        v_total_recaudar_usd := v_total_recaudar_usd + v_subtotal_usd;
    END LOOP;

    -- Insertar Cabecera de la Orden
    INSERT INTO public.ordenes_distribucion (
        id,
        correlativo,
        cliente_id,
        camion_id,
        chofer_id,
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
        total_recaudar_usd
    ) VALUES (
        v_orden_id,
        v_correlativo,
        p_cliente_id,
        p_camion_id,
        NULL, -- chofer_id ya no es obligatorio al crear la orden
        v_vendedor_id,
        v_despachador_id,
        v_id_ruta,
        'borrador',
        NULL,
        v_peso_total,
        v_factura_origen,
        p_vendedor_id,
        NOW(),
        v_tasa_cambio,
        v_total_recaudar_bs,
        v_total_recaudar_usd
    );

    -- Insertar Detalles de la Orden
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;
        
        v_val_recaudar_bs := COALESCE((v_item->>'valor_unitario_recaudar')::NUMERIC, (v_item->>'precio_unitario')::NUMERIC, 0.00);
        v_val_usd := COALESCE((v_item->>'valor_unitario_usd')::NUMERIC, 0.00);

        IF v_val_recaudar_bs > 0 AND (v_val_usd IS NULL OR v_val_usd = 0) THEN
            v_val_usd := ROUND(v_val_recaudar_bs / v_tasa_cambio, 2);
        ELSIF v_val_usd > 0 AND (v_val_recaudar_bs IS NULL OR v_val_recaudar_bs = 0) THEN
            v_val_recaudar_bs := ROUND(v_val_usd * v_tasa_cambio, 2);
        END IF;

        v_subtotal_bs := ROUND(v_cantidad * v_val_recaudar_bs, 2);
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
            subtotal_recaudar_usd
        ) VALUES (
            gen_random_uuid(),
            v_orden_id,
            v_producto_id,
            v_cantidad,
            0,
            v_val_recaudar_bs,
            v_subtotal_bs,
            v_secuencia,
            'pendiente',
            NULL,
            v_val_usd,
            v_subtotal_usd
        );
        
        v_secuencia := v_secuencia + 1;
    END LOOP;

    RETURN jsonb_build_object(
        'success', true, 
        'message', 'Orden de distribución creada exitosamente.', 
        'orden_id', v_orden_id,
        'data', jsonb_build_object(
            'orden_id', v_orden_id,
            'correlativo', v_correlativo,
            'tasa_cambio', v_tasa_cambio,
            'total_recaudar_bs', v_total_recaudar_bs,
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
