-- Patch Idempotente: Corrección de RPC registrar_movimiento_inventario_especial para inventario móvil
-- Corrige el error: column "cantidad_disponible" does not exist
-- En la tabla public.inventario_movil las columnas reales son camion_id, producto_id, cantidad_cargada, cantidad_entregada, cantidad_devolucion.
-- No existen las columnas radar_id ni cantidad_disponible. El stock disponible en camión es (cantidad_cargada - cantidad_entregada).

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
    -- Autenticación
    v_uid := auth.uid();
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'No autorizado. Debe iniciar sesión.';
    END IF;

    -- Validaciones Básicas
    IF p_tipo_inventario_afectado NOT IN ('ALMACEN', 'MOVIL') THEN
        RAISE EXCEPTION 'Tipo de inventario afectado inválido (Debe ser ALMACEN o MOVIL)';
    END IF;

    IF p_tipo_movimiento NOT IN ('ENTRADA', 'SALIDA') THEN
        RAISE EXCEPTION 'Tipo de movimiento inválido (Debe ser ENTRADA o SALIDA)';
    END IF;

    IF p_tipo_inventario_afectado = 'MOVIL' AND p_id_referencia_movil IS NULL THEN
        RAISE EXCEPTION 'Se requiere un camión para afectar el inventario móvil';
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
    -- Soporta tanto producto_id como id_producto por compatibilidad
    FOR v_detalle IN 
        SELECT 
            COALESCE(x.producto_id, x.id_producto) AS producto_id,
            x.cantidad,
            COALESCE(x.costo_unitario, 0) AS costo_unitario
        FROM jsonb_to_recordset(p_detalles) AS x(
            producto_id UUID, 
            id_producto UUID, 
            cantidad NUMERIC, 
            costo_unitario NUMERIC
        )
    LOOP
        IF v_detalle.producto_id IS NULL THEN
            RAISE EXCEPTION 'El identificador del producto es requerido.';
        END IF;

        IF v_detalle.cantidad IS NULL OR v_detalle.cantidad <= 0 THEN
            RAISE EXCEPTION 'La cantidad debe ser mayor a 0.';
        END IF;

        -- Insertar Detalle en movimientos_inventario_detalle
        INSERT INTO public.movimientos_inventario_detalle (
            id_movimiento, id_producto, cantidad, costo_unitario
        ) VALUES (
            v_id_movimiento, v_detalle.producto_id, v_detalle.cantidad, v_detalle.costo_unitario
        );

        -- Lógica de validación y actualización de stock (Almacén o Móvil)
        IF p_tipo_inventario_afectado = 'ALMACEN' THEN
            IF p_tipo_movimiento = 'SALIDA' THEN
                -- Validar stock suficiente
                SELECT stock_disponible INTO v_stock_actual 
                FROM public.inventario_almacen 
                WHERE producto_id = v_detalle.producto_id 
                FOR UPDATE;

                IF NOT FOUND OR v_stock_actual < v_detalle.cantidad THEN
                    RAISE EXCEPTION 'Stock insuficiente en almacén para el producto %', v_detalle.producto_id;
                END IF;

                -- Restar stock
                UPDATE public.inventario_almacen 
                SET stock_disponible = stock_disponible - v_detalle.cantidad::INTEGER,
                    updated_at = NOW()
                WHERE producto_id = v_detalle.producto_id;
            ELSE
                -- Sumar stock
                INSERT INTO public.inventario_almacen (producto_id, stock_disponible, stock_comprometido, updated_at)
                VALUES (v_detalle.producto_id, v_detalle.cantidad::INTEGER, 0, NOW())
                ON CONFLICT (producto_id) 
                DO UPDATE SET 
                    stock_disponible = public.inventario_almacen.stock_disponible + EXCLUDED.stock_disponible,
                    updated_at = NOW();
            END IF;

        ELSIF p_tipo_inventario_afectado = 'MOVIL' THEN
            IF p_tipo_movimiento = 'SALIDA' THEN
                -- Validar stock suficiente disponible en camión (cantidad_cargada - cantidad_entregada)
                SELECT (COALESCE(cantidad_cargada, 0) - COALESCE(cantidad_entregada, 0)) INTO v_stock_actual 
                FROM public.inventario_movil 
                WHERE camion_id = p_id_referencia_movil AND producto_id = v_detalle.producto_id 
                FOR UPDATE;

                IF NOT FOUND OR v_stock_actual < v_detalle.cantidad THEN
                    RAISE EXCEPTION 'Stock insuficiente en el camión para el producto %', v_detalle.producto_id;
                END IF;

                -- Restar stock cargado en el camión
                UPDATE public.inventario_movil 
                SET cantidad_cargada = cantidad_cargada - v_detalle.cantidad::INTEGER,
                    updated_at = NOW()
                WHERE camion_id = p_id_referencia_movil AND producto_id = v_detalle.producto_id;
            ELSE
                -- Sumar stock al camión
                INSERT INTO public.inventario_movil (
                    camion_id, 
                    producto_id, 
                    cantidad_cargada, 
                    cantidad_entregada, 
                    cantidad_devolucion, 
                    updated_at
                )
                VALUES (
                    p_id_referencia_movil, 
                    v_detalle.producto_id, 
                    v_detalle.cantidad::INTEGER, 
                    0, 
                    0, 
                    NOW()
                )
                ON CONFLICT (camion_id, producto_id) 
                DO UPDATE SET 
                    cantidad_cargada = public.inventario_movil.cantidad_cargada + EXCLUDED.cantidad_cargada,
                    updated_at = NOW();
            END IF;
        END IF;

    END LOOP;

    RETURN jsonb_build_object(
        'success', true, 
        'message', 'Movimiento registrado exitosamente',
        'data', jsonb_build_object('movimiento_id', v_id_movimiento),
        'error', null
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false, 
        'message', SQLERRM,
        'data', null,
        'error', jsonb_build_object('message', SQLERRM, 'code', SQLSTATE)
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.registrar_movimiento_inventario_especial(
    VARCHAR, VARCHAR, VARCHAR, UUID, UUID, TEXT, JSONB
) TO authenticated, service_role;
