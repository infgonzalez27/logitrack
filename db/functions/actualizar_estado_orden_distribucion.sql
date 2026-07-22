CREATE OR REPLACE FUNCTION public.actualizar_estado_orden_distribucion(
    p_orden_id UUID,
    p_estado TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_estado_actual TEXT;
    v_camion_id UUID;
    v_chofer_id UUID;
    v_item RECORD;
    v_producto_nombre TEXT;
    v_stock_disponible INT;
    v_stock_comprometido INT;
BEGIN
    -- Validar parámetros
    IF p_orden_id IS NULL THEN
        RAISE EXCEPTION 'El ID de la orden es requerido.';
    END IF;

    IF p_estado IS NULL THEN
        RAISE EXCEPTION 'El estado de destino es requerido.';
    END IF;

    -- Validar que el estado de destino sea válido
    IF p_estado NOT IN ('borrador', 'lista_para_carga', 'en_transito', 'liquidada', 'anulada') THEN
        RAISE EXCEPTION 'El estado % no es un estado válido para la orden.', p_estado;
    END IF;

    -- Obtener datos de la orden
    SELECT estado, camion_id, chofer_id 
    INTO v_estado_actual, v_camion_id, v_chofer_id
    FROM public.ordenes_distribucion
    WHERE id = p_orden_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La orden de distribución con ID % no existe.', p_orden_id;
    END IF;

    -- Si ya está en el estado solicitado, no hacer nada
    IF v_estado_actual = p_estado THEN
        RETURN;
    END IF;

    -- Validar transiciones de estado permitidas
    IF v_estado_actual = 'borrador' AND p_estado NOT IN ('lista_para_carga', 'anulada') THEN
        RAISE EXCEPTION 'Transición no permitida: de % a %.', v_estado_actual, p_estado;
    ELSIF v_estado_actual = 'lista_para_carga' AND p_estado NOT IN ('en_transito', 'borrador', 'anulada') THEN
        RAISE EXCEPTION 'Transición no permitida: de % a %.', v_estado_actual, p_estado;
    ELSIF v_estado_actual = 'en_transito' AND p_estado NOT IN ('liquidada', 'anulada') THEN
        RAISE EXCEPTION 'Transición no permitida: de % a %.', v_estado_actual, p_estado;
    ELSIF v_estado_actual IN ('liquidada', 'anulada') THEN
        RAISE EXCEPTION 'No se pueden realizar cambios de estado en una orden %.', v_estado_actual;
    END IF;

    ---------------------------------------------------------------------------
    -- LOGICA DE TRANSICIONES
    ---------------------------------------------------------------------------

    -- 1. De BORRADOR a LISTA_PARA_CARGA
    IF v_estado_actual = 'borrador' AND p_estado = 'lista_para_carga' THEN
        -- Reservar stock en el almacén principal
        FOR v_item IN 
            SELECT producto_id, cantidad_solicitada 
            FROM public.detalle_distribucion 
            WHERE orden_id = p_orden_id
        LOOP
            -- Buscar stock del producto
            SELECT stock_disponible, stock_comprometido 
            INTO v_stock_disponible, v_stock_comprometido
            FROM public.inventario_almacen
            WHERE producto_id = v_item.producto_id
            FOR UPDATE; -- Bloquear fila para concurrencia

            IF NOT FOUND THEN
                SELECT nombre INTO v_producto_nombre FROM public.productos WHERE id = v_item.producto_id;
                RAISE EXCEPTION 'El producto % no tiene un registro de inventario en almacén.', COALESCE(v_producto_nombre, v_item.producto_id::text);
            END IF;

            IF v_stock_disponible < v_item.cantidad_solicitada THEN
                SELECT nombre INTO v_producto_nombre FROM public.productos WHERE id = v_item.producto_id;
                RAISE EXCEPTION 'Stock insuficiente en almacén para el producto % (Disponible: %, Requerido: %).', 
                    COALESCE(v_producto_nombre, v_item.producto_id::text), v_stock_disponible, v_item.cantidad_solicitada;
            END IF;

            -- Actualizar inventario de almacén (descuenta de disponible, suma a comprometido)
            UPDATE public.inventario_almacen
            SET stock_disponible = stock_disponible - v_item.cantidad_solicitada,
                stock_comprometido = stock_comprometido + v_item.cantidad_solicitada,
                updated_at = NOW()
            WHERE producto_id = v_item.producto_id;
        END LOOP;

        -- Actualizar estado de la orden
        UPDATE public.ordenes_distribucion
        SET estado = 'lista_para_carga'
        WHERE id = p_orden_id;

    -- 2. De LISTA_PARA_CARGA a BORRADOR
    ELSIF v_estado_actual = 'lista_para_carga' AND p_estado = 'borrador' THEN
        -- Liberar reserva de stock
        FOR v_item IN 
            SELECT producto_id, cantidad_solicitada 
            FROM public.detalle_distribucion 
            WHERE orden_id = p_orden_id
        LOOP
            UPDATE public.inventario_almacen
            SET stock_disponible = stock_disponible + v_item.cantidad_solicitada,
                stock_comprometido = stock_comprometido - v_item.cantidad_solicitada,
                updated_at = NOW()
            WHERE producto_id = v_item.producto_id;
        END LOOP;

        -- Actualizar estado de la orden
        UPDATE public.ordenes_distribucion
        SET estado = 'borrador'
        WHERE id = p_orden_id;

    -- 3. De LISTA_PARA_CARGA a EN_TRANSITO
    ELSIF v_estado_actual = 'lista_para_carga' AND p_estado = 'en_transito' THEN
        -- Validar camión y chofer asignados
        IF v_camion_id IS NULL THEN
            RAISE EXCEPTION 'No se puede despachar la orden porque no tiene un camión asignado.';
        END IF;

        IF v_chofer_id IS NULL THEN
            RAISE EXCEPTION 'No se puede despachar la orden porque no tiene un chofer asignado.';
        END IF;

        -- Actualizar camión a estado 'en_ruta'
        UPDATE public.camiones
        SET estado = 'en_ruta'
        WHERE id = v_camion_id;

        -- Actualizar chofer a estado 'en_ruta'
        UPDATE public.choferes
        SET estado = 'en_ruta'
        WHERE perfil_id = v_chofer_id;

        -- Carga de mercancía al inventario móvil del camión
        FOR v_item IN 
            SELECT producto_id, cantidad_solicitada 
            FROM public.detalle_distribucion 
            WHERE orden_id = p_orden_id
        LOOP
            -- Descontar del comprometido del almacén principal (sale físicamente del centro de distribución)
            UPDATE public.inventario_almacen
            SET stock_comprometido = stock_comprometido - v_item.cantidad_solicitada,
                updated_at = NOW()
            WHERE producto_id = v_item.producto_id;

            -- Upsert en inventario móvil del camión
            INSERT INTO public.inventario_movil (
                camion_id,
                producto_id,
                cantidad_cargada,
                cantidad_entregada,
                cantidad_devolucion,
                updated_at
            ) VALUES (
                v_camion_id,
                v_item.producto_id,
                v_item.cantidad_solicitada,
                0,
                0,
                NOW()
            )
            ON CONFLICT (camion_id, producto_id) 
            DO UPDATE SET 
                cantidad_cargada = inventario_movil.cantidad_cargada + v_item.cantidad_solicitada,
                updated_at = NOW();

            -- Actualizar detalle: cantidad_despachada es la cantidad cargada
            UPDATE public.detalle_distribucion
            SET cantidad_despachada = v_item.cantidad_solicitada
            WHERE orden_id = p_orden_id AND producto_id = v_item.producto_id;
        END LOOP;

        -- Actualizar estado y fecha de despacho de la orden
        UPDATE public.ordenes_distribucion
        SET estado = 'en_transito',
            fecha_despacho = NOW()
        WHERE id = p_orden_id;

    -- 4. De EN_TRANSITO a LIQUIDADA
    ELSIF v_estado_actual = 'en_transito' AND p_estado = 'liquidada' THEN
        -- Retornar camión y chofer a estado 'disponible'
        UPDATE public.camiones
        SET estado = 'disponible'
        WHERE id = v_camion_id;

        UPDATE public.choferes
        SET estado = 'disponible'
        WHERE perfil_id = v_chofer_id;

        -- Procesar entregas y devoluciones en base a estado_entrega
        FOR v_item IN 
            SELECT producto_id, cantidad_despachada, COALESCE(estado_entrega, 'pendiente') as estado_entrega
            FROM public.detalle_distribucion 
            WHERE orden_id = p_orden_id
        LOOP
            -- Caso 1: Entregado (o pendiente que por defecto se liquida como entregado) o Entregado Parcial
            -- Nota: Como no existe columna de cantidad entregada parcial en detalle_distribucion,
            -- asumimos para efectos de inventario móvil que lo despachado fue entregado.
            IF v_item.estado_entrega IN ('entregado', 'pendiente', 'entregado_parcial') THEN
                UPDATE public.inventario_movil
                SET cantidad_cargada = cantidad_cargada - v_item.cantidad_despachada,
                    cantidad_entregada = cantidad_entregada + v_item.cantidad_despachada,
                    updated_at = NOW()
                WHERE camion_id = v_camion_id AND producto_id = v_item.producto_id;

            -- Caso 2: Rechazado
            ELSIF v_item.estado_entrega = 'rechazado' THEN
                -- Mover a cantidad_devolucion en inventario móvil
                UPDATE public.inventario_movil
                SET cantidad_cargada = cantidad_cargada - v_item.cantidad_despachada,
                    cantidad_devolucion = cantidad_devolucion + v_item.cantidad_despachada,
                    updated_at = NOW()
                WHERE camion_id = v_camion_id AND producto_id = v_item.producto_id;

                -- Regresar la mercancía al stock disponible del almacén principal
                UPDATE public.inventario_almacen
                SET stock_disponible = stock_disponible + v_item.cantidad_despachada,
                    updated_at = NOW()
                WHERE producto_id = v_item.producto_id;
            END IF;
        END LOOP;

        -- Actualizar estado de la orden
        UPDATE public.ordenes_distribucion
        SET estado = 'liquidada'
        WHERE id = p_orden_id;

    -- 5. De CUALQUIER ESTADO a ANULADA
    ELSIF p_estado = 'anulada' THEN
        -- Si estaba en 'borrador', no hay stock comprometido ni camión en ruta
        IF v_estado_actual = 'borrador' THEN
            -- No requiere ajustar inventarios
            NULL;

        -- Si estaba en 'lista_para_carga', liberar stock reservado
        ELSIF v_estado_actual = 'lista_para_carga' THEN
            FOR v_item IN 
                SELECT producto_id, cantidad_solicitada 
                FROM public.detalle_distribucion 
                WHERE orden_id = p_orden_id
            LOOP
                UPDATE public.inventario_almacen
                SET stock_disponible = stock_disponible + v_item.cantidad_solicitada,
                    stock_comprometido = stock_comprometido - v_item.cantidad_solicitada,
                    updated_at = NOW()
                WHERE producto_id = v_item.producto_id;
            END LOOP;

        -- Si estaba en 'en_transito', liberar camión, chofer y retornar stock cargado al almacén
        ELSIF v_estado_actual = 'en_transito' THEN
            -- Liberar camión y chofer
            UPDATE public.camiones
            SET estado = 'disponible'
            WHERE id = v_camion_id;

            UPDATE public.choferes
            SET estado = 'disponible'
            WHERE perfil_id = v_chofer_id;

            FOR v_item IN 
                SELECT producto_id, cantidad_despachada 
                FROM public.detalle_distribucion 
                WHERE orden_id = p_orden_id
            LOOP
                -- Descontar del inventario móvil cargado
                UPDATE public.inventario_movil
                SET cantidad_cargada = cantidad_cargada - v_item.cantidad_despachada,
                    updated_at = NOW()
                WHERE camion_id = v_camion_id AND producto_id = v_item.producto_id;

                -- Regresar al stock disponible del almacén principal
                UPDATE public.inventario_almacen
                SET stock_disponible = stock_disponible + v_item.cantidad_despachada,
                    updated_at = NOW()
                WHERE producto_id = v_item.producto_id;
            END LOOP;
        END IF;

        -- Actualizar estado de la orden
        UPDATE public.ordenes_distribucion
        SET estado = 'anulada'
        WHERE id = p_orden_id;
    END IF;

END;
$$;
