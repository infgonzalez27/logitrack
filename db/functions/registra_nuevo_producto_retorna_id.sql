CREATE OR REPLACE FUNCTION public.registra_nuevo_producto_retorna_id(
    p_codigo_producto TEXT,
    p_nombre TEXT,
    p_codigo_barras TEXT DEFAULT NULL,
    p_descripcion TEXT DEFAULT NULL,
    p_cant_unidad_medida NUMERIC DEFAULT NULL,
    p_precio_lista1 NUMERIC DEFAULT 0,
    p_precio_lista2 NUMERIC DEFAULT 0,
    p_precio_lista3 NUMERIC DEFAULT 0,
    p_contenedor_id UUID DEFAULT NULL,
    p_unidades_por_contenedor NUMERIC DEFAULT 1,
    p_imagen_path TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_new_id UUID;
    v_codigo_barras TEXT;
BEGIN
    -- Tratar cadena vac├¡a como NULL en codigo_barras para evitar violaciones de UNIQUE
    v_codigo_barras := NULLIF(TRIM(p_codigo_barras), '');

    INSERT INTO public.productos (
        codigo_producto,
        nombre,
        codigo_barras,
        descripcion,
        cant_unidad_medida,
        precio_lista1,
        precio_lista2,
        precio_lista3,
        contenedor_id,
        unidades_por_contenedor,
        imagen_path
    )
    VALUES (
        TRIM(p_codigo_producto),
        TRIM(p_nombre),
        v_codigo_barras,
        p_descripcion,
        p_cant_unidad_medida,
        COALESCE(p_precio_lista1, 0),
        COALESCE(p_precio_lista2, 0),
        COALESCE(p_precio_lista3, 0),
        p_contenedor_id,
        COALESCE(p_unidades_por_contenedor, 1),
        p_imagen_path
    )
    RETURNING id INTO v_new_id;

    RETURN v_new_id;
END;
$$;
