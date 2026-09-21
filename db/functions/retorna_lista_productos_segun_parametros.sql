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
