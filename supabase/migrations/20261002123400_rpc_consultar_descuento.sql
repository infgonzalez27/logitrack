CREATE OR REPLACE FUNCTION public.consultar_descuento_producto_cliente(
    p_cliente_id UUID,
    p_producto_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_val_usd_prod NUMERIC(14,2);
    v_desc_rec RECORD;
    v_pct_desc NUMERIC(5,2) := 0.00;
    v_monto_desc_unit NUMERIC(14,2) := 0.00;
    v_val_usd NUMERIC(14,2);
    v_aplica BOOLEAN := FALSE;
BEGIN
    -- Validar parámetros
    IF p_cliente_id IS NULL OR p_producto_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'cliente_id y producto_id son requeridos.');
    END IF;

    -- Extraer el precio base del producto
    SELECT COALESCE(precio_lista1, 0.00) INTO v_val_usd_prod 
    FROM public.productos 
    WHERE id = p_producto_id;

    IF v_val_usd_prod IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'Producto no encontrado.');
    END IF;

    -- Buscar si hay descuento activo para este cliente y producto
    SELECT * INTO v_desc_rec
    FROM public.descuentos_cliente_producto
    WHERE cliente_id = p_cliente_id AND producto_id = p_producto_id AND activo = true;

    IF v_desc_rec.id IS NOT NULL THEN
        v_aplica := TRUE;
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
            v_aplica := FALSE;
        END IF;
    ELSE
        -- No hay descuento registrado
        v_pct_desc := 0.00;
        v_monto_desc_unit := 0.00;
        v_val_usd := v_val_usd_prod;
    END IF;

    -- Retornar el detalle exacto
    RETURN jsonb_build_object(
        'success', true,
        'data', jsonb_build_object(
            'producto_id', p_producto_id,
            'cliente_id', p_cliente_id,
            'aplica_descuento', v_aplica,
            'precio_lista_usd', v_val_usd_prod,
            'precio_final_usd', v_val_usd,
            'porcentaje_descuento', v_pct_desc,
            'monto_descuento_usd', v_monto_desc_unit
        )
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;
