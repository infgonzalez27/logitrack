-- Migration: 20260921000000_descuentos_cliente_producto.sql
-- Description: Módulo de descuentos de clientes por producto y actualización de RPCs crear_orden_distribucion y retorna_lista_productos_segun_parametros

-- 1. Crear tabla de descuentos por cliente y producto
CREATE TABLE IF NOT EXISTS public.descuentos_cliente_producto (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cliente_id UUID NOT NULL REFERENCES public.clientes(id) ON DELETE CASCADE,
    producto_id UUID NOT NULL REFERENCES public.productos(id) ON DELETE CASCADE,
    porcentaje_descuento NUMERIC(5,2) NOT NULL DEFAULT 0.00,
    precio_pactado_usd NUMERIC(14,2) DEFAULT NULL,
    activo BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_cliente_producto_descuento UNIQUE (cliente_id, producto_id)
);

-- RLS y Permisos
ALTER TABLE public.descuentos_cliente_producto ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Permitir lectura publica a autenticados en descuentos_cliente_producto"
    ON public.descuentos_cliente_producto FOR SELECT
    TO authenticated
    USING (true);

CREATE POLICY "Permitir todo a autenticados en descuentos_cliente_producto"
    ON public.descuentos_cliente_producto FOR ALL
    TO authenticated
    USING (true)
    WITH CHECK (true);

-- Índices
CREATE INDEX IF NOT EXISTS idx_descuentos_cliente_id ON public.descuentos_cliente_producto(cliente_id);
CREATE INDEX IF NOT EXISTS idx_descuentos_producto_id ON public.descuentos_cliente_producto(producto_id);

-- 2. Alterar detalle_distribucion para agregar columnas de auditoria de descuento
ALTER TABLE public.detalle_distribucion 
    ADD COLUMN IF NOT EXISTS precio_lista_usd NUMERIC(14,2) DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS porcentaje_descuento NUMERIC(5,2) DEFAULT 0.00,
    ADD COLUMN IF NOT EXISTS monto_descuento_usd NUMERIC(14,2) DEFAULT 0.00;

-- 3. Actualizar función RPC retorna_lista_productos_segun_parametros
DROP FUNCTION IF EXISTS public.retorna_lista_productos_segun_parametros(TEXT);
DROP FUNCTION IF EXISTS public.retorna_lista_productos_segun_parametros(TEXT, UUID);

CREATE OR REPLACE FUNCTION public.retorna_lista_productos_segun_parametros(
    p_parametro TEXT,
    p_cliente_id UUID DEFAULT NULL
)
RETURNS TABLE (
    id UUID,
    nombre TEXT,
    codigo_barras TEXT,
    precio NUMERIC, 
    stock_disponible INT,
    imagen_path TEXT,
    precio_lista NUMERIC,
    porcentaje_descuento NUMERIC,
    precio_final_usd NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY 
    SELECT 
        p.id, 
        p.nombre, 
        p.codigo_barras, 
        ROUND(
            CASE 
                WHEN d.id IS NOT NULL AND d.activo = true AND d.precio_pactado_usd IS NOT NULL THEN d.precio_pactado_usd
                WHEN d.id IS NOT NULL AND d.activo = true AND d.porcentaje_descuento > 0 THEN COALESCE(p.precio_lista1, 0.00) * (1.00 - (d.porcentaje_descuento / 100.00))
                ELSE COALESCE(p.precio_lista1, 0.00)
            END,
            2
        ) AS precio,
        COALESCE(i.stock_disponible, 0)::INT AS stock_disponible,
        p.imagen_path,
        COALESCE(p.precio_lista1, 0.00) AS precio_lista,
        CASE 
            WHEN d.id IS NOT NULL AND d.activo = true THEN COALESCE(d.porcentaje_descuento, 0.00)
            ELSE 0.00
        END AS porcentaje_descuento,
        ROUND(
            CASE 
                WHEN d.id IS NOT NULL AND d.activo = true AND d.precio_pactado_usd IS NOT NULL THEN d.precio_pactado_usd
                WHEN d.id IS NOT NULL AND d.activo = true AND d.porcentaje_descuento > 0 THEN COALESCE(p.precio_lista1, 0.00) * (1.00 - (d.porcentaje_descuento / 100.00))
                ELSE COALESCE(p.precio_lista1, 0.00)
            END,
            2
        ) AS precio_final_usd
    FROM public.productos p
    LEFT JOIN public.inventario_almacen i ON p.id = i.producto_id
    LEFT JOIN public.descuentos_cliente_producto d ON p.id = d.producto_id AND d.cliente_id = p_cliente_id AND d.activo = true
    WHERE 
        (p_parametro = '.F.' OR p.nombre ILIKE '%' || p_parametro || '%' OR p.codigo_barras ILIKE '%' || p_parametro || '%');
END;
$$;

-- 4. Actualizar función RPC crear_orden_distribucion
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

        -- Buscar descuento específico del cliente para este producto
        SELECT * INTO v_desc_rec
        FROM public.descuentos_cliente_producto
        WHERE cliente_id = p_cliente_id AND producto_id = v_producto_id AND activo = true;

        -- Resolver precio unitario en USD
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

        IF v_val_usd <= 0 OR (v_val_usd < 1.00 AND v_val_usd_prod >= 1.00) THEN
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
        total_recaudar_usd
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
        v_total_recaudar_usd
    );

    -- Insertar Detalles de la Orden
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;
        
        SELECT COALESCE(precio_lista1, 0.00) INTO v_val_usd_prod
        FROM public.productos
        WHERE id = v_producto_id;

        -- Buscar descuento específico del cliente
        SELECT * INTO v_desc_rec
        FROM public.descuentos_cliente_producto
        WHERE cliente_id = p_cliente_id AND producto_id = v_producto_id AND activo = true;

        IF v_desc_rec.id IS NOT NULL THEN
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

        IF v_val_usd <= 0 OR (v_val_usd < 1.00 AND v_val_usd_prod >= 1.00) THEN
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
        'message', 'Orden de distribución creada exitosamente.', 
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
