CREATE OR REPLACE FUNCTION public.retorna_lista_productos_segun_parametros(
    p_parametro TEXT
)
RETURNS TABLE (
    id UUID,
    nombre TEXT,
    codigo_barras TEXT,
    precio NUMERIC, 
    stock_disponible INT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Si el parámetro es explícitamente '.F.', devolvemos todos los productos
    IF p_parametro = '.F.' THEN
        RETURN QUERY 
        SELECT 
            p.id, 
            p.nombre, 
            p.codigo_barras, 
            p.precio_lista1,
            COALESCE(i.stock_disponible, 0)
        FROM public.productos p
        LEFT JOIN public.inventario_almacen i ON p.id = i.producto_id;
    ELSE
        -- Filtramos los productos cuyo nombre contenga la cadena de texto
        RETURN QUERY 
        SELECT 
            p.id, 
            p.nombre, 
            p.codigo_barras, 
            p.precio_lista1,
            COALESCE(i.stock_disponible, 0)
        FROM public.productos p
        LEFT JOIN public.inventario_almacen i ON p.id = i.producto_id
        WHERE p.nombre ILIKE '%' || p_parametro || '%';
    END IF;
END;
$$;
