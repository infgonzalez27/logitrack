-- Migration: Regla de Permisos de Modificación de Órdenes (DB-012)
-- Un vendedor solo puede modificar sus propias órdenes (creado_por = auth.uid()).
-- Un gerente o admin puede modificar cualquier orden.

-- 1. Actualizar políticas RLS en ordenes_distribucion
DROP POLICY IF EXISTS modify_ordenes_distribucion ON public.ordenes_distribucion;

CREATE POLICY modify_ordenes_distribucion ON public.ordenes_distribucion
FOR ALL
USING (
    -- Admin, gerente o despachador pueden modificar cualquier orden
    public.user_has_role(ARRAY['admin', 'gerente', 'despachador'])
    -- Vendedor solo puede modificar las ordenes creadas por el mismo
    OR (
        public.user_has_role(ARRAY['vendedor']) 
        AND creado_por = auth.uid()
    )
);

-- 2. Actualizar función actualizar_estado_orden_distribucion con chequeo de autoría para vendedores
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
    v_creado_por UUID;
    v_user_id UUID := auth.uid();
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
    SELECT estado, camion_id, chofer_id, creado_por
    INTO v_estado_actual, v_camion_id, v_chofer_id, v_creado_por
    FROM public.ordenes_distribucion
    WHERE id = p_orden_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La orden de distribución con ID % no existe.', p_orden_id;
    END IF;

    -- VALIDACIÓN DE PERMISOS POR ROL Y AUTORÍA (DB-012)
    -- Si es vendedor y no es gerente/admin/despachador, validar que haya creado la orden
    IF public.user_has_role(ARRAY['vendedor']) AND NOT public.user_has_role(ARRAY['admin', 'gerente', 'despachador']) THEN
        IF v_user_id IS NOT NULL AND v_creado_por IS DISTINCT FROM v_user_id THEN
            RAISE EXCEPTION 'ACCESO_DENEGADO: Un vendedor solo puede modificar las órdenes que ha registrado.';
        END IF;
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
    -- LÓGICA DE TRANSICIONES
    ---------------------------------------------------------------------------

    -- 1. De BORRADOR a LISTA_PARA_CARGA
    IF v_estado_actual = 'borrador' AND p_estado = 'lista_para_carga' THEN
        FOR v_item IN 
            SELECT producto_id, cantidad_solicitada 
            FROM public.detalle_distribucion 
            WHERE orden_id = p_orden_id
        LOOP
            SELECT stock_disponible, stock_comprometido 
            INTO v_stock_disponible, v_stock_comprometido
            FROM public.inventario_almacen
            WHERE producto_id = v_item.producto_id
            FOR UPDATE;

            IF NOT FOUND THEN
                SELECT nombre INTO v_producto_nombre FROM public.productos WHERE id = v_item.producto_id;
                RAISE EXCEPTION 'El producto % no tiene un registro de inventario en almacén.', COALESCE(v_producto_nombre, v_item.producto_id::text);
            END IF;

            IF v_stock_disponible < v_item.cantidad_solicitada THEN
                SELECT nombre INTO v_producto_nombre FROM public.productos WHERE id = v_item.producto_id;
                RAISE EXCEPTION 'Stock insuficiente en almacén para el producto % (Disponible: %, Requerido: %).', 
                    COALESCE(v_producto_nombre, v_item.producto_id::text), v_stock_disponible, v_item.cantidad_solicitada;
            END IF;

            UPDATE public.inventario_almacen
            SET stock_disponible = stock_disponible - v_item.cantidad_solicitada,
                stock_comprometido = stock_comprometido + v_item.cantidad_solicitada,
                updated_at = NOW()
            WHERE producto_id = v_item.producto_id;
        END LOOP;

        UPDATE public.ordenes_distribucion
        SET estado = 'lista_para_carga'
        WHERE id = p_orden_id;

    -- 2. De LISTA_PARA_CARGA a BORRADOR (Reversión de reserva)
    ELSIF v_estado_actual = 'lista_para_carga' AND p_estado = 'borrador' THEN
        FOR v_item IN 
            SELECT producto_id, cantidad_solicitada 
            FROM public.detalle_distribucion 
            WHERE orden_id = p_orden_id
        LOOP
            UPDATE public.inventario_almacen
            SET stock_disponible = stock_disponible + v_item.cantidad_solicitada,
                stock_comprometido = GREATEST(0, stock_comprometido - v_item.cantidad_solicitada),
                updated_at = NOW()
            WHERE producto_id = v_item.producto_id;
        END LOOP;

        UPDATE public.ordenes_distribucion
        SET estado = 'borrador'
        WHERE id = p_orden_id;

    -- 3. De LISTA_PARA_CARGA a EN_TRANSITO
    ELSIF v_estado_actual = 'lista_para_carga' AND p_estado = 'en_transito' THEN
        IF v_camion_id IS NULL OR v_chofer_id IS NULL THEN
            RAISE EXCEPTION 'Para pasar a en_transito la orden debe tener asignado un camión y un chofer.';
        END IF;

        FOR v_item IN 
            SELECT producto_id, cantidad_solicitada 
            FROM public.detalle_distribucion 
            WHERE orden_id = p_orden_id
        LOOP
            UPDATE public.inventario_almacen
            SET stock_comprometido = GREATEST(0, stock_comprometido - v_item.cantidad_solicitada),
                updated_at = NOW()
            WHERE producto_id = v_item.producto_id;

            INSERT INTO public.inventario_movil (camion_id, producto_id, cantidad_cargada, cantidad_entregada, cantidad_devolucion, updated_at)
            VALUES (v_camion_id, v_item.producto_id, v_item.cantidad_solicitada, 0, 0, NOW())
            ON CONFLICT (camion_id, producto_id) 
            DO UPDATE SET 
                cantidad_cargada = public.inventario_movil.cantidad_cargada + EXCLUDED.cantidad_cargada,
                updated_at = NOW();
        END LOOP;

        UPDATE public.ordenes_distribucion
        SET estado = 'en_transito'
        WHERE id = p_orden_id;

        UPDATE public.camiones SET estado = 'en_ruta' WHERE id = v_camion_id;
        UPDATE public.perfiles_usuario SET activo = true WHERE id = v_chofer_id;

    -- 4. De EN_TRANSITO a LIQUIDADA
    ELSIF v_estado_actual = 'en_transito' AND p_estado = 'liquidada' THEN
        UPDATE public.ordenes_distribucion
        SET estado = 'liquidada'
        WHERE id = p_orden_id;

        UPDATE public.camiones SET estado = 'disponible' WHERE id = v_camion_id;

    -- 5. CUALQUIERA a ANULADA
    ELSIF p_estado = 'anulada' THEN
        IF v_estado_actual = 'lista_para_carga' THEN
            FOR v_item IN 
                SELECT producto_id, cantidad_solicitada 
                FROM public.detalle_distribucion 
                WHERE orden_id = p_orden_id
            LOOP
                UPDATE public.inventario_almacen
                SET stock_disponible = stock_disponible + v_item.cantidad_solicitada,
                    stock_comprometido = GREATEST(0, stock_comprometido - v_item.cantidad_solicitada),
                    updated_at = NOW()
                WHERE producto_id = v_item.producto_id;
            END LOOP;
        END IF;

        UPDATE public.ordenes_distribucion
        SET estado = 'anulada'
        WHERE id = p_orden_id;

        IF v_camion_id IS NOT NULL THEN
            UPDATE public.camiones SET estado = 'disponible' WHERE id = v_camion_id;
        END IF;
    END IF;
END;
$$;


-- 3. Actualizar función anular_orden_distribucion con chequeo de autoría para vendedores
CREATE OR REPLACE FUNCTION public.anular_orden_distribucion(
    p_orden_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_estado_actual TEXT;
    v_creado_por UUID;
    v_user_id UUID := auth.uid();
    v_item RECORD;
BEGIN
    -- Validar parámetros
    IF p_orden_id IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID de la orden es requerido.',
                'details', NULL
            )
        );
    END IF;

    -- Obtener estado y creador de la orden
    SELECT estado, creado_por INTO v_estado_actual, v_creado_por
    FROM public.ordenes_distribucion
    WHERE id = p_orden_id;

    IF v_estado_actual IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ORDEN_INEXISTENTE',
                'message', 'La orden de distribución especificada no existe.',
                'details', NULL
            )
        );
    END IF;

    -- VALIDACIÓN DE PERMISOS POR ROL Y AUTORÍA (DB-012)
    IF public.user_has_role(ARRAY['vendedor']) AND NOT public.user_has_role(ARRAY['admin', 'gerente', 'despachador']) THEN
        IF v_user_id IS NOT NULL AND v_creado_por IS DISTINCT FROM v_user_id THEN
            RETURN json_build_object(
                'success', false,
                'data', NULL,
                'error', json_build_object(
                    'code', 'ACCESO_DENEGADO',
                    'message', 'Un vendedor solo puede anular las órdenes que ha registrado.',
                    'details', NULL
                )
            );
        END IF;
    END IF;

    -- Validar si la orden puede ser anulada
    IF v_estado_actual IN ('en_transito', 'liquidada', 'anulada') THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'No se puede anular una orden en estado ' || v_estado_actual || '.',
                'details', NULL
            )
        );
    END IF;

    -- Si está aprobada / lista_para_carga, liberar reservas de inventario
    IF v_estado_actual IN ('aprobada', 'lista_para_carga') THEN
        FOR v_item IN 
            SELECT producto_id, cantidad_solicitada 
            FROM public.detalle_distribucion 
            WHERE orden_id = p_orden_id
        LOOP
            UPDATE public.inventario_almacen
            SET stock_comprometido = GREATEST(0, stock_comprometido - v_item.cantidad_solicitada),
                stock_disponible = stock_disponible + v_item.cantidad_solicitada,
                updated_at = NOW()
            WHERE producto_id = v_item.producto_id;
        END LOOP;
    END IF;

    -- Cambiar estado a anulada
    UPDATE public.ordenes_distribucion
    SET estado = 'anulada'
    WHERE id = p_orden_id;

    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'orden_id', p_orden_id,
            'nuevo_estado', 'anulada'
        ),
        'error', NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'SQL_ERROR',
                'message', SQLERRM,
                'details', 'SQLSTATE: ' || SQLSTATE
            )
        );
END;
$$;
