-- Patch para corregir el nombre del campo en el JSONB (producto_id en lugar de id_producto)
-- para que coincida con lo que enva el frontend en la accin de movimientos de inventario.

CREATE OR REPLACE FUNCTION public.registrar_movimiento_inventario_especial(
    p_tipo_movimiento VARCHAR, 
    p_concepto VARCHAR,
    p_tipo_inventario_afectado VARCHAR, 
    p_id_referencia_movil UUID, 
    p_id_cliente UUID, 
    p_observaciones TEXT, 
    p_detalles JSONB 
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_uid UUID;
    v_id_movimiento UUID;
    v_detalle RECORD;
    v_stock_actual NUMERIC;
BEGIN
    -- Autenticacin
    v_uid := auth.uid();
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'No autenticado';
    END IF;

    -- Validaciones Bǭsicas
    IF p_tipo_inventario_afectado NOT IN ('ALMACEN', 'MOVIL') THEN
        RAISE EXCEPTION 'Tipo de inventario afectado invǭlido (Debe ser ALMACEN o MOVIL)';
    END IF;

    IF p_tipo_movimiento NOT IN ('ENTRADA', 'SALIDA') THEN
        RAISE EXCEPTION 'Tipo de movimiento invǭlido (Debe ser ENTRADA o SALIDA)';
    END IF;

    -- 1. Insertar Cabecera
    INSERT INTO public.movimientos_inventario (
        tipo_movimiento, concepto, tipo_inventario_afectado, id_referencia_movil,
        id_cliente, autorizado_por, observaciones
    ) VALUES (
        p_tipo_movimiento, p_concepto, p_tipo_inventario_afectado, p_id_referencia_movil,
        p_id_cliente, v_uid, p_observaciones
    ) RETURNING id INTO v_id_movimiento;

    -- 2. Procesar Detalles y Actualizar Stock
    -- SE CORRIGI": id_producto -> producto_id en jsonb_to_recordset
    FOR v_detalle IN SELECT * FROM jsonb_to_recordset(p_detalles) AS x(producto_id UUID, cantidad NUMERIC, costo_unitario NUMERIC)
    LOOP
        -- Insertar Detalle
        INSERT INTO public.movimientos_inventario_detalle (
            id_movimiento, id_producto, cantidad, costo_unitario
        ) VALUES (
            v_id_movimiento, v_detalle.producto_id, v_detalle.cantidad, v_detalle.costo_unitario
        );

        -- Lgica de validacin y actualizacin de stock (AlmacǸn o Mvil)
        IF p_tipo_inventario_afectado = 'ALMACEN' THEN
            IF p_tipo_movimiento = 'SALIDA' THEN
                -- Validar stock suficiente
                SELECT stock_disponible INTO v_stock_actual FROM public.inventario_almacen WHERE producto_id = v_detalle.producto_id FOR UPDATE;
                IF NOT FOUND OR v_stock_actual < v_detalle.cantidad THEN
                    RAISE EXCEPTION 'Stock insuficiente en almacǸn para el producto %', v_detalle.producto_id;
                END IF;
                -- Restar stock
                UPDATE public.inventario_almacen SET stock_disponible = stock_disponible - v_detalle.cantidad WHERE producto_id = v_detalle.producto_id;
            ELSE
                -- Sumar stock
                INSERT INTO public.inventario_almacen (producto_id, stock_disponible)
                VALUES (v_detalle.producto_id, v_detalle.cantidad)
                ON CONFLICT (producto_id) DO UPDATE SET stock_disponible = inventario_almacen.stock_disponible + v_detalle.cantidad;
            END IF;

        ELSIF p_tipo_inventario_afectado = 'MOVIL' THEN
            IF p_id_referencia_movil IS NULL THEN
                RAISE EXCEPTION 'Se requiere un ID de radar/camin para afectar inventario mvil';
            END IF;

            IF p_tipo_movimiento = 'SALIDA' THEN
                -- Validar stock suficiente
                SELECT cantidad_disponible INTO v_stock_actual FROM public.inventario_movil WHERE radar_id = p_id_referencia_movil AND producto_id = v_detalle.producto_id FOR UPDATE;
                IF NOT FOUND OR v_stock_actual < v_detalle.cantidad THEN
                    RAISE EXCEPTION 'Stock insuficiente en el camin para el producto %', v_detalle.producto_id;
                END IF;
                -- Restar stock
                UPDATE public.inventario_movil SET cantidad_disponible = cantidad_disponible - v_detalle.cantidad WHERE radar_id = p_id_referencia_movil AND producto_id = v_detalle.producto_id;
            ELSE
                -- Sumar stock (Nota: Usualmente los camiones inician vacos y se cargan, pero se permite entrada directa por ajuste)
                INSERT INTO public.inventario_movil (radar_id, producto_id, cantidad_disponible)
                VALUES (p_id_referencia_movil, v_detalle.producto_id, v_detalle.cantidad)
                ON CONFLICT (radar_id, producto_id) DO UPDATE SET cantidad_disponible = inventario_movil.cantidad_disponible + v_detalle.cantidad;
            END IF;
        END IF;

    END LOOP;

    RETURN jsonb_build_object(
        'success', true, 
        'message', 'Movimiento registrado exitosamente',
        'movimiento_id', v_id_movimiento
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'message', SQLERRM);
END;
$$;
