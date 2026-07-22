CREATE OR REPLACE FUNCTION public.actualizar_registro_productos_segun_id(
    p_id UUID,
    p_codigo_producto TEXT,
    p_nombre TEXT,
    p_codigo_barras TEXT,
    p_precio_lista1 NUMERIC,
    p_precio_lista2 NUMERIC,
    p_precio_lista3 NUMERIC
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE public.productos
    SET 
        codigo_producto = p_codigo_producto,
        nombre = p_nombre,
        codigo_barras = p_codigo_barras,
        precio_lista1 = p_precio_lista1,
        precio_lista2 = p_precio_lista2,
        precio_lista3 = p_precio_lista3
    WHERE id = p_id;

    RETURN FOUND;
END;
$$;
