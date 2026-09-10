CREATE OR REPLACE FUNCTION public.actualizar_registro_productos_segun_id(
    p_id UUID,
    p_codigo_producto TEXT,
    p_nombre TEXT,
    p_codigo_barras TEXT DEFAULT NULL,
    p_precio_lista1 NUMERIC DEFAULT 0,
    p_precio_lista2 NUMERIC DEFAULT 0,
    p_precio_lista3 NUMERIC DEFAULT 0,
    p_descripcion TEXT DEFAULT NULL,
    p_cant_unidad_medida NUMERIC DEFAULT NULL,
    p_contenedor_id UUID DEFAULT NULL,
    p_unidades_por_contenedor NUMERIC DEFAULT 1,
    p_imagen_path TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_codigo_barras TEXT;
BEGIN
    -- Tratar cadena vacía como NULL en codigo_barras para evitar violaciones de UNIQUE
    v_codigo_barras := NULLIF(TRIM(p_codigo_barras), '');

    UPDATE public.productos
    SET 
        codigo_producto = TRIM(p_codigo_producto),
        nombre = TRIM(p_nombre),
        codigo_barras = v_codigo_barras,
        precio_lista1 = COALESCE(p_precio_lista1, 0),
        precio_lista2 = COALESCE(p_precio_lista2, 0),
        precio_lista3 = COALESCE(p_precio_lista3, 0),
        descripcion = p_descripcion,
        cant_unidad_medida = p_cant_unidad_medida,
        contenedor_id = p_contenedor_id,
        unidades_por_contenedor = COALESCE(p_unidades_por_contenedor, 1),
        imagen_path = p_imagen_path
    WHERE id = p_id;

    RETURN FOUND;
END;
$$;
