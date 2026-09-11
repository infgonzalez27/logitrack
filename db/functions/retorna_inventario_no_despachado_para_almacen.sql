CREATE OR REPLACE FUNCTION public.retorna_inventario_no_despachado_para_almacen(
    p_radar_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_rec RECORD;
    v_detalles JSONB := '[]'::jsonb;
BEGIN
    IF p_radar_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID del radar es requerido.'
            )
        );
    END IF;

    -- Recorrer todos los productos no despachados/devueltos de las órdenes del radar
    FOR v_rec IN
        SELECT 
            d.producto_id,
            p.codigo_producto,
            p.nombre AS nombre_producto,
            SUM(GREATEST(0, d.cantidad_solicitada - COALESCE(d.cantidad_despachada, 0))) AS total_devuelto,
            MIN(o.camion_id) AS camion_id
        FROM public.ordenes_distribucion o
        JOIN public.detalle_distribucion d ON d.orden_id = o.id
        JOIN public.productos p ON p.id = d.producto_id
        WHERE o.radar_id = p_radar_id
        GROUP BY d.producto_id, p.codigo_producto, p.nombre
        HAVING SUM(GREATEST(0, d.cantidad_solicitada - COALESCE(d.cantidad_despachada, 0))) > 0
    LOOP
        -- 1. Reingresar el stock no despachado al almacén principal (inventario_almacen.stock_disponible)
        INSERT INTO public.inventario_almacen (producto_id, stock_disponible, stock_comprometido, updated_at)
        VALUES (v_rec.producto_id, v_rec.total_devuelto, 0, NOW())
        ON CONFLICT (producto_id)
        DO UPDATE SET 
            stock_disponible = public.inventario_almacen.stock_disponible + v_rec.total_devuelto,
            updated_at = NOW();

        -- Opcional: Actualizar también en la tabla productos si existiera la columna stock_disponible
        BEGIN
            UPDATE public.productos
            SET stock_disponible = COALESCE(stock_disponible, 0) + v_rec.total_devuelto,
                updated_at = NOW()
            WHERE id = v_rec.producto_id;
        EXCEPTION WHEN OTHERS THEN
            -- Ignorar si la columna no existe en la tabla productos
            NULL;
        END;

        -- 2. Descontar / rebajar del inventario móvil del camión la mercancía no entregada (devuelta)
        IF v_rec.camion_id IS NOT NULL THEN
            UPDATE public.inventario_movil
            SET cantidad_cargada = GREATEST(0, cantidad_cargada - v_rec.total_devuelto),
                updated_at = NOW()
            WHERE camion_id = v_rec.camion_id AND producto_id = v_rec.producto_id;
        END IF;

        -- Agregar al arreglo de respuesta
        v_detalles := v_detalles || jsonb_build_object(
            'producto_id', v_rec.producto_id,
            'codigo_producto', v_rec.codigo_producto,
            'nombre_producto', v_rec.nombre_producto,
            'cantidad_devuelta', v_rec.total_devuelto
        );
    END LOOP;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Inventario no despachado retornado exitosamente al almacén principal.',
        'data', v_detalles,
        'error', NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', SQLSTATE,
                'message', SQLERRM
            )
        );
END;
$$;

GRANT EXECUTE ON FUNCTION public.retorna_inventario_no_despachado_para_almacen TO authenticated, service_role;

COMMENT ON FUNCTION public.retorna_inventario_no_despachado_para_almacen(UUID) IS 'Reingresa la mercancía no despachada de las órdenes asociadas a un radar al stock disponible del almacén principal.';
