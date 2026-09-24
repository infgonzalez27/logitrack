-- 1. Crear tabla maestra de tipos de contenedores
CREATE TABLE IF NOT EXISTS public.tipos_contenedores (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    codigo TEXT NOT NULL UNIQUE,
    nombre TEXT NOT NULL,
    descripcion TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. Crear tabla de saldo de contenedores por cliente
CREATE TABLE IF NOT EXISTS public.saldo_contenedores_clientes (
    cliente_id UUID REFERENCES public.clientes(id) ON DELETE CASCADE,
    contenedor_id UUID REFERENCES public.tipos_contenedores(id) ON DELETE RESTRICT,
    saldo_pendiente INT NOT NULL DEFAULT 0 CHECK (saldo_pendiente >= 0),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    PRIMARY KEY (cliente_id, contenedor_id)
);

-- 3. Modificar la tabla de productos para relacionarla con contenedores
ALTER TABLE public.productos 
ADD COLUMN IF NOT EXISTS contenedor_id UUID REFERENCES public.tipos_contenedores(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS unidades_por_contenedor NUMERIC(5,0) DEFAULT 1;

-- 4. Crear la tabla de transacciones de movimientos de contenedores en ruta
CREATE TABLE IF NOT EXISTS public.movimientos_contenedores (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    cliente_id UUID REFERENCES public.clientes(id) ON DELETE RESTRICT,
    orden_id UUID REFERENCES public.ordenes_distribucion(id) ON DELETE CASCADE,
    contenedor_id UUID REFERENCES public.tipos_contenedores(id) ON DELETE RESTRICT,
    cantidad_entregada INT NOT NULL DEFAULT 0 CHECK (cantidad_entregada >= 0),
    cantidad_retirada INT NOT NULL DEFAULT 0 CHECK (cantidad_retirada >= 0),
    creado_por UUID REFERENCES auth.users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 5. Actualizar la restricciÃ³n CHECK de estado en la tabla ordenes_distribucion
-- Primero eliminamos la restricciÃ³n existente para evitar que bloquee la actualizaciÃ³n de estados
ALTER TABLE public.ordenes_distribucion DROP CONSTRAINT IF EXISTS ordenes_distribucion_estado_check;

-- Migramos datos existentes de 'lista_para_carga' a 'aprobada'
UPDATE public.ordenes_distribucion SET estado = 'aprobada' WHERE estado = 'lista_para_carga';

-- Creamos la nueva restricciÃ³n con los nuevos estados permitidos
ALTER TABLE public.ordenes_distribucion 
ADD CONSTRAINT ordenes_distribucion_estado_check 
CHECK (estado IN ('borrador', 'aprobada', 'en_transito', 'por_liquidar', 'liquidada', 'anulada'));

-- 6. Insertar algunos tipos de contenedores por defecto para iniciar
INSERT INTO public.tipos_contenedores (codigo, nombre, descripcion)
VALUES 
  ('huacal_plastico', 'Huacal PlÃ¡stico', 'Cesta plÃ¡stica estÃ¡ndar para botellas o productos varios'),
  ('caja_carton_retornable', 'Caja de CartÃ³n Retornable', 'Caja de cartÃ³n reforzado para transporte y retorno'),
  ('pallet_madera', 'Pallet de Madera', 'Plataforma de madera para transporte de carga pesada')
ON CONFLICT (codigo) DO NOTHING;
CREATE OR REPLACE FUNCTION public.aprobar_orden_distribucion(
    p_orden_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_estado_actual TEXT;
    v_item RECORD;
    v_producto_nombre TEXT;
    v_stock_disponible INT;
BEGIN
    -- 1. Validaciones bÃ¡sicas
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

    -- Obtener estado actual de la orden
    SELECT estado INTO v_estado_actual
    FROM public.ordenes_distribucion
    WHERE id = p_orden_id;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ORDEN_INEXISTENTE',
                'message', 'La orden de distribuciÃ³n especificada no existe.',
                'details', 'ID: ' || p_orden_id
            )
        );
    END IF;

    -- Validar que estÃ© en estado 'borrador'
    IF v_estado_actual != 'borrador' THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo las Ã³rdenes en estado borrador pueden ser aprobadas.',
                'details', 'Estado actual: ' || v_estado_actual
            )
        );
    END IF;

    -- 2. Validar stock disponible para todos los detalles en almacÃ©n
    FOR v_item IN 
        SELECT d.producto_id, d.cantidad_solicitada, p.nombre
        FROM public.detalle_distribucion d
        JOIN public.productos p ON p.id = d.producto_id
        WHERE d.orden_id = p_orden_id
    LOOP
        -- Buscar stock disponible en el almacÃ©n principal
        SELECT stock_disponible 
        INTO v_stock_disponible
        FROM public.inventario_almacen
        WHERE producto_id = v_item.producto_id
        FOR UPDATE; -- Bloquear fila para evitar condiciones de carrera

        IF NOT FOUND THEN
            RETURN json_build_object(
                'success', false,
                'data', NULL,
                'error', json_build_object(
                    'code', 'SIN_REGISTRO_INVENTARIO',
                    'message', 'El producto ' || v_item.nombre || ' no tiene registro de inventario en almacÃ©n.',
                    'details', 'Producto ID: ' || v_item.producto_id
                )
            );
        END IF;

        -- Verificar si el stock es suficiente
        IF v_stock_disponible < v_item.cantidad_solicitada THEN
            RETURN json_build_object(
                'success', false,
                'data', NULL,
                'error', json_build_object(
                    'code', 'STOCK_INSUFICIENTE',
                    'message', 'Stock insuficiente en almacÃ©n para el producto: ' || v_item.nombre,
                    'details', 'Disponible: ' || v_stock_disponible || ', Solicitado: ' || v_item.cantidad_solicitada
                )
            );
        END IF;
    END LOOP;

    -- 3. Comprometer stock y cambiar estado (TransacciÃ³n AtÃ³mica)
    FOR v_item IN 
        SELECT producto_id, cantidad_solicitada
        FROM public.detalle_distribucion
        WHERE orden_id = p_orden_id
    LOOP
        -- Descontar de stock_disponible y sumar a stock_comprometido
        UPDATE public.inventario_almacen
        SET stock_disponible = stock_disponible - v_item.cantidad_solicitada,
            stock_comprometido = stock_comprometido + v_item.cantidad_solicitada,
            updated_at = NOW()
        WHERE producto_id = v_item.producto_id;
    END LOOP;

    -- Cambiar estado de la orden a 'aprobada'
    UPDATE public.ordenes_distribucion
    SET estado = 'aprobada'
    WHERE id = p_orden_id;

    -- 4. Retorno exitoso
    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'orden_id', p_orden_id,
            'nuevo_estado', 'aprobada'
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
CREATE OR REPLACE FUNCTION public.cargar_inventario_movil(
    p_orden_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_estado_actual TEXT;
    v_camion_id UUID;
    v_item RECORD;
BEGIN
    -- 1. Validaciones bÃ¡sicas
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

    -- Obtener datos de la orden
    SELECT estado, camion_id
    INTO v_estado_actual, v_camion_id
    FROM public.ordenes_distribucion
    WHERE id = p_orden_id;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ORDEN_INEXISTENTE',
                'message', 'La orden de distribuciÃ³n especificada no existe.',
                'details', 'ID: ' || p_orden_id
            )
        );
    END IF;

    -- Validar estado 'aprobada'
    IF v_estado_actual != 'aprobada' THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'La orden debe estar en estado aprobada para poder ser despachada.',
                'details', 'Estado actual: ' || v_estado_actual
            )
        );
    END IF;

    -- Validar que el camiÃ³n estÃ© asignado
    IF v_camion_id IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'CAMION_NO_ASIGNADO',
                'message', 'No se puede despachar la orden porque no tiene un camiÃ³n asignado.',
                'details', NULL
            )
        );
    END IF;

    -- 2. Procesamiento e IntegraciÃ³n de Inventario (Operaciones AtÃ³micas)
    FOR v_item IN 
        SELECT producto_id, cantidad_solicitada
        FROM public.detalle_distribucion
        WHERE orden_id = p_orden_id
    LOOP
        -- Descontar del comprometido del almacÃ©n principal (sale fÃ­sicamente del centro de distribuciÃ³n)
        UPDATE public.inventario_almacen
        SET stock_comprometido = stock_comprometido - v_item.cantidad_solicitada,
            updated_at = NOW()
        WHERE producto_id = v_item.producto_id;

        -- Upsert en el inventario mÃ³vil del camiÃ³n (suma a la cantidad cargada)
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

        -- Inicializar cantidad_despachada como cargada
        UPDATE public.detalle_distribucion
        SET cantidad_despachada = v_item.cantidad_solicitada
        WHERE orden_id = p_orden_id AND producto_id = v_item.producto_id;
    END LOOP;

    -- 3. Actualizar estados de recursos de transporte
    -- Cambiar camiÃ³n a estado 'en_ruta'
    UPDATE public.camiones
    SET estado = 'en_ruta'
    WHERE id = v_camion_id;

    -- Cambiar orden a estado 'en_transito'
    UPDATE public.ordenes_distribucion
    SET estado = 'en_transito',
        fecha_despacho = NOW()
    WHERE id = p_orden_id;

    -- 4. Respuesta Exitosa
    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'orden_id', p_orden_id,
            'nuevo_estado', 'en_transito'
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
CREATE OR REPLACE FUNCTION public.registrar_entrega_detalle(
    p_detalle_id UUID,
    p_cantidad_despachada INT,
    p_estado_entrega TEXT,
    p_motivo_rechazo TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_orden_id UUID;
    v_producto_id UUID;
    v_cantidad_solicitada INT;
    v_estado_orden TEXT;
    v_camion_id UUID;
    v_devolucion INT;
    v_pendientes_count INT;
    v_nuevo_estado_orden TEXT;
BEGIN
    -- 1. Validaciones bÃ¡sicas
    IF p_detalle_id IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID del detalle de distribuciÃ³n es requerido.',
                'details', NULL
            )
        );
    END IF;

    IF p_estado_entrega NOT IN ('entregado', 'entregado_parcial', 'rechazado') THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El estado de entrega debe ser entregado, entregado_parcial o rechazado.',
                'details', 'Estado recibido: ' || COALESCE(p_estado_entrega, 'NULL')
            )
        );
    END IF;

    IF p_cantidad_despachada IS NULL OR p_cantidad_despachada < 0 THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'La cantidad despachada/entregada debe ser mayor o igual a 0.',
                'details', NULL
            )
        );
    END IF;

    -- Obtener informaciÃ³n del detalle
    SELECT orden_id, producto_id, cantidad_solicitada
    INTO v_orden_id, v_producto_id, v_cantidad_solicitada
    FROM public.detalle_distribucion
    WHERE id = p_detalle_id;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'DETALLE_INEXISTENTE',
                'message', 'El registro de detalle de distribuciÃ³n no existe.',
                'details', 'ID: ' || p_detalle_id
            )
        );
    END IF;

    -- Obtener informaciÃ³n de la orden
    SELECT estado, camion_id
    INTO v_estado_orden, v_camion_id
    FROM public.ordenes_distribucion
    WHERE id = v_orden_id;

    -- Validar que la orden estÃ© en trÃ¡nsito
    IF v_estado_orden != 'en_transito' THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo se pueden registrar entregas para Ã³rdenes en estado en_transito.',
                'details', 'Estado actual de la orden: ' || v_estado_orden
            )
        );
    END IF;

    -- Validar que la cantidad despachada no sea mayor a la solicitada/cargada
    IF p_cantidad_despachada > v_cantidad_solicitada THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'CANTIDAD_EXCEDIDA',
                'message', 'La cantidad entregada no puede ser mayor que la cantidad solicitada.',
                'details', 'Solicitado: ' || v_cantidad_solicitada || ', Entregado: ' || p_cantidad_despachada
            )
        );
    END IF;

    -- Si el estado es 'rechazado', la cantidad entregada debe ser 0
    IF p_estado_entrega = 'rechazado' AND p_cantidad_despachada != 0 THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'RECHAZO_CON_CANTIDAD',
                'message', 'Si el estado es rechazado, la cantidad despachada debe ser 0.',
                'details', NULL
            )
        );
    END IF;

    -- Si el estado es 'entregado', la cantidad entregada debe ser igual a la solicitada
    IF p_estado_entrega = 'entregado' AND p_cantidad_despachada != v_cantidad_solicitada THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ENTREGA_INCOMPLETA',
                'message', 'Si el estado es entregado, la cantidad despachada debe ser igual a la solicitada. De lo contrario, use entregado_parcial.',
                'details', 'Solicitado: ' || v_cantidad_solicitada || ', Entregado: ' || p_cantidad_despachada
            )
        );
    END IF;

    -- 2. Procesamiento de Inventario MÃ³vil
    -- Calcular la devoluciÃ³n
    v_devolucion := v_cantidad_solicitada - p_cantidad_despachada;

    -- Actualizar inventario mÃ³vil (resta de cantidad_cargada, suma a cantidad_entregada y cantidad_devolucion)
    UPDATE public.inventario_movil
    SET cantidad_cargada = cantidad_cargada - v_cantidad_solicitada,
        cantidad_entregada = cantidad_entregada + p_cantidad_despachada,
        cantidad_devolucion = cantidad_devolucion + v_devolucion,
        updated_at = NOW()
    WHERE camion_id = v_camion_id AND producto_id = v_producto_id;

    -- 3. Actualizar la lÃ­nea de detalle
    UPDATE public.detalle_distribucion
    SET cantidad_despachada = p_cantidad_despachada,
        estado_entrega = p_estado_entrega,
        motivo_rechazo = p_motivo_rechazo
    WHERE id = p_detalle_id;

    -- 4. Verificar si todas las lÃ­neas estÃ¡n entregadas para transicionar la orden a 'por_liquidar'
    SELECT COUNT(*) INTO v_pendientes_count
    FROM public.detalle_distribucion
    WHERE orden_id = v_orden_id AND estado_entrega = 'pendiente';

    v_nuevo_estado_orden := v_estado_orden;

    IF v_pendientes_count = 0 THEN
        UPDATE public.ordenes_distribucion
        SET estado = 'por_liquidar'
        WHERE id = v_orden_id;
        v_nuevo_estado_orden := 'por_liquidar';
    END IF;

    -- 5. Respuesta Exitosa
    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'detalle_id', p_detalle_id,
            'estado_entrega', p_estado_entrega,
            'orden_estado', v_nuevo_estado_orden
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
CREATE OR REPLACE FUNCTION public.registrar_movimiento_contenedores(
    p_cliente_id UUID,
    p_orden_id UUID,
    p_contenedor_id UUID,
    p_cantidad_entregada INT,
    p_cantidad_retirada INT,
    p_creado_por UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_estado_orden TEXT;
    v_movimiento_id UUID;
BEGIN
    -- 1. Validaciones bÃ¡sicas
    IF p_cliente_id IS NULL OR p_orden_id IS NULL OR p_contenedor_id IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'Los IDs de cliente, orden y contenedor son requeridos.',
                'details', NULL
            )
        );
    END IF;

    IF p_cantidad_entregada IS NULL OR p_cantidad_entregada < 0 OR
       p_cantidad_retirada IS NULL OR p_cantidad_retirada < 0 THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'Las cantidades entregadas y retiradas deben ser mayores o iguales a 0.',
                'details', NULL
            )
        );
    END IF;

    -- Validar si el cliente existe
    IF NOT EXISTS (SELECT 1 FROM public.clientes WHERE id = p_cliente_id) THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'CLIENTE_INEXISTENTE',
                'message', 'El cliente especificado no existe.',
                'details', 'ID: ' || p_cliente_id
            )
        );
    END IF;

    -- Validar si la orden existe y obtener su estado
    SELECT estado INTO v_estado_orden
    FROM public.ordenes_distribucion
    WHERE id = p_orden_id;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ORDEN_INEXISTENTE',
                'message', 'La orden de distribuciÃ³n especificada no existe.',
                'details', 'ID: ' || p_orden_id
            )
        );
    END IF;

    -- Validar que la orden estÃ© en ruta o entregada en espera de conciliaciÃ³n
    IF v_estado_orden NOT IN ('en_transito', 'por_liquidar') THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo se pueden registrar movimientos de envases para Ã³rdenes en trÃ¡nsito o por liquidar.',
                'details', 'Estado actual de la orden: ' || v_estado_orden
            )
        );
    END IF;

    -- Validar si el contenedor existe
    IF NOT EXISTS (SELECT 1 FROM public.tipos_contenedores WHERE id = p_contenedor_id) THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'CONTENEDOR_INEXISTENTE',
                'message', 'El tipo de contenedor especificado no existe.',
                'details', 'ID: ' || p_contenedor_id
            )
        );
    END IF;

    -- 2. Registrar movimiento
    INSERT INTO public.movimientos_contenedores (
        cliente_id,
        orden_id,
        contenedor_id,
        cantidad_entregada,
        cantidad_retirada,
        creado_por,
        created_at
    ) VALUES (
        p_cliente_id,
        p_orden_id,
        p_contenedor_id,
        p_cantidad_entregada,
        p_cantidad_retirada,
        p_creado_por,
        NOW()
    ) RETURNING id INTO v_movimiento_id;

    -- 3. Respuesta Exitosa
    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'movimiento_id', v_movimiento_id
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
CREATE OR REPLACE FUNCTION public.liquidar_orden_distribucion(
    p_orden_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_estado_actual TEXT;
    v_camion_id UUID;
    v_chofer_id UUID;
    v_cliente_id UUID;
    v_rendicion_id UUID;
    v_rendicion_estado TEXT;
    v_item RECORD;
    v_mov RECORD;
    v_devolucion INT;
BEGIN
    -- 1. Validaciones bÃ¡sicas
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

    -- Obtener datos de la orden
    SELECT estado, camion_id, chofer_id, cliente_id
    INTO v_estado_actual, v_camion_id, v_chofer_id, v_cliente_id
    FROM public.ordenes_distribucion
    WHERE id = p_orden_id;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ORDEN_INEXISTENTE',
                'message', 'La orden de distribuciÃ³n especificada no existe.',
                'details', 'ID: ' || p_orden_id
            )
        );
    END IF;

    -- Validar que la orden estÃ© en estado 'por_liquidar'
    IF v_estado_actual != 'por_liquidar' THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'La orden debe estar en estado por_liquidar para poder ser liquidada.',
                'details', 'Estado actual: ' || v_estado_actual
            )
        );
    END IF;

    -- 2. Validar rendiciÃ³n de cuentas (MÃ³dulo 4)
    -- Buscar si hay un detalle de rendiciÃ³n asociado a esta orden
    SELECT rendicion_id INTO v_rendicion_id
    FROM public.detalle_rendicion_ordenes
    WHERE orden_distribucion_id = p_orden_id;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'COBRANZA_PENDIENTE',
                'message', 'No se puede liquidar la orden porque no tiene ninguna rendiciÃ³n de cuentas registrada.',
                'details', NULL
            )
        );
    END IF;

    -- Obtener estado de la rendiciÃ³n
    SELECT estado INTO v_rendicion_estado
    FROM public.rendiciones_cuentas
    WHERE id = v_rendicion_id;

    -- Validar que la rendiciÃ³n estÃ© aprobada
    IF v_rendicion_estado != 'aprobada' THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'COBRANZA_PENDIENTE',
                'message', 'No se puede liquidar la orden porque la rendiciÃ³n de cuentas asociada no ha sido aprobada por el gerente.',
                'details', 'RendiciÃ³n ID: ' || v_rendicion_id || ' - Estado: ' || v_rendicion_estado
            )
        );
    END IF;

    -- 3. ConciliaciÃ³n FÃ­sica de Inventario (Devoluciones al almacÃ©n principal)
    FOR v_item IN 
        SELECT producto_id, cantidad_solicitada, cantidad_despachada
        FROM public.detalle_distribucion
        WHERE orden_id = p_orden_id
    LOOP
        -- La cantidad despachada en detalle_distribucion es la que realmente recibiÃ³ el cliente (se actualiza en registrar_entrega_detalle)
        -- Por lo tanto, las devoluciones son: cantidad_solicitada (cargada) - cantidad_despachada (recibida)
        v_devolucion := v_item.cantidad_solicitada - v_item.cantidad_despachada;

        IF v_devolucion > 0 THEN
            -- Regresar la mercancÃ­a al stock disponible del almacÃ©n principal
            UPDATE public.inventario_almacen
            SET stock_disponible = stock_disponible + v_devolucion,
                updated_at = NOW()
            WHERE producto_id = v_item.producto_id;

            -- Descontar del inventario mÃ³vil del camiÃ³n (las devoluciones ya no estÃ¡n en el camiÃ³n)
            UPDATE public.inventario_movil
            SET cantidad_devolucion = cantidad_devolucion - v_devolucion,
                updated_at = NOW()
            WHERE camion_id = v_camion_id AND producto_id = v_item.producto_id;
        END IF;
    END LOOP;

    -- 4. ConsolidaciÃ³n del Saldo de Contenedores del Cliente
    FOR v_mov IN 
        SELECT contenedor_id, cantidad_entregada, cantidad_retirada
        FROM public.movimientos_contenedores
        WHERE orden_id = p_orden_id
    LOOP
        -- Insertar o actualizar el saldo del cliente para este tipo de contenedor
        INSERT INTO public.saldo_contenedores_clientes (
            cliente_id,
            contenedor_id,
            saldo_pendiente,
            updated_at
        ) VALUES (
            v_cliente_id,
            v_mov.contenedor_id,
            GREATEST(0, v_mov.cantidad_entregada - v_mov.cantidad_retirada),
            NOW()
        )
        ON CONFLICT (cliente_id, contenedor_id)
        DO UPDATE SET
            saldo_pendiente = GREATEST(0, saldo_contenedores_clientes.saldo_pendiente + (v_mov.cantidad_entregada - v_mov.cantidad_retirada)),
            updated_at = NOW();
    END LOOP;

    -- 5. Liberar recursos de transporte (CamiÃ³n y Chofer a disponible)
    UPDATE public.camiones
    SET estado = 'disponible'
    WHERE id = v_camion_id;

    UPDATE public.choferes
    SET estado = 'disponible'
    WHERE perfil_id = v_chofer_id;

    -- Cambiar estado de la orden a 'liquidada'
    UPDATE public.ordenes_distribucion
    SET estado = 'liquidada'
    WHERE id = p_orden_id;

    -- 6. Respuesta Exitosa
    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'orden_id', p_orden_id,
            'nuevo_estado', 'liquidada'
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
CREATE OR REPLACE FUNCTION public.anular_orden_distribucion(
    p_orden_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_estado_actual TEXT;
    v_item RECORD;
BEGIN
    -- 1. Validaciones bÃ¡sicas
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

    -- Obtener datos de la orden
    SELECT estado
    INTO v_estado_actual
    FROM public.ordenes_distribucion
    WHERE id = p_orden_id;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ORDEN_INEXISTENTE',
                'message', 'La orden de distribuciÃ³n especificada no existe.',
                'details', 'ID: ' || p_orden_id
            )
        );
    END IF;

    -- Validar estado para anulaciÃ³n
    IF v_estado_actual = 'anulada' THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'La orden de distribuciÃ³n ya se encuentra anulada.',
                'details', NULL
            )
        );
    END IF;

    IF v_estado_actual = 'liquidada' THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'No se puede anular una orden que ya ha sido liquidada.',
                'details', NULL
            )
        );
    END IF;

    IF v_estado_actual IN ('en_transito', 'por_liquidar') THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'No se puede anular una orden que ya ha sido despachada y se encuentra en trÃ¡nsito o por liquidar.',
                'details', 'Estado actual: ' || v_estado_actual
            )
        );
    END IF;

    -- 2. Procesamiento de AnulaciÃ³n
    -- Si la orden estÃ¡ aprobada, debemos liberar el stock comprometido en almacÃ©n
    IF v_estado_actual = 'aprobada' THEN
        FOR v_item IN 
            SELECT producto_id, cantidad_solicitada
            FROM public.detalle_distribucion
            WHERE orden_id = p_orden_id
        LOOP
            -- Sumar de vuelta a stock_disponible, restar de stock_comprometido
            UPDATE public.inventario_almacen
            SET stock_disponible = stock_disponible + v_item.cantidad_solicitada,
                stock_comprometido = stock_comprometido - v_item.cantidad_solicitada,
                updated_at = NOW()
            WHERE producto_id = v_item.producto_id;
        END LOOP;
    END IF;

    -- Cambiar estado de la orden a 'anulada'
    UPDATE public.ordenes_distribucion
    SET estado = 'anulada'
    WHERE id = p_orden_id;

    -- 3. Respuesta Exitosa
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
-- 1. Crear funciÃ³n trigger para auditorÃ­a global de cambios
CREATE OR REPLACE FUNCTION public.audit_changes_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_usuario_id UUID;
    v_registro_id UUID;
    v_valores_anteriores JSONB := NULL;
    v_valores_nuevos JSONB := NULL;
BEGIN
    -- Obtener el ID del usuario autenticado actual desde auth.uid() de Supabase
    BEGIN
        v_usuario_id := auth.uid();
    EXCEPTION WHEN OTHERS THEN
        v_usuario_id := NULL;
    END;

    -- Determinar el ID del registro afectado (id o perfil_id)
    IF TG_OP = 'DELETE' THEN
        IF to_jsonb(OLD) ? 'id' THEN
            v_registro_id := (OLD.id)::UUID;
        ELSIF to_jsonb(OLD) ? 'perfil_id' THEN
            v_registro_id := (OLD.perfil_id)::UUID;
        ELSE
            v_registro_id := gen_random_uuid();
        END IF;
        v_valores_anteriores := to_jsonb(OLD);
    ELSE
        IF to_jsonb(NEW) ? 'id' THEN
            v_registro_id := (NEW.id)::UUID;
        ELSIF to_jsonb(NEW) ? 'perfil_id' THEN
            v_registro_id := (NEW.perfil_id)::UUID;
        ELSE
            v_registro_id := gen_random_uuid();
        END IF;
        
        IF TG_OP = 'UPDATE' THEN
            v_valores_anteriores := to_jsonb(OLD);
            v_valores_nuevos := to_jsonb(NEW);
        ELSIF TG_OP = 'INSERT' THEN
            v_valores_nuevos := to_jsonb(NEW);
        END IF;
    END IF;

    -- Insertar en la tabla de logs de auditorÃ­a
    INSERT INTO public.logs_auditoria (
        usuario_id,
        tabla_afectada,
        accion,
        registro_id,
        valores_anteriores,
        valores_nuevos,
        fecha_registro
    ) VALUES (
        v_usuario_id,
        TG_TABLE_NAME::TEXT,
        TG_OP,
        v_registro_id,
        v_valores_anteriores,
        v_valores_nuevos,
        NOW()
    );

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$;

-- 2. Vincular trigger de auditorÃ­a a tablas crÃ­ticas (eliminar si ya existen)
DROP TRIGGER IF EXISTS audit_ordenes_distribucion ON public.ordenes_distribucion;
CREATE TRIGGER audit_ordenes_distribucion
AFTER INSERT OR UPDATE OR DELETE ON public.ordenes_distribucion
FOR EACH ROW EXECUTE FUNCTION public.audit_changes_trigger();

DROP TRIGGER IF EXISTS audit_detalle_distribucion ON public.detalle_distribucion;
CREATE TRIGGER audit_detalle_distribucion
AFTER INSERT OR UPDATE OR DELETE ON public.detalle_distribucion
FOR EACH ROW EXECUTE FUNCTION public.audit_changes_trigger();

DROP TRIGGER IF EXISTS audit_inventario_almacen ON public.inventario_almacen;
CREATE TRIGGER audit_inventario_almacen
AFTER INSERT OR UPDATE OR DELETE ON public.inventario_almacen
FOR EACH ROW EXECUTE FUNCTION public.audit_changes_trigger();

DROP TRIGGER IF EXISTS audit_inventario_movil ON public.inventario_movil;
CREATE TRIGGER audit_inventario_movil
AFTER INSERT OR UPDATE OR DELETE ON public.inventario_movil
FOR EACH ROW EXECUTE FUNCTION public.audit_changes_trigger();

DROP TRIGGER IF EXISTS audit_movimientos_contenedores ON public.movimientos_contenedores;
CREATE TRIGGER audit_movimientos_contenedores
AFTER INSERT OR UPDATE OR DELETE ON public.movimientos_contenedores
FOR EACH ROW EXECUTE FUNCTION public.audit_changes_trigger();


-- 3. Crear funciÃ³n helper para validar rol del usuario autenticado actual
CREATE OR REPLACE FUNCTION public.user_has_role(
    p_role_names TEXT[]
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID;
    v_has_role BOOLEAN;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RETURN FALSE;
    END IF;

    SELECT EXISTS (
        SELECT 1 
        FROM public.perfiles_usuario p
        JOIN public.roles r ON r.id = p.rol_id
        WHERE p.id = v_user_id AND r.nombre = ANY(p_role_names)
    ) INTO v_has_role;

    RETURN v_has_role;
END;
$$;


-- 4. Habilitar RLS y Configurar polÃ­ticas en la tabla ordenes_distribucion
ALTER TABLE public.ordenes_distribucion ENABLE ROW LEVEL SECURITY;

-- Eliminar polÃ­ticas previas para evitar conflictos
DROP POLICY IF EXISTS select_ordenes_distribucion ON public.ordenes_distribucion;
DROP POLICY IF EXISTS modify_ordenes_distribucion ON public.ordenes_distribucion;

-- Crear polÃ­tica de lectura restrictiva por rol
CREATE POLICY select_ordenes_distribucion ON public.ordenes_distribucion
FOR SELECT
USING (
    -- Si es administrador, gerente o despachador, puede ver todas las Ã³rdenes
    public.user_has_role(ARRAY['admin', 'gerente', 'despachador'])
    -- Si es chofer, solo puede ver las asignadas a Ã©l
    OR (public.user_has_role(ARRAY['chofer_cobrador']) AND chofer_id = auth.uid())
);

-- Crear polÃ­tica de modificaciÃ³n para personal administrativo
CREATE POLICY modify_ordenes_distribucion ON public.ordenes_distribucion
FOR ALL
USING (
    public.user_has_role(ARRAY['admin', 'gerente', 'despachador'])
);
-- 1. Agregar columna saldo_favor a la tabla clientes
ALTER TABLE public.clientes ADD COLUMN IF NOT EXISTS saldo_favor NUMERIC(12, 2) DEFAULT 0.00 CHECK (saldo_favor >= 0.00);

-- 2. Crear tabla de auditorÃ­a para movimientos del saldo a favor de clientes
CREATE TABLE IF NOT EXISTS public.movimientos_saldo_favor (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    cliente_id UUID REFERENCES public.clientes(id) ON DELETE CASCADE,
    rendicion_id UUID REFERENCES public.rendiciones_cuentas(id) ON DELETE SET NULL,
    orden_id UUID REFERENCES public.ordenes_distribucion(id) ON DELETE SET NULL,
    monto NUMERIC(12, 2) NOT NULL, -- Positivo para abonos, negativo para cargos/descuentos
    tipo TEXT NOT NULL CHECK (tipo IN ('abono_recaudacion', 'cargo_pago_orden', 'devolucion_efectivo')),
    observaciones TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 3. Crear Stored Procedure registrar_rendicion_cuentas
CREATE OR REPLACE FUNCTION public.registrar_rendicion_cuentas(
    p_cliente_id UUID,
    p_observaciones TEXT,
    p_creado_por UUID,
    p_ordenes JSONB,
    p_pagos JSONB
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_rendicion_id UUID;
    v_total_ordenes NUMERIC(12, 2) := 0.00;
    v_total_pagos NUMERIC(12, 2) := 0.00;
    v_total_efectivo NUMERIC(12, 2) := 0.00;
    v_total_transferencias NUMERIC(12, 2) := 0.00;
    v_item RECORD;
    v_pago RECORD;
    v_exceso NUMERIC(12, 2) := 0.00;
BEGIN
    -- Validaciones bÃ¡sicas
    IF p_cliente_id IS NULL OR p_creado_por IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID de cliente y el usuario creador son requeridos.',
                'details', NULL
            )
        );
    END IF;

    -- Validar que el cliente exista
    IF NOT EXISTS (SELECT 1 FROM public.clientes WHERE id = p_cliente_id) THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'CLIENTE_INEXISTENTE',
                'message', 'El cliente especificado no existe.',
                'details', NULL
            )
        );
    END IF;

    -- Validar que las listas hijas tengan al menos un elemento
    IF p_ordenes IS NULL OR jsonb_array_length(p_ordenes) = 0 THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'DETALLE_REQUISITO_FALTANTE',
                'message', 'Debe registrar al menos una orden en el detalle de la rendiciÃ³n.',
                'details', NULL
            )
        );
    END IF;

    IF p_pagos IS NULL OR jsonb_array_length(p_pagos) = 0 THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'DETALLE_REQUISITO_FALTANTE',
                'message', 'Debe registrar al menos una forma de pago en la rendiciÃ³n.',
                'details', NULL
            )
        );
    END IF;

    -- Calcular total recaudado de las Ã³rdenes
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_ordenes) AS x(orden_id UUID, monto_recaudado NUMERIC(12,2)) LOOP
        v_total_ordenes := v_total_ordenes + v_item.monto_recaudado;
    END LOOP;

    -- Calcular total y clasificar segÃºn formas de pago
    FOR v_pago IN SELECT * FROM jsonb_to_recordset(p_pagos) AS y(metodo_pago TEXT, monto NUMERIC(12,2), referencia_bancaria TEXT, cuenta_bancaria TEXT, capture_url TEXT) LOOP
        v_total_pagos := v_total_pagos + v_pago.monto;
        IF v_pago.metodo_pago IN ('efectivo_usd', 'efectivo_bs') THEN
            v_total_efectivo := v_total_efectivo + v_pago.monto;
        ELSIF v_pago.metodo_pago IN ('transferencia', 'pago_movil') THEN
            v_total_transferencias := v_total_transferencias + v_pago.monto;
        END IF;
    END LOOP;

    -- Crear cabecera
    INSERT INTO public.rendiciones_cuentas (
        cliente_id,
        fecha_rendicion,
        total_efectivo_recaudado,
        total_transferencias_recaudado,
        total_devoluciones_valoradas,
        estado,
        observaciones,
        auditado_por
    ) VALUES (
        p_cliente_id,
        NOW(),
        v_total_efectivo,
        v_total_transferencias,
        0.00,
        'revision',
        p_observaciones,
        NULL
    ) RETURNING id INTO v_rendicion_id;

    -- Registrar Ã³rdenes
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_ordenes) AS x(orden_id UUID, monto_recaudado NUMERIC(12,2)) LOOP
        INSERT INTO public.detalle_rendicion_ordenes (
            rendicion_id,
            orden_distribucion_id,
            recaudado
        ) VALUES (
            v_rendicion_id,
            v_item.orden_id,
            v_item.monto_recaudado
        );
    END LOOP;

    -- Registrar formas de pago (detalle_rendicion_fpagos)
    FOR v_pago IN SELECT * FROM jsonb_to_recordset(p_pagos) AS y(metodo_pago TEXT, monto NUMERIC(12,2), referencia_bancaria TEXT, cuenta_bancaria TEXT, capture_url TEXT) LOOP
        INSERT INTO public.detalle_rendicion_fpagos (
            rendicion_id,
            metodo_pago,
            monto,
            referencia_bancaria,
            cuenta_bancaria,
            capture_url
        ) VALUES (
            v_rendicion_id,
            v_pago.metodo_pago,
            v_pago.monto,
            v_pago.referencia_bancaria,
            v_pago.cuenta_bancaria,
            v_pago.capture_url
        );
    END LOOP;

    -- Manejo de CrÃ©dito a Favor del Cliente
    IF v_total_pagos > v_total_ordenes THEN
        v_exceso := v_total_pagos - v_total_ordenes;

        -- Registrar abono histÃ³rico
        INSERT INTO public.movimientos_saldo_favor (
            cliente_id,
            rendicion_id,
            orden_id,
            monto,
            tipo,
            observaciones,
            created_at
        ) VALUES (
            p_cliente_id,
            v_rendicion_id,
            NULL,
            v_exceso,
            'abono_recaudacion',
            'Excedente en formas de pago de rendiciÃ³n de cuentas ID: ' || v_rendicion_id,
            NOW()
        );

        -- Actualizar saldo a favor en cliente
        UPDATE public.clientes
        SET saldo_favor = COALESCE(saldo_favor, 0.00) + v_exceso
        WHERE id = p_cliente_id;
    END IF;

    -- Retorno
    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'rendicion_id', v_rendicion_id,
            'total_ordenes', v_total_ordenes,
            'total_pagos', v_total_pagos,
            'saldo_favor_generado', v_exceso
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


-- 4. Crear Trigger automÃ¡tico para liquidar Ã³rdenes al aprobarse la recaudaciÃ³n
CREATE OR REPLACE FUNCTION public.on_rendicion_aprobada_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_item RECORD;
    v_res JSON;
BEGIN
    -- Solo actuar cuando el estado cambia a 'aprobada'
    IF NEW.estado = 'aprobada' AND (OLD.estado IS DISTINCT FROM 'aprobada') THEN
        -- Buscar todas las Ã³rdenes asociadas a esta rendiciÃ³n de cuentas
        FOR v_item IN 
            SELECT orden_distribucion_id 
            FROM public.detalle_rendicion_ordenes 
            WHERE rendicion_id = NEW.id
        LOOP
            -- Ejecutar liquidaciÃ³n de forma automÃ¡tica
            v_res := public.liquidar_orden_distribucion(v_item.orden_distribucion_id);
            
            -- Si falla, revertimos toda la transacciÃ³n
            IF (v_res->>'success')::BOOLEAN = FALSE THEN
                RAISE EXCEPTION 'Fallo al liquidar automÃ¡ticamente la orden %: %', 
                    v_item.orden_distribucion_id, v_res->'error'->>'message';
            END IF;
        END LOOP;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_liquidar_ordenes_on_aprobacion ON public.rendiciones_cuentas;
CREATE TRIGGER trigger_liquidar_ordenes_on_aprobacion
AFTER UPDATE ON public.rendiciones_cuentas
FOR EACH ROW
EXECUTE FUNCTION public.on_rendicion_aprobada_trigger();
-- Migration: MÃ³dulo de Formas de Pago (DB-009, DB-010, DB-011)

-- 1. Crear tabla fpagos si no existe (DB-009)
CREATE TABLE IF NOT EXISTS public.fpagos (
    fpago_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    fpago_concepto TEXT NOT NULL UNIQUE,
    fpago_info BOOLEAN NOT NULL DEFAULT FALSE
);

-- Habilitar RLS en fpagos
ALTER TABLE public.fpagos ENABLE ROW LEVEL SECURITY;

-- PolÃ­tica de lectura pÃºblica/autenticada para fpagos
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'fpagos' AND policyname = 'Permitir lectura autenticada de fpagos'
    ) THEN
        CREATE POLICY "Permitir lectura autenticada de fpagos" ON public.fpagos
            FOR SELECT TO authenticated USING (true);
    END IF;
END $$;

-- Insertar formas de pago base con UUIDs estÃ¡ticos
INSERT INTO public.fpagos (fpago_id, fpago_concepto, fpago_info)
VALUES 
    ('1a5b84c8-47bc-4ee0-880c-7833215be11b', 'Pago movil', true),
    ('2b6c95d9-58cd-4ff1-991d-8944326cf22c', 'Transferencia', true),
    ('3c7da6ea-69de-4002-aa2e-9a55437d033d', 'Efectivo Bs', false),
    ('4d8eb7fb-7ade-4113-bb3f-ab66548e144e', 'Efectivo USD', false),
    ('5e9fc80c-8bef-4224-cc4f-bc77659f255f', 'ZELLE', true),
    ('6fa0d91d-9c00-4335-dd5f-cd88760a366a', 'BINANCE', true)
ON CONFLICT (fpago_concepto) DO UPDATE 
SET fpago_info = EXCLUDED.fpago_info;

-- 2. Modificar tabla detalle_rendicion_fpagos para incluir FK fpago_id (DB-010)
ALTER TABLE public.detalle_rendicion_fpagos 
ADD COLUMN IF NOT EXISTS fpago_id UUID REFERENCES public.fpagos(fpago_id) ON DELETE RESTRICT;

-- Mapear registros existentes si la columna metodo_pago existe
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'detalle_rendicion_fpagos' 
          AND column_name = 'metodo_pago'
    ) THEN
        UPDATE public.detalle_rendicion_fpagos d
        SET fpago_id = f.fpago_id
        FROM public.fpagos f
        WHERE d.fpago_id IS NULL AND (
            (d.metodo_pago IN ('pago_movil', 'Pago movil') AND f.fpago_concepto = 'Pago movil') OR
            (d.metodo_pago IN ('transferencia', 'Transferencia') AND f.fpago_concepto = 'Transferencia') OR
            (d.metodo_pago IN ('efectivo_bs', 'Efectivo Bs') AND f.fpago_concepto = 'Efectivo Bs') OR
            (d.metodo_pago IN ('efectivo_usd', 'Efectivo USD') AND f.fpago_concepto = 'Efectivo USD') OR
            (d.metodo_pago = 'ZELLE' AND f.fpago_concepto = 'ZELLE') OR
            (d.metodo_pago = 'BINANCE' AND f.fpago_concepto = 'BINANCE')
        );

        -- Eliminar la columna antigua metodo_pago
        ALTER TABLE public.detalle_rendicion_fpagos DROP COLUMN metodo_pago;
    END IF;
END $$;

-- 3. Actualizar funciÃ³n registrar_rendicion_cuentas
CREATE OR REPLACE FUNCTION public.registrar_rendicion_cuentas(
    p_cliente_id UUID,
    p_observaciones TEXT,
    p_creado_por UUID,
    p_ordenes JSONB,  -- Array de objetos: [{"orden_id": "...", "monto_recaudado": 150.00}]
    p_pagos JSONB      -- Array de objetos: [{"fpago_id": "...", "monto": 200.00, "referencia_bancaria": "...", "cuenta_bancaria": "...", "capture_url": "..."}]
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_rendicion_id UUID;
    v_total_ordenes NUMERIC(12, 2) := 0.00;
    v_total_pagos NUMERIC(12, 2) := 0.00;
    v_total_efectivo NUMERIC(12, 2) := 0.00;
    v_total_transferencias NUMERIC(12, 2) := 0.00;
    v_item RECORD;
    v_pago RECORD;
    v_exceso NUMERIC(12, 2) := 0.00;
    v_fpago_info BOOLEAN;
BEGIN
    -- 1. Validaciones bÃ¡sicas
    IF p_cliente_id IS NULL OR p_creado_por IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID de cliente y el usuario creador son requeridos.',
                'details', NULL
            )
        );
    END IF;

    -- Validar que el cliente exista
    IF NOT EXISTS (SELECT 1 FROM public.clientes WHERE id = p_cliente_id) THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'CLIENTE_INEXISTENTE',
                'message', 'El cliente especificado no existe.',
                'details', NULL
            )
        );
    END IF;

    -- Validar que las listas hijas tengan al menos un elemento
    IF p_ordenes IS NULL OR jsonb_array_length(p_ordenes) = 0 THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'DETALLE_REQUISITO_FALTANTE',
                'message', 'Debe registrar al menos una orden en el detalle de la rendiciÃ³n.',
                'details', NULL
            )
        );
    END IF;

    IF p_pagos IS NULL OR jsonb_array_length(p_pagos) = 0 THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'DETALLE_REQUISITO_FALTANTE',
                'message', 'Debe registrar al menos una forma de pago en la rendiciÃ³n.',
                'details', NULL
            )
        );
    END IF;

    -- 2. Calcular totales de Ã³rdenes
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_ordenes) AS x(orden_id UUID, monto_recaudado NUMERIC(12,2)) LOOP
        v_total_ordenes := v_total_ordenes + v_item.monto_recaudado;
    END LOOP;

    -- 3. Calcular totales y clasificar segÃºn formas de pago (fpagos.fpago_info)
    FOR v_pago IN SELECT * FROM jsonb_to_recordset(p_pagos) AS y(fpago_id UUID, monto NUMERIC(12,2), referencia_bancaria TEXT, cuenta_bancaria TEXT, capture_url TEXT) LOOP
        v_total_pagos := v_total_pagos + v_pago.monto;
        
        -- Obtener fpago_info para saber si es transferencia/digital (true) o efectivo (false)
        SELECT fpago_info INTO v_fpago_info FROM public.fpagos WHERE fpago_id = v_pago.fpago_id;
        
        IF v_fpago_info IS NULL THEN
            RETURN json_build_object(
                'success', false,
                'data', NULL,
                'error', json_build_object(
                    'code', 'FORMA_PAGO_INEXISTENTE',
                    'message', 'La forma de pago especificada no existe.',
                    'details', 'fpago_id: ' || v_pago.fpago_id
                )
            );
        END IF;

        IF v_fpago_info = FALSE THEN
            v_total_efectivo := v_total_efectivo + v_pago.monto;
        ELSE
            v_total_transferencias := v_total_transferencias + v_pago.monto;
        END IF;
    END LOOP;

    -- 4. Crear el registro principal (Cabecera) en rendiciones_cuentas
    INSERT INTO public.rendiciones_cuentas (
        cliente_id,
        fecha_rendicion,
        total_efectivo_recaudado,
        total_transferencias_recaudado,
        total_devoluciones_valoradas,
        estado,
        observaciones,
        auditado_por
    ) VALUES (
        p_cliente_id,
        NOW(),
        v_total_efectivo,
        v_total_transferencias,
        0.00,
        'revision',
        p_observaciones,
        NULL
    ) RETURNING id INTO v_rendicion_id;

    -- 5. Registrar detalle de Ã³rdenes asociadas
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_ordenes) AS x(orden_id UUID, monto_recaudado NUMERIC(12,2)) LOOP
        INSERT INTO public.detalle_rendicion_ordenes (
            rendicion_id,
            orden_distribucion_id,
            recaudado
        ) VALUES (
            v_rendicion_id,
            v_item.orden_id,
            v_item.monto_recaudado
        );
    END LOOP;

    -- 6. Registrar formas de pago (detalle_rendicion_fpagos)
    FOR v_pago IN SELECT * FROM jsonb_to_recordset(p_pagos) AS y(fpago_id UUID, monto NUMERIC(12,2), referencia_bancaria TEXT, cuenta_bancaria TEXT, capture_url TEXT) LOOP
        INSERT INTO public.detalle_rendicion_fpagos (
            rendicion_id,
            fpago_id,
            monto,
            referencia_bancaria,
            cuenta_bancaria,
            capture_url
        ) VALUES (
            v_rendicion_id,
            v_pago.fpago_id,
            v_pago.monto,
            v_pago.referencia_bancaria,
            v_pago.cuenta_bancaria,
            v_pago.capture_url
        );
    END LOOP;

    -- 7. Manejo de CrÃ©dito a Favor del Cliente
    IF v_total_pagos > v_total_ordenes THEN
        v_exceso := v_total_pagos - v_total_ordenes;

        INSERT INTO public.movimientos_saldo_favor (
            cliente_id,
            rendicion_id,
            orden_id,
            monto,
            tipo,
            observaciones,
            created_at
        ) VALUES (
            p_cliente_id,
            v_rendicion_id,
            NULL,
            v_exceso,
            'abono_recaudacion',
            'Excedente en formas de pago de rendiciÃ³n de cuentas ID: ' || v_rendicion_id,
            NOW()
        );

        UPDATE public.clientes
        SET saldo_favor = COALESCE(saldo_favor, 0.00) + v_exceso
        WHERE id = p_cliente_id;
    END IF;

    -- 8. Retorno Exitoso
    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'rendicion_id', v_rendicion_id,
            'total_ordenes', v_total_ordenes,
            'total_pagos', v_total_pagos,
            'saldo_favor_generado', v_exceso
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

-- 4. Crear la funciÃ³n consulta_registros_formas_pago (DB-011)
CREATE OR REPLACE FUNCTION public.consulta_registros_formas_pago()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_data JSON;
BEGIN
    SELECT json_agg(
        json_build_object(
            'fpago_id', fpago_id,
            'fpago_concepto', fpago_concepto,
            'fpago_info', fpago_info
        ) ORDER BY fpago_concepto
    ) INTO v_data
    FROM public.fpagos;

    RETURN json_build_object(
        'success', true,
        'data', COALESCE(v_data, '[]'::json),
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
-- Migration: Regla de Permisos de ModificaciÃ³n de Ã“rdenes (DB-012)
-- Un vendedor solo puede modificar sus propias Ã³rdenes (creado_por = auth.uid()).
-- Un gerente o admin puede modificar cualquier orden.

-- 1. Actualizar polÃ­ticas RLS en ordenes_distribucion
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

-- 2. Actualizar funciÃ³n actualizar_estado_orden_distribucion con chequeo de autorÃ­a para vendedores
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
    -- Validar parÃ¡metros
    IF p_orden_id IS NULL THEN
        RAISE EXCEPTION 'El ID de la orden es requerido.';
    END IF;

    IF p_estado IS NULL THEN
        RAISE EXCEPTION 'El estado de destino es requerido.';
    END IF;

    -- Validar que el estado de destino sea vÃ¡lido
    IF p_estado NOT IN ('borrador', 'lista_para_carga', 'en_transito', 'liquidada', 'anulada') THEN
        RAISE EXCEPTION 'El estado % no es un estado vÃ¡lido para la orden.', p_estado;
    END IF;

    -- Obtener datos de la orden
    SELECT estado, camion_id, chofer_id, creado_por
    INTO v_estado_actual, v_camion_id, v_chofer_id, v_creado_por
    FROM public.ordenes_distribucion
    WHERE id = p_orden_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La orden de distribuciÃ³n con ID % no existe.', p_orden_id;
    END IF;

    -- VALIDACIÃ“N DE PERMISOS POR ROL Y AUTORÃA (DB-012)
    -- Si es vendedor y no es gerente/admin/despachador, validar que haya creado la orden
    IF public.user_has_role(ARRAY['vendedor']) AND NOT public.user_has_role(ARRAY['admin', 'gerente', 'despachador']) THEN
        IF v_user_id IS NOT NULL AND v_creado_por IS DISTINCT FROM v_user_id THEN
            RAISE EXCEPTION 'ACCESO_DENEGADO: Un vendedor solo puede modificar las Ã³rdenes que ha registrado.';
        END IF;
    END IF;

    -- Si ya estÃ¡ en el estado solicitado, no hacer nada
    IF v_estado_actual = p_estado THEN
        RETURN;
    END IF;

    -- Validar transiciones de estado permitidas
    IF v_estado_actual = 'borrador' AND p_estado NOT IN ('lista_para_carga', 'anulada') THEN
        RAISE EXCEPTION 'TransiciÃ³n no permitida: de % a %.', v_estado_actual, p_estado;
    ELSIF v_estado_actual = 'lista_para_carga' AND p_estado NOT IN ('en_transito', 'borrador', 'anulada') THEN
        RAISE EXCEPTION 'TransiciÃ³n no permitida: de % a %.', v_estado_actual, p_estado;
    ELSIF v_estado_actual = 'en_transito' AND p_estado NOT IN ('liquidada', 'anulada') THEN
        RAISE EXCEPTION 'TransiciÃ³n no permitida: de % a %.', v_estado_actual, p_estado;
    ELSIF v_estado_actual IN ('liquidada', 'anulada') THEN
        RAISE EXCEPTION 'No se pueden realizar cambios de estado en una orden %.', v_estado_actual;
    END IF;

    ---------------------------------------------------------------------------
    -- LÃ“GICA DE TRANSICIONES
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
                RAISE EXCEPTION 'El producto % no tiene un registro de inventario en almacÃ©n.', COALESCE(v_producto_nombre, v_item.producto_id::text);
            END IF;

            IF v_stock_disponible < v_item.cantidad_solicitada THEN
                SELECT nombre INTO v_producto_nombre FROM public.productos WHERE id = v_item.producto_id;
                RAISE EXCEPTION 'Stock insuficiente en almacÃ©n para el producto % (Disponible: %, Requerido: %).', 
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

    -- 2. De LISTA_PARA_CARGA a BORRADOR (ReversiÃ³n de reserva)
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
            RAISE EXCEPTION 'Para pasar a en_transito la orden debe tener asignado un camiÃ³n y un chofer.';
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


-- 3. Actualizar funciÃ³n anular_orden_distribucion con chequeo de autorÃ­a para vendedores
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
    -- Validar parÃ¡metros
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
                'message', 'La orden de distribuciÃ³n especificada no existe.',
                'details', NULL
            )
        );
    END IF;

    -- VALIDACIÃ“N DE PERMISOS POR ROL Y AUTORÃA (DB-012)
    IF public.user_has_role(ARRAY['vendedor']) AND NOT public.user_has_role(ARRAY['admin', 'gerente', 'despachador']) THEN
        IF v_user_id IS NOT NULL AND v_creado_por IS DISTINCT FROM v_user_id THEN
            RETURN json_build_object(
                'success', false,
                'data', NULL,
                'error', json_build_object(
                    'code', 'ACCESO_DENEGADO',
                    'message', 'Un vendedor solo puede anular las Ã³rdenes que ha registrado.',
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

    -- Si estÃ¡ aprobada / lista_para_carga, liberar reservas de inventario
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
-- Migration: Tasa de Cambio, Multimoneda y GestiÃ³n por Vendedor (DB-013 a DB-018)

-- 1. Tabla tasa_cambio (DB-013)
CREATE TABLE IF NOT EXISTS public.tasa_cambio (
    fecha_tasa DATE PRIMARY KEY,
    tasa_cambio NUMERIC(14,4) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Habilitar RLS en tasa_cambio
ALTER TABLE public.tasa_cambio ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'tasa_cambio' AND policyname = 'Permitir lectura de tasa_cambio a usuarios autenticados'
    ) THEN
        CREATE POLICY "Permitir lectura de tasa_cambio a usuarios autenticados"
            ON public.tasa_cambio FOR SELECT TO authenticated USING (true);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'tasa_cambio' AND policyname = 'Permitir administracion de tasa_cambio a usuarios autorizados'
    ) THEN
        CREATE POLICY "Permitir administracion de tasa_cambio a usuarios autorizados"
            ON public.tasa_cambio FOR ALL TO authenticated
            USING (public.user_has_role(ARRAY['admin', 'gerente']));
    END IF;
END $$;

-- 2. RPC inserta_tasa_cambio
CREATE OR REPLACE FUNCTION public.inserta_tasa_cambio(
    p_fecha_tasa DATE,
    p_tasa NUMERIC
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF p_fecha_tasa IS NULL OR p_tasa IS NULL OR p_tasa <= 0 THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'La fecha y el monto de la tasa deben ser vÃ¡lidos y mayores a cero.',
                'details', NULL
            )
        );
    END IF;

    IF EXISTS (SELECT 1 FROM public.tasa_cambio WHERE fecha_tasa = p_fecha_tasa) THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'FECHA_TASA_DUPLICADA',
                'message', 'Ya existe una tasa registrada para la fecha ' || p_fecha_tasa::text || '. Para modificarla, elimÃ­nela primero.',
                'details', NULL
            )
        );
    END IF;

    INSERT INTO public.tasa_cambio (fecha_tasa, tasa_cambio)
    VALUES (p_fecha_tasa, p_tasa);

    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'fecha_tasa', p_fecha_tasa,
            'tasa_cambio', p_tasa
        ),
        'error', NULL
    );
EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object(
        'success', false,
        'data', NULL,
        'error', json_build_object(
            'code', 'SQL_ERROR',
            'message', SQLERRM,
            'details', NULL
        )
    );
END;
$$;

-- 3. RPC elimina_tasa_cambio
CREATE OR REPLACE FUNCTION public.elimina_tasa_cambio(
    p_fecha_tasa DATE
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF p_fecha_tasa IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'La fecha de la tasa es requerida.',
                'details', NULL
            )
        );
    END IF;

    DELETE FROM public.tasa_cambio WHERE fecha_tasa = p_fecha_tasa;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'TASA_NO_ENCONTRADA',
                'message', 'No se encontrÃ³ ninguna tasa registrada para la fecha ' || p_fecha_tasa::text,
                'details', NULL
            )
        );
    END IF;

    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'fecha_tasa', p_fecha_tasa,
            'eliminado', true
        ),
        'error', NULL
    );
EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object(
        'success', false,
        'data', NULL,
        'error', json_build_object(
            'code', 'SQL_ERROR',
            'message', SQLERRM,
            'details', NULL
        )
    );
END;
$$;

-- 4. RPC retorna_ultima_tasa_cambio
CREATE OR REPLACE FUNCTION public.retorna_ultima_tasa_cambio()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result RECORD;
BEGIN
    SELECT fecha_tasa, tasa_cambio, created_at
    INTO v_result
    FROM public.tasa_cambio
    ORDER BY fecha_tasa DESC
    LIMIT 1;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', true,
            'data', NULL,
            'error', NULL
        );
    END IF;

    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'fecha_tasa', v_result.fecha_tasa,
            'tasa_cambio', v_result.tasa_cambio,
            'created_at', v_result.created_at
        ),
        'error', NULL
    );
EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object(
        'success', false,
        'data', NULL,
        'error', json_build_object(
            'code', 'SQL_ERROR',
            'message', SQLERRM,
            'details', NULL
        )
    );
END;
$$;

-- 5. RPC retorna_tasas_cambio_por_rango
CREATE OR REPLACE FUNCTION public.retorna_tasas_cambio_por_rango(
    p_fecha_desde DATE,
    p_fecha_hasta DATE
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_tasas JSON;
BEGIN
    IF p_fecha_desde IS NULL OR p_fecha_hasta IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'Las fechas de inicio y fin son requeridas.',
                'details', NULL
            )
        );
    END IF;

    SELECT COALESCE(json_agg(
        json_build_object(
            'fecha_tasa', fecha_tasa,
            'tasa_cambio', tasa_cambio,
            'created_at', created_at
        ) ORDER BY fecha_tasa DESC
    ), '[]'::json)
    INTO v_tasas
    FROM public.tasa_cambio
    WHERE fecha_tasa >= p_fecha_desde AND fecha_tasa <= p_fecha_hasta;

    RETURN json_build_object(
        'success', true,
        'data', v_tasas,
        'error', NULL
    );
EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object(
        'success', false,
        'data', NULL,
        'error', json_build_object(
            'code', 'SQL_ERROR',
            'message', SQLERRM,
            'details', NULL
        )
    );
END;
$$;

-- 6. Agregar vendedor_id a clientes (DB-014)
ALTER TABLE public.clientes
ADD COLUMN IF NOT EXISTS vendedor_id UUID REFERENCES public.perfiles_usuario(id) ON DELETE SET NULL;

-- 7. Agregar campos multimoneda (DB-015)
ALTER TABLE public.ordenes_distribucion
ADD COLUMN IF NOT EXISTS tasa_cambio NUMERIC(14,4),
ADD COLUMN IF NOT EXISTS total_recaudar_bs NUMERIC(14,2),
ADD COLUMN IF NOT EXISTS total_recaudar_usd NUMERIC(14,2);

ALTER TABLE public.detalle_distribucion
ADD COLUMN IF NOT EXISTS valor_unitario_usd NUMERIC(14,2),
ADD COLUMN IF NOT EXISTS subtotal_recaudar_usd NUMERIC(14,2);

-- 8. RPC actualiza_orden_distribucion_segun_correlativo (DB-017)
CREATE OR REPLACE FUNCTION public.actualiza_orden_distribucion_segun_correlativo(
    p_correlativo INT,
    p_header JSONB,
    p_detalle JSONB
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_orden_id UUID;
    v_estado_actual TEXT;
    v_creado_por UUID;
    v_user_id UUID := auth.uid();
    
    v_cliente_id UUID;
    v_chofer_id UUID;
    v_camion_id UUID;
    v_fecha_despacho TIMESTAMPTZ;
    v_factura_origen TEXT;
    v_fecha_tasa DATE;
    v_tasa_cambio NUMERIC(14,4);
    
    v_peso_total NUMERIC(14,2) := 0.00;
    v_total_bs NUMERIC(14,2) := 0.00;
    v_total_usd NUMERIC(14,2) := 0.00;
    
    v_item JSONB;
    v_secuencia INT := 1;
    v_producto_id UUID;
    v_cantidad INT;
    v_val_recaudar_bs NUMERIC(14,2);
    v_val_usd NUMERIC(14,2);
    v_subtotal_bs NUMERIC(14,2);
    v_subtotal_usd NUMERIC(14,2);
    v_peso_unitario NUMERIC(14,2);
BEGIN
    IF p_correlativo IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El correlativo de la orden es requerido.',
                'details', NULL
            )
        );
    END IF;

    SELECT id, estado, creado_por
    INTO v_orden_id, v_estado_actual, v_creado_por
    FROM public.ordenes_distribucion
    WHERE correlativo = p_correlativo;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ORDEN_NO_ENCONTRADA',
                'message', 'No se encontrÃ³ la orden con correlativo ' || p_correlativo::text,
                'details', NULL
            )
        );
    END IF;

    IF v_estado_actual NOT IN ('borrador') THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo se pueden actualizar Ã³rdenes en estado borrador. Estado actual: ' || v_estado_actual,
                'details', NULL
            )
        );
    END IF;

    IF public.user_has_role(ARRAY['vendedor']) AND NOT public.user_has_role(ARRAY['admin', 'gerente', 'despachador']) THEN
        IF v_user_id IS NOT NULL AND v_creado_por IS DISTINCT FROM v_user_id THEN
            RETURN json_build_object(
                'success', false,
                'data', NULL,
                'error', json_build_object(
                    'code', 'ACCESO_DENEGADO',
                    'message', 'Un vendedor solo puede actualizar las Ã³rdenes que Ã©l mismo ha registrado.',
                    'details', NULL
                )
            );
        END IF;
    END IF;

    v_cliente_id := (p_header->>'cliente_id')::UUID;
    v_chofer_id := (p_header->>'chofer_id')::UUID;
    v_camion_id := (p_header->>'camion_id')::UUID;
    v_fecha_despacho := (p_header->>'fecha_despacho')::TIMESTAMPTZ;
    v_factura_origen := p_header->>'factura_origen_numero';
    v_fecha_tasa := COALESCE(v_fecha_despacho::date, CURRENT_DATE);

    SELECT tasa_cambio INTO v_tasa_cambio
    FROM public.tasa_cambio
    WHERE fecha_tasa = v_fecha_tasa;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'EXCEPCION_TASA_NO_ENCONTRADA',
                'message', 'No existe tasa de cambio registrada para la fecha ' || v_fecha_tasa::text,
                'details', NULL
            )
        );
    END IF;

    IF p_detalle IS NOT NULL AND jsonb_array_length(p_detalle) > 0 THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(p_detalle) LOOP
            v_producto_id := (v_item->>'producto_id')::UUID;
            v_cantidad := (v_item->>'cantidad_solicitada')::INT;
            v_val_recaudar_bs := (v_item->>'valor_unitario_recaudar')::NUMERIC;
            v_val_usd := (v_item->>'valor_unitario_usd')::NUMERIC;

            IF v_val_usd IS NULL OR v_val_usd = 0 THEN
                v_val_usd := ROUND(v_val_recaudar_bs / v_tasa_cambio, 2);
            END IF;

            v_subtotal_bs := v_cantidad * v_val_recaudar_bs;
            v_subtotal_usd := v_cantidad * v_val_usd;

            v_total_bs := v_total_bs + v_subtotal_bs;
            v_total_usd := v_total_usd + v_subtotal_usd;

            SELECT COALESCE(peso_unitario_kg, 0) INTO v_peso_unitario
            FROM public.productos WHERE id = v_producto_id;

            v_peso_total := v_peso_total + (v_peso_unitario * v_cantidad);
        END LOOP;
    END IF;

    UPDATE public.ordenes_distribucion
    SET cliente_id = COALESCE(v_cliente_id, cliente_id),
        chofer_id = COALESCE(v_chofer_id, chofer_id),
        camion_id = COALESCE(v_camion_id, camion_id),
        fecha_despacho = COALESCE(v_fecha_despacho, fecha_despacho),
        factura_origen_numero = COALESCE(v_factura_origen, factura_origen_numero),
        tasa_cambio = v_tasa_cambio,
        peso_total_calculado = v_peso_total,
        total_recaudar_bs = v_total_bs,
        total_recaudar_usd = v_total_usd
    WHERE id = v_orden_id;

    IF p_detalle IS NOT NULL AND jsonb_array_length(p_detalle) > 0 THEN
        DELETE FROM public.detalle_distribucion WHERE orden_id = v_orden_id;

        FOR v_item IN SELECT * FROM jsonb_array_elements(p_detalle) LOOP
            v_producto_id := (v_item->>'producto_id')::UUID;
            v_cantidad := (v_item->>'cantidad_solicitada')::INT;
            v_val_recaudar_bs := (v_item->>'valor_unitario_recaudar')::NUMERIC;
            v_val_usd := (v_item->>'valor_unitario_usd')::NUMERIC;

            IF v_val_usd IS NULL OR v_val_usd = 0 THEN
                v_val_usd := ROUND(v_val_recaudar_bs / v_tasa_cambio, 2);
            END IF;

            v_subtotal_bs := v_cantidad * v_val_recaudar_bs;
            v_subtotal_usd := v_cantidad * v_val_usd;

            INSERT INTO public.detalle_distribucion (
                id,
                orden_id,
                producto_id,
                cantidad_solicitada,
                cantidad_despachada,
                valor_unitario_recaudar,
                subtotal_recaudar,
                valor_unitario_usd,
                subtotal_recaudar_usd,
                secuencia_entrega,
                estado_entrega
            ) VALUES (
                gen_random_uuid(),
                v_orden_id,
                v_producto_id,
                v_cantidad,
                0,
                v_val_recaudar_bs,
                v_subtotal_bs,
                v_val_usd,
                v_subtotal_usd,
                v_secuencia,
                'pendiente'
            );

            v_secuencia := v_secuencia + 1;
        END LOOP;
    END IF;

    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'correlativo', p_correlativo,
            'orden_id', v_orden_id,
            'tasa_cambio', v_tasa_cambio,
            'total_recaudar_bs', v_total_bs,
            'total_recaudar_usd', v_total_usd
        ),
        'error', NULL
    );

EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object(
        'success', false,
        'data', NULL,
        'error', json_build_object(
            'code', 'SQL_ERROR',
            'message', SQLERRM,
            'details', NULL
        )
    );
END;
$$;

-- 9. RPC retorna_ordenes_distribucion_segun_estado (DB-018)
CREATE OR REPLACE FUNCTION public.retorna_ordenes_distribucion_segun_estado(
    p_estado TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_is_vendedor BOOLEAN := FALSE;
    v_is_gerente_admin BOOLEAN := FALSE;
    v_ordenes JSON;
BEGIN
    IF p_estado IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El estado de la orden es requerido.',
                'details', NULL
            )
        );
    END IF;

    v_is_gerente_admin := public.user_has_role(ARRAY['admin', 'gerente', 'despachador']);
    v_is_vendedor := public.user_has_role(ARRAY['vendedor']);

    SELECT COALESCE(json_agg(
        json_build_object(
            'id', o.id,
            'correlativo', o.correlativo,
            'cliente_id', o.cliente_id,
            'cliente_razon_social', c.razon_social,
            'cliente_vendedor_id', c.vendedor_id,
            'camion_id', o.camion_id,
            'chofer_id', o.chofer_id,
            'estado', o.estado,
            'fecha_despacho', o.fecha_despacho,
            'peso_total_calculado', o.peso_total_calculado,
            'factura_origen_numero', o.factura_origen_numero,
            'tasa_cambio', o.tasa_cambio,
            'total_recaudar_bs', o.total_recaudar_bs,
            'total_recaudar_usd', o.total_recaudar_usd,
            'creado_por', o.creado_por,
            'created_at', o.created_at
        ) ORDER BY o.correlativo DESC
    ), '[]'::json)
    INTO v_ordenes
    FROM public.ordenes_distribucion o
    LEFT JOIN public.clientes c ON c.id = o.cliente_id
    WHERE o.estado = p_estado
      AND (
          v_is_gerente_admin 
          OR (v_is_vendedor AND (c.vendedor_id = v_user_id OR o.creado_por = v_user_id))
      );

    RETURN json_build_object(
        'success', true,
        'data', v_ordenes,
        'error', NULL
    );

EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object(
        'success', false,
        'data', NULL,
        'error', json_build_object(
            'code', 'SQL_ERROR',
            'message', SQLERRM,
            'details', NULL
        )
    );
END;
$$;
-- Migration: Actualizar funciÃ³n crear_orden_distribucion con soporte para campos multimoneda (DB-016b)

CREATE OR REPLACE FUNCTION public.crear_orden_distribucion(
    p_vendedor_id UUID,
    p_chofer_id UUID,
    p_cliente_id UUID,
    p_camion_id UUID,
    p_tasa_cambio NUMERIC DEFAULT NULL,
    p_productos_json JSONB DEFAULT '[]'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_orden_id UUID;
    v_correlativo INT;
    v_factura_origen VARCHAR(30);
    v_tasa_cambio NUMERIC(14,4);
    
    v_peso_total NUMERIC(10,2) := 0.00;
    v_total_recaudar_bs NUMERIC(14,2) := 0.00;
    v_total_recaudar_usd NUMERIC(14,2) := 0.00;
    
    v_item JSONB;
    v_secuencia INT := 1;
    v_producto_id UUID;
    v_cantidad INT;
    v_val_recaudar_bs NUMERIC(14,2);
    v_val_usd NUMERIC(14,2);
    v_subtotal_bs NUMERIC(14,2);
    v_subtotal_usd NUMERIC(14,2);
    v_peso_unitario NUMERIC(10,2);
BEGIN
    -- Validaciones bÃ¡sicas
    IF p_vendedor_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del vendedor es requerido.');
    END IF;

    IF p_chofer_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del chofer es requerido.');
    END IF;

    IF p_cliente_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del cliente es requerido.');
    END IF;

    IF p_camion_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del camiÃ³n es requerido.');
    END IF;

    IF p_productos_json IS NULL OR jsonb_array_length(p_productos_json) = 0 THEN
        RETURN jsonb_build_object('success', false, 'message', 'Debe incluir al menos un producto en la orden.');
    END IF;

    -- Determinar / validar la tasa de cambio
    IF p_tasa_cambio IS NOT NULL AND p_tasa_cambio > 0 THEN
        v_tasa_cambio := p_tasa_cambio;
    ELSE
        -- Buscar la tasa de cambio registrada para la fecha actual
        SELECT tasa_cambio INTO v_tasa_cambio
        FROM public.tasa_cambio
        WHERE fecha_tasa = CURRENT_DATE;

        -- Si no hay tasa para hoy, tomar la mÃ¡s reciente registrada
        IF v_tasa_cambio IS NULL THEN
            SELECT tasa_cambio INTO v_tasa_cambio
            FROM public.tasa_cambio
            ORDER BY fecha_tasa DESC
            LIMIT 1;
        END IF;

        IF v_tasa_cambio IS NULL THEN
            RETURN jsonb_build_object(
                'success', false, 
                'message', 'No hay tasa de cambio registrada. Debe proporcionar p_tasa_cambio o registrar una tasa oficial en el sistema.'
            );
        END IF;
    END IF;

    -- Validar existencia de entidades
    IF NOT EXISTS (SELECT 1 FROM public.perfiles_usuario WHERE id = p_vendedor_id) THEN
        RETURN jsonb_build_object('success', false, 'message', 'El vendedor especificado no existe.');
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.choferes WHERE perfil_id = p_chofer_id
        UNION ALL
        SELECT 1 FROM public.perfiles_usuario WHERE id = p_chofer_id
    ) THEN
        RETURN jsonb_build_object('success', false, 'message', 'El chofer especificado no existe o no estÃ¡ registrado.');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.clientes WHERE id = p_cliente_id) THEN
        RETURN jsonb_build_object('success', false, 'message', 'El cliente especificado no existe.');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.camiones WHERE id = p_camion_id) THEN
        RETURN jsonb_build_object('success', false, 'message', 'El camiÃ³n especificado no existe.');
    END IF;

    -- Generar correlativo y nÃºmero de factura de origen automÃ¡ticamente
    v_correlativo := nextval('public.ordenes_distribucion_correlativo_seq');
    v_factura_origen := 'FAC-' || LPAD(v_correlativo::text, 6, '0');
    v_orden_id := gen_random_uuid();

    -- Validar productos y calcular totales multimoneda y peso total
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;
        
        IF v_cantidad IS NULL OR v_cantidad <= 0 THEN
            RETURN jsonb_build_object('success', false, 'message', 'La cantidad del producto debe ser mayor a cero.');
        END IF;

        -- Obtener peso unitario del producto
        SELECT peso_unitario_kg INTO v_peso_unitario
        FROM public.productos
        WHERE id = v_producto_id;

        IF NOT FOUND THEN
            RETURN jsonb_build_object('success', false, 'message', 'El producto con ID ' || v_producto_id::text || ' no existe.');
        END IF;

        -- Precios unitarios (soporta 'valor_unitario_recaudar' o 'precio_unitario' para compatibilidad)
        v_val_recaudar_bs := COALESCE((v_item->>'valor_unitario_recaudar')::NUMERIC, (v_item->>'precio_unitario')::NUMERIC, 0.00);
        v_val_usd := COALESCE((v_item->>'valor_unitario_usd')::NUMERIC, 0.00);

        -- ConversiÃ³n si uno de los valores no estÃ¡ definido
        IF v_val_recaudar_bs > 0 AND (v_val_usd IS NULL OR v_val_usd = 0) THEN
            v_val_usd := ROUND(v_val_recaudar_bs / v_tasa_cambio, 2);
        ELSIF v_val_usd > 0 AND (v_val_recaudar_bs IS NULL OR v_val_recaudar_bs = 0) THEN
            v_val_recaudar_bs := ROUND(v_val_usd * v_tasa_cambio, 2);
        END IF;

        v_subtotal_bs := ROUND(v_cantidad * v_val_recaudar_bs, 2);
        v_subtotal_usd := ROUND(v_cantidad * v_val_usd, 2);

        v_peso_total := v_peso_total + (COALESCE(v_peso_unitario, 0.00) * v_cantidad);
        v_total_recaudar_bs := v_total_recaudar_bs + v_subtotal_bs;
        v_total_recaudar_usd := v_total_recaudar_usd + v_subtotal_usd;
    END LOOP;

    -- Insertar Cabecera de la Orden
    INSERT INTO public.ordenes_distribucion (
        id,
        correlativo,
        cliente_id,
        camion_id,
        chofer_id,
        estado,
        fecha_despacho,
        peso_total_calculado,
        factura_origen_numero,
        creado_por,
        created_at,
        tasa_cambio,
        total_recaudar_bs,
        total_recaudar_usd
    ) VALUES (
        v_orden_id,
        v_correlativo,
        p_cliente_id,
        p_camion_id,
        p_chofer_id,
        'borrador',
        NULL,
        v_peso_total,
        v_factura_origen,
        p_vendedor_id,
        NOW(),
        v_tasa_cambio,
        v_total_recaudar_bs,
        v_total_recaudar_usd
    );

    -- Insertar Detalles de la Orden
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;
        
        v_val_recaudar_bs := COALESCE((v_item->>'valor_unitario_recaudar')::NUMERIC, (v_item->>'precio_unitario')::NUMERIC, 0.00);
        v_val_usd := COALESCE((v_item->>'valor_unitario_usd')::NUMERIC, 0.00);

        IF v_val_recaudar_bs > 0 AND (v_val_usd IS NULL OR v_val_usd = 0) THEN
            v_val_usd := ROUND(v_val_recaudar_bs / v_tasa_cambio, 2);
        ELSIF v_val_usd > 0 AND (v_val_recaudar_bs IS NULL OR v_val_recaudar_bs = 0) THEN
            v_val_recaudar_bs := ROUND(v_val_usd * v_tasa_cambio, 2);
        END IF;

        v_subtotal_bs := ROUND(v_cantidad * v_val_recaudar_bs, 2);
        v_subtotal_usd := ROUND(v_cantidad * v_val_usd, 2);

        INSERT INTO public.detalle_distribucion (
            id,
            orden_id,
            producto_id,
            cantidad_solicitada,
            cantidad_despachada,
            valor_unitario_recaudar,
            subtotal_recaudar,
            secuencia_entrega,
            estado_entrega,
            motivo_rechazo,
            valor_unitario_usd,
            subtotal_recaudar_usd
        ) VALUES (
            gen_random_uuid(),
            v_orden_id,
            v_producto_id,
            v_cantidad,
            0, -- Despachado inicialmente en 0
            v_val_recaudar_bs,
            v_subtotal_bs,
            v_secuencia,
            'pendiente',
            NULL,
            v_val_usd,
            v_subtotal_usd
        );
        
        v_secuencia := v_secuencia + 1;
    END LOOP;

    RETURN jsonb_build_object(
        'success', true, 
        'message', 'Orden de distribuciÃ³n creada exitosamente.', 
        'orden_id', v_orden_id,
        'data', jsonb_build_object(
            'orden_id', v_orden_id,
            'correlativo', v_correlativo,
            'tasa_cambio', v_tasa_cambio,
            'total_recaudar_bs', v_total_recaudar_bs,
            'total_recaudar_usd', v_total_recaudar_usd,
            'peso_total_calculado', v_peso_total
        )
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false, 
        'message', 'Error al crear la orden: ' || SQLERRM
    );
END;
$$;
-- Migration: RPC Consulta de Lista de Contenedores (DB-019)

CREATE OR REPLACE FUNCTION public.retorna_lista_contenedores()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_contenedores JSON;
BEGIN
    SELECT COALESCE(json_agg(
        json_build_object(
            'id', id,
            'nombre', nombre
        ) ORDER BY nombre ASC
    ), '[]'::json)
    INTO v_contenedores
    FROM public.tipos_contenedores;

    RETURN json_build_object(
        'success', true,
        'data', v_contenedores,
        'error', NULL
    );
EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object(
        'success', false,
        'data', NULL,
        'error', json_build_object(
            'code', 'SQL_ERROR',
            'message', SQLERRM,
            'details', NULL
        )
    );
END;
$$;
-- MigraciÃ³n para agregar/corregir la columna despachador_id en la tabla clientes
-- Permite la asignaciÃ³n opcional de un usuario despachador a la ficha del cliente (relaciÃ³n 1:N con perfiles_usuario)

DO $$
BEGIN
    -- Si la columna ya existe pero no es de tipo UUID (ej: int2/integer de esquemas legados), se elimina la vieja para reemplazarla por UUID
    IF EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'clientes' 
          AND column_name = 'despachador_id'
          AND data_type != 'uuid'
    ) THEN
        ALTER TABLE public.clientes DROP COLUMN despachador_id;
    END IF;

    -- Agregar la columna UUID con Foreign Key si no existe
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'clientes' 
          AND column_name = 'despachador_id'
    ) THEN
        ALTER TABLE public.clientes 
        ADD COLUMN despachador_id UUID REFERENCES public.perfiles_usuario(id) ON DELETE SET NULL;
    END IF;
END $$;

COMMENT ON COLUMN public.clientes.despachador_id IS 'ID del perfil de usuario con rol despachador asignado preferencialmente al cliente';
-- MigraciÃ³n para crear la tabla maestra rutas e integrar id_ruta en clientes

-- 1. Crear tabla rutas
CREATE TABLE IF NOT EXISTS public.rutas (
    id_ruta UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    nombre_ruta TEXT NOT NULL,
    descripcion_ruta TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

COMMENT ON TABLE public.rutas IS 'Tabla maestra de rutas de despacho y distribuciÃ³n';
COMMENT ON COLUMN public.rutas.id_ruta IS 'Identificador Ãºnico de la ruta (UUID)';
COMMENT ON COLUMN public.rutas.nombre_ruta IS 'Nombre identificador de la ruta (no nulo)';
COMMENT ON COLUMN public.rutas.descripcion_ruta IS 'DescripciÃ³n o detalles adicionales de la ruta (acepta nulo)';

-- 2. Habilitar RLS en rutas y definir polÃ­ticas de acceso
ALTER TABLE public.rutas ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Usuarios autenticados pueden ver rutas"
ON public.rutas FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "Admin y Gerente pueden gestionar rutas"
ON public.rutas FOR ALL
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.perfiles_usuario p
        JOIN public.roles r ON p.rol_id = r.id
        WHERE p.id = auth.uid()
          AND r.nombre IN ('admin', 'gerente')
    )
);

-- 3. Agregar campo id_ruta a la tabla clientes
ALTER TABLE public.clientes
ADD COLUMN IF NOT EXISTS id_ruta UUID REFERENCES public.rutas(id_ruta) ON DELETE SET NULL;

COMMENT ON COLUMN public.clientes.id_ruta IS 'FK hacia la ruta asignada al cliente';
-- MigraciÃ³n: RPC retorna_lista_rutas (Tarea DB-020)

CREATE OR REPLACE FUNCTION public.retorna_lista_rutas()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_total_registros INT;
    v_data JSONB;
BEGIN
    -- Obtenemos el total de registros en la tabla rutas
    SELECT COUNT(*) INTO v_total_registros FROM public.rutas;

    -- Obtenemos el arreglo de rutas ordenadas por nombre_ruta
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'id_ruta', id_ruta,
                'nombre_ruta', nombre_ruta,
                'descripcion_ruta', descripcion_ruta,
                'created_at', created_at
            )
            ORDER BY nombre_ruta ASC
        ),
        '[]'::jsonb
    ) INTO v_data
    FROM public.rutas;

    -- Retornamos respuesta exitosa
    RETURN jsonb_build_object(
        'success', TRUE,
        'total_registros', v_total_registros,
        'data', v_data
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', SQLSTATE,
                'message', SQLERRM
            )
        );
END;
$$;

COMMENT ON FUNCTION public.retorna_lista_rutas() IS 'Retorna el listado completo de rutas y la cantidad total de registros almacenados';
-- MigraciÃ³n: RPC retorna_usuarios_despachadores (Tarea DB-021)

CREATE OR REPLACE FUNCTION public.retorna_usuarios_despachadores()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_data JSONB;
BEGIN
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'id', p.id,
                'nombre_completo', p.nombre_completo,
                'telefono', p.telefono
            )
            ORDER BY p.nombre_completo ASC
        ),
        '[]'::jsonb
    ) INTO v_data
    FROM public.perfiles_usuario p
    JOIN public.roles r ON p.rol_id = r.id
    WHERE r.nombre = 'despachador'
      AND p.activo = TRUE;

    RETURN jsonb_build_object(
        'success', TRUE,
        'data', v_data
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', SQLSTATE,
                'message', SQLERRM
            )
        );
END;
$$;

COMMENT ON FUNCTION public.retorna_usuarios_despachadores() IS 'Retorna la lista de usuarios activos que poseen el rol de despachador';
-- MigraciÃ³n: RPC actualiza_registro_rutas_segun_uuid (Tarea DB-022)

CREATE OR REPLACE FUNCTION public.actualiza_registro_rutas_segun_uuid(
    p_id_ruta UUID,
    p_nombre_ruta TEXT,
    p_descripcion_ruta TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_ruta_actualizada RECORD;
BEGIN
    -- Validar que el id_ruta no sea nulo
    IF p_id_ruta IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El parÃ¡metro p_id_ruta es obligatorio.'
            )
        );
    END IF;

    -- Validar que el nombre_ruta no estÃ© vacÃ­o
    IF p_nombre_ruta IS NULL OR TRIM(p_nombre_ruta) = '' THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El parÃ¡metro p_nombre_ruta es obligatorio y no puede estar vacÃ­o.'
            )
        );
    END IF;

    -- Verificar si la ruta existe
    IF NOT EXISTS (SELECT 1 FROM public.rutas WHERE id_ruta = p_id_ruta) THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'RUTA_INEXISTENTE',
                'message', 'No se encontrÃ³ ninguna ruta con el id_ruta especificado.'
            )
        );
    END IF;

    -- Actualizar el registro en la tabla rutas
    UPDATE public.rutas
    SET nombre_ruta = TRIM(p_nombre_ruta),
        descripcion_ruta = p_descripcion_ruta
    WHERE id_ruta = p_id_ruta
    RETURNING id_ruta, nombre_ruta, descripcion_ruta, created_at
    INTO v_ruta_actualizada;

    -- Retornar Ã©xito
    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Ruta actualizada exitosamente.',
        'data', jsonb_build_object(
            'id_ruta', v_ruta_actualizada.id_ruta,
            'nombre_ruta', v_ruta_actualizada.nombre_ruta,
            'descripcion_ruta', v_ruta_actualizada.descripcion_ruta,
            'created_at', v_ruta_actualizada.created_at
        )
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', SQLSTATE,
                'message', SQLERRM
            )
        );
END;
$$;

COMMENT ON FUNCTION public.actualiza_registro_rutas_segun_uuid(UUID, TEXT, TEXT) IS 'Actualiza el nombre y descripciÃ³n de una ruta existente identificada por su id_ruta (UUID)';
-- MigraciÃ³n de CorrecciÃ³n de Seguridad: Habilitar RLS y polÃ­ticas en las 4 tablas faltantes

-- 1. tipos_contenedores
ALTER TABLE public.tipos_contenedores ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS select_tipos_contenedores ON public.tipos_contenedores;
DROP POLICY IF EXISTS modify_tipos_contenedores ON public.tipos_contenedores;

CREATE POLICY select_tipos_contenedores ON public.tipos_contenedores
FOR SELECT TO authenticated USING (true);

CREATE POLICY modify_tipos_contenedores ON public.tipos_contenedores
FOR ALL TO authenticated
USING (public.user_has_role(ARRAY['admin', 'gerente', 'despachador']));


-- 2. saldo_contenedores_clientes
ALTER TABLE public.saldo_contenedores_clientes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS select_saldo_contenedores_clientes ON public.saldo_contenedores_clientes;
DROP POLICY IF EXISTS modify_saldo_contenedores_clientes ON public.saldo_contenedores_clientes;

CREATE POLICY select_saldo_contenedores_clientes ON public.saldo_contenedores_clientes
FOR SELECT TO authenticated USING (true);

CREATE POLICY modify_saldo_contenedores_clientes ON public.saldo_contenedores_clientes
FOR ALL TO authenticated
USING (public.user_has_role(ARRAY['admin', 'gerente', 'despachador', 'vendedor']));


-- 3. movimientos_contenedores
ALTER TABLE public.movimientos_contenedores ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS select_movimientos_contenedores ON public.movimientos_contenedores;
DROP POLICY IF EXISTS modify_movimientos_contenedores ON public.movimientos_contenedores;

CREATE POLICY select_movimientos_contenedores ON public.movimientos_contenedores
FOR SELECT TO authenticated USING (true);

CREATE POLICY modify_movimientos_contenedores ON public.movimientos_contenedores
FOR ALL TO authenticated
USING (public.user_has_role(ARRAY['admin', 'gerente', 'despachador', 'vendedor']));


-- 4. movimientos_saldo_favor
ALTER TABLE public.movimientos_saldo_favor ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS select_movimientos_saldo_favor ON public.movimientos_saldo_favor;
DROP POLICY IF EXISTS modify_movimientos_saldo_favor ON public.movimientos_saldo_favor;

CREATE POLICY select_movimientos_saldo_favor ON public.movimientos_saldo_favor
FOR SELECT TO authenticated USING (true);

CREATE POLICY modify_movimientos_saldo_favor ON public.movimientos_saldo_favor
FOR ALL TO authenticated
USING (public.user_has_role(ARRAY['admin', 'gerente', 'despachador', 'vendedor']));
-- MigraciÃ³n para crear el procedure actualiza_registro_cliente_segun_uuid

CREATE OR REPLACE FUNCTION public.actualiza_registro_cliente_segun_uuid(
    p_id UUID,
    p_rif_nit TEXT DEFAULT NULL,
    p_razon_social TEXT DEFAULT NULL,
    p_direccion_fiscal TEXT DEFAULT NULL,
    p_telefono TEXT DEFAULT NULL,
    p_movil1 TEXT DEFAULT NULL,
    p_movil2 TEXT DEFAULT NULL,
    p_movil3 TEXT DEFAULT NULL,
    p_correo_e TEXT DEFAULT NULL,
    p_cond_liq NUMERIC DEFAULT NULL,
    p_max_liq NUMERIC DEFAULT NULL,
    p_vendedor_id UUID DEFAULT NULL,
    p_despachador_id UUID DEFAULT NULL,
    p_id_ruta UUID DEFAULT NULL,
    p_activo BOOLEAN DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_cliente_actualizado RECORD;
BEGIN
    -- Validar que el id del cliente no sea nulo
    IF p_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El parÃ¡metro p_id es obligatorio.'
            )
        );
    END IF;

    -- Verificar si el cliente existe
    IF NOT EXISTS (SELECT 1 FROM public.clientes WHERE id = p_id) THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'CLIENTE_INEXISTENTE',
                'message', 'No se encontrÃ³ ningÃºn cliente con el ID especificado.'
            )
        );
    END IF;

    -- Validar si el RIF/NIT ingresado ya pertenece a otro cliente
    IF p_rif_nit IS NOT NULL AND TRIM(p_rif_nit) <> '' THEN
        IF EXISTS (SELECT 1 FROM public.clientes WHERE rif_nit = TRIM(p_rif_nit) AND id <> p_id) THEN
            RETURN jsonb_build_object(
                'success', FALSE,
                'error', jsonb_build_object(
                    'code', 'RIF_DUPLICADO',
                    'message', 'El RIF/NIT especificado ya estÃ¡ registrado en otro cliente.'
                )
            );
        END IF;
    END IF;

    -- Actualizar el registro en la tabla clientes
    UPDATE public.clientes
    SET 
        rif_nit = COALESCE(NULLIF(TRIM(p_rif_nit), ''), rif_nit),
        razon_social = COALESCE(NULLIF(TRIM(p_razon_social), ''), razon_social),
        direccion_fiscal = COALESCE(NULLIF(TRIM(p_direccion_fiscal), ''), direccion_fiscal),
        telefono = COALESCE(p_telefono, telefono),
        movil1 = COALESCE(p_movil1, movil1),
        movil2 = COALESCE(p_movil2, movil2),
        movil3 = COALESCE(p_movil3, movil3),
        correo_e = COALESCE(p_correo_e, correo_e),
        cond_liq = COALESCE(p_cond_liq, cond_liq),
        max_liq = COALESCE(p_max_liq, max_liq),
        vendedor_id = COALESCE(p_vendedor_id, vendedor_id),
        despachador_id = COALESCE(p_despachador_id, despachador_id),
        id_ruta = COALESCE(p_id_ruta, id_ruta),
        activo = COALESCE(p_activo, activo)
    WHERE id = p_id
    RETURNING id, rif_nit, razon_social, direccion_fiscal, telefono, movil1, movil2, movil3, 
              correo_e, cond_liq, max_liq, vendedor_id, despachador_id, id_ruta, activo, created_at
    INTO v_cliente_actualizado;

    -- Retornar Ã©xito
    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Cliente actualizado exitosamente.',
        'data', jsonb_build_object(
            'id', v_cliente_actualizado.id,
            'rif_nit', v_cliente_actualizado.rif_nit,
            'razon_social', v_cliente_actualizado.razon_social,
            'direccion_fiscal', v_cliente_actualizado.direccion_fiscal,
            'telefono', v_cliente_actualizado.telefono,
            'movil1', v_cliente_actualizado.movil1,
            'movil2', v_cliente_actualizado.movil2,
            'movil3', v_cliente_actualizado.movil3,
            'correo_e', v_cliente_actualizado.correo_e,
            'cond_liq', v_cliente_actualizado.cond_liq,
            'max_liq', v_cliente_actualizado.max_liq,
            'vendedor_id', v_cliente_actualizado.vendedor_id,
            'despachador_id', v_cliente_actualizado.despachador_id,
            'id_ruta', v_cliente_actualizado.id_ruta,
            'activo', v_cliente_actualizado.activo,
            'created_at', v_cliente_actualizado.created_at
        )
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', SQLSTATE,
                'message', SQLERRM
            )
        );
END;
$$;

COMMENT ON FUNCTION public.actualiza_registro_cliente_segun_uuid(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC, NUMERIC, UUID, UUID, UUID, BOOLEAN) 
IS 'Actualiza la informaciÃ³n de un cliente existente en la tabla clientes segÃºn su ID (UUID)';
-- MigraciÃ³n para el MÃ³dulo Radar del Despachador (DB-024)

-- 1. Agregar columnas para control provisional de contenedores en la tabla detalle_distribucion
ALTER TABLE public.detalle_distribucion
ADD COLUMN IF NOT EXISTS contenedores_retirados INT DEFAULT 0 CHECK (contenedores_retirados >= 0),
ADD COLUMN IF NOT EXISTS contenedor_id UUID REFERENCES public.tipos_contenedores(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.detalle_distribucion.contenedores_retirados IS 'Cantidad de envases vacÃ­os retirados al cliente en ruta (provisional hasta liquidaciÃ³n)';
COMMENT ON COLUMN public.detalle_distribucion.contenedor_id IS 'Tipo de contenedor asociado al retiro/entrega de esta lÃ­nea';

-- 2. RPC retorna_radar_despachador
CREATE OR REPLACE FUNCTION public.retorna_radar_despachador()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_despachador_id UUID;
    v_resultado JSONB;
BEGIN
    v_despachador_id := auth.uid();

    IF v_despachador_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'NO_AUTENTICADO',
                'message', 'El usuario no estÃ¡ autenticado.'
            )
        );
    END IF;

    SELECT jsonb_build_object(
        'success', TRUE,
        'total_ordenes', COUNT(o.id),
        'data', COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'orden_id', o.id,
                    'correlativo', o.correlativo,
                    'estado', o.estado,
                    'fecha_despacho', o.fecha_despacho,
                    'tasa_cambio', o.tasa_cambio,
                    'total_recaudar_bs', o.total_recaudar_bs,
                    'total_recaudar_usd', o.total_recaudar_usd,
                    'cliente', jsonb_build_object(
                        'id', c.id,
                        'razon_social', c.razon_social,
                        'rif_nit', c.rif_nit,
                        'direccion_fiscal', c.direccion_fiscal,
                        'telefono', c.telefono,
                        'movil1', c.movil1,
                        'nombre_ruta', r.nombre_ruta
                    ),
                    'detalles', (
                        SELECT COALESCE(jsonb_agg(
                            jsonb_build_object(
                                'detalle_id', d.id,
                                'producto_id', p.id,
                                'codigo_producto', p.codigo_producto,
                                'nombre_producto', p.nombre,
                                'cantidad_solicitada', d.cantidad_solicitada,
                                'cantidad_despachada', COALESCE(d.cantidad_despachada, 0),
                                'valor_unitario_recaudar', d.valor_unitario_recaudar,
                                'subtotal_recaudar', d.subtotal_recaudar,
                                'valor_unitario_usd', d.valor_unitario_usd,
                                'subtotal_recaudar_usd', d.subtotal_recaudar_usd,
                                'estado_entrega', COALESCE(d.estado_entrega, 'pendiente'),
                                'motivo_rechazo', d.motivo_rechazo,
                                'contenedores_retirados', COALESCE(d.contenedores_retirados, 0),
                                'contenedor_id', d.contenedor_id
                            )
                        ), '[]'::jsonb)
                        FROM public.detalle_distribucion d
                        JOIN public.productos p ON d.producto_id = p.id
                        WHERE d.orden_id = o.id
                    ),
                    'saldo_contenedores', (
                        SELECT COALESCE(jsonb_agg(
                            jsonb_build_object(
                                'contenedor_id', tc.id,
                                'nombre_contenedor', tc.nombre,
                                'saldo_pendiente', COALESCE(sc.saldo_pendiente, 0)
                            )
                        ), '[]'::jsonb)
                        FROM public.tipos_contenedores tc
                        LEFT JOIN public.saldo_contenedores_clientes sc ON sc.contenedor_id = tc.id AND sc.cliente_id = c.id
                    )
                )
            ),
            '[]'::jsonb
        )
    ) INTO v_resultado
    FROM public.ordenes_distribucion o
    JOIN public.clientes c ON o.cliente_id = c.id
    LEFT JOIN public.rutas r ON c.id_ruta = r.id_ruta
    WHERE c.despachador_id = v_despachador_id
      AND o.estado IN ('en_transito', 'por_liquidar');

    RETURN v_resultado;

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', SQLSTATE,
                'message', SQLERRM
            )
        );
END;
$$;

COMMENT ON FUNCTION public.retorna_radar_despachador() IS 'Retorna las Ã³rdenes en trÃ¡nsito del despachador autenticado con detalles de mercancÃ­a y saldo de envases del cliente';

-- 3. RPC registrar_despacho_cliente_radar
CREATE OR REPLACE FUNCTION public.registrar_despacho_cliente_radar(
    p_orden_id UUID,
    p_detalles_json JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_estado_orden TEXT;
    v_camion_id UUID;
    v_item JSONB;
    v_detalle_id UUID;
    v_cantidad_despachada INT;
    v_estado_entrega TEXT;
    v_motivo_rechazo TEXT;
    v_contenedores_retirados INT;
    v_contenedor_id UUID;
    v_producto_id UUID;
    v_cantidad_solicitada INT;
    v_devolucion INT;
    v_pendientes_count INT;
BEGIN
    IF p_orden_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El parÃ¡metro p_orden_id es obligatorio.'
            )
        );
    END IF;

    SELECT estado, camion_id INTO v_estado_orden, v_camion_id
    FROM public.ordenes_distribucion
    WHERE id = p_orden_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'ORDEN_INEXISTENTE',
                'message', 'No se encontrÃ³ la orden especificada.'
            )
        );
    END IF;

    IF v_estado_orden NOT IN ('en_transito', 'por_liquidar') THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo se pueden registrar entregas de Ã³rdenes en estado en_transito o por_liquidar.'
            )
        );
    END IF;

    -- Procesar cada objeto del arreglo JSON p_detalles_json
    IF p_detalles_json IS NOT NULL AND jsonb_array_length(p_detalles_json) > 0 THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(p_detalles_json) LOOP
            v_detalle_id := (v_item->>'detalle_id')::UUID;
            v_cantidad_despachada := (v_item->>'cantidad_despachada')::INT;
            v_estado_entrega := v_item->>'estado_entrega';
            v_motivo_rechazo := v_item->>'motivo_rechazo';
            v_contenedores_retirados := COALESCE((v_item->>'contenedores_retirados')::INT, 0);
            v_contenedor_id := (v_item->>'contenedor_id')::UUID;

            SELECT producto_id, cantidad_solicitada INTO v_producto_id, v_cantidad_solicitada
            FROM public.detalle_distribucion
            WHERE id = v_detalle_id AND orden_id = p_orden_id;

            IF FOUND THEN
                v_devolucion := GREATEST(0, v_cantidad_solicitada - v_cantidad_despachada);

                -- Actualizar inventario mÃ³vil para el camiÃ³n
                UPDATE public.inventario_movil
                SET cantidad_cargada = GREATEST(0, cantidad_cargada - v_cantidad_solicitada),
                    cantidad_entregada = cantidad_entregada + v_cantidad_despachada,
                    cantidad_devolucion = cantidad_devolucion + v_devolucion,
                    updated_at = NOW()
                WHERE camion_id = v_camion_id AND producto_id = v_producto_id;

                -- Actualizar renglÃ³n en detalle_distribucion
                UPDATE public.detalle_distribucion
                SET cantidad_despachada = v_cantidad_despachada,
                    estado_entrega = v_estado_entrega,
                    motivo_rechazo = v_motivo_rechazo,
                    contenedores_retirados = v_contenedores_retirados,
                    contenedor_id = v_contenedor_id
                WHERE id = v_detalle_id;
            END IF;
        END LOOP;
    END IF;

    -- Verificar si todas las lÃ­neas estÃ¡n procesadas
    SELECT COUNT(*) INTO v_pendientes_count
    FROM public.detalle_distribucion
    WHERE orden_id = p_orden_id AND (estado_entrega IS NULL OR estado_entrega = 'pendiente');

    IF v_pendientes_count = 0 THEN
        UPDATE public.ordenes_distribucion
        SET estado = 'por_liquidar'
        WHERE id = p_orden_id;
        v_estado_orden := 'por_liquidar';
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Despacho registrado en radar exitosamente.',
        'data', jsonb_build_object(
            'orden_id', p_orden_id,
            'nuevo_estado_orden', v_estado_orden
        )
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', SQLSTATE,
                'message', SQLERRM
            )
        );
END;
$$;

COMMENT ON FUNCTION public.registrar_despacho_cliente_radar(UUID, JSONB) IS 'Registra las entregas y el retiro provisional de envases del cliente desde la interfaz del despachador, cambiando la orden a por_liquidar';

-- 4. Actualizar liquidar_orden_distribucion para consolidar envases retirados al aprobar por la gerencia
CREATE OR REPLACE FUNCTION public.liquidar_orden_distribucion(
    p_orden_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_estado_orden TEXT;
    v_cliente_id UUID;
    v_camion_id UUID;
    v_chofer_id UUID;
    v_rendicion_aprobada BOOLEAN := FALSE;
    v_det RECORD;
BEGIN
    -- Validar parÃ¡metro
    IF p_orden_id IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID de la orden es requerido.'
            )
        );
    END IF;

    -- Obtener orden
    SELECT estado, cliente_id, camion_id, chofer_id
    INTO v_estado_orden, v_cliente_id, v_camion_id, v_chofer_id
    FROM public.ordenes_distribucion
    WHERE id = p_orden_id;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'ORDEN_INEXISTENTE',
                'message', 'La orden de distribuciÃ³n especificada no existe.'
            )
        );
    END IF;

    IF v_estado_orden != 'por_liquidar' THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo se pueden liquidar Ã³rdenes que estÃ©n en estado por_liquidar.'
            )
        );
    END IF;

    -- Verificar que exista una rendiciÃ³n aprobada vinculada a esta orden
    SELECT EXISTS (
        SELECT 1 
        FROM public.detalle_rendicion_ordenes dro
        JOIN public.rendiciones_cuentas rc ON dro.rendicion_id = rc.id
        WHERE dro.orden_distribucion_id = p_orden_id
          AND rc.estado = 'aprobada'
    ) INTO v_rendicion_aprobada;

    IF NOT v_rendicion_aprobada THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'COBRANZA_PENDIENTE',
                'message', 'La orden no tiene una rendiciÃ³n de cuentas aprobada vinculada.'
            )
        );
    END IF;

    -- A. Reingresar mercancÃ­a devuelta/rechazada de inventario mÃ³vil al almacÃ©n principal
    FOR v_det IN 
        SELECT producto_id, (cantidad_solicitada - COALESCE(cantidad_despachada, 0)) AS cantidad_devuelta
        FROM public.detalle_distribucion
        WHERE orden_id = p_orden_id AND (cantidad_solicitada - COALESCE(cantidad_despachada, 0)) > 0
    LOOP
        UPDATE public.inventario_almacen
        SET stock_disponible = stock_disponible + v_det.cantidad_devuelta,
            updated_at = NOW()
        WHERE producto_id = v_det.producto_id;

        UPDATE public.inventario_movil
        SET cantidad_devolucion = GREATEST(0, cantidad_devolucion - v_det.cantidad_devuelta),
            updated_at = NOW()
        WHERE camion_id = v_camion_id AND producto_id = v_det.producto_id;
    END LOOP;

    -- B. Trasladar envases retirados provisionales de detalle_distribucion a movimientos_contenedores y actualizar saldo
    FOR v_det IN
        SELECT contenedor_id, SUM(contenedores_retirados) AS total_retirados
        FROM public.detalle_distribucion
        WHERE orden_id = p_orden_id AND contenedor_id IS NOT NULL AND contenedores_retirados > 0
        GROUP BY contenedor_id
    LOOP
        -- Insertar auditorÃ­a oficial de movimiento de contenedores
        INSERT INTO public.movimientos_contenedores (
            cliente_id,
            orden_id,
            contenedor_id,
            cantidad_entregada,
            cantidad_retirada,
            creado_por,
            created_at
        ) VALUES (
            v_cliente_id,
            p_orden_id,
            v_det.contenedor_id,
            0,
            v_det.total_retirados,
            auth.uid(),
            NOW()
        );

        -- Rebajar el saldo del cliente
        INSERT INTO public.saldo_contenedores_clientes (
            cliente_id,
            contenedor_id,
            saldo_pendiente,
            updated_at
        ) VALUES (
            v_cliente_id,
            v_det.contenedor_id,
            0,
            NOW()
        )
        ON CONFLICT (cliente_id, contenedor_id)
        DO UPDATE SET
            saldo_pendiente = GREATEST(0, saldo_contenedores_clientes.saldo_pendiente - v_det.total_retirados),
            updated_at = NOW();
    END LOOP;

    -- C. Liberar camiÃ³n y chofer
    UPDATE public.camiones SET estado = 'disponible' WHERE id = v_camion_id;
    UPDATE public.choferes SET estado = 'disponible' WHERE perfil_id = v_chofer_id;

    -- D. Transicionar orden a 'liquidada'
    UPDATE public.ordenes_distribucion SET estado = 'liquidada' WHERE id = p_orden_id;

    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'orden_id', p_orden_id,
            'nuevo_estado', 'liquidada'
        ),
        'error', NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'SQL_ERROR',
                'message', SQLERRM,
                'details', 'SQLSTATE: ' || SQLSTATE
            )
        );
END;
$$;
-- MigraciÃ³n para el procedimiento aprobar_despacho_orden_distribucion y separaciÃ³n de flujo fÃ­sico vs financiero

-- 1. ActualizaciÃ³n de restricciones CHECK en ordenes_distribucion si aplica
DO $$
BEGIN
    ALTER TABLE public.ordenes_distribucion DROP CONSTRAINT IF EXISTS ordenes_distribucion_estado_check;
    ALTER TABLE public.ordenes_distribucion ADD CONSTRAINT ordenes_distribucion_estado_check 
        CHECK (estado IN ('borrador', 'aprobada', 'en_transito', 'despachada', 'por_liquidar', 'liquidada', 'anulada'));
EXCEPTION
    WHEN OTHERS THEN NULL;
END $$;

-- 2. RPC aprobar_despacho_orden_distribucion (AprobaciÃ³n fÃ­sica de almacÃ©n / gerencia)
CREATE OR REPLACE FUNCTION public.aprobar_despacho_orden_distribucion(
    p_orden_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_estado_orden TEXT;
    v_cliente_id UUID;
    v_camion_id UUID;
    v_det RECORD;
    v_pendientes_count INT;
BEGIN
    IF p_orden_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El parÃ¡metro p_orden_id es obligatorio.'
            )
        );
    END IF;

    SELECT estado, cliente_id, camion_id
    INTO v_estado_orden, v_cliente_id, v_camion_id
    FROM public.ordenes_distribucion
    WHERE id = p_orden_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'ORDEN_INEXISTENTE',
                'message', 'No se encontrÃ³ la orden de distribuciÃ³n especificada.'
            )
        );
    END IF;

    IF v_estado_orden NOT IN ('en_transito', 'despachada') THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo se puede aprobar el despacho de Ã³rdenes en estado en_transito o despachada.',
                'details', 'Estado actual: ' || v_estado_orden
            )
        );
    END IF;

    SELECT COUNT(*) INTO v_pendientes_count
    FROM public.detalle_distribucion
    WHERE orden_id = p_orden_id AND (estado_entrega IS NULL OR estado_entrega = 'pendiente');

    IF v_pendientes_count > 0 THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'ENTREGA_INCOMPLETA',
                'message', 'La orden aÃºn tiene productos pendientes por despachar en el radar.',
                'details', 'LÃ­neas pendientes: ' || v_pendientes_count
            )
        );
    END IF;

    -- A. Reingresar mercancÃ­a devuelta del inventario mÃ³vil al almacÃ©n principal
    FOR v_det IN 
        SELECT producto_id, (cantidad_solicitada - COALESCE(cantidad_despachada, 0)) AS cantidad_devuelta
        FROM public.detalle_distribucion
        WHERE orden_id = p_orden_id AND (cantidad_solicitada - COALESCE(cantidad_despachada, 0)) > 0
    LOOP
        UPDATE public.inventario_almacen
        SET stock_disponible = stock_disponible + v_det.cantidad_devuelta,
            updated_at = NOW()
        WHERE producto_id = v_det.producto_id;

        UPDATE public.inventario_movil
        SET cantidad_devolucion = GREATEST(0, cantidad_devolucion - v_det.cantidad_devuelta),
            updated_at = NOW()
        WHERE camion_id = v_camion_id AND producto_id = v_det.producto_id;
    END LOOP;

    -- B. Trasladar envases retirados provisionales de detalle_distribucion a movimientos_contenedores y actualizar saldo del cliente
    FOR v_det IN
        SELECT contenedor_id, SUM(contenedores_retirados) AS total_retirados
        FROM public.detalle_distribucion
        WHERE orden_id = p_orden_id AND contenedor_id IS NOT NULL AND contenedores_retirados > 0
        GROUP BY contenedor_id
    LOOP
        INSERT INTO public.movimientos_contenedores (
            cliente_id,
            orden_id,
            contenedor_id,
            cantidad_entregada,
            cantidad_retirada,
            creado_por,
            created_at
        ) VALUES (
            v_cliente_id,
            p_orden_id,
            v_det.contenedor_id,
            0,
            v_det.total_retirados,
            auth.uid(),
            NOW()
        );

        INSERT INTO public.saldo_contenedores_clientes (
            cliente_id,
            contenedor_id,
            saldo_pendiente,
            updated_at
        ) VALUES (
            v_cliente_id,
            v_det.contenedor_id,
            0,
            NOW()
        )
        ON CONFLICT (cliente_id, contenedor_id)
        DO UPDATE SET
            saldo_pendiente = GREATEST(0, saldo_contenedores_clientes.saldo_pendiente - v_det.total_retirados),
            updated_at = NOW();
    END LOOP;

    -- C. Transicionar el estado de la orden a 'por_liquidar'
    UPDATE public.ordenes_distribucion
    SET estado = 'por_liquidar'
    WHERE id = p_orden_id;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Despacho de orden aprobado exitosamente. Orden pasa a estado por_liquidar.',
        'data', jsonb_build_object(
            'orden_id', p_orden_id,
            'nuevo_estado', 'por_liquidar'
        )
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', SQLSTATE,
                'message', SQLERRM
            )
        );
END;
$$;

COMMENT ON FUNCTION public.aprobar_despacho_orden_distribucion(UUID) IS 'Aprueba el despacho fÃ­sico de la orden al cierre de dÃ­a, ajusta inventarios de almacÃ©n, registra movimientos de envases retirados y transiciona a por_liquidar';

-- 3. Actualizar registrar_despacho_cliente_radar para transicionar a despachada
CREATE OR REPLACE FUNCTION public.registrar_despacho_cliente_radar(
    p_orden_id UUID,
    p_detalles_json JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_estado_orden TEXT;
    v_camion_id UUID;
    v_item JSONB;
    v_detalle_id UUID;
    v_cantidad_despachada INT;
    v_estado_entrega TEXT;
    v_motivo_rechazo TEXT;
    v_contenedores_retirados INT;
    v_contenedor_id UUID;
    v_producto_id UUID;
    v_cantidad_solicitada INT;
    v_devolucion INT;
    v_pendientes_count INT;
BEGIN
    IF p_orden_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El parÃ¡metro p_orden_id es obligatorio.'
            )
        );
    END IF;

    SELECT estado, camion_id INTO v_estado_orden, v_camion_id
    FROM public.ordenes_distribucion
    WHERE id = p_orden_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'ORDEN_INEXISTENTE',
                'message', 'No se encontrÃ³ la orden especificada.'
            )
        );
    END IF;

    IF v_estado_orden NOT IN ('en_transito', 'despachada') THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo se pueden registrar entregas de Ã³rdenes en estado en_transito o despachada.'
            )
        );
    END IF;

    IF p_detalles_json IS NOT NULL AND jsonb_array_length(p_detalles_json) > 0 THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(p_detalles_json) LOOP
            v_detalle_id := (v_item->>'detalle_id')::UUID;
            v_cantidad_despachada := (v_item->>'cantidad_despachada')::INT;
            v_estado_entrega := v_item->>'estado_entrega';
            v_motivo_rechazo := v_item->>'motivo_rechazo';
            v_contenedores_retirados := COALESCE((v_item->>'contenedores_retirados')::INT, 0);
            v_contenedor_id := (v_item->>'contenedor_id')::UUID;

            SELECT producto_id, cantidad_solicitada INTO v_producto_id, v_cantidad_solicitada
            FROM public.detalle_distribucion
            WHERE id = v_detalle_id AND orden_id = p_orden_id;

            IF FOUND THEN
                v_devolucion := GREATEST(0, v_cantidad_solicitada - v_cantidad_despachada);

                UPDATE public.inventario_movil
                SET cantidad_cargada = GREATEST(0, cantidad_cargada - v_cantidad_solicitada),
                    cantidad_entregada = cantidad_entregada + v_cantidad_despachada,
                    cantidad_devolucion = cantidad_devolucion + v_devolucion,
                    updated_at = NOW()
                WHERE camion_id = v_camion_id AND producto_id = v_producto_id;

                UPDATE public.detalle_distribucion
                SET cantidad_despachada = v_cantidad_despachada,
                    estado_entrega = v_estado_entrega,
                    motivo_rechazo = v_motivo_rechazo,
                    contenedores_retirados = v_contenedores_retirados,
                    contenedor_id = v_contenedor_id
                WHERE id = v_detalle_id;
            END IF;
        END LOOP;
    END IF;

    SELECT COUNT(*) INTO v_pendientes_count
    FROM public.detalle_distribucion
    WHERE orden_id = p_orden_id AND (estado_entrega IS NULL OR estado_entrega = 'pendiente');

    IF v_pendientes_count = 0 THEN
        UPDATE public.ordenes_distribucion
        SET estado = 'despachada'
        WHERE id = p_orden_id;
        v_estado_orden := 'despachada';
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Despacho registrado en radar exitosamente.',
        'data', jsonb_build_object(
            'orden_id', p_orden_id,
            'nuevo_estado_orden', v_estado_orden
        )
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', SQLSTATE,
                'message', SQLERRM
            )
        );
END;
$$;

-- 4. Actualizar liquidar_orden_distribucion (LiquidaciÃ³n financiera)
CREATE OR REPLACE FUNCTION public.liquidar_orden_distribucion(
    p_orden_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_estado_orden TEXT;
    v_cliente_id UUID;
    v_camion_id UUID;
    v_chofer_id UUID;
    v_rendicion_aprobada BOOLEAN := FALSE;
BEGIN
    IF p_orden_id IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID de la orden es requerido.'
            )
        );
    END IF;

    SELECT estado, cliente_id, camion_id, chofer_id
    INTO v_estado_orden, v_cliente_id, v_camion_id, v_chofer_id
    FROM public.ordenes_distribucion
    WHERE id = p_orden_id;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'ORDEN_INEXISTENTE',
                'message', 'La orden de distribuciÃ³n especificada no existe.'
            )
        );
    END IF;

    IF v_estado_orden != 'por_liquidar' THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo se pueden liquidar financieramente Ã³rdenes que estÃ©n en estado por_liquidar.'
            )
        );
    END IF;

    SELECT EXISTS (
        SELECT 1 
        FROM public.detalle_rendicion_ordenes dro
        JOIN public.rendiciones_cuentas rc ON dro.rendicion_id = rc.id
        WHERE dro.orden_distribucion_id = p_orden_id
          AND rc.estado = 'aprobada'
    ) INTO v_rendicion_aprobada;

    IF NOT v_rendicion_aprobada THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'COBRANZA_PENDIENTE',
                'message', 'La orden no tiene una rendiciÃ³n de cuentas aprobada vinculada.'
            )
        );
    END IF;

    UPDATE public.camiones SET estado = 'disponible' WHERE id = v_camion_id;
    UPDATE public.choferes SET estado = 'disponible' WHERE perfil_id = v_chofer_id;

    UPDATE public.ordenes_distribucion SET estado = 'liquidada' WHERE id = p_orden_id;

    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'orden_id', p_orden_id,
            'nuevo_estado', 'liquidada'
        ),
        'error', NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'SQL_ERROR',
                'message', SQLERRM,
                'details', 'SQLSTATE: ' || SQLSTATE
            )
        );
END;
$$;
-- MigraciÃ³n Tarea DB-025: Agregar campo imagen_path a productos y perfiles_usuario

-- 1. Agregar columna imagen_path a productos
ALTER TABLE public.productos
ADD COLUMN IF NOT EXISTS imagen_path TEXT;

COMMENT ON COLUMN public.productos.imagen_path IS 'Ruta relativa de la imagen del producto en el almacenamiento de archivos (ej: /productos/harina-pan.webp)';

-- 2. Agregar columna imagen_path a perfiles_usuario
ALTER TABLE public.perfiles_usuario
ADD COLUMN IF NOT EXISTS imagen_path TEXT;

COMMENT ON COLUMN public.perfiles_usuario.imagen_path IS 'Ruta relativa del avatar o fotografÃ­a del usuario en el almacenamiento de archivos (ej: /usuarios/avatar-001.webp)';

-- 3. Actualizar RPC retorna_lista_productos_segun_parametros para incluir imagen_path
CREATE OR REPLACE FUNCTION public.retorna_lista_productos_segun_parametros(
    p_busqueda TEXT DEFAULT NULL,
    p_activo BOOLEAN DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_resultado JSONB;
BEGIN
    SELECT jsonb_build_object(
        'success', TRUE,
        'total_registros', COUNT(p.id),
        'data', COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'id', p.id,
                    'codigo_producto', p.codigo_producto,
                    'nombre', p.nombre,
                    'codigo_barras', p.codigo_barras,
                    'precio_lista1', p.precio_lista1,
                    'precio_lista2', p.precio_lista2,
                    'precio_lista3', p.precio_lista3,
                    'imagen_path', p.imagen_path,
                    'created_at', p.created_at
                )
            ),
            '[]'::jsonb
        )
    ) INTO v_resultado
    FROM public.productos p
    WHERE (p_busqueda IS NULL OR p.nombre ILIKE '%' || p_busqueda || '%' OR p.codigo_producto ILIKE '%' || p_busqueda || '%')
      AND (p_activo IS NULL OR p.activo = p_activo);

    RETURN v_resultado;

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', SQLSTATE,
                'message', SQLERRM
            )
        );
END;
$$;

-- 4. Actualizar RPC retorna_radar_despachador para incluir imagen_path en los productos
CREATE OR REPLACE FUNCTION public.retorna_radar_despachador()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_despachador_id UUID;
    v_resultado JSONB;
BEGIN
    v_despachador_id := auth.uid();

    IF v_despachador_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'NO_AUTENTICADO',
                'message', 'El usuario no estÃ¡ autenticado.'
            )
        );
    END IF;

    SELECT jsonb_build_object(
        'success', TRUE,
        'total_ordenes', COUNT(o.id),
        'data', COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'orden_id', o.id,
                    'correlativo', o.correlativo,
                    'estado', o.estado,
                    'fecha_despacho', o.fecha_despacho,
                    'tasa_cambio', o.tasa_cambio,
                    'total_recaudar_bs', o.total_recaudar_bs,
                    'total_recaudar_usd', o.total_recaudar_usd,
                    'cliente', jsonb_build_object(
                        'id', c.id,
                        'razon_social', c.razon_social,
                        'rif_nit', c.rif_nit,
                        'direccion_fiscal', c.direccion_fiscal,
                        'telefono', c.telefono,
                        'movil1', c.movil1,
                        'nombre_ruta', r.nombre_ruta
                    ),
                    'detalles', (
                        SELECT COALESCE(jsonb_agg(
                            jsonb_build_object(
                                'detalle_id', d.id,
                                'producto_id', p.id,
                                'codigo_producto', p.codigo_producto,
                                'nombre_producto', p.nombre,
                                'imagen_path', p.imagen_path,
                                'cantidad_solicitada', d.cantidad_solicitada,
                                'cantidad_despachada', COALESCE(d.cantidad_despachada, 0),
                                'valor_unitario_recaudar', d.valor_unitario_recaudar,
                                'subtotal_recaudar', d.subtotal_recaudar,
                                'valor_unitario_usd', d.valor_unitario_usd,
                                'subtotal_recaudar_usd', d.subtotal_recaudar_usd,
                                'estado_entrega', COALESCE(d.estado_entrega, 'pendiente'),
                                'motivo_rechazo', d.motivo_rechazo,
                                'contenedores_retirados', COALESCE(d.contenedores_retirados, 0),
                                'contenedor_id', d.contenedor_id
                            )
                        ), '[]'::jsonb)
                        FROM public.detalle_distribucion d
                        JOIN public.productos p ON d.producto_id = p.id
                        WHERE d.orden_id = o.id
                    ),
                    'saldo_contenedores', (
                        SELECT COALESCE(jsonb_agg(
                            jsonb_build_object(
                                'contenedor_id', tc.id,
                                'nombre_contenedor', tc.nombre,
                                'saldo_pendiente', COALESCE(sc.saldo_pendiente, 0)
                            )
                        ), '[]'::jsonb)
                        FROM public.tipos_contenedores tc
                        LEFT JOIN public.saldo_contenedores_clientes sc ON sc.contenedor_id = tc.id AND sc.cliente_id = c.id
                    )
                )
            ),
            '[]'::jsonb
        )
    ) INTO v_resultado
    FROM public.ordenes_distribucion o
    JOIN public.clientes c ON o.cliente_id = c.id
    LEFT JOIN public.rutas r ON c.id_ruta = r.id_ruta
    WHERE c.despachador_id = v_despachador_id
      AND o.estado IN ('en_transito', 'despachada');

    RETURN v_resultado;

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', SQLSTATE,
                'message', SQLERRM
            )
        );
END;
$$;
-- Migration: Quitar FK chofer_id y actualizar crear_orden_distribucion sin p_chofer_id

-- 1. Quitar restricciones FK y UNIQUE de chofer_id en ordenes_distribucion
ALTER TABLE public.ordenes_distribucion DROP CONSTRAINT IF EXISTS ordenes_distribucion_chofer_id_fkey;
ALTER TABLE public.ordenes_distribucion DROP CONSTRAINT IF EXISTS ordenes_distribucion_chofer_id_key;
DROP INDEX IF EXISTS public.ordenes_distribucion_chofer_id_key;
ALTER TABLE public.ordenes_distribucion ALTER COLUMN chofer_id DROP NOT NULL;

-- 2. Asegurar existencia de columnas y FKs para vendedor_id, despachador_id e id_ruta en ordenes_distribucion
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'ordenes_distribucion' AND column_name = 'vendedor_id'
    ) THEN
        ALTER TABLE public.ordenes_distribucion ADD COLUMN vendedor_id UUID REFERENCES public.perfiles_usuario(id) ON DELETE SET NULL;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'ordenes_distribucion' AND column_name = 'despachador_id'
    ) THEN
        ALTER TABLE public.ordenes_distribucion ADD COLUMN despachador_id UUID REFERENCES public.perfiles_usuario(id) ON DELETE SET NULL;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'ordenes_distribucion' AND column_name = 'id_ruta'
    ) THEN
        ALTER TABLE public.ordenes_distribucion ADD COLUMN id_ruta UUID REFERENCES public.rutas(id_ruta) ON DELETE SET NULL;
    END IF;
END $$;

-- 3. Eliminar firmas anteriores de la funciÃ³n crear_orden_distribucion
DROP FUNCTION IF EXISTS public.crear_orden_distribucion(UUID, UUID, UUID, UUID, NUMERIC, JSONB);
DROP FUNCTION IF EXISTS public.crear_orden_distribucion(UUID, UUID, UUID, NUMERIC, JSONB);

-- 4. Recrear funciÃ³n crear_orden_distribucion sin p_chofer_id
CREATE OR REPLACE FUNCTION public.crear_orden_distribucion(
    p_vendedor_id UUID,
    p_cliente_id UUID,
    p_camion_id UUID,
    p_tasa_cambio NUMERIC DEFAULT NULL,
    p_productos_json JSONB DEFAULT '[]'::jsonb,
    p_despachador_id UUID DEFAULT NULL,
    p_id_ruta UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_orden_id UUID;
    v_correlativo INT;
    v_factura_origen VARCHAR(30);
    v_tasa_cambio NUMERIC(14,4);
    
    v_vendedor_id UUID;
    v_despachador_id UUID;
    v_id_ruta UUID;
    
    v_peso_total NUMERIC(10,2) := 0.00;
    v_total_recaudar_bs NUMERIC(14,2) := 0.00;
    v_total_recaudar_usd NUMERIC(14,2) := 0.00;
    
    v_item JSONB;
    v_secuencia INT := 1;
    v_producto_id UUID;
    v_cantidad INT;
    v_val_recaudar_bs NUMERIC(14,2);
    v_val_usd NUMERIC(14,2);
    v_subtotal_bs NUMERIC(14,2);
    v_subtotal_usd NUMERIC(14,2);
    v_peso_unitario NUMERIC(10,2);
BEGIN
    -- Validaciones bÃ¡sicas
    IF p_vendedor_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del vendedor es requerido.');
    END IF;

    IF p_cliente_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del cliente es requerido.');
    END IF;

    IF p_camion_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del camiÃ³n es requerido.');
    END IF;

    IF p_productos_json IS NULL OR jsonb_array_length(p_productos_json) = 0 THEN
        RETURN jsonb_build_object('success', false, 'message', 'Debe incluir al menos un producto en la orden.');
    END IF;

    -- Obtener informaciÃ³n del cliente (vendedor_id, despachador_id, id_ruta)
    SELECT c.vendedor_id, c.despachador_id, c.id_ruta
    INTO v_vendedor_id, v_despachador_id, v_id_ruta
    FROM public.clientes c
    WHERE c.id = p_cliente_id;

    -- Priorizar parÃ¡metros explÃ­citos si fueron proporcionados
    v_vendedor_id := COALESCE(p_vendedor_id, v_vendedor_id);
    v_despachador_id := COALESCE(p_despachador_id, v_despachador_id);
    v_id_ruta := COALESCE(p_id_ruta, v_id_ruta);

    -- Validar existencia de entidades
    IF NOT EXISTS (SELECT 1 FROM public.perfiles_usuario WHERE id = p_vendedor_id) THEN
        RETURN jsonb_build_object('success', false, 'message', 'El vendedor especificado no existe.');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.clientes WHERE id = p_cliente_id) THEN
        RETURN jsonb_build_object('success', false, 'message', 'El cliente especificado no existe.');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.camiones WHERE id = p_camion_id) THEN
        RETURN jsonb_build_object('success', false, 'message', 'El camiÃ³n especificado no existe.');
    END IF;

    -- Determinar / validar la tasa de cambio
    IF p_tasa_cambio IS NOT NULL AND p_tasa_cambio > 0 THEN
        v_tasa_cambio := p_tasa_cambio;
    ELSE
        SELECT tasa_cambio INTO v_tasa_cambio
        FROM public.tasa_cambio
        WHERE fecha_tasa = CURRENT_DATE;

        IF v_tasa_cambio IS NULL THEN
            SELECT tasa_cambio INTO v_tasa_cambio
            FROM public.tasa_cambio
            ORDER BY fecha_tasa DESC
            LIMIT 1;
        END IF;

        IF v_tasa_cambio IS NULL THEN
            RETURN jsonb_build_object(
                'success', false, 
                'message', 'No hay tasa de cambio registrada. Debe proporcionar p_tasa_cambio o registrar una tasa oficial en el sistema.'
            );
        END IF;
    END IF;

    -- Generar correlativo y nÃºmero de factura de origen automÃ¡ticamente
    v_correlativo := nextval('public.ordenes_distribucion_correlativo_seq');
    v_factura_origen := 'FAC-' || LPAD(v_correlativo::text, 6, '0');
    v_orden_id := gen_random_uuid();

    -- Validar productos y calcular totales multimoneda y peso total
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;
        
        IF v_cantidad IS NULL OR v_cantidad <= 0 THEN
            RETURN jsonb_build_object('success', false, 'message', 'La cantidad del producto debe ser mayor a cero.');
        END IF;

        SELECT peso_unitario_kg INTO v_peso_unitario
        FROM public.productos
        WHERE id = v_producto_id;

        IF NOT FOUND THEN
            RETURN jsonb_build_object('success', false, 'message', 'El producto con ID ' || v_producto_id::text || ' no existe.');
        END IF;

        v_val_recaudar_bs := COALESCE((v_item->>'valor_unitario_recaudar')::NUMERIC, (v_item->>'precio_unitario')::NUMERIC, 0.00);
        v_val_usd := COALESCE((v_item->>'valor_unitario_usd')::NUMERIC, 0.00);

        IF v_val_recaudar_bs > 0 AND (v_val_usd IS NULL OR v_val_usd = 0) THEN
            v_val_usd := ROUND(v_val_recaudar_bs / v_tasa_cambio, 2);
        ELSIF v_val_usd > 0 AND (v_val_recaudar_bs IS NULL OR v_val_recaudar_bs = 0) THEN
            v_val_recaudar_bs := ROUND(v_val_usd * v_tasa_cambio, 2);
        END IF;

        v_subtotal_bs := ROUND(v_cantidad * v_val_recaudar_bs, 2);
        v_subtotal_usd := ROUND(v_cantidad * v_val_usd, 2);

        v_peso_total := v_peso_total + (COALESCE(v_peso_unitario, 0.00) * v_cantidad);
        v_total_recaudar_bs := v_total_recaudar_bs + v_subtotal_bs;
        v_total_recaudar_usd := v_total_recaudar_usd + v_subtotal_usd;
    END LOOP;

    -- Insertar Cabecera de la Orden
    INSERT INTO public.ordenes_distribucion (
        id,
        correlativo,
        cliente_id,
        camion_id,
        chofer_id,
        vendedor_id,
        despachador_id,
        id_ruta,
        estado,
        fecha_despacho,
        peso_total_calculado,
        factura_origen_numero,
        creado_por,
        created_at,
        tasa_cambio,
        total_recaudar_bs,
        total_recaudar_usd
    ) VALUES (
        v_orden_id,
        v_correlativo,
        p_cliente_id,
        p_camion_id,
        NULL, -- chofer_id ya no es obligatorio al crear la orden
        v_vendedor_id,
        v_despachador_id,
        v_id_ruta,
        'borrador',
        NULL,
        v_peso_total,
        v_factura_origen,
        p_vendedor_id,
        NOW(),
        v_tasa_cambio,
        v_total_recaudar_bs,
        v_total_recaudar_usd
    );

    -- Insertar Detalles de la Orden
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;
        
        v_val_recaudar_bs := COALESCE((v_item->>'valor_unitario_recaudar')::NUMERIC, (v_item->>'precio_unitario')::NUMERIC, 0.00);
        v_val_usd := COALESCE((v_item->>'valor_unitario_usd')::NUMERIC, 0.00);

        IF v_val_recaudar_bs > 0 AND (v_val_usd IS NULL OR v_val_usd = 0) THEN
            v_val_usd := ROUND(v_val_recaudar_bs / v_tasa_cambio, 2);
        ELSIF v_val_usd > 0 AND (v_val_recaudar_bs IS NULL OR v_val_recaudar_bs = 0) THEN
            v_val_recaudar_bs := ROUND(v_val_usd * v_tasa_cambio, 2);
        END IF;

        v_subtotal_bs := ROUND(v_cantidad * v_val_recaudar_bs, 2);
        v_subtotal_usd := ROUND(v_cantidad * v_val_usd, 2);

        INSERT INTO public.detalle_distribucion (
            id,
            orden_id,
            producto_id,
            cantidad_solicitada,
            cantidad_despachada,
            valor_unitario_recaudar,
            subtotal_recaudar,
            secuencia_entrega,
            estado_entrega,
            motivo_rechazo,
            valor_unitario_usd,
            subtotal_recaudar_usd
        ) VALUES (
            gen_random_uuid(),
            v_orden_id,
            v_producto_id,
            v_cantidad,
            0,
            v_val_recaudar_bs,
            v_subtotal_bs,
            v_secuencia,
            'pendiente',
            NULL,
            v_val_usd,
            v_subtotal_usd
        );
        
        v_secuencia := v_secuencia + 1;
    END LOOP;

    RETURN jsonb_build_object(
        'success', true, 
        'message', 'Orden de distribuciÃ³n creada exitosamente.', 
        'orden_id', v_orden_id,
        'data', jsonb_build_object(
            'orden_id', v_orden_id,
            'correlativo', v_correlativo,
            'tasa_cambio', v_tasa_cambio,
            'total_recaudar_bs', v_total_recaudar_bs,
            'total_recaudar_usd', v_total_recaudar_usd,
            'peso_total_calculado', v_peso_total
        )
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false, 
        'message', 'Error al crear la orden: ' || SQLERRM
    );
END;
$$;
-- MigraciÃ³n para el MÃ³dulo de Control de Radares por Despachador (SecciÃ³n 4 de PROPOSICION-CAMBIOS-DB.md)

-- 1. Tabla Maestra de Radares (public.radars)
CREATE TABLE IF NOT EXISTS public.radars (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    correlativo SERIAL UNIQUE,
    despachador_id UUID NOT NULL REFERENCES public.perfiles_usuario(id) ON DELETE RESTRICT,
    fecha_despacho DATE NOT NULL DEFAULT CURRENT_DATE,
    total_cantidad_solicitada NUMERIC(10,0) DEFAULT 0,
    total_cantidad_despachada NUMERIC(10,0) DEFAULT 0,
    total_contenedores_retirados NUMERIC(10,0) DEFAULT 0,
    status_radar BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Ãndices de optimizaciÃ³n para la tabla radars
CREATE INDEX IF NOT EXISTS idx_radars_despachador_fecha ON public.radars(despachador_id, fecha_despacho);
CREATE INDEX IF NOT EXISTS idx_radars_status ON public.radars(status_radar);

-- 2. RelaciÃ³n en Cabecera de Orden (ordenes_distribucion.radar_id)
ALTER TABLE public.ordenes_distribucion
ADD COLUMN IF NOT EXISTS radar_id UUID REFERENCES public.radars(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_ordenes_distribucion_radar_id ON public.ordenes_distribucion(radar_id);

-- 3. Habilitar RLS en public.radars
ALTER TABLE public.radars ENABLE ROW LEVEL SECURITY;

-- PolÃ­ticas RLS para public.radars
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'radars' AND policyname = 'Permitir lectura de radares a usuarios autenticados'
    ) THEN
        CREATE POLICY "Permitir lectura de radares a usuarios autenticados" 
        ON public.radars FOR SELECT 
        TO authenticated 
        USING (true);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'radars' AND policyname = 'Permitir insercion y actualizacion de radares a usuarios autenticados'
    ) THEN
        CREATE POLICY "Permitir insercion y actualizacion de radares a usuarios autenticados" 
        ON public.radars FOR ALL 
        TO authenticated 
        USING (true) 
        WITH CHECK (true);
    END IF;
END $$;


-- =============================================================================
-- 4. PROCEDIMIENTOS ALMACENADOS (RPC)
-- =============================================================================

-- 4.1 RPC: crear_o_obtener_radar
CREATE OR REPLACE FUNCTION public.crear_o_obtener_radar(
    p_despachador_id UUID DEFAULT NULL,
    p_fecha_despacho DATE DEFAULT CURRENT_DATE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_despachador_id UUID;
    v_radar_id UUID;
    v_correlativo INT;
    v_status_radar BOOLEAN;
    v_tot_solicitada NUMERIC(10,0);
    v_tot_despachada NUMERIC(10,0);
    v_tot_retirados NUMERIC(10,0);
    v_total_ordenes INT;
    v_resultado JSONB;
BEGIN
    v_despachador_id := COALESCE(p_despachador_id, auth.uid());

    IF v_despachador_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_REQUERIDO',
                'message', 'Se requiere especificar un despachador_id o estar autenticado.'
            )
        );
    END IF;

    -- Verificar si existe un radar para este despachador y fecha
    SELECT id, correlativo, status_radar
    INTO v_radar_id, v_correlativo, v_status_radar
    FROM public.radars
    WHERE despachador_id = v_despachador_id
      AND fecha_despacho = p_fecha_despacho
    ORDER BY created_at DESC
    LIMIT 1;

    -- Si no existe, crearlo
    IF v_radar_id IS NULL THEN
        INSERT INTO public.radars (despachador_id, fecha_despacho, status_radar)
        VALUES (v_despachador_id, p_fecha_despacho, FALSE)
        RETURNING id, correlativo, status_radar INTO v_radar_id, v_correlativo, v_status_radar;
    END IF;

    -- Asociar las Ã³rdenes del despachador de esa fecha al radar (si no tienen radar asignado)
    UPDATE public.ordenes_distribucion o
    SET radar_id = v_radar_id
    FROM public.clientes c
    WHERE o.cliente_id = c.id
      AND c.despachador_id = v_despachador_id
      AND o.fecha_despacho::date = p_fecha_despacho
      AND o.estado IN ('aprobada', 'en_transito', 'por_liquidar', 'liquidada')
      AND (o.radar_id IS NULL OR o.radar_id = v_radar_id);

    -- Recalcular totales del radar
    SELECT 
        COALESCE(SUM(d.cantidad_solicitada), 0),
        COALESCE(SUM(d.cantidad_despachada), 0),
        COALESCE(SUM(d.contenedores_retirados), 0),
        COUNT(DISTINCT o.id)
    INTO v_tot_solicitada, v_tot_despachada, v_tot_retirados, v_total_ordenes
    FROM public.ordenes_distribucion o
    JOIN public.detalle_distribucion d ON d.orden_id = o.id
    WHERE o.radar_id = v_radar_id;

    UPDATE public.radars
    SET total_cantidad_solicitada = v_tot_solicitada,
        total_cantidad_despachada = v_tot_despachada,
        total_contenedores_retirados = v_tot_retirados
    WHERE id = v_radar_id;

    SELECT jsonb_build_object(
        'success', TRUE,
        'message', 'Radar obtenido/creado exitosamente.',
        'data', jsonb_build_object(
            'id', v_radar_id,
            'correlativo', v_correlativo,
            'despachador_id', v_despachador_id,
            'fecha_despacho', p_fecha_despacho,
            'status_radar', v_status_radar,
            'total_cantidad_solicitada', v_tot_solicitada,
            'total_cantidad_despachada', v_tot_despachada,
            'total_contenedores_retirados', v_tot_retirados,
            'total_ordenes', v_total_ordenes
        )
    ) INTO v_resultado;

    RETURN v_resultado;
END;
$$;


-- 4.2 RPC: retorna_radar_detalle_reporte
CREATE OR REPLACE FUNCTION public.retorna_radar_detalle_reporte(
    p_radar_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_radar RECORD;
    v_despachador RECORD;
    v_resumen_productos JSONB;
    v_ordenes JSONB;
    v_resultado JSONB;
BEGIN
    -- 1. Obtener la cabecera del radar
    SELECT r.id, r.correlativo, r.despachador_id, r.fecha_despacho,
           r.total_cantidad_solicitada, r.total_cantidad_despachada,
           r.total_contenedores_retirados, r.status_radar, r.created_at
    INTO v_radar
    FROM public.radars r
    WHERE r.id = p_radar_id;

    IF v_radar.id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'RADAR_INEXISTENTE',
                'message', 'No se encontrÃ³ el radar especificado.'
            )
        );
    END IF;

    -- 2. Obtener datos del despachador
    SELECT pu.id, pu.nombre_completo, pu.telefono, u.email AS correo_e
    INTO v_despachador
    FROM public.perfiles_usuario pu
    LEFT JOIN auth.users u ON pu.id = u.id
    WHERE pu.id = v_radar.despachador_id;

    -- 3. Consolidado de productos solicitados/despachados en este radar (Reporte global de carga)
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'producto_id', sub.producto_id,
                'codigo_producto', sub.codigo_producto,
                'nombre_producto', sub.nombre_producto,
                'imagen_path', sub.imagen_path,
                'cantidad_solicitada', sub.cantidad_solicitada,
                'cantidad_despachada', sub.cantidad_despachada
            )
        ),
        '[]'::jsonb
    )
    INTO v_resumen_productos
    FROM (
        SELECT p.id AS producto_id,
               p.codigo_producto,
               p.nombre AS nombre_producto,
               p.imagen_path,
               SUM(d.cantidad_solicitada) AS cantidad_solicitada,
               SUM(COALESCE(d.cantidad_despachada, 0)) AS cantidad_despachada
        FROM public.ordenes_distribucion o
        JOIN public.detalle_distribucion d ON d.orden_id = o.id
        JOIN public.productos p ON d.producto_id = p.id
        WHERE o.radar_id = p_radar_id
        GROUP BY p.id, p.codigo_producto, p.nombre, p.imagen_path
    ) sub;

    -- 4. Detalle orden por orden
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'orden_id', o.id,
                'correlativo', o.correlativo,
                'estado', o.estado,
                'fecha_despacho', o.fecha_despacho,
                'tasa_cambio', o.tasa_cambio,
                'total_recaudar_bs', o.total_recaudar_bs,
                'total_recaudar_usd', o.total_recaudar_usd,
                'cliente', jsonb_build_object(
                    'id', c.id,
                    'razon_social', c.razon_social,
                    'rif_nit', c.rif_nit,
                    'direccion_fiscal', c.direccion_fiscal,
                    'telefono', c.telefono,
                    'movil1', c.movil1,
                    'nombre_ruta', rut.nombre_ruta
                ),
                'detalles', (
                    SELECT COALESCE(jsonb_agg(
                        jsonb_build_object(
                            'detalle_id', d.id,
                            'producto_id', p.id,
                            'codigo_producto', p.codigo_producto,
                            'nombre_producto', p.nombre,
                            'imagen_path', p.imagen_path,
                            'cantidad_solicitada', d.cantidad_solicitada,
                            'cantidad_despachada', COALESCE(d.cantidad_despachada, 0),
                            'valor_unitario_recaudar', d.valor_unitario_recaudar,
                            'subtotal_recaudar', d.subtotal_recaudar,
                            'valor_unitario_usd', d.valor_unitario_usd,
                            'subtotal_recaudar_usd', d.subtotal_recaudar_usd,
                            'estado_entrega', COALESCE(d.estado_entrega, 'pendiente'),
                            'motivo_rechazo', d.motivo_rechazo,
                            'contenedores_retirados', COALESCE(d.contenedores_retirados, 0),
                            'contenedor_id', d.contenedor_id
                        )
                    ), '[]'::jsonb)
                    FROM public.detalle_distribucion d
                    JOIN public.productos p ON d.producto_id = p.id
                    WHERE d.orden_id = o.id
                )
            )
        ),
        '[]'::jsonb
    )
    INTO v_ordenes
    FROM public.ordenes_distribucion o
    JOIN public.clientes c ON o.cliente_id = c.id
    LEFT JOIN public.rutas rut ON c.id_ruta = rut.id_ruta
    WHERE o.radar_id = p_radar_id;

    SELECT jsonb_build_object(
        'success', TRUE,
        'data', jsonb_build_object(
            'radar', jsonb_build_object(
                'id', v_radar.id,
                'correlativo', v_radar.correlativo,
                'fecha_despacho', v_radar.fecha_despacho,
                'status_radar', v_radar.status_radar,
                'total_cantidad_solicitada', v_radar.total_cantidad_solicitada,
                'total_cantidad_despachada', v_radar.total_cantidad_despachada,
                'total_contenedores_retirados', v_radar.total_contenedores_retirados,
                'created_at', v_radar.created_at
            ),
            'despachador', jsonb_build_object(
                'id', v_despachador.id,
                'nombre_completo', v_despachador.nombre_completo,
                'telefono', v_despachador.telefono,
                'correo_e', v_despachador.correo_e
            ),
            'resumen_productos', v_resumen_productos,
            'ordenes', v_ordenes
        )
    ) INTO v_resultado;

    RETURN v_resultado;
END;
$$;


-- 4.3 RPC: reasignar_orden_a_radar
CREATE OR REPLACE FUNCTION public.reasignar_orden_a_radar(
    p_orden_id UUID,
    p_nuevo_radar_id UUID DEFAULT NULL,
    p_nueva_fecha DATE DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_radar_anterior_id UUID;
    v_estado_orden TEXT;
BEGIN
    SELECT radar_id, estado INTO v_radar_anterior_id, v_estado_orden
    FROM public.ordenes_distribucion
    WHERE id = p_orden_id;

    IF v_radar_anterior_id IS NULL AND v_estado_orden IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'ORDEN_INEXISTENTE',
                'message', 'La orden especificada no existe.'
            )
        );
    END IF;

    IF v_estado_orden = 'liquidada' THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'ORDEN_LIQUIDADA',
                'message', 'No se puede reasignar una orden que ya ha sido liquidada.'
            )
        );
    END IF;

    -- Actualizar la orden
    UPDATE public.ordenes_distribucion
    SET radar_id = p_nuevo_radar_id,
        fecha_despacho = COALESCE(p_nueva_fecha::timestamptz, fecha_despacho)
    WHERE id = p_orden_id;

    -- Recalcular totales en el radar anterior si existÃ­a
    IF v_radar_anterior_id IS NOT NULL THEN
        UPDATE public.radars
        SET total_cantidad_solicitada = (
                SELECT COALESCE(SUM(d.cantidad_solicitada), 0)
                FROM public.ordenes_distribucion o
                JOIN public.detalle_distribucion d ON d.orden_id = o.id
                WHERE o.radar_id = v_radar_anterior_id
            ),
            total_cantidad_despachada = (
                SELECT COALESCE(SUM(d.cantidad_despachada), 0)
                FROM public.ordenes_distribucion o
                JOIN public.detalle_distribucion d ON d.orden_id = o.id
                WHERE o.radar_id = v_radar_anterior_id
            ),
            total_contenedores_retirados = (
                SELECT COALESCE(SUM(d.contenedores_retirados), 0)
                FROM public.ordenes_distribucion o
                JOIN public.detalle_distribucion d ON d.orden_id = o.id
                WHERE o.radar_id = v_radar_anterior_id
            )
        WHERE id = v_radar_anterior_id;
    END IF;

    -- Recalcular totales en el nuevo radar si existe
    IF p_nuevo_radar_id IS NOT NULL THEN
        UPDATE public.radars
        SET total_cantidad_solicitada = (
                SELECT COALESCE(SUM(d.cantidad_solicitada), 0)
                FROM public.ordenes_distribucion o
                JOIN public.detalle_distribucion d ON d.orden_id = o.id
                WHERE o.radar_id = p_nuevo_radar_id
            ),
            total_cantidad_despachada = (
                SELECT COALESCE(SUM(d.cantidad_despachada), 0)
                FROM public.ordenes_distribucion o
                JOIN public.detalle_distribucion d ON d.orden_id = o.id
                WHERE o.radar_id = p_nuevo_radar_id
            ),
            total_contenedores_retirados = (
                SELECT COALESCE(SUM(d.contenedores_retirados), 0)
                FROM public.ordenes_distribucion o
                JOIN public.detalle_distribucion d ON d.orden_id = o.id
                WHERE o.radar_id = p_nuevo_radar_id
            )
        WHERE id = p_nuevo_radar_id;
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Orden reasignada exitosamente.',
        'data', jsonb_build_object(
            'orden_id', p_orden_id,
            'radar_id', p_nuevo_radar_id,
            'fecha_despacho', p_nueva_fecha
        )
    );
END;
$$;


-- 4.4 RPC: guardar_resultado_despacho_radar
CREATE OR REPLACE FUNCTION public.guardar_resultado_despacho_radar(
    p_radar_id UUID,
    p_despacho_json JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_orden RECORD;
    v_detalle RECORD;
    v_cliente_id UUID;
    v_contenedor_id UUID;
    v_cant_entregada INT;
    v_cant_retirada INT;
    v_tot_solicitada NUMERIC(10,0);
    v_tot_despachada NUMERIC(10,0);
    v_tot_retirados NUMERIC(10,0);
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.radars WHERE id = p_radar_id) THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'RADAR_INEXISTENTE',
                'message', 'El radar especificado no existe.'
            )
        );
    END IF;

    -- Procesar cada orden entregada en el JSON
    FOR v_orden IN SELECT * FROM jsonb_to_recordset(p_despacho_json->'ordenes') AS x(orden_id UUID, detalles JSONB)
    LOOP
        -- Obtener el cliente de la orden
        SELECT cliente_id INTO v_cliente_id
        FROM public.ordenes_distribucion
        WHERE id = v_orden.orden_id;

        IF v_cliente_id IS NOT NULL THEN
            -- Recorrer detalles de la orden
            FOR v_detalle IN SELECT * FROM jsonb_to_recordset(v_orden.detalles) AS d(
                detalle_id UUID,
                cantidad_despachada NUMERIC,
                estado_entrega TEXT,
                motivo_rechazo TEXT,
                contenedores_retirados INT,
                contenedor_id UUID
            )
            LOOP
                -- Actualizar el renglÃ³n en detalle_distribucion
                UPDATE public.detalle_distribucion
                SET cantidad_despachada = COALESCE(v_detalle.cantidad_despachada, 0),
                    estado_entrega = COALESCE(v_detalle.estado_entrega, 'entregado'),
                    motivo_rechazo = v_detalle.motivo_rechazo,
                    contenedores_retirados = COALESCE(v_detalle.contenedores_retirados, 0),
                    contenedor_id = v_detalle.contenedor_id
                WHERE id = v_detalle.detalle_id;

                -- Identificar contenedor asociado al producto si no vino explÃ­cito
                v_contenedor_id := v_detalle.contenedor_id;
                IF v_contenedor_id IS NULL THEN
                    SELECT p.contenedor_id INTO v_contenedor_id
                    FROM public.detalle_distribucion dd
                    JOIN public.productos p ON dd.producto_id = p.id
                    WHERE dd.id = v_detalle.detalle_id;
                END IF;

                -- Calcular movimiento de contenedores
                IF v_contenedor_id IS NOT NULL THEN
                    v_cant_entregada := COALESCE(v_detalle.cantidad_despachada, 0)::INT;
                    v_cant_retirada := COALESCE(v_detalle.contenedores_retirados, 0);

                    IF v_cant_entregada > 0 OR v_cant_retirada > 0 THEN
                        INSERT INTO public.movimientos_contenedores (
                            cliente_id, orden_id, contenedor_id, cantidad_entregada, cantidad_retirada, creado_por
                        ) VALUES (
                            v_cliente_id, v_orden.orden_id, v_contenedor_id, v_cant_entregada, v_cant_retirada, auth.uid()
                        );
                    END IF;
                END IF;
            END LOOP;

            -- Actualizar estado de la orden a 'por_liquidar'
            UPDATE public.ordenes_distribucion
            SET estado = 'por_liquidar'
            WHERE id = v_orden.orden_id
              AND estado IN ('en_transito', 'aprobada');
        END IF;
    END LOOP;

    -- Actualizar totales globales del Radar y marcar status_radar = TRUE (.T.)
    SELECT 
        COALESCE(SUM(d.cantidad_solicitada), 0),
        COALESCE(SUM(d.cantidad_despachada), 0),
        COALESCE(SUM(d.contenedores_retirados), 0)
    INTO v_tot_solicitada, v_tot_despachada, v_tot_retirados
    FROM public.ordenes_distribucion o
    JOIN public.detalle_distribucion d ON d.orden_id = o.id
    WHERE o.radar_id = p_radar_id;

    UPDATE public.radars
    SET total_cantidad_solicitada = v_tot_solicitada,
        total_cantidad_despachada = v_tot_despachada,
        total_contenedores_retirados = v_tot_retirados,
        status_radar = TRUE
    WHERE id = p_radar_id;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Resultado del despacho registrado en el radar exitosamente.',
        'data', jsonb_build_object(
            'radar_id', p_radar_id,
            'status_radar', TRUE,
            'total_cantidad_solicitada', v_tot_solicitada,
            'total_cantidad_despachada', v_tot_despachada,
            'total_contenedores_retirados', v_tot_retirados
        )
    );
END;
$$;

-- Permisos de ejecuciÃ³n
GRANT EXECUTE ON FUNCTION public.crear_o_obtener_radar TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.retorna_radar_detalle_reporte TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.reasignar_orden_a_radar TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.guardar_resultado_despacho_radar TO authenticated, service_role;
-- Migration: Quitar validaciÃ³n y actualizaciÃ³n de chofer en cargar_inventario_movil

CREATE OR REPLACE FUNCTION public.cargar_inventario_movil(
    p_orden_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_estado_actual TEXT;
    v_camion_id UUID;
    v_item RECORD;
BEGIN
    -- 1. Validaciones bÃ¡sicas
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

    -- Obtener datos de la orden
    SELECT estado, camion_id
    INTO v_estado_actual, v_camion_id
    FROM public.ordenes_distribucion
    WHERE id = p_orden_id;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ORDEN_INEXISTENTE',
                'message', 'La orden de distribuciÃ³n especificada no existe.',
                'details', 'ID: ' || p_orden_id
            )
        );
    END IF;

    -- Validar estado 'aprobada'
    IF v_estado_actual != 'aprobada' THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'La orden debe estar en estado aprobada para poder ser despachada.',
                'details', 'Estado actual: ' || v_estado_actual
            )
        );
    END IF;

    -- Validar que el camiÃ³n estÃ© asignado
    IF v_camion_id IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'CAMION_NO_ASIGNADO',
                'message', 'No se puede despachar la orden porque no tiene un camiÃ³n asignado.',
                'details', NULL
            )
        );
    END IF;

    -- 2. Procesamiento e IntegraciÃ³n de Inventario (Operaciones AtÃ³micas)
    FOR v_item IN 
        SELECT producto_id, cantidad_solicitada
        FROM public.detalle_distribucion
        WHERE orden_id = p_orden_id
    LOOP
        -- Descontar del comprometido del almacÃ©n principal (sale fÃ­sicamente del centro de distribuciÃ³n)
        UPDATE public.inventario_almacen
        SET stock_comprometido = stock_comprometido - v_item.cantidad_solicitada,
            updated_at = NOW()
        WHERE producto_id = v_item.producto_id;

        -- Upsert en el inventario mÃ³vil del camiÃ³n (suma a la cantidad cargada)
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

        -- Inicializar cantidad_despachada como cargada
        UPDATE public.detalle_distribucion
        SET cantidad_despachada = v_item.cantidad_solicitada
        WHERE orden_id = p_orden_id AND producto_id = v_item.producto_id;
    END LOOP;

    -- 3. Actualizar estados de recursos de transporte
    -- Cambiar camiÃ³n a estado 'en_ruta'
    UPDATE public.camiones
    SET estado = 'en_ruta'
    WHERE id = v_camion_id;

    -- Cambiar orden a estado 'en_transito'
    UPDATE public.ordenes_distribucion
    SET estado = 'en_transito',
        fecha_despacho = NOW()
    WHERE id = p_orden_id;

    -- 4. Respuesta Exitosa
    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'orden_id', p_orden_id,
            'nuevo_estado', 'en_transito'
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
-- Migration: Quitar chofer de todos los procedimientos almacenados y polÃ­ticas RLS

-- 1. liquidar_orden_distribucion
CREATE OR REPLACE FUNCTION public.liquidar_orden_distribucion(
    p_orden_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_estado_orden TEXT;
    v_cliente_id UUID;
    v_camion_id UUID;
    v_rendicion_aprobada BOOLEAN := FALSE;
BEGIN
    IF p_orden_id IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID de la orden es requerido.'
            )
        );
    END IF;

    SELECT estado, cliente_id, camion_id
    INTO v_estado_orden, v_cliente_id, v_camion_id
    FROM public.ordenes_distribucion
    WHERE id = p_orden_id;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'ORDEN_INEXISTENTE',
                'message', 'La orden de distribuciÃ³n especificada no existe.'
            )
        );
    END IF;

    IF v_estado_orden != 'por_liquidar' THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo se pueden liquidar financieramente Ã³rdenes que estÃ©n en estado por_liquidar.'
            )
        );
    END IF;

    SELECT EXISTS (
        SELECT 1 
        FROM public.detalle_rendicion_ordenes dro
        JOIN public.rendiciones_cuentas rc ON dro.rendicion_id = rc.id
        WHERE dro.orden_distribucion_id = p_orden_id
          AND rc.estado = 'aprobada'
    ) INTO v_rendicion_aprobada;

    IF NOT v_rendicion_aprobada THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'COBRANZA_PENDIENTE',
                'message', 'La orden no tiene una rendiciÃ³n de cuentas aprobada vinculada.'
            )
        );
    END IF;

    UPDATE public.camiones SET estado = 'disponible' WHERE id = v_camion_id;
    UPDATE public.ordenes_distribucion SET estado = 'liquidada' WHERE id = p_orden_id;

    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'orden_id', p_orden_id,
            'nuevo_estado', 'liquidada'
        ),
        'error', NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'SQL_ERROR',
                'message', SQLERRM,
                'details', 'SQLSTATE: ' || SQLSTATE
            )
        );
END;
$$;

-- 2. actualizar_estado_orden_distribucion
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
    v_creado_por UUID;
    v_user_id UUID := auth.uid();
    v_item RECORD;
    v_producto_nombre TEXT;
    v_stock_disponible INT;
    v_stock_comprometido INT;
BEGIN
    IF p_orden_id IS NULL THEN
        RAISE EXCEPTION 'El ID de la orden es requerido.';
    END IF;

    IF p_estado IS NULL THEN
        RAISE EXCEPTION 'El estado de destino es requerido.';
    END IF;

    IF p_estado NOT IN ('borrador', 'lista_para_carga', 'en_transito', 'liquidada', 'anulada') THEN
        RAISE EXCEPTION 'El estado % no es un estado vÃ¡lido para la orden.', p_estado;
    END IF;

    SELECT estado, camion_id, creado_por 
    INTO v_estado_actual, v_camion_id, v_creado_por
    FROM public.ordenes_distribucion
    WHERE id = p_orden_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La orden de distribuciÃ³n con ID % no existe.', p_orden_id;
    END IF;

    IF public.user_has_role(ARRAY['vendedor']) AND NOT public.user_has_role(ARRAY['admin', 'gerente', 'despachador']) THEN
        IF v_user_id IS NOT NULL AND v_creado_por IS DISTINCT FROM v_user_id THEN
            RAISE EXCEPTION 'ACCESO_DENEGADO: Un vendedor solo puede modificar las Ã³rdenes que ha registrado.';
        END IF;
    END IF;

    IF v_estado_actual = p_estado THEN
        RETURN;
    END IF;

    IF v_estado_actual = 'borrador' AND p_estado NOT IN ('lista_para_carga', 'anulada') THEN
        RAISE EXCEPTION 'TransiciÃ³n no permitida: de % a %.', v_estado_actual, p_estado;
    ELSIF v_estado_actual = 'lista_para_carga' AND p_estado NOT IN ('en_transito', 'borrador', 'anulada') THEN
        RAISE EXCEPTION 'TransiciÃ³n no permitida: de % a %.', v_estado_actual, p_estado;
    ELSIF v_estado_actual = 'en_transito' AND p_estado NOT IN ('liquidada', 'anulada') THEN
        RAISE EXCEPTION 'TransiciÃ³n no permitida: de % a %.', v_estado_actual, p_estado;
    ELSIF v_estado_actual IN ('liquidada', 'anulada') THEN
        RAISE EXCEPTION 'No se pueden realizar cambios de estado en una orden %.', v_estado_actual;
    END IF;

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
                RAISE EXCEPTION 'El producto % no tiene un registro de inventario en almacÃ©n.', COALESCE(v_producto_nombre, v_item.producto_id::text);
            END IF;

            IF v_stock_disponible < v_item.cantidad_solicitada THEN
                SELECT nombre INTO v_producto_nombre FROM public.productos WHERE id = v_item.producto_id;
                RAISE EXCEPTION 'Stock insuficiente en almacÃ©n para el producto % (Disponible: %, Requerido: %).', 
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

    ELSIF v_estado_actual = 'lista_para_carga' AND p_estado = 'borrador' THEN
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

        UPDATE public.ordenes_distribucion
        SET estado = 'borrador'
        WHERE id = p_orden_id;

    ELSIF v_estado_actual = 'lista_para_carga' AND p_estado = 'en_transito' THEN
        IF v_camion_id IS NULL THEN
            RAISE EXCEPTION 'No se puede despachar la orden porque no tiene un camiÃ³n asignado.';
        END IF;

        UPDATE public.camiones
        SET estado = 'en_ruta'
        WHERE id = v_camion_id;

        FOR v_item IN 
            SELECT producto_id, cantidad_solicitada 
            FROM public.detalle_distribucion 
            WHERE orden_id = p_orden_id
        LOOP
            UPDATE public.inventario_almacen
            SET stock_comprometido = stock_comprometido - v_item.cantidad_solicitada,
                updated_at = NOW()
            WHERE producto_id = v_item.producto_id;

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

            UPDATE public.detalle_distribucion
            SET cantidad_despachada = v_item.cantidad_solicitada
            WHERE orden_id = p_orden_id AND producto_id = v_item.producto_id;
        END LOOP;

        UPDATE public.ordenes_distribucion
        SET estado = 'en_transito',
            fecha_despacho = NOW()
        WHERE id = p_orden_id;

    ELSIF v_estado_actual = 'en_transito' AND p_estado = 'liquidada' THEN
        UPDATE public.camiones
        SET estado = 'disponible'
        WHERE id = v_camion_id;

        FOR v_item IN 
            SELECT producto_id, cantidad_despachada, COALESCE(estado_entrega, 'pendiente') as estado_entrega
            FROM public.detalle_distribucion 
            WHERE orden_id = p_orden_id
        LOOP
            IF v_item.estado_entrega IN ('entregado', 'pendiente', 'entregado_parcial') THEN
                UPDATE public.inventario_movil
                SET cantidad_cargada = cantidad_cargada - v_item.cantidad_despachada,
                    cantidad_entregada = cantidad_entregada + v_item.cantidad_despachada,
                    updated_at = NOW()
                WHERE camion_id = v_camion_id AND producto_id = v_item.producto_id;

            ELSIF v_item.estado_entrega = 'rechazado' THEN
                UPDATE public.inventario_movil
                SET cantidad_cargada = cantidad_cargada - v_item.cantidad_despachada,
                    cantidad_devolucion = cantidad_devolucion + v_item.cantidad_despachada,
                    updated_at = NOW()
                WHERE camion_id = v_camion_id AND producto_id = v_item.producto_id;

                UPDATE public.inventario_almacen
                SET stock_disponible = stock_disponible + v_item.cantidad_despachada,
                    updated_at = NOW()
                WHERE producto_id = v_item.producto_id;
            END IF;
        END LOOP;

        UPDATE public.ordenes_distribucion
        SET estado = 'liquidada'
        WHERE id = p_orden_id;

    ELSIF p_estado = 'anulada' THEN
        IF v_estado_actual = 'borrador' THEN
            NULL;

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

        ELSIF v_estado_actual = 'en_transito' THEN
            UPDATE public.camiones
            SET estado = 'disponible'
            WHERE id = v_camion_id;

            FOR v_item IN 
                SELECT producto_id, cantidad_despachada 
                FROM public.detalle_distribucion 
                WHERE orden_id = p_orden_id
            LOOP
                UPDATE public.inventario_movil
                SET cantidad_cargada = cantidad_cargada - v_item.cantidad_despachada,
                    updated_at = NOW()
                WHERE camion_id = v_camion_id AND producto_id = v_item.producto_id;

                UPDATE public.inventario_almacen
                SET stock_disponible = stock_disponible + v_item.cantidad_despachada,
                    updated_at = NOW()
                WHERE producto_id = v_item.producto_id;
            END LOOP;
        END IF;

        UPDATE public.ordenes_distribucion
        SET estado = 'anulada'
        WHERE id = p_orden_id;
    END IF;

END;
$$;

-- 3. actualiza_orden_distribucion_segun_correlativo
CREATE OR REPLACE FUNCTION public.actualiza_orden_distribucion_segun_correlativo(
    p_correlativo INT,
    p_header JSONB,
    p_detalle JSONB
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_orden_id UUID;
    v_estado_actual TEXT;
    v_creado_por UUID;
    v_user_id UUID := auth.uid();
    
    v_cliente_id UUID;
    v_camion_id UUID;
    v_fecha_despacho TIMESTAMPTZ;
    v_factura_origen TEXT;
    v_fecha_tasa DATE;
    v_tasa_cambio NUMERIC(14,4);
    
    v_peso_total NUMERIC(14,2) := 0.00;
    v_total_bs NUMERIC(14,2) := 0.00;
    v_total_usd NUMERIC(14,2) := 0.00;
    
    v_item JSONB;
    v_secuencia INT := 1;
    v_producto_id UUID;
    v_cantidad INT;
    v_val_recaudar_bs NUMERIC(14,2);
    v_val_usd NUMERIC(14,2);
    v_subtotal_bs NUMERIC(14,2);
    v_subtotal_usd NUMERIC(14,2);
    v_peso_unitario NUMERIC(14,2);
BEGIN
    IF p_correlativo IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El correlativo de la orden es requerido.',
                'details', NULL
            )
        );
    END IF;

    SELECT id, estado, creado_por
    INTO v_orden_id, v_estado_actual, v_creado_por
    FROM public.ordenes_distribucion
    WHERE correlativo = p_correlativo;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ORDEN_NO_ENCONTRADA',
                'message', 'No se encontrÃ³ la orden con correlativo ' || p_correlativo::text,
                'details', NULL
            )
        );
    END IF;

    IF v_estado_actual NOT IN ('borrador') THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo se pueden actualizar Ã³rdenes en estado borrador. Estado actual: ' || v_estado_actual,
                'details', NULL
            )
        );
    END IF;

    IF public.user_has_role(ARRAY['vendedor']) AND NOT public.user_has_role(ARRAY['admin', 'gerente', 'despachador']) THEN
        IF v_user_id IS NOT NULL AND v_creado_por IS DISTINCT FROM v_user_id THEN
            RETURN json_build_object(
                'success', false,
                'data', NULL,
                'error', json_build_object(
                    'code', 'ACCESO_DENEGADO',
                    'message', 'Un vendedor solo puede actualizar las Ã³rdenes que Ã©l mismo ha registrado.',
                    'details', NULL
                )
            );
        END IF;
    END IF;

    v_cliente_id := (p_header->>'cliente_id')::UUID;
    v_camion_id := (p_header->>'camion_id')::UUID;
    v_fecha_despacho := (p_header->>'fecha_despacho')::TIMESTAMPTZ;
    v_factura_origen := p_header->>'factura_origen_numero';
    v_fecha_tasa := COALESCE(v_fecha_despacho::date, CURRENT_DATE);

    SELECT tasa_cambio INTO v_tasa_cambio
    FROM public.tasa_cambio
    WHERE fecha_tasa = v_fecha_tasa;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'EXCEPCION_TASA_NO_ENCONTRADA',
                'message', 'No existe tasa de cambio registrada para la fecha ' || v_fecha_tasa::text,
                'details', NULL
            )
        );
    END IF;

    IF p_detalle IS NOT NULL AND jsonb_array_length(p_detalle) > 0 THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(p_detalle) LOOP
            v_producto_id := (v_item->>'producto_id')::UUID;
            v_cantidad := (v_item->>'cantidad_solicitada')::INT;
            v_val_recaudar_bs := (v_item->>'valor_unitario_recaudar')::NUMERIC;
            v_val_usd := (v_item->>'valor_unitario_usd')::NUMERIC;

            IF v_val_usd IS NULL OR v_val_usd = 0 THEN
                v_val_usd := ROUND(v_val_recaudar_bs / v_tasa_cambio, 2);
            END IF;

            v_subtotal_bs := v_cantidad * v_val_recaudar_bs;
            v_subtotal_usd := v_cantidad * v_val_usd;

            v_total_bs := v_total_bs + v_subtotal_bs;
            v_total_usd := v_total_usd + v_subtotal_usd;

            SELECT COALESCE(peso_unitario_kg, 0) INTO v_peso_unitario
            FROM public.productos WHERE id = v_producto_id;

            v_peso_total := v_peso_total + (v_peso_unitario * v_cantidad);
        END LOOP;
    END IF;

    UPDATE public.ordenes_distribucion
    SET cliente_id = COALESCE(v_cliente_id, cliente_id),
        camion_id = COALESCE(v_camion_id, camion_id),
        fecha_despacho = COALESCE(v_fecha_despacho, fecha_despacho),
        factura_origen_numero = COALESCE(v_factura_origen, factura_origen_numero),
        tasa_cambio = v_tasa_cambio,
        peso_total_calculado = v_peso_total,
        total_recaudar_bs = v_total_bs,
        total_recaudar_usd = v_total_usd
    WHERE id = v_orden_id;

    IF p_detalle IS NOT NULL AND jsonb_array_length(p_detalle) > 0 THEN
        DELETE FROM public.detalle_distribucion WHERE orden_id = v_orden_id;

        FOR v_item IN SELECT * FROM jsonb_array_elements(p_detalle) LOOP
            v_producto_id := (v_item->>'producto_id')::UUID;
            v_cantidad := (v_item->>'cantidad_solicitada')::INT;
            v_val_recaudar_bs := (v_item->>'valor_unitario_recaudar')::NUMERIC;
            v_val_usd := (v_item->>'valor_unitario_usd')::NUMERIC;

            IF v_val_usd IS NULL OR v_val_usd = 0 THEN
                v_val_usd := ROUND(v_val_recaudar_bs / v_tasa_cambio, 2);
            END IF;

            v_subtotal_bs := v_cantidad * v_val_recaudar_bs;
            v_subtotal_usd := v_cantidad * v_val_usd;

            INSERT INTO public.detalle_distribucion (
                id,
                orden_id,
                producto_id,
                cantidad_solicitada,
                cantidad_despachada,
                valor_unitario_recaudar,
                subtotal_recaudar,
                valor_unitario_usd,
                subtotal_recaudar_usd,
                secuencia_entrega,
                estado_entrega
            ) VALUES (
                gen_random_uuid(),
                v_orden_id,
                v_producto_id,
                v_cantidad,
                0,
                v_val_recaudar_bs,
                v_subtotal_bs,
                v_val_usd,
                v_subtotal_usd,
                v_secuencia,
                'pendiente'
            );

            v_secuencia := v_secuencia + 1;
        END LOOP;
    END IF;

    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'correlativo', p_correlativo,
            'orden_id', v_orden_id,
            'tasa_cambio', v_tasa_cambio,
            'total_recaudar_bs', v_total_bs,
            'total_recaudar_usd', v_total_usd
        ),
        'error', NULL
    );

EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object(
        'success', false,
        'data', NULL,
        'error', json_build_object(
            'code', 'SQL_ERROR',
            'message', SQLERRM,
            'details', NULL
        )
    );
END;
$$;

-- 4. retorna_ordenes_distribucion_segun_estado
CREATE OR REPLACE FUNCTION public.retorna_ordenes_distribucion_segun_estado(
    p_estado TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_is_vendedor BOOLEAN := FALSE;
    v_is_gerente_admin BOOLEAN := FALSE;
    v_ordenes JSON;
BEGIN
    IF p_estado IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El estado de la orden es requerido.',
                'details', NULL
            )
        );
    END IF;

    v_is_gerente_admin := public.user_has_role(ARRAY['admin', 'gerente', 'despachador']);
    v_is_vendedor := public.user_has_role(ARRAY['vendedor']);

    SELECT COALESCE(json_agg(
        json_build_object(
            'id', o.id,
            'correlativo', o.correlativo,
            'cliente_id', o.cliente_id,
            'cliente_razon_social', c.razon_social,
            'cliente_vendedor_id', c.vendedor_id,
            'camion_id', o.camion_id,
            'estado', o.estado,
            'fecha_despacho', o.fecha_despacho,
            'peso_total_calculado', o.peso_total_calculado,
            'factura_origen_numero', o.factura_origen_numero,
            'tasa_cambio', o.tasa_cambio,
            'total_recaudar_bs', o.total_recaudar_bs,
            'total_recaudar_usd', o.total_recaudar_usd,
            'creado_por', o.creado_por,
            'created_at', o.created_at
        ) ORDER BY o.correlativo DESC
    ), '[]'::json)
    INTO v_ordenes
    FROM public.ordenes_distribucion o
    LEFT JOIN public.clientes c ON c.id = o.cliente_id
    WHERE o.estado = p_estado
      AND (
          v_is_gerente_admin 
          OR (v_is_vendedor AND (c.vendedor_id = v_user_id OR o.creado_por = v_user_id))
      );

    RETURN json_build_object(
        'success', true,
        'data', v_ordenes,
        'error', NULL
    );

EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object(
        'success', false,
        'data', NULL,
        'error', json_build_object(
            'code', 'SQL_ERROR',
            'message', SQLERRM,
            'details', NULL
        )
    );
END;
$$;

-- 5. registra_nuevo_usuario
CREATE OR REPLACE FUNCTION public.registra_nuevo_usuario(
    p_email TEXT,
    p_password TEXT,
    p_nombre_completo TEXT,
    p_telefono TEXT,
    p_rol_nombre TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID;
    v_rol_id UUID;
    v_rol_normalizado TEXT;
    v_identity_id UUID;
BEGIN
    IF p_email IS NULL OR p_email = '' THEN
        RETURN jsonb_build_object('success', false, 'message', 'El correo electrÃ³nico es requerido.');
    END IF;

    IF p_password IS NULL OR p_password = '' THEN
        RETURN jsonb_build_object('success', false, 'message', 'La contraseÃ±a es requerida.');
    END IF;

    IF p_nombre_completo IS NULL OR p_nombre_completo = '' THEN
        RETURN jsonb_build_object('success', false, 'message', 'El nombre completo es requerido.');
    END IF;

    IF EXISTS (SELECT 1 FROM auth.users WHERE email = p_email) THEN
        RETURN jsonb_build_object('success', false, 'message', 'El correo electrÃ³nico ya estÃ¡ registrado.');
    END IF;

    v_rol_normalizado := LOWER(TRIM(p_rol_nombre));

    SELECT id INTO v_rol_id FROM public.roles WHERE nombre = v_rol_normalizado;
    IF v_rol_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El rol ' || p_rol_nombre || ' no existe en el sistema.');
    END IF;

    v_user_id := gen_random_uuid();
    v_identity_id := gen_random_uuid();

    INSERT INTO auth.users (
        id, instance_id, email, encrypted_password, email_confirmed_at,
        created_at, updated_at, raw_app_meta_data, raw_user_meta_data,
        aud, role, is_anonymous, confirmation_token, recovery_token,
        email_change_token_new, email_change_token_current, phone_change_token, reauthentication_token
    ) VALUES (
        v_user_id, '00000000-0000-0000-0000-000000000000', p_email, crypt(p_password, gen_salt('bf')), NOW(),
        NOW(), NOW(), jsonb_build_object('provider', 'email', 'providers', array_to_json(array['email'])),
        jsonb_build_object('full_name', p_nombre_completo), 'authenticated', 'authenticated', FALSE,
        '', '', '', '', '', ''
    );

    INSERT INTO auth.identities (
        id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at
    ) VALUES (
        v_identity_id, v_user_id, jsonb_build_object('sub', v_user_id::text, 'email', p_email, 'email_verified', true, 'phone_verified', false),
        'email', v_user_id::text, NOW(), NOW(), NOW()
    );

    INSERT INTO public.perfiles_usuario (
        id, rol_id, nombre_completo, telefono, activo, updated_at
    ) VALUES (
        v_user_id, v_rol_id, p_nombre_completo, p_telefono, TRUE, NOW()
    )
    ON CONFLICT (id) DO UPDATE 
    SET rol_id = EXCLUDED.rol_id, nombre_completo = EXCLUDED.nombre_completo, telefono = EXCLUDED.telefono, updated_at = NOW();

    RETURN jsonb_build_object(
        'success', true,
        'message', 'Usuario y perfil creados exitosamente.',
        'user_id', v_user_id
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false,
        'message', 'Error en el registro del usuario: ' || SQLERRM
    );
END;
$$;

-- 6. ActualizaciÃ³n de RLS
DROP POLICY IF EXISTS select_ordenes_distribucion ON public.ordenes_distribucion;
CREATE POLICY select_ordenes_distribucion ON public.ordenes_distribucion
FOR SELECT
USING (
    public.user_has_role(ARRAY['admin', 'gerente', 'despachador'])
);
-- Migration: Registrar las Ã³rdenes de distribuciÃ³n bajo estado 'aprobada' por defecto al crearlas sin bloquear por stock ni modificar inventario en almacÃ©n

CREATE OR REPLACE FUNCTION public.crear_orden_distribucion(
    p_vendedor_id UUID,
    p_cliente_id UUID,
    p_camion_id UUID,
    p_tasa_cambio NUMERIC DEFAULT NULL,
    p_productos_json JSONB DEFAULT '[]'::jsonb,
    p_despachador_id UUID DEFAULT NULL,
    p_id_ruta UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_orden_id UUID;
    v_correlativo INT;
    v_factura_origen VARCHAR(30);
    v_tasa_cambio NUMERIC(14,4);
    
    v_vendedor_id UUID;
    v_despachador_id UUID;
    v_id_ruta UUID;
    
    v_peso_total NUMERIC(10,2) := 0.00;
    v_total_recaudar_bs NUMERIC(14,2) := 0.00;
    v_total_recaudar_usd NUMERIC(14,2) := 0.00;
    
    v_item JSONB;
    v_secuencia INT := 1;
    v_producto_id UUID;
    v_cantidad INT;
    v_val_recaudar_bs NUMERIC(14,2);
    v_val_usd NUMERIC(14,2);
    v_subtotal_bs NUMERIC(14,2);
    v_subtotal_usd NUMERIC(14,2);
    v_peso_unitario NUMERIC(10,2);
BEGIN
    -- Validaciones bÃ¡sicas
    IF p_vendedor_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del vendedor es requerido.');
    END IF;

    IF p_cliente_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del cliente es requerido.');
    END IF;

    IF p_camion_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del camiÃ³n es requerido.');
    END IF;

    IF p_productos_json IS NULL OR jsonb_array_length(p_productos_json) = 0 THEN
        RETURN jsonb_build_object('success', false, 'message', 'Debe incluir al menos un producto en la orden.');
    END IF;

    -- Obtener informaciÃ³n del cliente (vendedor_id, despachador_id, id_ruta)
    SELECT c.vendedor_id, c.despachador_id, c.id_ruta
    INTO v_vendedor_id, v_despachador_id, v_id_ruta
    FROM public.clientes c
    WHERE c.id = p_cliente_id;

    -- Priorizar parÃ¡metros explÃ­citos si fueron proporcionados
    v_vendedor_id := COALESCE(p_vendedor_id, v_vendedor_id);
    v_despachador_id := COALESCE(p_despachador_id, v_despachador_id);
    v_id_ruta := COALESCE(p_id_ruta, v_id_ruta);

    -- Validar existencia de entidades
    IF NOT EXISTS (SELECT 1 FROM public.perfiles_usuario WHERE id = p_vendedor_id) THEN
        RETURN jsonb_build_object('success', false, 'message', 'El vendedor especificado no existe.');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.clientes WHERE id = p_cliente_id) THEN
        RETURN jsonb_build_object('success', false, 'message', 'El cliente especificado no existe.');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.camiones WHERE id = p_camion_id) THEN
        RETURN jsonb_build_object('success', false, 'message', 'El camiÃ³n especificado no existe.');
    END IF;

    -- Determinar / validar la tasa de cambio
    IF p_tasa_cambio IS NOT NULL AND p_tasa_cambio > 0 THEN
        v_tasa_cambio := p_tasa_cambio;
    ELSE
        SELECT tasa_cambio INTO v_tasa_cambio
        FROM public.tasa_cambio
        WHERE fecha_tasa = CURRENT_DATE;

        IF v_tasa_cambio IS NULL THEN
            SELECT tasa_cambio INTO v_tasa_cambio
            FROM public.tasa_cambio
            ORDER BY fecha_tasa DESC
            LIMIT 1;
        END IF;

        IF v_tasa_cambio IS NULL THEN
            RETURN jsonb_build_object(
                'success', false, 
                'message', 'No hay tasa de cambio registrada. Debe proporcionar p_tasa_cambio o registrar una tasa oficial en el sistema.'
            );
        END IF;
    END IF;

    -- Generar correlativo y nÃºmero de factura de origen automÃ¡ticamente
    v_correlativo := nextval('public.ordenes_distribucion_correlativo_seq');
    v_factura_origen := 'FAC-' || LPAD(v_correlativo::text, 6, '0');
    v_orden_id := gen_random_uuid();

    -- Validar productos y calcular totales multimoneda y peso total
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;
        
        IF v_cantidad IS NULL OR v_cantidad <= 0 THEN
            RETURN jsonb_build_object('success', false, 'message', 'La cantidad del producto debe ser mayor a cero.');
        END IF;

        SELECT peso_unitario_kg INTO v_peso_unitario
        FROM public.productos
        WHERE id = v_producto_id;

        IF NOT FOUND THEN
            RETURN jsonb_build_object('success', false, 'message', 'El producto con ID ' || v_producto_id::text || ' no existe.');
        END IF;

        v_val_recaudar_bs := COALESCE((v_item->>'valor_unitario_recaudar')::NUMERIC, (v_item->>'precio_unitario')::NUMERIC, 0.00);
        v_val_usd := COALESCE((v_item->>'valor_unitario_usd')::NUMERIC, 0.00);

        IF v_val_recaudar_bs > 0 AND (v_val_usd IS NULL OR v_val_usd = 0) THEN
            v_val_usd := ROUND(v_val_recaudar_bs / v_tasa_cambio, 2);
        ELSIF v_val_usd > 0 AND (v_val_recaudar_bs IS NULL OR v_val_recaudar_bs = 0) THEN
            v_val_recaudar_bs := ROUND(v_val_usd * v_tasa_cambio, 2);
        END IF;

        v_subtotal_bs := ROUND(v_cantidad * v_val_recaudar_bs, 2);
        v_subtotal_usd := ROUND(v_cantidad * v_val_usd, 2);

        v_peso_total := v_peso_total + (COALESCE(v_peso_unitario, 0.00) * v_cantidad);
        v_total_recaudar_bs := v_total_recaudar_bs + v_subtotal_bs;
        v_total_recaudar_usd := v_total_recaudar_usd + v_subtotal_usd;
    END LOOP;

    -- Insertar Cabecera de la Orden con estado 'aprobada'
    INSERT INTO public.ordenes_distribucion (
        id,
        correlativo,
        cliente_id,
        camion_id,
        vendedor_id,
        despachador_id,
        id_ruta,
        estado,
        fecha_despacho,
        peso_total_calculado,
        factura_origen_numero,
        creado_por,
        created_at,
        tasa_cambio,
        total_recaudar_bs,
        total_recaudar_usd
    ) VALUES (
        v_orden_id,
        v_correlativo,
        p_cliente_id,
        p_camion_id,
        v_vendedor_id,
        v_despachador_id,
        v_id_ruta,
        'aprobada',
        NULL,
        v_peso_total,
        v_factura_origen,
        p_vendedor_id,
        NOW(),
        v_tasa_cambio,
        v_total_recaudar_bs,
        v_total_recaudar_usd
    );

    -- Insertar Detalles de la Orden
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;
        
        v_val_recaudar_bs := COALESCE((v_item->>'valor_unitario_recaudar')::NUMERIC, (v_item->>'precio_unitario')::NUMERIC, 0.00);
        v_val_usd := COALESCE((v_item->>'valor_unitario_usd')::NUMERIC, 0.00);

        IF v_val_recaudar_bs > 0 AND (v_val_usd IS NULL OR v_val_usd = 0) THEN
            v_val_usd := ROUND(v_val_recaudar_bs / v_tasa_cambio, 2);
        ELSIF v_val_usd > 0 AND (v_val_recaudar_bs IS NULL OR v_val_recaudar_bs = 0) THEN
            v_val_recaudar_bs := ROUND(v_val_usd * v_tasa_cambio, 2);
        END IF;

        v_subtotal_bs := ROUND(v_cantidad * v_val_recaudar_bs, 2);
        v_subtotal_usd := ROUND(v_cantidad * v_val_usd, 2);

        INSERT INTO public.detalle_distribucion (
            id,
            orden_id,
            producto_id,
            cantidad_solicitada,
            cantidad_despachada,
            valor_unitario_recaudar,
            subtotal_recaudar,
            secuencia_entrega,
            estado_entrega,
            motivo_rechazo,
            valor_unitario_usd,
            subtotal_recaudar_usd
        ) VALUES (
            gen_random_uuid(),
            v_orden_id,
            v_producto_id,
            v_cantidad,
            0,
            v_val_recaudar_bs,
            v_subtotal_bs,
            v_secuencia,
            'pendiente',
            NULL,
            v_val_usd,
            v_subtotal_usd
        );
        
        v_secuencia := v_secuencia + 1;
    END LOOP;

    RETURN jsonb_build_object(
        'success', true, 
        'message', 'Orden de distribuciÃ³n creada exitosamente.', 
        'orden_id', v_orden_id,
        'data', jsonb_build_object(
            'orden_id', v_orden_id,
            'correlativo', v_correlativo,
            'tasa_cambio', v_tasa_cambio,
            'total_recaudar_bs', v_total_recaudar_bs,
            'total_recaudar_usd', v_total_recaudar_usd,
            'peso_total_calculado', v_peso_total
        )
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false, 
        'message', 'Error al crear la orden: ' || SQLERRM
    );
END;
$$;
-- Migration: Ajustar crear_orden_distribucion para registrar como aprobada sin bloquear por stock ni modificar inventario en almacÃ©n

CREATE OR REPLACE FUNCTION public.crear_orden_distribucion(
    p_vendedor_id UUID,
    p_cliente_id UUID,
    p_camion_id UUID,
    p_tasa_cambio NUMERIC DEFAULT NULL,
    p_productos_json JSONB DEFAULT '[]'::jsonb,
    p_despachador_id UUID DEFAULT NULL,
    p_id_ruta UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_orden_id UUID;
    v_correlativo INT;
    v_factura_origen VARCHAR(30);
    v_tasa_cambio NUMERIC(14,4);
    
    v_vendedor_id UUID;
    v_despachador_id UUID;
    v_id_ruta UUID;
    
    v_peso_total NUMERIC(10,2) := 0.00;
    v_total_recaudar_bs NUMERIC(14,2) := 0.00;
    v_total_recaudar_usd NUMERIC(14,2) := 0.00;
    
    v_item JSONB;
    v_secuencia INT := 1;
    v_producto_id UUID;
    v_cantidad INT;
    v_val_recaudar_bs NUMERIC(14,2);
    v_val_usd NUMERIC(14,2);
    v_subtotal_bs NUMERIC(14,2);
    v_subtotal_usd NUMERIC(14,2);
    v_peso_unitario NUMERIC(10,2);
BEGIN
    -- Validaciones bÃ¡sicas
    IF p_vendedor_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del vendedor es requerido.');
    END IF;

    IF p_cliente_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del cliente es requerido.');
    END IF;

    IF p_camion_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del camiÃ³n es requerido.');
    END IF;

    IF p_productos_json IS NULL OR jsonb_array_length(p_productos_json) = 0 THEN
        RETURN jsonb_build_object('success', false, 'message', 'Debe incluir al menos un producto en la orden.');
    END IF;

    -- Obtener informaciÃ³n del cliente (vendedor_id, despachador_id, id_ruta)
    SELECT c.vendedor_id, c.despachador_id, c.id_ruta
    INTO v_vendedor_id, v_despachador_id, v_id_ruta
    FROM public.clientes c
    WHERE c.id = p_cliente_id;

    -- Priorizar parÃ¡metros explÃ­citos si fueron proporcionados
    v_vendedor_id := COALESCE(p_vendedor_id, v_vendedor_id);
    v_despachador_id := COALESCE(p_despachador_id, v_despachador_id);
    v_id_ruta := COALESCE(p_id_ruta, v_id_ruta);

    -- Validar existencia de entidades
    IF NOT EXISTS (SELECT 1 FROM public.perfiles_usuario WHERE id = p_vendedor_id) THEN
        RETURN jsonb_build_object('success', false, 'message', 'El vendedor especificado no existe.');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.clientes WHERE id = p_cliente_id) THEN
        RETURN jsonb_build_object('success', false, 'message', 'El cliente especificado no existe.');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.camiones WHERE id = p_camion_id) THEN
        RETURN jsonb_build_object('success', false, 'message', 'El camiÃ³n especificado no existe.');
    END IF;

    -- Determinar / validar la tasa de cambio
    IF p_tasa_cambio IS NOT NULL AND p_tasa_cambio > 0 THEN
        v_tasa_cambio := p_tasa_cambio;
    ELSE
        SELECT tasa_cambio INTO v_tasa_cambio
        FROM public.tasa_cambio
        WHERE fecha_tasa = CURRENT_DATE;

        IF v_tasa_cambio IS NULL THEN
            SELECT tasa_cambio INTO v_tasa_cambio
            FROM public.tasa_cambio
            ORDER BY fecha_tasa DESC
            LIMIT 1;
        END IF;

        IF v_tasa_cambio IS NULL THEN
            RETURN jsonb_build_object(
                'success', false, 
                'message', 'No hay tasa de cambio registrada. Debe proporcionar p_tasa_cambio o registrar una tasa oficial en el sistema.'
            );
        END IF;
    END IF;

    -- Generar correlativo y nÃºmero de factura de origen automÃ¡ticamente
    v_correlativo := nextval('public.ordenes_distribucion_correlativo_seq');
    v_factura_origen := 'FAC-' || LPAD(v_correlativo::text, 6, '0');
    v_orden_id := gen_random_uuid();

    -- Validar productos y calcular totales multimoneda y peso total
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;
        
        IF v_cantidad IS NULL OR v_cantidad <= 0 THEN
            RETURN jsonb_build_object('success', false, 'message', 'La cantidad del producto debe ser mayor a cero.');
        END IF;

        SELECT peso_unitario_kg INTO v_peso_unitario
        FROM public.productos
        WHERE id = v_producto_id;

        IF NOT FOUND THEN
            RETURN jsonb_build_object('success', false, 'message', 'El producto con ID ' || v_producto_id::text || ' no existe.');
        END IF;

        v_val_recaudar_bs := COALESCE((v_item->>'valor_unitario_recaudar')::NUMERIC, (v_item->>'precio_unitario')::NUMERIC, 0.00);
        v_val_usd := COALESCE((v_item->>'valor_unitario_usd')::NUMERIC, 0.00);

        IF v_val_recaudar_bs > 0 AND (v_val_usd IS NULL OR v_val_usd = 0) THEN
            v_val_usd := ROUND(v_val_recaudar_bs / v_tasa_cambio, 2);
        ELSIF v_val_usd > 0 AND (v_val_recaudar_bs IS NULL OR v_val_recaudar_bs = 0) THEN
            v_val_recaudar_bs := ROUND(v_val_usd * v_tasa_cambio, 2);
        END IF;

        v_subtotal_bs := ROUND(v_cantidad * v_val_recaudar_bs, 2);
        v_subtotal_usd := ROUND(v_cantidad * v_val_usd, 2);

        v_peso_total := v_peso_total + (COALESCE(v_peso_unitario, 0.00) * v_cantidad);
        v_total_recaudar_bs := v_total_recaudar_bs + v_subtotal_bs;
        v_total_recaudar_usd := v_total_recaudar_usd + v_subtotal_usd;
    END LOOP;

    -- Insertar Cabecera de la Orden con estado 'aprobada'
    INSERT INTO public.ordenes_distribucion (
        id,
        correlativo,
        cliente_id,
        camion_id,
        vendedor_id,
        despachador_id,
        id_ruta,
        estado,
        fecha_despacho,
        peso_total_calculado,
        factura_origen_numero,
        creado_por,
        created_at,
        tasa_cambio,
        total_recaudar_bs,
        total_recaudar_usd
    ) VALUES (
        v_orden_id,
        v_correlativo,
        p_cliente_id,
        p_camion_id,
        v_vendedor_id,
        v_despachador_id,
        v_id_ruta,
        'aprobada',
        NULL,
        v_peso_total,
        v_factura_origen,
        p_vendedor_id,
        NOW(),
        v_tasa_cambio,
        v_total_recaudar_bs,
        v_total_recaudar_usd
    );

    -- Insertar Detalles de la Orden
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;
        
        v_val_recaudar_bs := COALESCE((v_item->>'valor_unitario_recaudar')::NUMERIC, (v_item->>'precio_unitario')::NUMERIC, 0.00);
        v_val_usd := COALESCE((v_item->>'valor_unitario_usd')::NUMERIC, 0.00);

        IF v_val_recaudar_bs > 0 AND (v_val_usd IS NULL OR v_val_usd = 0) THEN
            v_val_usd := ROUND(v_val_recaudar_bs / v_tasa_cambio, 2);
        ELSIF v_val_usd > 0 AND (v_val_recaudar_bs IS NULL OR v_val_recaudar_bs = 0) THEN
            v_val_recaudar_bs := ROUND(v_val_usd * v_tasa_cambio, 2);
        END IF;

        v_subtotal_bs := ROUND(v_cantidad * v_val_recaudar_bs, 2);
        v_subtotal_usd := ROUND(v_cantidad * v_val_usd, 2);

        INSERT INTO public.detalle_distribucion (
            id,
            orden_id,
            producto_id,
            cantidad_solicitada,
            cantidad_despachada,
            valor_unitario_recaudar,
            subtotal_recaudar,
            secuencia_entrega,
            estado_entrega,
            motivo_rechazo,
            valor_unitario_usd,
            subtotal_recaudar_usd
        ) VALUES (
            gen_random_uuid(),
            v_orden_id,
            v_producto_id,
            v_cantidad,
            0,
            v_val_recaudar_bs,
            v_subtotal_bs,
            v_secuencia,
            'pendiente',
            NULL,
            v_val_usd,
            v_subtotal_usd
        );
        
        v_secuencia := v_secuencia + 1;
    END LOOP;

    RETURN jsonb_build_object(
        'success', true, 
        'message', 'Orden de distribuciÃ³n creada exitosamente.', 
        'orden_id', v_orden_id,
        'data', jsonb_build_object(
            'orden_id', v_orden_id,
            'correlativo', v_correlativo,
            'tasa_cambio', v_tasa_cambio,
            'total_recaudar_bs', v_total_recaudar_bs,
            'total_recaudar_usd', v_total_recaudar_usd,
            'peso_total_calculado', v_peso_total
        )
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false, 
        'message', 'Error al crear la orden: ' || SQLERRM
    );
END;
$$;
-- Migration: MÃ³dulo de PolÃ­ticas de CrÃ©dito y Excepciones de Despacho Gerenciales (DB-027)

-- 1. DDL: Agregar columnas de polÃ­ticas de crÃ©dito a public.clientes
ALTER TABLE public.clientes
ADD COLUMN IF NOT EXISTS limite_credito NUMERIC(14,2) DEFAULT 0.00 CHECK (limite_credito >= 0.00),
ADD COLUMN IF NOT EXISTS max_facturas_vencidas INT DEFAULT 0 CHECK (max_facturas_vencidas >= 0),
ADD COLUMN IF NOT EXISTS permiso_despacho_manual BOOLEAN DEFAULT TRUE,
ADD COLUMN IF NOT EXISTS excepcion_despacho_gerencia BOOLEAN DEFAULT FALSE;

COMMENT ON COLUMN public.clientes.limite_credito IS 'Monto mÃ¡ximo de saldo deudor permitido para el cliente en Bs/USD';
COMMENT ON COLUMN public.clientes.max_facturas_vencidas IS 'Cantidad mÃ¡xima de facturas o solicitudes vencidas pendientes sin pago';
COMMENT ON COLUMN public.clientes.permiso_despacho_manual IS 'HabilitaciÃ³n manual de despacho para el cliente (.T. / .F.)';
COMMENT ON COLUMN public.clientes.excepcion_despacho_gerencia IS 'Permiso especial de un solo uso otorgado por Gerencia para permitir el despacho en morosidad';

-- 2. RPC: otorgar_excepcion_despacho_gerencia
CREATE OR REPLACE FUNCTION public.otorgar_excepcion_despacho_gerencia(
    p_cliente_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_is_gerente_admin BOOLEAN := FALSE;
BEGIN
    IF p_cliente_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID del cliente es obligatorio.'
            )
        );
    END IF;

    v_is_gerente_admin := public.user_has_role(ARRAY['admin', 'gerente']);
    IF NOT v_is_gerente_admin THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'ACCESO_DENEGADO',
                'message', 'Solo el personal gerencial o administrador puede otorgar excepciones de despacho.'
            )
        );
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.clientes WHERE id = p_cliente_id) THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'CLIENTE_INEXISTENTE',
                'message', 'El cliente especificado no existe.'
            )
        );
    END IF;

    UPDATE public.clientes
    SET excepcion_despacho_gerencia = TRUE
    WHERE id = p_cliente_id;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'ExcepciÃ³n de despacho otorgada exitosamente por gerencia (VÃ¡lida por 1 despacho).',
        'data', jsonb_build_object(
            'cliente_id', p_cliente_id,
            'excepcion_despacho_gerencia', TRUE
        )
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', SQLSTATE,
                'message', SQLERRM
            )
        );
END;
$$;

-- 3. RPC: actualiza_registro_cliente_segun_uuid con crÃ©dito
CREATE OR REPLACE FUNCTION public.actualiza_registro_cliente_segun_uuid(
    p_id UUID,
    p_rif_nit TEXT DEFAULT NULL,
    p_razon_social TEXT DEFAULT NULL,
    p_direccion_fiscal TEXT DEFAULT NULL,
    p_telefono TEXT DEFAULT NULL,
    p_movil1 TEXT DEFAULT NULL,
    p_movil2 TEXT DEFAULT NULL,
    p_movil3 TEXT DEFAULT NULL,
    p_correo_e TEXT DEFAULT NULL,
    p_cond_liq NUMERIC DEFAULT NULL,
    p_max_liq NUMERIC DEFAULT NULL,
    p_vendedor_id UUID DEFAULT NULL,
    p_despachador_id UUID DEFAULT NULL,
    p_id_ruta UUID DEFAULT NULL,
    p_activo BOOLEAN DEFAULT NULL,
    p_limite_credito NUMERIC DEFAULT NULL,
    p_max_facturas_vencidas INT DEFAULT NULL,
    p_permiso_despacho_manual BOOLEAN DEFAULT NULL,
    p_excepcion_despacho_gerencia BOOLEAN DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_cliente_actualizado RECORD;
BEGIN
    IF p_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El parÃ¡metro p_id es obligatorio.'
            )
        );
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.clientes WHERE id = p_id) THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'CLIENTE_INEXISTENTE',
                'message', 'No se encontrÃ³ ningÃºn cliente con el ID especificado.'
            )
        );
    END IF;

    IF p_rif_nit IS NOT NULL AND TRIM(p_rif_nit) <> '' THEN
        IF EXISTS (SELECT 1 FROM public.clientes WHERE rif_nit = TRIM(p_rif_nit) AND id <> p_id) THEN
            RETURN jsonb_build_object(
                'success', FALSE,
                'error', jsonb_build_object(
                    'code', 'RIF_DUPLICADO',
                    'message', 'El RIF/NIT especificado ya estÃ¡ registrado en otro cliente.'
                )
            );
        END IF;
    END IF;

    UPDATE public.clientes
    SET 
        rif_nit = COALESCE(NULLIF(TRIM(p_rif_nit), ''), rif_nit),
        razon_social = COALESCE(NULLIF(TRIM(p_razon_social), ''), razon_social),
        direccion_fiscal = COALESCE(NULLIF(TRIM(p_direccion_fiscal), ''), direccion_fiscal),
        telefono = COALESCE(p_telefono, telefono),
        movil1 = COALESCE(p_movil1, movil1),
        movil2 = COALESCE(p_movil2, movil2),
        movil3 = COALESCE(p_movil3, movil3),
        correo_e = COALESCE(p_correo_e, correo_e),
        cond_liq = COALESCE(p_cond_liq, cond_liq),
        max_liq = COALESCE(p_max_liq, max_liq),
        vendedor_id = COALESCE(p_vendedor_id, vendedor_id),
        despachador_id = COALESCE(p_despachador_id, despachador_id),
        id_ruta = COALESCE(p_id_ruta, id_ruta),
        activo = COALESCE(p_activo, activo),
        limite_credito = COALESCE(p_limite_credito, limite_credito),
        max_facturas_vencidas = COALESCE(p_max_facturas_vencidas, max_facturas_vencidas),
        permiso_despacho_manual = COALESCE(p_permiso_despacho_manual, permiso_despacho_manual),
        excepcion_despacho_gerencia = COALESCE(p_excepcion_despacho_gerencia, excepcion_despacho_gerencia)
    WHERE id = p_id
    RETURNING id, rif_nit, razon_social, direccion_fiscal, telefono, movil1, movil2, movil3, 
              correo_e, cond_liq, max_liq, vendedor_id, despachador_id, id_ruta, activo, created_at,
              limite_credito, max_facturas_vencidas, permiso_despacho_manual, excepcion_despacho_gerencia
    INTO v_cliente_actualizado;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Cliente actualizado exitosamente.',
        'data', jsonb_build_object(
            'id', v_cliente_actualizado.id,
            'rif_nit', v_cliente_actualizado.rif_nit,
            'razon_social', v_cliente_actualizado.razon_social,
            'direccion_fiscal', v_cliente_actualizado.direccion_fiscal,
            'telefono', v_cliente_actualizado.telefono,
            'movil1', v_cliente_actualizado.movil1,
            'movil2', v_cliente_actualizado.movil2,
            'movil3', v_cliente_actualizado.movil3,
            'correo_e', v_cliente_actualizado.correo_e,
            'cond_liq', v_cliente_actualizado.cond_liq,
            'max_liq', v_cliente_actualizado.max_liq,
            'vendedor_id', v_cliente_actualizado.vendedor_id,
            'despachador_id', v_cliente_actualizado.despachador_id,
            'id_ruta', v_cliente_actualizado.id_ruta,
            'activo', v_cliente_actualizado.activo,
            'limite_credito', v_cliente_actualizado.limite_credito,
            'max_facturas_vencidas', v_cliente_actualizado.max_facturas_vencidas,
            'permiso_despacho_manual', v_cliente_actualizado.permiso_despacho_manual,
            'excepcion_despacho_gerencia', v_cliente_actualizado.excepcion_despacho_gerencia,
            'created_at', v_cliente_actualizado.created_at
        )
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', SQLSTATE,
                'message', SQLERRM
            )
        );
END;
$$;

-- 4. RPC: retorna_radar_despachador
CREATE OR REPLACE FUNCTION public.retorna_radar_despachador()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_despachador_id UUID;
    v_resultado JSONB;
BEGIN
    v_despachador_id := auth.uid();

    IF v_despachador_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'NO_AUTENTICADO',
                'message', 'El usuario no estÃ¡ autenticado.'
            )
        );
    END IF;

    SELECT jsonb_build_object(
        'success', TRUE,
        'total_ordenes', COUNT(o.id),
        'data', COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'orden_id', o.id,
                    'correlativo', o.correlativo,
                    'estado', o.estado,
                    'fecha_despacho', o.fecha_despacho,
                    'tasa_cambio', o.tasa_cambio,
                    'total_recaudar_bs', o.total_recaudar_bs,
                    'total_recaudar_usd', o.total_recaudar_usd,
                    'cliente', jsonb_build_object(
                        'id', c.id,
                        'razon_social', c.razon_social,
                        'rif_nit', c.rif_nit,
                        'direccion_fiscal', c.direccion_fiscal,
                        'telefono', c.telefono,
                        'movil1', c.movil1,
                        'nombre_ruta', r.nombre_ruta,
                        'limite_credito', COALESCE(c.limite_credito, 0.00),
                        'max_facturas_vencidas', COALESCE(c.max_facturas_vencidas, 0),
                        'permiso_despacho_manual', COALESCE(c.permiso_despacho_manual, TRUE),
                        'excepcion_despacho_gerencia', COALESCE(c.excepcion_despacho_gerencia, FALSE),
                        'despacho_permitido', (
                            COALESCE(c.excepcion_despacho_gerencia, FALSE) = TRUE OR (
                                COALESCE(c.permiso_despacho_manual, TRUE) = TRUE
                                AND (COALESCE(c.limite_credito, 0.00) = 0.00 OR COALESCE(o.total_recaudar_bs, 0.00) <= COALESCE(c.limite_credito, 0.00))
                            )
                        ),
                        'motivo_bloqueo', CASE
                            WHEN COALESCE(c.excepcion_despacho_gerencia, FALSE) = TRUE THEN NULL
                            WHEN COALESCE(c.permiso_despacho_manual, TRUE) = FALSE THEN 'Despacho bloqueado manualmente por polÃ­tica de crÃ©dito'
                            WHEN COALESCE(c.limite_credito, 0.00) > 0.00 AND COALESCE(o.total_recaudar_bs, 0.00) > COALESCE(c.limite_credito, 0.00) THEN 'Monto de la orden supera el lÃ­mite de crÃ©dito del cliente'
                            ELSE NULL
                        END
                    ),
                    'detalles', (
                        SELECT COALESCE(jsonb_agg(
                            jsonb_build_object(
                                'detalle_id', d.id,
                                'producto_id', p.id,
                                'codigo_producto', p.codigo_producto,
                                'nombre_producto', p.nombre,
                                'cantidad_solicitada', d.cantidad_solicitada,
                                'cantidad_despachada', COALESCE(d.cantidad_despachada, 0),
                                'valor_unitario_recaudar', d.valor_unitario_recaudar,
                                'subtotal_recaudar', d.subtotal_recaudar,
                                'valor_unitario_usd', d.valor_unitario_usd,
                                'subtotal_recaudar_usd', d.subtotal_recaudar_usd,
                                'estado_entrega', COALESCE(d.estado_entrega, 'pendiente'),
                                'motivo_rechazo', d.motivo_rechazo,
                                'contenedores_retirados', COALESCE(d.contenedores_retirados, 0),
                                'contenedor_id', d.contenedor_id
                            )
                        ), '[]'::jsonb)
                        FROM public.detalle_distribucion d
                        JOIN public.productos p ON d.producto_id = p.id
                        WHERE d.orden_id = o.id
                    ),
                    'saldo_contenedores', (
                        SELECT COALESCE(jsonb_agg(
                            jsonb_build_object(
                                'contenedor_id', tc.id,
                                'nombre_contenedor', tc.nombre,
                                'saldo_pendiente', COALESCE(sc.saldo_pendiente, 0)
                            )
                        ), '[]'::jsonb)
                        FROM public.tipos_contenedores tc
                        LEFT JOIN public.saldo_contenedores_clientes sc ON sc.contenedor_id = tc.id AND sc.cliente_id = c.id
                    )
                )
            ),
            '[]'::jsonb
        )
    ) INTO v_resultado
    FROM public.ordenes_distribucion o
    JOIN public.clientes c ON o.cliente_id = c.id
    LEFT JOIN public.rutas r ON c.id_ruta = r.id_ruta
    WHERE c.despachador_id = v_despachador_id
      AND o.estado IN ('en_transito', 'despachada');

    RETURN v_resultado;

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', SQLSTATE,
                'message', SQLERRM
            )
        );
END;
$$;

-- 5. RPC: registrar_despacho_cliente_radar con validaciÃ³n y reseteo de excepciÃ³n
CREATE OR REPLACE FUNCTION public.registrar_despacho_cliente_radar(
    p_orden_id UUID,
    p_detalles_json JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_estado_orden TEXT;
    v_camion_id UUID;
    v_item JSONB;
    v_detalle_id UUID;
    v_cantidad_despachada INT;
    v_estado_entrega TEXT;
    v_motivo_rechazo TEXT;
    v_contenedores_retirados INT;
    v_contenedor_id UUID;
    v_producto_id UUID;
    v_cantidad_solicitada INT;
    v_devolucion INT;
    v_pendientes_count INT;
    v_cliente_id UUID;
    v_despacho_permitido BOOLEAN;
    v_excepcion_gerencia BOOLEAN;
BEGIN
    IF p_orden_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El parÃ¡metro p_orden_id es obligatorio.'
            )
        );
    END IF;

    SELECT o.estado, o.camion_id, o.cliente_id,
           COALESCE(c.excepcion_despacho_gerencia, FALSE),
           (COALESCE(c.excepcion_despacho_gerencia, FALSE) = TRUE OR (
               COALESCE(c.permiso_despacho_manual, TRUE) = TRUE
               AND (COALESCE(c.limite_credito, 0.00) = 0.00 OR COALESCE(o.total_recaudar_bs, 0.00) <= COALESCE(c.limite_credito, 0.00))
           ))
    INTO v_estado_orden, v_camion_id, v_cliente_id, v_excepcion_gerencia, v_despacho_permitido
    FROM public.ordenes_distribucion o
    JOIN public.clientes c ON o.cliente_id = c.id
    WHERE o.id = p_orden_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'ORDEN_INEXISTENTE',
                'message', 'No se encontrÃ³ la orden especificada.'
            )
        );
    END IF;

    IF NOT v_despacho_permitido THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'DESPACHO_BLOQUEADO_CREDITO',
                'message', 'No se puede despachar la orden: El cliente se encuentra bloqueado por polÃ­tica de crÃ©dito y no posee una excepciÃ³n gerencial activa.'
            )
        );
    END IF;

    IF v_estado_orden NOT IN ('en_transito', 'despachada') THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo se pueden registrar entregas de Ã³rdenes en estado en_transito o despachada.'
            )
        );
    END IF;

    IF p_detalles_json IS NOT NULL AND jsonb_array_length(p_detalles_json) > 0 THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(p_detalles_json) LOOP
            v_detalle_id := (v_item->>'detalle_id')::UUID;
            v_cantidad_despachada := (v_item->>'cantidad_despachada')::INT;
            v_estado_entrega := v_item->>'estado_entrega';
            v_motivo_rechazo := v_item->>'motivo_rechazo';
            v_contenedores_retirados := COALESCE((v_item->>'contenedores_retirados')::INT, 0);
            v_contenedor_id := (v_item->>'contenedor_id')::UUID;

            SELECT producto_id, cantidad_solicitada INTO v_producto_id, v_cantidad_solicitada
            FROM public.detalle_distribucion
            WHERE id = v_detalle_id AND orden_id = p_orden_id;

            IF FOUND THEN
                v_devolucion := GREATEST(0, v_cantidad_solicitada - v_cantidad_despachada);

                UPDATE public.inventario_movil
                SET cantidad_cargada = GREATEST(0, cantidad_cargada - v_cantidad_solicitada),
                    cantidad_entregada = cantidad_entregada + v_cantidad_despachada,
                    cantidad_devolucion = cantidad_devolucion + v_devolucion,
                    updated_at = NOW()
                WHERE camion_id = v_camion_id AND producto_id = v_producto_id;

                UPDATE public.detalle_distribucion
                SET cantidad_despachada = v_cantidad_despachada,
                    estado_entrega = v_estado_entrega,
                    motivo_rechazo = v_motivo_rechazo,
                    contenedores_retirados = v_contenedores_retirados,
                    contenedor_id = v_contenedor_id
                WHERE id = v_detalle_id;
            END IF;
        END LOOP;
    END IF;

    SELECT COUNT(*) INTO v_pendientes_count
    FROM public.detalle_distribucion
    WHERE orden_id = p_orden_id AND (estado_entrega IS NULL OR estado_entrega = 'pendiente');

    IF v_pendientes_count = 0 THEN
        UPDATE public.ordenes_distribucion
        SET estado = 'despachada'
        WHERE id = p_orden_id;
        v_estado_orden := 'despachada';

        IF v_excepcion_gerencia THEN
            UPDATE public.clientes
            SET excepcion_despacho_gerencia = FALSE
            WHERE id = v_cliente_id;
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Despacho registrado en radar exitosamente.',
        'data', jsonb_build_object(
            'orden_id', p_orden_id,
            'nuevo_estado_orden', v_estado_orden
        )
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', SQLSTATE,
                'message', SQLERRM
            )
        );
END;
$$;
-- Migration: MÃ³dulo de RendiciÃ³n de Cuentas y LiquidaciÃ³n (Flujo Completo)

-- 1. Insertar la forma de pago 'Saldo a favor' en la tabla fpagos
INSERT INTO public.fpagos (fpago_id, fpago_concepto, fpago_info)
VALUES ('7eb1e02e-ad11-4446-ee6f-de99870b477b', 'Saldo a favor', false)
ON CONFLICT (fpago_concepto) DO UPDATE 
SET fpago_info = EXCLUDED.fpago_info;

-- 2. FunciÃ³n consulta solicita_abonos_orden_distribucion
CREATE OR REPLACE FUNCTION public.solicita_abonos_orden_distribucion(
    p_cliente_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_saldo_favor NUMERIC(12, 2) := 0.00;
    v_ordenes JSON;
BEGIN
    -- Validar parÃ¡metro
    IF p_cliente_id IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID de cliente es requerido.'
            )
        );
    END IF;

    -- Validar que el cliente exista y obtener saldo a favor
    SELECT COALESCE(saldo_favor, 0.00) INTO v_saldo_favor
    FROM public.clientes
    WHERE id = p_cliente_id;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'CLIENTE_INEXISTENTE',
                'message', 'El cliente especificado no existe.'
            )
        );
    END IF;

    -- Obtener ordenes por_liquidar con abonos acumulados
    SELECT json_agg(
        json_build_object(
            'orden_id', od.id,
            'correlativo', od.correlativo,
            'fecha_despacho', od.fecha_despacho,
            'monto_total_orden', COALESCE(od.subtotal_recaudar, od.subtotal, 0.00),
            'abonos_acumulados', COALESCE(abonos.total_recaudado, 0.00),
            'saldo_pendiente', COALESCE(od.subtotal_recaudar, od.subtotal, 0.00) - COALESCE(abonos.total_recaudado, 0.00)
        ) ORDER BY od.created_at ASC
    ) INTO v_ordenes
    FROM public.ordenes_distribucion od
    LEFT JOIN LATERAL (
        SELECT SUM(dro.recaudado) AS total_recaudado
        FROM public.detalle_rendicion_ordenes dro
        JOIN public.rendiciones_cuentas rc ON dro.rendicion_id = rc.id
        WHERE dro.orden_distribucion_id = od.id
          AND rc.estado = 'aprobada'
    ) abonos ON TRUE
    WHERE od.cliente_id = p_cliente_id
      AND od.estado = 'por_liquidar';

    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'cliente_id', p_cliente_id,
            'saldo_favor', v_saldo_favor,
            'ordenes', COALESCE(v_ordenes, '[]'::json)
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


-- 3. FunciÃ³n registrar_rendicion_cuentas (Soporta uso de Saldo a Favor)
CREATE OR REPLACE FUNCTION public.registrar_rendicion_cuentas(
    p_cliente_id UUID,
    p_observaciones TEXT,
    p_creado_por UUID,
    p_ordenes JSONB,  -- Array: [{"orden_id": "...", "monto_recaudado": 150.00}]
    p_pagos JSONB      -- Array: [{"fpago_id": "...", "monto": 200.00, "referencia_bancaria": "...", "cuenta_bancaria": "...", "capture_url": "..."}]
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_rendicion_id UUID;
    v_total_ordenes NUMERIC(12, 2) := 0.00;
    v_total_pagos NUMERIC(12, 2) := 0.00;
    v_total_efectivo NUMERIC(12, 2) := 0.00;
    v_total_transferencias NUMERIC(12, 2) := 0.00;
    v_saldo_favor_usado NUMERIC(12, 2) := 0.00;
    v_cliente_saldo_favor NUMERIC(12, 2) := 0.00;
    v_item RECORD;
    v_pago RECORD;
    v_exceso NUMERIC(12, 2) := 0.00;
    v_fpago_concepto TEXT;
    v_fpago_info BOOLEAN;
BEGIN
    -- 1. Validaciones bÃ¡sicas
    IF p_cliente_id IS NULL OR p_creado_por IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID de cliente y el usuario creador son requeridos.',
                'details', NULL
            )
        );
    END IF;

    -- Validar que el cliente exista y obtener saldo a favor actual
    SELECT COALESCE(saldo_favor, 0.00) 
    INTO v_cliente_saldo_favor 
    FROM public.clientes 
    WHERE id = p_cliente_id;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'CLIENTE_INEXISTENTE',
                'message', 'El cliente especificado no existe.',
                'details', NULL
            )
        );
    END IF;

    -- Validar que las listas hijas tengan al menos un elemento
    IF p_ordenes IS NULL OR jsonb_array_length(p_ordenes) = 0 THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'DETALLE_REQUISITO_FALTANTE',
                'message', 'Debe registrar al menos una orden en el detalle de la rendiciÃ³n.',
                'details', NULL
            )
        );
    END IF;

    IF p_pagos IS NULL OR jsonb_array_length(p_pagos) = 0 THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'DETALLE_REQUISITO_FALTANTE',
                'message', 'Debe registrar al menos una forma de pago en la rendiciÃ³n.',
                'details', NULL
            )
        );
    END IF;

    -- 2. Calcular totales de Ã³rdenes
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_ordenes) AS x(orden_id UUID, monto_recaudado NUMERIC(12,2)) LOOP
        v_total_ordenes := v_total_ordenes + COALESCE(v_item.monto_recaudado, 0.00);
    END LOOP;

    -- 3. Validar y clasificar formas de pago
    FOR v_pago IN SELECT * FROM jsonb_to_recordset(p_pagos) AS y(fpago_id UUID, monto NUMERIC(12,2), referencia_bancaria TEXT, cuenta_bancaria TEXT, capture_url TEXT) LOOP
        v_total_pagos := v_total_pagos + COALESCE(v_pago.monto, 0.00);
        
        -- Obtener informaciÃ³n de la forma de pago
        SELECT fpago_concepto, fpago_info 
        INTO v_fpago_concepto, v_fpago_info 
        FROM public.fpagos 
        WHERE fpago_id = v_pago.fpago_id;
        
        IF v_fpago_concepto IS NULL THEN
            RETURN json_build_object(
                'success', false,
                'data', NULL,
                'error', json_build_object(
                    'code', 'FORMA_PAGO_INEXISTENTE',
                    'message', 'La forma de pago especificada no existe.',
                    'details', 'fpago_id: ' || v_pago.fpago_id
                )
            );
        END IF;

        -- Verificar si es uso de Saldo a Favor
        IF v_fpago_concepto ILIKE '%saldo%favor%' THEN
            v_saldo_favor_usado := v_saldo_favor_usado + COALESCE(v_pago.monto, 0.00);
        ELSIF v_fpago_info = FALSE THEN
            v_total_efectivo := v_total_efectivo + COALESCE(v_pago.monto, 0.00);
        ELSE
            v_total_transferencias := v_total_transferencias + COALESCE(v_pago.monto, 0.00);
        END IF;
    END LOOP;

    -- Validar si el saldo a favor usado excede el disponible del cliente
    IF v_saldo_favor_usado > v_cliente_saldo_favor THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'SALDO_FAVOR_INSUFICIENTE',
                'message', 'El saldo a favor utilizado (' || v_saldo_favor_usado || ') supera el saldo a favor disponible del cliente (' || v_cliente_saldo_favor || ').',
                'details', NULL
            )
        );
    END IF;

    -- 4. Crear el registro principal (Cabecera) en rendiciones_cuentas
    INSERT INTO public.rendiciones_cuentas (
        cliente_id,
        fecha_rendicion,
        total_efectivo_recaudado,
        total_transferencias_recaudado,
        total_devoluciones_valoradas,
        estado,
        observaciones,
        auditado_por
    ) VALUES (
        p_cliente_id,
        NOW(),
        v_total_efectivo,
        v_total_transferencias,
        0.00,
        'revision',
        p_observaciones,
        NULL
    ) RETURNING id INTO v_rendicion_id;

    -- 5. Registrar detalle de Ã³rdenes asociadas
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_ordenes) AS x(orden_id UUID, monto_recaudado NUMERIC(12,2)) LOOP
        INSERT INTO public.detalle_rendicion_ordenes (
            rendicion_id,
            orden_distribucion_id,
            recaudado
        ) VALUES (
            v_rendicion_id,
            v_item.orden_id,
            v_item.monto_recaudado
        );
    END LOOP;

    -- 6. Registrar formas de pago (detalle_rendicion_fpagos)
    FOR v_pago IN SELECT * FROM jsonb_to_recordset(p_pagos) AS y(fpago_id UUID, monto NUMERIC(12,2), referencia_bancaria TEXT, cuenta_bancaria TEXT, capture_url TEXT) LOOP
        INSERT INTO public.detalle_rendicion_fpagos (
            rendicion_id,
            fpago_id,
            monto,
            referencia_bancaria,
            cuenta_bancaria,
            capture_url
        ) VALUES (
            v_rendicion_id,
            v_pago.fpago_id,
            v_pago.monto,
            v_pago.referencia_bancaria,
            v_pago.cuenta_bancaria,
            v_pago.capture_url
        );
    END LOOP;

    -- 7. Procesar uso de Saldo a Favor si aplica
    IF v_saldo_favor_usado > 0 THEN
        UPDATE public.clientes
        SET saldo_favor = saldo_favor - v_saldo_favor_usado
        WHERE id = p_cliente_id;

        INSERT INTO public.movimientos_saldo_favor (
            cliente_id,
            rendicion_id,
            orden_id,
            monto,
            tipo,
            observaciones,
            created_at
        ) VALUES (
            p_cliente_id,
            v_rendicion_id,
            NULL,
            -v_saldo_favor_usado,
            'cargo_pago_orden',
            'Uso de saldo a favor en rendiciÃ³n de cuentas ID: ' || v_rendicion_id,
            NOW()
        );
    END IF;

    -- 8. Manejo de Excedente de Pago (CrÃ©dito a Favor Generado)
    IF v_total_pagos > v_total_ordenes THEN
        v_exceso := v_total_pagos - v_total_ordenes;

        INSERT INTO public.movimientos_saldo_favor (
            cliente_id,
            rendicion_id,
            orden_id,
            monto,
            tipo,
            observaciones,
            created_at
        ) VALUES (
            p_cliente_id,
            v_rendicion_id,
            NULL,
            v_exceso,
            'abono_recaudacion',
            'Excedente en formas de pago de rendiciÃ³n de cuentas ID: ' || v_rendicion_id,
            NOW()
        );

        UPDATE public.clientes
        SET saldo_favor = COALESCE(saldo_favor, 0.00) + v_exceso
        WHERE id = p_cliente_id;
    END IF;

    -- 9. Retorno Exitoso
    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'rendicion_id', v_rendicion_id,
            'total_ordenes', v_total_ordenes,
            'total_pagos', v_total_pagos,
            'saldo_favor_usado', v_saldo_favor_usado,
            'saldo_favor_generado', v_exceso
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


-- 4. FunciÃ³n liquidar_orden_distribucion con evaluaciÃ³n de cobro 100%
CREATE OR REPLACE FUNCTION public.liquidar_orden_distribucion(
    p_orden_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_estado_orden TEXT;
    v_cliente_id UUID;
    v_camion_id UUID;
    v_subtotal_recaudar NUMERIC(12, 2) := 0.00;
    v_total_abonos_aprobados NUMERIC(12, 2) := 0.00;
BEGIN
    -- Validar parÃ¡metro
    IF p_orden_id IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID de la orden es requerido.'
            )
        );
    END IF;

    -- Obtener orden
    SELECT estado, cliente_id, camion_id, COALESCE(subtotal_recaudar, subtotal, 0.00)
    INTO v_estado_orden, v_cliente_id, v_camion_id, v_subtotal_recaudar
    FROM public.ordenes_distribucion
    WHERE id = p_orden_id;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'ORDEN_INEXISTENTE',
                'message', 'La orden de distribuciÃ³n especificada no existe.'
            )
        );
    END IF;

    IF v_estado_orden != 'por_liquidar' THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo se pueden evaluar o liquidar financieramente Ã³rdenes en estado por_liquidar.'
            )
        );
    END IF;

    -- Calcular la suma de todos los abonos aprobados para esta orden
    SELECT COALESCE(SUM(dro.recaudado), 0.00)
    INTO v_total_abonos_aprobados
    FROM public.detalle_rendicion_ordenes dro
    JOIN public.rendiciones_cuentas rc ON dro.rendicion_id = rc.id
    WHERE dro.orden_distribucion_id = p_orden_id
      AND rc.estado = 'aprobada';

    -- Si la suma de abonos alcanza o supera el subtotal a recaudar
    IF v_total_abonos_aprobados >= v_subtotal_recaudar THEN
        -- Liberar camiÃ³n si aplica
        IF v_camion_id IS NOT NULL THEN
            UPDATE public.camiones SET estado = 'disponible' WHERE id = v_camion_id;
        END IF;

        -- Transicionar orden a 'liquidada'
        UPDATE public.ordenes_distribucion 
        SET estado = 'liquidada' 
        WHERE id = p_orden_id;

        RETURN json_build_object(
            'success', true,
            'data', json_build_object(
                'orden_id', p_orden_id,
                'nuevo_estado', 'liquidada',
                'total_recaudado', v_total_abonos_aprobados,
                'subtotal_recaudar', v_subtotal_recaudar
            ),
            'error', NULL
        );
    ELSE
        -- Se mantiene en 'por_liquidar' ya que la recaudaciÃ³n acumulada es parcial
        RETURN json_build_object(
            'success', true,
            'data', json_build_object(
                'orden_id', p_orden_id,
                'nuevo_estado', 'por_liquidar',
                'total_recaudado', v_total_abonos_aprobados,
                'subtotal_recaudar', v_subtotal_recaudar,
                'saldo_pendiente', (v_subtotal_recaudar - v_total_abonos_aprobados)
            ),
            'error', NULL
        );
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'SQL_ERROR',
                'message', SQLERRM,
                'details', 'SQLSTATE: ' || SQLSTATE
            )
        );
END;
$$;


-- 5. FunciÃ³n reporte_recaudaciones_gerenciales
CREATE OR REPLACE FUNCTION public.reporte_recaudaciones_gerenciales(
    p_fecha_desde DATE DEFAULT NULL,
    p_fecha_hasta DATE DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_data JSON;
    v_desde TIMESTAMP WITH TIME ZONE;
    v_hasta TIMESTAMP WITH TIME ZONE;
BEGIN
    -- Configurar fechas por defecto si no son pasadas (mes actual)
    v_desde := COALESCE(p_fecha_desde::TIMESTAMP WITH TIME ZONE, date_trunc('month', CURRENT_DATE));
    v_hasta := COALESCE((p_fecha_hasta + INTERVAL '1 day - 1 microsecond')::TIMESTAMP WITH TIME ZONE, CURRENT_TIMESTAMP);

    SELECT json_agg(
        json_build_object(
            'rendicion_id', rc.id,
            'fecha_rendicion', rc.fecha_rendicion,
            'cliente_id', rc.cliente_id,
            'cliente_nombre', c.razon_social,
            'cliente_rif', c.rif_nit,
            'estado', rc.estado,
            'total_efectivo_recaudado', rc.total_efectivo_recaudado,
            'total_transferencias_recaudado', rc.total_transferencias_recaudado,
            'observaciones', rc.observaciones,
            'detalle_fpagos', COALESCE(fpagos_agg.fpagos, '[]'::json),
            'detalle_ordenes', COALESCE(ordenes_agg.ordenes, '[]'::json)
        ) ORDER BY rc.fecha_rendicion DESC
    ) INTO v_data
    FROM public.rendiciones_cuentas rc
    JOIN public.clientes c ON rc.cliente_id = c.id
    LEFT JOIN LATERAL (
        SELECT json_agg(
            json_build_object(
                'fpago_id', dfp.fpago_id,
                'concepto', fp.fpago_concepto,
                'monto', dfp.monto,
                'referencia_bancaria', dfp.referencia_bancaria,
                'cuenta_bancaria', dfp.cuenta_bancaria,
                'capture_url', dfp.capture_url
            )
        ) AS fpagos
        FROM public.detalle_rendicion_fpagos dfp
        LEFT JOIN public.fpagos fp ON dfp.fpago_id = fp.fpago_id
        WHERE dfp.rendicion_id = rc.id
    ) fpagos_agg ON TRUE
    LEFT JOIN LATERAL (
        SELECT json_agg(
            json_build_object(
                'orden_id', dro.orden_distribucion_id,
                'correlativo', od.correlativo,
                'recaudado', dro.recaudado
            )
        ) AS ordenes
        FROM public.detalle_rendicion_ordenes dro
        LEFT JOIN public.ordenes_distribucion od ON dro.orden_distribucion_id = od.id
        WHERE dro.rendicion_id = rc.id
    ) ordenes_agg ON TRUE
    WHERE rc.fecha_rendicion >= v_desde
      AND rc.fecha_rendicion <= v_hasta;

    RETURN json_build_object(
        'success', true,
        'data', COALESCE(v_data, '[]'::json),
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
-- Migration: MÃ³dulo de Cuentas Bancarias de la Empresa y Multimoneda (USD/Bs) en RendiciÃ³n de Cuentas

-- 1. Crear tabla maestra cuentas_bancarias_empresa
CREATE TABLE IF NOT EXISTS public.cuentas_bancarias_empresa (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    cuenta_bancaria VARCHAR(20) NOT NULL UNIQUE,
    entidad_bancaria VARCHAR(100) NOT NULL,
    status_cuenta BOOLEAN DEFAULT TRUE, -- TRUE = Activa (.T.), FALSE = Suspendida (.F.)
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Habilitar RLS
ALTER TABLE public.cuentas_bancarias_empresa ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'cuentas_bancarias_empresa' AND policyname = 'Permitir lectura autenticada de cuentas bancarias'
    ) THEN
        CREATE POLICY "Permitir lectura autenticada de cuentas bancarias" ON public.cuentas_bancarias_empresa
            FOR SELECT TO authenticated USING (true);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'cuentas_bancarias_empresa' AND policyname = 'Permitir edicion autenticada de cuentas bancarias'
    ) THEN
        CREATE POLICY "Permitir edicion autenticada de cuentas bancarias" ON public.cuentas_bancarias_empresa
            FOR ALL TO authenticated USING (true);
    END IF;
END $$;


-- 2. Alteraciones de columnas multimoneda y relaciones
ALTER TABLE public.rendiciones_cuentas 
ADD COLUMN IF NOT EXISTS tasa_cambio NUMERIC(10, 4) NOT NULL DEFAULT 1.0000,
ADD COLUMN IF NOT EXISTS total_recaudado_bs NUMERIC(12, 2) DEFAULT 0.00,
ADD COLUMN IF NOT EXISTS total_recaudado_usd NUMERIC(12, 2) DEFAULT 0.00;

ALTER TABLE public.detalle_rendicion_fpagos 
ADD COLUMN IF NOT EXISTS cuenta_bancaria_id UUID REFERENCES public.cuentas_bancarias_empresa(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS monto_bs NUMERIC(12, 2) DEFAULT 0.00,
ADD COLUMN IF NOT EXISTS monto_usd NUMERIC(12, 2) DEFAULT 0.00;

ALTER TABLE public.detalle_rendicion_ordenes 
ADD COLUMN IF NOT EXISTS recaudado_bs NUMERIC(12, 2) DEFAULT 0.00;


-- 3. FunciÃ³n crear_cuenta_bancaria_empresa
CREATE OR REPLACE FUNCTION public.crear_cuenta_bancaria_empresa(
    p_cuenta_bancaria TEXT,
    p_entidad_bancaria TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_id UUID;
BEGIN
    IF p_cuenta_bancaria IS NULL OR TRIM(p_cuenta_bancaria) = '' THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El nÃºmero de cuenta bancaria es requerido.'
            )
        );
    END IF;

    IF p_entidad_bancaria IS NULL OR TRIM(p_entidad_bancaria) = '' THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'La entidad bancaria es requerida.'
            )
        );
    END IF;

    IF EXISTS (SELECT 1 FROM public.cuentas_bancarias_empresa WHERE cuenta_bancaria = TRIM(p_cuenta_bancaria)) THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'CUENTA_DUPLICADA',
                'message', 'La cuenta bancaria especificada ya estÃ¡ registrada.'
            )
        );
    END IF;

    INSERT INTO public.cuentas_bancarias_empresa (
        cuenta_bancaria,
        entidad_bancaria,
        status_cuenta
    ) VALUES (
        TRIM(p_cuenta_bancaria),
        TRIM(p_entidad_bancaria),
        TRUE
    ) RETURNING id INTO v_id;

    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'id', v_id,
            'cuenta_bancaria', TRIM(p_cuenta_bancaria),
            'entidad_bancaria', TRIM(p_entidad_bancaria),
            'status_cuenta', true
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


-- 4. FunciÃ³n actualizar_cuenta_bancaria_empresa
CREATE OR REPLACE FUNCTION public.actualizar_cuenta_bancaria_empresa(
    p_id UUID,
    p_cuenta_bancaria TEXT DEFAULT NULL,
    p_entidad_bancaria TEXT DEFAULT NULL,
    p_status_cuenta BOOLEAN DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_rec RECORD;
BEGIN
    IF p_id IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID de la cuenta bancaria es requerido.'
            )
        );
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.cuentas_bancarias_empresa WHERE id = p_id) THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'CUENTA_INEXISTENTE',
                'message', 'La cuenta bancaria especificada no existe.'
            )
        );
    END IF;

    IF p_cuenta_bancaria IS NOT NULL AND TRIM(p_cuenta_bancaria) <> '' THEN
        IF EXISTS (SELECT 1 FROM public.cuentas_bancarias_empresa WHERE cuenta_bancaria = TRIM(p_cuenta_bancaria) AND id <> p_id) THEN
            RETURN json_build_object(
                'success', false,
                'data', NULL,
                'error', json_build_object(
                    'code', 'CUENTA_DUPLICADA',
                    'message', 'El nÃºmero de cuenta especificado pertenece a otra cuenta registrada.'
                )
            );
        END IF;
    END IF;

    UPDATE public.cuentas_bancarias_empresa
    SET 
        cuenta_bancaria = COALESCE(NULLIF(TRIM(p_cuenta_bancaria), ''), cuenta_bancaria),
        entidad_bancaria = COALESCE(NULLIF(TRIM(p_entidad_bancaria), ''), entidad_bancaria),
        status_cuenta = COALESCE(p_status_cuenta, status_cuenta)
    WHERE id = p_id
    RETURNING id, cuenta_bancaria, entidad_bancaria, status_cuenta, created_at
    INTO v_rec;

    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'id', v_rec.id,
            'cuenta_bancaria', v_rec.cuenta_bancaria,
            'entidad_bancaria', v_rec.entidad_bancaria,
            'status_cuenta', v_rec.status_cuenta
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


-- 5. FunciÃ³n cambiar_status_cuenta_bancaria_empresa
CREATE OR REPLACE FUNCTION public.cambiar_status_cuenta_bancaria_empresa(
    p_id UUID,
    p_status_cuenta BOOLEAN
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF p_id IS NULL OR p_status_cuenta IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID de la cuenta y el estatus son requeridos.'
            )
        );
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.cuentas_bancarias_empresa WHERE id = p_id) THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'CUENTA_INEXISTENTE',
                'message', 'La cuenta bancaria especificada no existe.'
            )
        );
    END IF;

    UPDATE public.cuentas_bancarias_empresa
    SET status_cuenta = p_status_cuenta
    WHERE id = p_id;

    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'id', p_id,
            'status_cuenta', p_status_cuenta
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


-- 6. FunciÃ³n retorna_cuentas_bancarias_empresa
CREATE OR REPLACE FUNCTION public.retorna_cuentas_bancarias_empresa(
    p_solo_activas BOOLEAN DEFAULT TRUE
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_data JSON;
BEGIN
    SELECT json_agg(
        json_build_object(
            'id', id,
            'cuenta_bancaria', cuenta_bancaria,
            'entidad_bancaria', entidad_bancaria,
            'status_cuenta', status_cuenta,
            'created_at', created_at
        ) ORDER BY entidad_bancaria ASC, cuenta_bancaria ASC
    ) INTO v_data
    FROM public.cuentas_bancarias_empresa
    WHERE (NOT p_solo_activas OR status_cuenta = TRUE);

    RETURN json_build_object(
        'success', true,
        'data', COALESCE(v_data, '[]'::json),
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


-- 7. FunciÃ³n solicita_abonos_orden_distribucion (Multimoneda USD/Bs)
CREATE OR REPLACE FUNCTION public.solicita_abonos_orden_distribucion(
    p_cliente_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_saldo_favor NUMERIC(12, 2) := 0.00;
    v_tasa_oficial NUMERIC(10, 4) := 1.0000;
    v_ordenes JSON;
BEGIN
    -- Validar parÃ¡metro
    IF p_cliente_id IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID de cliente es requerido.'
            )
        );
    END IF;

    -- Validar que el cliente exista y obtener saldo a favor
    SELECT COALESCE(saldo_favor, 0.00) INTO v_saldo_favor
    FROM public.clientes
    WHERE id = p_cliente_id;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'CLIENTE_INEXISTENTE',
                'message', 'El cliente especificado no existe.'
            )
        );
    END IF;

    -- Obtener la Ãºltima tasa de cambio oficial
    SELECT COALESCE(tasa_cambio, 1.0000) INTO v_tasa_oficial
    FROM public.tasa_cambio
    ORDER BY fecha_tasa DESC, created_at DESC
    LIMIT 1;

    -- Obtener ordenes por_liquidar con abonos acumulados en USD y Bs
    SELECT json_agg(
        json_build_object(
            'orden_id', od.id,
            'correlativo', od.correlativo,
            'fecha_despacho', od.fecha_despacho,
            'tasa_orden', COALESCE(od.tasa_cambio, v_tasa_oficial),
            'monto_total_orden', COALESCE(od.subtotal_recaudar, od.subtotal, 0.00),
            'monto_total_orden_bs', COALESCE(od.total_recaudar_bs, (COALESCE(od.subtotal_recaudar, od.subtotal, 0.00) * COALESCE(od.tasa_cambio, v_tasa_oficial)), 0.00),
            'abonos_acumulados', COALESCE(abonos.total_recaudado_usd, 0.00),
            'abonos_acumulados_bs', COALESCE(abonos.total_recaudado_bs, 0.00),
            'saldo_pendiente', COALESCE(od.subtotal_recaudar, od.subtotal, 0.00) - COALESCE(abonos.total_recaudado_usd, 0.00),
            'saldo_pendiente_bs', COALESCE(od.total_recaudar_bs, (COALESCE(od.subtotal_recaudar, od.subtotal, 0.00) * COALESCE(od.tasa_cambio, v_tasa_oficial)), 0.00) - COALESCE(abonos.total_recaudado_bs, 0.00)
        ) ORDER BY od.created_at ASC
    ) INTO v_ordenes
    FROM public.ordenes_distribucion od
    LEFT JOIN LATERAL (
        SELECT 
            SUM(COALESCE(dro.recaudado, 0.00)) AS total_recaudado_usd,
            SUM(COALESCE(dro.recaudado_bs, (COALESCE(dro.recaudado, 0.00) * COALESCE(rc.tasa_cambio, v_tasa_oficial)), 0.00)) AS total_recaudado_bs
        FROM public.detalle_rendicion_ordenes dro
        JOIN public.rendiciones_cuentas rc ON dro.rendicion_id = rc.id
        WHERE dro.orden_distribucion_id = od.id
          AND rc.estado = 'aprobada'
    ) abonos ON TRUE
    WHERE od.cliente_id = p_cliente_id
      AND od.estado = 'por_liquidar';

    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'cliente_id', p_cliente_id,
            'saldo_favor', v_saldo_favor,
            'saldo_favor_bs', (v_saldo_favor * v_tasa_oficial),
            'tasa_oficial_actual', v_tasa_oficial,
            'ordenes', COALESCE(v_ordenes, '[]'::json)
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


-- 8. FunciÃ³n registrar_rendicion_cuentas (Multimoneda USD/Bs y Cuentas Bancarias)
CREATE OR REPLACE FUNCTION public.registrar_rendicion_cuentas(
    p_cliente_id UUID,
    p_observaciones TEXT,
    p_creado_por UUID,
    p_ordenes JSONB,  -- Array: [{"orden_id": "...", "monto_recaudado": 150.00, "monto_recaudado_bs": 7500.00}]
    p_pagos JSONB,     -- Array: [{"fpago_id": "...", "monto": 200.00, "monto_bs": 10000.00, "monto_usd": 200.00, "cuenta_bancaria_id": "...", "referencia_bancaria": "...", "cuenta_bancaria": "...", "capture_url": "..."}]
    p_tasa_cambio NUMERIC DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_rendicion_id UUID;
    v_tasa_cambio NUMERIC(10, 4);
    v_total_ordenes NUMERIC(12, 2) := 0.00;
    v_total_ordenes_bs NUMERIC(12, 2) := 0.00;
    v_total_pagos NUMERIC(12, 2) := 0.00;
    v_total_pagos_bs NUMERIC(12, 2) := 0.00;
    v_total_efectivo NUMERIC(12, 2) := 0.00;
    v_total_transferencias NUMERIC(12, 2) := 0.00;
    v_saldo_favor_usado NUMERIC(12, 2) := 0.00;
    v_cliente_saldo_favor NUMERIC(12, 2) := 0.00;
    v_item RECORD;
    v_pago RECORD;
    v_exceso NUMERIC(12, 2) := 0.00;
    v_exceso_bs NUMERIC(12, 2) := 0.00;
    v_fpago_concepto TEXT;
    v_fpago_info BOOLEAN;
    v_item_usd NUMERIC(12, 2);
    v_item_bs NUMERIC(12, 2);
    v_rec_usd NUMERIC(12, 2);
    v_rec_bs NUMERIC(12, 2);
BEGIN
    -- 1. Validaciones bÃ¡sicas
    IF p_cliente_id IS NULL OR p_creado_por IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID de cliente y el usuario creador son requeridos.',
                'details', NULL
            )
        );
    END IF;

    -- Determinar tasa de cambio
    IF p_tasa_cambio IS NOT NULL AND p_tasa_cambio > 0 THEN
        v_tasa_cambio := p_tasa_cambio;
    ELSE
        SELECT COALESCE(tasa_cambio, 1.0000) INTO v_tasa_cambio
        FROM public.tasa_cambio
        ORDER BY fecha_tasa DESC, created_at DESC
        LIMIT 1;

        IF v_tasa_cambio IS NULL THEN
            v_tasa_cambio := 1.0000;
        END IF;
    END IF;

    -- Validar que el cliente exista y obtener saldo a favor actual
    SELECT COALESCE(saldo_favor, 0.00) 
    INTO v_cliente_saldo_favor 
    FROM public.clientes 
    WHERE id = p_cliente_id;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'CLIENTE_INEXISTENTE',
                'message', 'El cliente especificado no existe.',
                'details', NULL
            )
        );
    END IF;

    -- Validar que las listas hijas tengan al menos un elemento
    IF p_ordenes IS NULL OR jsonb_array_length(p_ordenes) = 0 THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'DETALLE_REQUISITO_FALTANTE',
                'message', 'Debe registrar al menos una orden en el detalle de la rendiciÃ³n.',
                'details', NULL
            )
        );
    END IF;

    IF p_pagos IS NULL OR jsonb_array_length(p_pagos) = 0 THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'DETALLE_REQUISITO_FALTANTE',
                'message', 'Debe registrar al menos una forma de pago en la rendiciÃ³n.',
                'details', NULL
            )
        );
    END IF;

    -- 2. Calcular totales de Ã³rdenes
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_ordenes) AS x(orden_id UUID, monto_recaudado NUMERIC(12,2), monto_recaudado_bs NUMERIC(12,2)) LOOP
        v_rec_usd := COALESCE(v_item.monto_recaudado, 0.00);
        v_rec_bs := COALESCE(v_item.monto_recaudado_bs, v_rec_usd * v_tasa_cambio);

        v_total_ordenes := v_total_ordenes + v_rec_usd;
        v_total_ordenes_bs := v_total_ordenes_bs + v_rec_bs;
    END LOOP;

    -- 3. Validar y clasificar formas de pago (USD y Bs)
    FOR v_pago IN SELECT * FROM jsonb_to_recordset(p_pagos) AS y(fpago_id UUID, monto NUMERIC(12,2), monto_bs NUMERIC(12,2), monto_usd NUMERIC(12,2), cuenta_bancaria_id UUID, referencia_bancaria TEXT, cuenta_bancaria TEXT, capture_url TEXT) LOOP
        -- Calcular valores en ambas monedas
        IF v_pago.monto_bs IS NOT NULL AND v_pago.monto_bs > 0 THEN
            v_item_bs := v_pago.monto_bs;
            v_item_usd := COALESCE(v_pago.monto_usd, v_item_bs / v_tasa_cambio);
        ELSE
            v_item_usd := COALESCE(v_pago.monto_usd, v_pago.monto, 0.00);
            v_item_bs := COALESCE(v_pago.monto_bs, v_item_usd * v_tasa_cambio);
        END IF;

        v_total_pagos := v_total_pagos + v_item_usd;
        v_total_pagos_bs := v_total_pagos_bs + v_item_bs;
        
        -- Obtener informaciÃ³n de la forma de pago
        SELECT fpago_concepto, fpago_info 
        INTO v_fpago_concepto, v_fpago_info 
        FROM public.fpagos 
        WHERE fpago_id = v_pago.fpago_id;
        
        IF v_fpago_concepto IS NULL THEN
            RETURN json_build_object(
                'success', false,
                'data', NULL,
                'error', json_build_object(
                    'code', 'FORMA_PAGO_INEXISTENTE',
                    'message', 'La forma de pago especificada no existe.',
                    'details', 'fpago_id: ' || v_pago.fpago_id
                )
            );
        END IF;

        -- Verificar si es uso de Saldo a Favor
        IF v_fpago_concepto ILIKE '%saldo%favor%' THEN
            v_saldo_favor_usado := v_saldo_favor_usado + v_item_usd;
        ELSIF v_fpago_info = FALSE THEN
            v_total_efectivo := v_total_efectivo + v_item_usd;
        ELSE
            v_total_transferencias := v_total_transferencias + v_item_usd;
        END IF;
    END LOOP;

    -- Validar si el saldo a favor usado excede el disponible del cliente
    IF v_saldo_favor_usado > v_cliente_saldo_favor THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'SALDO_FAVOR_INSUFICIENTE',
                'message', 'El saldo a favor utilizado (' || v_saldo_favor_usado || ') supera el saldo a favor disponible del cliente (' || v_cliente_saldo_favor || ').',
                'details', NULL
            )
        );
    END IF;

    -- 4. Crear el registro principal (Cabecera) en rendiciones_cuentas
    INSERT INTO public.rendiciones_cuentas (
        cliente_id,
        fecha_rendicion,
        tasa_cambio,
        total_efectivo_recaudado,
        total_transferencias_recaudado,
        total_recaudado_bs,
        total_recaudado_usd,
        total_devoluciones_valoradas,
        estado,
        observaciones,
        auditado_por
    ) VALUES (
        p_cliente_id,
        NOW(),
        v_tasa_cambio,
        v_total_efectivo,
        v_total_transferencias,
        v_total_pagos_bs,
        v_total_pagos,
        0.00,
        'revision',
        p_observaciones,
        NULL
    ) RETURNING id INTO v_rendicion_id;

    -- 5. Registrar detalle de Ã³rdenes asociadas
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_ordenes) AS x(orden_id UUID, monto_recaudado NUMERIC(12,2), monto_recaudado_bs NUMERIC(12,2)) LOOP
        v_rec_usd := COALESCE(v_item.monto_recaudado, 0.00);
        v_rec_bs := COALESCE(v_item.monto_recaudado_bs, v_rec_usd * v_tasa_cambio);

        INSERT INTO public.detalle_rendicion_ordenes (
            rendicion_id,
            orden_distribucion_id,
            recaudado,
            recaudado_bs
        ) VALUES (
            v_rendicion_id,
            v_item.orden_id,
            v_rec_usd,
            v_rec_bs
        );
    END LOOP;

    -- 6. Registrar formas de pago (detalle_rendicion_fpagos)
    FOR v_pago IN SELECT * FROM jsonb_to_recordset(p_pagos) AS y(fpago_id UUID, monto NUMERIC(12,2), monto_bs NUMERIC(12,2), monto_usd NUMERIC(12,2), cuenta_bancaria_id UUID, referencia_bancaria TEXT, cuenta_bancaria TEXT, capture_url TEXT) LOOP
        IF v_pago.monto_bs IS NOT NULL AND v_pago.monto_bs > 0 THEN
            v_item_bs := v_pago.monto_bs;
            v_item_usd := COALESCE(v_pago.monto_usd, v_item_bs / v_tasa_cambio);
        ELSE
            v_item_usd := COALESCE(v_pago.monto_usd, v_pago.monto, 0.00);
            v_item_bs := COALESCE(v_pago.monto_bs, v_item_usd * v_tasa_cambio);
        END IF;

        INSERT INTO public.detalle_rendicion_fpagos (
            rendicion_id,
            fpago_id,
            cuenta_bancaria_id,
            monto,
            monto_bs,
            monto_usd,
            referencia_bancaria,
            cuenta_bancaria,
            capture_url
        ) VALUES (
            v_rendicion_id,
            v_pago.fpago_id,
            v_pago.cuenta_bancaria_id,
            v_item_usd,
            v_item_bs,
            v_item_usd,
            v_pago.referencia_bancaria,
            v_pago.cuenta_bancaria,
            v_pago.capture_url
        );
    END LOOP;

    -- 7. Procesar uso de Saldo a Favor si aplica
    IF v_saldo_favor_usado > 0 THEN
        UPDATE public.clientes
        SET saldo_favor = saldo_favor - v_saldo_favor_usado
        WHERE id = p_cliente_id;

        INSERT INTO public.movimientos_saldo_favor (
            cliente_id,
            rendicion_id,
            orden_id,
            monto,
            tipo,
            observaciones,
            created_at
        ) VALUES (
            p_cliente_id,
            v_rendicion_id,
            NULL,
            -v_saldo_favor_usado,
            'cargo_pago_orden',
            'Uso de saldo a favor en rendiciÃ³n de cuentas ID: ' || v_rendicion_id,
            NOW()
        );
    END IF;

    -- 8. Manejo de Excedente de Pago (CrÃ©dito a Favor Generado)
    IF v_total_pagos > v_total_ordenes THEN
        v_exceso := v_total_pagos - v_total_ordenes;
        v_exceso_bs := v_total_pagos_bs - v_total_ordenes_bs;

        INSERT INTO public.movimientos_saldo_favor (
            cliente_id,
            rendicion_id,
            orden_id,
            monto,
            tipo,
            observaciones,
            created_at
        ) VALUES (
            p_cliente_id,
            v_rendicion_id,
            NULL,
            v_exceso,
            'abono_recaudacion',
            'Excedente en formas de pago de rendiciÃ³n de cuentas ID: ' || v_rendicion_id,
            NOW()
        );

        UPDATE public.clientes
        SET saldo_favor = COALESCE(saldo_favor, 0.00) + v_exceso
        WHERE id = p_cliente_id;
    END IF;

    -- 9. Retorno Exitoso
    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'rendicion_id', v_rendicion_id,
            'tasa_cambio', v_tasa_cambio,
            'total_ordenes', v_total_ordenes,
            'total_ordenes_bs', v_total_ordenes_bs,
            'total_pagos', v_total_pagos,
            'total_pagos_bs', v_total_pagos_bs,
            'saldo_favor_usado', v_saldo_favor_usado,
            'saldo_favor_generado', v_exceso
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


-- 9. FunciÃ³n reporte_recaudaciones_gerenciales (Multimoneda)
CREATE OR REPLACE FUNCTION public.reporte_recaudaciones_gerenciales(
    p_fecha_desde DATE DEFAULT NULL,
    p_fecha_hasta DATE DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_data JSON;
    v_desde TIMESTAMP WITH TIME ZONE;
    v_hasta TIMESTAMP WITH TIME ZONE;
BEGIN
    -- Configurar fechas por defecto si no son pasadas (mes actual)
    v_desde := COALESCE(p_fecha_desde::TIMESTAMP WITH TIME ZONE, date_trunc('month', CURRENT_DATE));
    v_hasta := COALESCE((p_fecha_hasta + INTERVAL '1 day - 1 microsecond')::TIMESTAMP WITH TIME ZONE, CURRENT_TIMESTAMP);

    SELECT json_agg(
        json_build_object(
            'rendicion_id', rc.id,
            'fecha_rendicion', rc.fecha_rendicion,
            'tasa_cambio', COALESCE(rc.tasa_cambio, 1.0000),
            'cliente_id', rc.cliente_id,
            'cliente_nombre', c.razon_social,
            'cliente_rif', c.rif_nit,
            'estado', rc.estado,
            'total_efectivo_recaudado', rc.total_efectivo_recaudado,
            'total_transferencias_recaudado', rc.total_transferencias_recaudado,
            'total_recaudado_usd', COALESCE(rc.total_recaudado_usd, 0.00),
            'total_recaudado_bs', COALESCE(rc.total_recaudado_bs, 0.00),
            'observaciones', rc.observaciones,
            'detalle_fpagos', COALESCE(fpagos_agg.fpagos, '[]'::json),
            'detalle_ordenes', COALESCE(ordenes_agg.ordenes, '[]'::json)
        ) ORDER BY rc.fecha_rendicion DESC
    ) INTO v_data
    FROM public.rendiciones_cuentas rc
    JOIN public.clientes c ON rc.cliente_id = c.id
    LEFT JOIN LATERAL (
        SELECT json_agg(
            json_build_object(
                'fpago_id', dfp.fpago_id,
                'concepto', fp.fpago_concepto,
                'monto', dfp.monto,
                'monto_bs', COALESCE(dfp.monto_bs, 0.00),
                'monto_usd', COALESCE(dfp.monto_usd, dfp.monto, 0.00),
                'cuenta_bancaria_id', dfp.cuenta_bancaria_id,
                'entidad_bancaria', cbe.entidad_bancaria,
                'cuenta_bancaria', COALESCE(cbe.cuenta_bancaria, dfp.cuenta_bancaria),
                'referencia_bancaria', dfp.referencia_bancaria,
                'capture_url', dfp.capture_url
            )
        ) AS fpagos
        FROM public.detalle_rendicion_fpagos dfp
        LEFT JOIN public.fpagos fp ON dfp.fpago_id = fp.fpago_id
        LEFT JOIN public.cuentas_bancarias_empresa cbe ON dfp.cuenta_bancaria_id = cbe.id
        WHERE dfp.rendicion_id = rc.id
    ) fpagos_agg ON TRUE
    LEFT JOIN LATERAL (
        SELECT json_agg(
            json_build_object(
                'orden_id', dro.orden_distribucion_id,
                'correlativo', od.correlativo,
                'recaudado', dro.recaudado,
                'recaudado_bs', COALESCE(dro.recaudado_bs, 0.00)
            )
        ) AS ordenes
        FROM public.detalle_rendicion_ordenes dro
        LEFT JOIN public.ordenes_distribucion od ON dro.orden_distribucion_id = od.id
        WHERE dro.rendicion_id = rc.id
    ) ordenes_agg ON TRUE
    WHERE rc.fecha_rendicion >= v_desde
      AND rc.fecha_rendicion <= v_hasta;

    RETURN json_build_object(
        'success', true,
        'data', COALESCE(v_data, '[]'::json),
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
-- MigraciÃ³n: MÃ³dulo de Consulta de Lista de Radares por Rango de Fecha y Detalle de Ã“rdenes por Radar ID

-- =============================================================================
-- 1. RPC: retorna_lista_radars_segun_rango_fechas
-- =============================================================================
CREATE OR REPLACE FUNCTION public.retorna_lista_radars_segun_rango_fechas(
    p_despachador_id UUID DEFAULT NULL,
    p_fecha_inicial DATE DEFAULT NULL,
    p_fecha_limite DATE DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_despachador_id UUID;
    v_resultado JSONB;
BEGIN
    -- Si no se pasa despachador_id, toma el usuario autenticado
    v_despachador_id := COALESCE(p_despachador_id, auth.uid());

    IF v_despachador_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'Se requiere el ID de despachador o estar autenticado.'
            )
        );
    END IF;

    SELECT jsonb_build_object(
        'success', TRUE,
        'data', COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'fecha_despacho', r.fecha_despacho,
                    'id_radar', r.id,
                    'correlativo', r.correlativo,
                    'total_paradas', COALESCE(ord_stats.total_paradas, 0),
                    'items', COALESCE(ord_stats.total_items, 0),
                    'sku', COALESCE(ord_stats.total_sku, 0),
                    'status_radar', COALESCE(r.status_radar, FALSE),
                    'aprobado', COALESCE(r.aprobado, FALSE)
                ) ORDER BY r.fecha_despacho DESC, r.correlativo DESC
            ),
            '[]'::jsonb
        ),
        'error', NULL
    ) INTO v_resultado
    FROM public.radars r
    LEFT JOIN LATERAL (
        SELECT 
            COUNT(DISTINCT o.id) AS total_paradas,
            SUM(COALESCE(d.cantidad_despachada, d.cantidad_solicitada, 0)) AS total_items,
            COUNT(DISTINCT d.producto_id) AS total_sku
        FROM public.ordenes_distribucion o
        LEFT JOIN public.detalle_distribucion d ON d.orden_id = o.id
        WHERE o.radar_id = r.id
    ) ord_stats ON TRUE
    WHERE r.despachador_id = v_despachador_id
      AND (p_fecha_inicial IS NULL OR r.fecha_despacho >= p_fecha_inicial)
      AND (p_fecha_limite IS NULL OR r.fecha_despacho <= p_fecha_limite);

    RETURN v_resultado;

EXCEPTION WHEN OTHERS THEN
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

GRANT EXECUTE ON FUNCTION public.retorna_lista_radars_segun_rango_fechas TO authenticated, service_role;

COMMENT ON FUNCTION public.retorna_lista_radars_segun_rango_fechas(UUID, DATE, DATE) IS 'Retorna la lista de radares asignados a un despachador ordenados por fecha descendente en un rango de fechas con mÃ©tricas consolidadas (paradas, items, sku).';


-- =============================================================================
-- 2. RPC: retorna_ordenes_distribucion_segun_idradar
-- =============================================================================
CREATE OR REPLACE FUNCTION public.retorna_ordenes_distribucion_segun_idradar(
    p_radar_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_resultado JSONB;
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

    SELECT jsonb_build_object(
        'success', TRUE,
        'data', COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'id_orden_distribucion', o.id,
                    'correlativo', o.correlativo,
                    'ruta', COALESCE(rut.nombre_ruta, 'Sin Ruta'),
                    'razon_social', c.razon_social,
                    'direccion_fiscal', c.direccion_fiscal,
                    'items', COALESCE(det_stats.total_items, 0),
                    'sku', COALESCE(det_stats.total_sku, 0),
                    'contenedores_retirados', COALESCE(det_stats.total_contenedores_retirados, 0)
                ) ORDER BY o.correlativo ASC
            ),
            '[]'::jsonb
        ),
        'error', NULL
    ) INTO v_resultado
    FROM public.ordenes_distribucion o
    LEFT JOIN public.clientes c ON c.id = o.cliente_id
    LEFT JOIN public.rutas rut ON c.id_ruta = rut.id_ruta
    LEFT JOIN LATERAL (
        SELECT 
            SUM(COALESCE(d.cantidad_despachada, d.cantidad_solicitada, 0)) AS total_items,
            COUNT(DISTINCT d.producto_id) AS total_sku,
            SUM(COALESCE(d.contenedores_retirados, 0)) AS total_contenedores_retirados
        FROM public.detalle_distribucion d
        WHERE d.orden_id = o.id
    ) det_stats ON TRUE
    WHERE o.radar_id = p_radar_id;

    RETURN v_resultado;

EXCEPTION WHEN OTHERS THEN
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

GRANT EXECUTE ON FUNCTION public.retorna_ordenes_distribucion_segun_idradar TO authenticated, service_role;

COMMENT ON FUNCTION public.retorna_ordenes_distribucion_segun_idradar(UUID) IS 'Retorna el detalle resumido de las Ã³rdenes de distribuciÃ³n vinculadas a un id_radar especÃ­fico.';
-- MigraciÃ³n: DepuraciÃ³n de Base de Datos y CreaciÃ³n de retorna_ordenes_por_liquidar

-- =============================================================================
-- 1. DEPURACIÃ“N DE BASE DE DATOS
-- =============================================================================

-- 1.1. Eliminar ordenes de distribuciÃ³n sin detalle (sin productos asociados)
DELETE FROM public.ordenes_distribucion od
WHERE NOT EXISTS (
    SELECT 1 FROM public.detalle_distribucion d WHERE d.orden_id = od.id
);

-- 1.2. Mantener solo los 3 primeros camiones y eliminar los demÃ¡s desvinculando FKs
WITH camiones_conservar AS (
    SELECT id FROM public.camiones ORDER BY created_at ASC LIMIT 3
)
UPDATE public.ordenes_distribucion
SET camion_id = NULL
WHERE camion_id NOT IN (SELECT id FROM camiones_conservar);

WITH camiones_conservar AS (
    SELECT id FROM public.camiones ORDER BY created_at ASC LIMIT 3
)
UPDATE public.inventario_movil
SET camion_id = NULL
WHERE camion_id NOT IN (SELECT id FROM camiones_conservar);

WITH camiones_conservar AS (
    SELECT id FROM public.camiones ORDER BY created_at ASC LIMIT 3
)
DELETE FROM public.camiones
WHERE id NOT IN (SELECT id FROM camiones_conservar);


-- =============================================================================
-- 2. RPC: retorna_ordenes_por_liquidar
-- =============================================================================
CREATE OR REPLACE FUNCTION public.retorna_ordenes_por_liquidar()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_resultado JSONB;
BEGIN
    SELECT jsonb_build_object(
        'success', TRUE,
        'data', COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'cliente_id', c.id,
                    'razon_social', c.razon_social,
                    'rif_nit', c.rif_nit,
                    'dias_vencidos', (CURRENT_DATE - MIN(od.fecha_despacho::date))::INT,
                    'cant_ordenes', COUNT(od.id),
                    'monto_por_liquidar', SUM(
                        COALESCE(od.subtotal_recaudar, od.subtotal, od.total_recaudar_usd, 0.00) - COALESCE(abonos.total_recaudado_usd, 0.00)
                    )
                ) ORDER BY (CURRENT_DATE - MIN(od.fecha_despacho::date)) DESC
            ),
            '[]'::jsonb
        ),
        'error', NULL
    ) INTO v_resultado
    FROM public.ordenes_distribucion od
    JOIN public.clientes c ON c.id = od.cliente_id
    LEFT JOIN LATERAL (
        SELECT 
            SUM(COALESCE(dro.recaudado, 0.00)) AS total_recaudado_usd
        FROM public.detalle_rendicion_ordenes dro
        JOIN public.rendiciones_cuentas rc ON dro.rendicion_id = rc.id
        WHERE dro.orden_distribucion_id = od.id
          AND rc.estado = 'aprobada'
    ) abonos ON TRUE
    WHERE od.estado = 'por_liquidar'
    GROUP BY c.id, c.razon_social, c.rif_nit;

    RETURN v_resultado;

EXCEPTION WHEN OTHERS THEN
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

GRANT EXECUTE ON FUNCTION public.retorna_ordenes_por_liquidar TO authenticated, service_role;

COMMENT ON FUNCTION public.retorna_ordenes_por_liquidar() IS 'Retorna el listado de Ã³rdenes en estado por_liquidar agrupadas por cliente y ordenadas por dÃ­as vencidos descendente.';
-- MigraciÃ³n: CorrecciÃ³n de columnas de totalizaciÃ³n en la cabecera ordenes_distribucion (total_recaudar_usd)

-- =============================================================================
-- 1. RPC: retorna_ordenes_por_liquidar
-- =============================================================================
CREATE OR REPLACE FUNCTION public.retorna_ordenes_por_liquidar()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_resultado JSONB;
BEGIN
    SELECT jsonb_build_object(
        'success', TRUE,
        'data', COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'cliente_id', c.id,
                    'razon_social', c.razon_social,
                    'rif_nit', c.rif_nit,
                    'dias_vencidos', (CURRENT_DATE - MIN(od.fecha_despacho::date))::INT,
                    'cant_ordenes', COUNT(od.id),
                    'monto_por_liquidar', SUM(
                        COALESCE(od.total_recaudar_usd, 0.00) - COALESCE(abonos.total_recaudado_usd, 0.00)
                    )
                ) ORDER BY (CURRENT_DATE - MIN(od.fecha_despacho::date)) DESC
            ),
            '[]'::jsonb
        ),
        'error', NULL
    ) INTO v_resultado
    FROM public.ordenes_distribucion od
    JOIN public.clientes c ON c.id = od.cliente_id
    LEFT JOIN LATERAL (
        SELECT 
            SUM(COALESCE(dro.recaudado, 0.00)) AS total_recaudado_usd
        FROM public.detalle_rendicion_ordenes dro
        JOIN public.rendiciones_cuentas rc ON dro.rendicion_id = rc.id
        WHERE dro.orden_distribucion_id = od.id
          AND rc.estado = 'aprobada'
    ) abonos ON TRUE
    WHERE od.estado = 'por_liquidar'
    GROUP BY c.id, c.razon_social, c.rif_nit;

    RETURN v_resultado;

EXCEPTION WHEN OTHERS THEN
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

GRANT EXECUTE ON FUNCTION public.retorna_ordenes_por_liquidar TO authenticated, service_role;


-- =============================================================================
-- 2. RPC: solicita_abonos_orden_distribucion
-- =============================================================================
CREATE OR REPLACE FUNCTION public.solicita_abonos_orden_distribucion(
    p_cliente_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_saldo_favor NUMERIC(12, 2) := 0.00;
    v_tasa_oficial NUMERIC(10, 4) := 1.0000;
    v_ordenes JSON;
BEGIN
    IF p_cliente_id IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID de cliente es requerido.'
            )
        );
    END IF;

    SELECT COALESCE(saldo_favor, 0.00) INTO v_saldo_favor
    FROM public.clientes
    WHERE id = p_cliente_id;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'CLIENTE_INEXISTENTE',
                'message', 'El cliente especificado no existe.'
            )
        );
    END IF;

    SELECT COALESCE(tasa_cambio, 1.0000) INTO v_tasa_oficial
    FROM public.tasa_cambio
    ORDER BY fecha_tasa DESC, created_at DESC
    LIMIT 1;

    SELECT json_agg(
        json_build_object(
            'orden_id', od.id,
            'correlativo', od.correlativo,
            'fecha_despacho', od.fecha_despacho,
            'tasa_orden', COALESCE(od.tasa_cambio, v_tasa_oficial),
            'monto_total_orden', COALESCE(od.total_recaudar_usd, 0.00),
            'monto_total_orden_bs', COALESCE(od.total_recaudar_bs, (COALESCE(od.total_recaudar_usd, 0.00) * COALESCE(od.tasa_cambio, v_tasa_oficial)), 0.00),
            'abonos_acumulados', COALESCE(abonos.total_recaudado_usd, 0.00),
            'abonos_acumulados_bs', COALESCE(abonos.total_recaudado_bs, 0.00),
            'saldo_pendiente', COALESCE(od.total_recaudar_usd, 0.00) - COALESCE(abonos.total_recaudado_usd, 0.00),
            'saldo_pendiente_bs', COALESCE(od.total_recaudar_bs, (COALESCE(od.total_recaudar_usd, 0.00) * COALESCE(od.tasa_cambio, v_tasa_oficial)), 0.00) - COALESCE(abonos.total_recaudado_bs, 0.00)
        ) ORDER BY od.created_at ASC
    ) INTO v_ordenes
    FROM public.ordenes_distribucion od
    LEFT JOIN LATERAL (
        SELECT 
            SUM(COALESCE(dro.recaudado, 0.00)) AS total_recaudado_usd,
            SUM(COALESCE(dro.recaudado_bs, (COALESCE(dro.recaudado, 0.00) * COALESCE(rc.tasa_cambio, v_tasa_oficial)), 0.00)) AS total_recaudado_bs
        FROM public.detalle_rendicion_ordenes dro
        JOIN public.rendiciones_cuentas rc ON dro.rendicion_id = rc.id
        WHERE dro.orden_distribucion_id = od.id
          AND rc.estado = 'aprobada'
    ) abonos ON TRUE
    WHERE od.cliente_id = p_cliente_id
      AND od.estado = 'por_liquidar';

    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'cliente_id', p_cliente_id,
            'saldo_favor', v_saldo_favor,
            'saldo_favor_bs', (v_saldo_favor * v_tasa_oficial),
            'tasa_oficial_actual', v_tasa_oficial,
            'ordenes', COALESCE(v_ordenes, '[]'::json)
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


-- =============================================================================
-- 3. RPC: liquidar_orden_distribucion
-- =============================================================================
CREATE OR REPLACE FUNCTION public.liquidar_orden_distribucion(
    p_orden_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_estado_orden TEXT;
    v_cliente_id UUID;
    v_camion_id UUID;
    v_subtotal_recaudar NUMERIC(12, 2) := 0.00;
    v_total_abonos_aprobados NUMERIC(12, 2) := 0.00;
BEGIN
    IF p_orden_id IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID de la orden es requerido.'
            )
        );
    END IF;

    SELECT estado, cliente_id, camion_id, COALESCE(total_recaudar_usd, 0.00)
    INTO v_estado_orden, v_cliente_id, v_camion_id, v_subtotal_recaudar
    FROM public.ordenes_distribucion
    WHERE id = p_orden_id;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'ORDEN_INEXISTENTE',
                'message', 'La orden de distribuciÃ³n especificada no existe.'
            )
        );
    END IF;

    IF v_estado_orden != 'por_liquidar' THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo se pueden evaluar o liquidar financieramente Ã³rdenes en estado por_liquidar.'
            )
        );
    END IF;

    SELECT COALESCE(SUM(dro.recaudado), 0.00)
    INTO v_total_abonos_aprobados
    FROM public.detalle_rendicion_ordenes dro
    JOIN public.rendiciones_cuentas rc ON dro.rendicion_id = rc.id
    WHERE dro.orden_distribucion_id = p_orden_id
      AND rc.estado = 'aprobada';

    IF v_total_abonos_aprobados >= v_subtotal_recaudar THEN
        IF v_camion_id IS NOT NULL THEN
            UPDATE public.camiones SET estado = 'disponible' WHERE id = v_camion_id;
        END IF;

        UPDATE public.ordenes_distribucion 
        SET estado = 'liquidada' 
        WHERE id = p_orden_id;

        RETURN json_build_object(
            'success', true,
            'data', json_build_object(
                'orden_id', p_orden_id,
                'nuevo_estado', 'liquidada',
                'total_recaudado', v_total_abonos_aprobados,
                'subtotal_recaudar', v_subtotal_recaudar
            ),
            'error', NULL
        );
    ELSE
        RETURN json_build_object(
            'success', true,
            'data', json_build_object(
                'orden_id', p_orden_id,
                'nuevo_estado', 'por_liquidar',
                'total_recaudado', v_total_abonos_aprobados,
                'subtotal_recaudar', v_subtotal_recaudar,
                'saldo_pendiente', (v_subtotal_recaudar - v_total_abonos_aprobados)
            ),
            'error', NULL
        );
    END IF;

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
-- MigraciÃ³n: MÃ³dulo de AprobaciÃ³n de Radar, Estado Devuelta, Reingreso a AlmacÃ©n y TransiciÃ³n a Anulada

-- =============================================================================
-- 1. DDL: Actualizar restricciÃ³n CHECK en ordenes_distribucion para permitir 'devuelta'
-- =============================================================================
ALTER TABLE public.ordenes_distribucion DROP CONSTRAINT IF EXISTS ordenes_distribucion_estado_check;

ALTER TABLE public.ordenes_distribucion 
ADD CONSTRAINT ordenes_distribucion_estado_check 
CHECK (estado IN ('borrador', 'aprobada', 'en_transito', 'despachada', 'por_liquidar', 'liquidada', 'anulada', 'devuelta'));


-- =============================================================================
-- 2. RPC: registrar_despacho_cliente_radar (Actualizado con bloqueo y estado devuelta)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.registrar_despacho_cliente_radar(
    p_orden_id UUID,
    p_detalles_json JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_estado_orden TEXT;
    v_camion_id UUID;
    v_radar_id UUID;
    v_status_radar BOOLEAN;
    v_aprobado BOOLEAN;
    v_item JSONB;
    v_detalle_id UUID;
    v_cantidad_despachada INT;
    v_estado_entrega TEXT;
    v_motivo_rechazo TEXT;
    v_contenedores_retirados INT;
    v_contenedor_id UUID;
    v_producto_id UUID;
    v_cantidad_solicitada INT;
    v_devolucion INT;
    v_pendientes_count INT;
    v_total_despachado INT := 0;
    v_cliente_id UUID;
    v_despacho_permitido BOOLEAN;
    v_excepcion_gerencia BOOLEAN;
    v_nuevo_estado_orden TEXT;
BEGIN
    IF p_orden_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El parÃ¡metro p_orden_id es obligatorio.'
            )
        );
    END IF;

    SELECT o.estado, o.camion_id, o.cliente_id, o.radar_id,
           COALESCE(c.excepcion_despacho_gerencia, FALSE),
           (COALESCE(c.excepcion_despacho_gerencia, FALSE) = TRUE OR (
               COALESCE(c.permiso_despacho_manual, TRUE) = TRUE
               AND (COALESCE(c.limite_credito, 0.00) = 0.00 OR COALESCE(o.total_recaudar_bs, 0.00) <= COALESCE(c.limite_credito, 0.00))
           ))
    INTO v_estado_orden, v_camion_id, v_cliente_id, v_radar_id, v_excepcion_gerencia, v_despacho_permitido
    FROM public.ordenes_distribucion o
    JOIN public.clientes c ON o.cliente_id = c.id
    WHERE o.id = p_orden_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'ORDEN_INEXISTENTE',
                'message', 'No se encontrÃ³ la orden especificada.'
            )
        );
    END IF;

    IF v_radar_id IS NOT NULL THEN
        SELECT COALESCE(status_radar, FALSE), COALESCE(aprobado, FALSE)
        INTO v_status_radar, v_aprobado
        FROM public.radars
        WHERE id = v_radar_id;

        IF v_status_radar = TRUE OR v_aprobado = TRUE THEN
            RETURN jsonb_build_object(
                'success', FALSE,
                'error', jsonb_build_object(
                    'code', 'RADAR_APROBADO_BLOQUEADO',
                    'message', 'El radar correspondiente ya ha sido aprobado por la Gerencia y se encuentra bloqueado para modificaciones.'
                )
            );
        END IF;
    END IF;

    IF NOT v_despacho_permitido THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'DESPACHO_BLOQUEADO_CREDITO',
                'message', 'No se puede despachar la orden: El cliente se encuentra bloqueado por polÃ­tica de crÃ©dito y no posee una excepciÃ³n gerencial activa.'
            )
        );
    END IF;

    IF v_estado_orden NOT IN ('en_transito', 'despachada', 'por_liquidar', 'devuelta') THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo se pueden registrar entregas de Ã³rdenes activas en ruta.'
            )
        );
    END IF;

    IF p_detalles_json IS NOT NULL AND jsonb_array_length(p_detalles_json) > 0 THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(p_detalles_json) LOOP
            v_detalle_id := (v_item->>'detalle_id')::UUID;
            v_cantidad_despachada := COALESCE((v_item->>'cantidad_despachada')::INT, 0);
            v_estado_entrega := v_item->>'estado_entrega';
            v_motivo_rechazo := v_item->>'motivo_rechazo';
            v_contenedores_retirados := COALESCE((v_item->>'contenedores_retirados')::INT, 0);
            v_contenedor_id := (v_item->>'contenedor_id')::UUID;

            SELECT producto_id, cantidad_solicitada INTO v_producto_id, v_cantidad_solicitada
            FROM public.detalle_distribucion
            WHERE id = v_detalle_id AND orden_id = p_orden_id;

            IF FOUND THEN
                v_devolucion := GREATEST(0, v_cantidad_solicitada - v_cantidad_despachada);

                IF v_camion_id IS NOT NULL THEN
                    UPDATE public.inventario_movil
                    SET cantidad_entregada = cantidad_entregada + v_cantidad_despachada,
                        cantidad_devolucion = cantidad_devolucion + v_devolucion,
                        updated_at = NOW()
                    WHERE camion_id = v_camion_id AND producto_id = v_producto_id;
                END IF;

                UPDATE public.detalle_distribucion
                SET cantidad_despachada = v_cantidad_despachada,
                    estado_entrega = COALESCE(v_estado_entrega, CASE WHEN v_cantidad_despachada > 0 THEN 'entregado' ELSE 'rechazado' END),
                    motivo_rechazo = v_motivo_rechazo,
                    contenedores_retirados = v_contenedores_retirados,
                    contenedor_id = v_contenedor_id
                WHERE id = v_detalle_id;
            END IF;
        END LOOP;
    END IF;

    SELECT COUNT(*) INTO v_pendientes_count
    FROM public.detalle_distribucion
    WHERE orden_id = p_orden_id AND (estado_entrega IS NULL OR estado_entrega = 'pendiente');

    IF v_pendientes_count = 0 THEN
        SELECT COALESCE(SUM(cantidad_despachada), 0) INTO v_total_despachado
        FROM public.detalle_distribucion
        WHERE orden_id = p_orden_id;

        IF v_total_despachado = 0 THEN
            v_nuevo_estado_orden := 'devuelta';
        ELSE
            v_nuevo_estado_orden := 'por_liquidar';
        END IF;

        UPDATE public.ordenes_distribucion
        SET estado = v_nuevo_estado_orden
        WHERE id = p_orden_id;

        IF v_excepcion_gerencia THEN
            UPDATE public.clientes
            SET excepcion_despacho_gerencia = FALSE
            WHERE id = v_cliente_id;
        END IF;
    ELSE
        v_nuevo_estado_orden := v_estado_orden;
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Despacho registrado en radar exitosamente.',
        'data', jsonb_build_object(
            'orden_id', p_orden_id,
            'nuevo_estado', v_nuevo_estado_orden,
            'total_despachado', v_total_despachado
        ),
        'error', NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', SQLSTATE,
                'message', SQLERRM
            )
        );
END;
$$;

GRANT EXECUTE ON FUNCTION public.registrar_despacho_cliente_radar TO authenticated, service_role;


-- =============================================================================
-- 3. RPC: retorna_inventario_no_despachado_para_almacen
-- =============================================================================
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
        UPDATE public.productos
        SET stock_disponible = stock_disponible + v_rec.total_devuelto,
            updated_at = NOW()
        WHERE id = v_rec.producto_id;

        IF v_rec.camion_id IS NOT NULL THEN
            UPDATE public.inventario_movil
            SET cantidad_cargada = GREATEST(0, cantidad_cargada - v_rec.total_devuelto),
                updated_at = NOW()
            WHERE camion_id = v_rec.camion_id AND producto_id = v_rec.producto_id;
        END IF;

        v_detalles := v_detalles || jsonb_build_object(
            'producto_id', v_rec.producto_id,
            'codigo_producto', v_rec.codigo_producto,
            'nombre_producto', v_rec.nombre_producto,
            'cantidad_devuelta', v_rec.total_devuelto
        );
    END LOOP;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Inventario no despachado retornado exitosamente al almacÃ©n principal.',
        'data', v_detalles,
        'error', NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', SQLSTATE,
                'message', SQLERRM
            )
        );
END;
$$;

GRANT EXECUTE ON FUNCTION public.retorna_inventario_no_despachado_para_almacen TO authenticated, service_role;


-- =============================================================================
-- 4. RPC: solicita_aprobar_radar
-- =============================================================================
CREATE OR REPLACE FUNCTION public.solicita_aprobar_radar(
    p_radar_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_despachador_id UUID;
    v_fecha_despacho DATE;
    v_status_radar BOOLEAN;
    v_aprobado BOOLEAN;
    v_rec RECORD;
    v_inv_res JSONB;
    v_ordenes_anuladas_count INT := 0;
    v_contenedores_procesados INT := 0;
BEGIN
    IF p_radar_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID del radar es obligatorio.'
            )
        );
    END IF;

    SELECT despachador_id, fecha_despacho, COALESCE(status_radar, FALSE), COALESCE(aprobado, FALSE)
    INTO v_despachador_id, v_fecha_despacho, v_status_radar, v_aprobado
    FROM public.radars
    WHERE id = p_radar_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'RADAR_INEXISTENTE',
                'message', 'El radar especificado no existe.'
            )
        );
    END IF;

    IF v_status_radar = TRUE AND v_aprobado = TRUE THEN
        RETURN jsonb_build_object(
            'success', TRUE,
            'message', 'El radar ya se encuentra previamente aprobado.',
            'data', jsonb_build_object(
                'radar_id', p_radar_id,
                'status_radar', TRUE,
                'aprobado', TRUE
            ),
            'error', NULL
        );
    END IF;

    UPDATE public.radars
    SET status_radar = TRUE,
        aprobado = TRUE
    WHERE id = p_radar_id;

    FOR v_rec IN
        SELECT 
            o.cliente_id,
            d.orden_id,
            COALESCE(d.contenedor_id, p.contenedor_id) AS contenedor_id,
            SUM(COALESCE(d.contenedores_retirados, 0)) AS total_retirados
        FROM public.ordenes_distribucion o
        JOIN public.detalle_distribucion d ON d.orden_id = o.id
        LEFT JOIN public.productos p ON p.id = d.producto_id
        WHERE o.radar_id = p_radar_id
          AND COALESCE(d.contenedores_retirados, 0) > 0
        GROUP BY o.cliente_id, d.orden_id, COALESCE(d.contenedor_id, p.contenedor_id)
    LOOP
        IF v_rec.contenedor_id IS NOT NULL THEN
            INSERT INTO public.movimientos_contenedores (
                cliente_id, orden_id, contenedor_id, cantidad_entregada, cantidad_retirada, creado_por
            ) VALUES (
                v_rec.cliente_id, v_rec.orden_id, v_rec.contenedor_id, 0, v_rec.total_retirados, auth.uid()
            );

            UPDATE public.saldo_contenedores_clientes
            SET saldo_pendiente = GREATEST(0, saldo_pendiente - v_rec.total_retirados),
                updated_at = NOW()
            WHERE cliente_id = v_rec.cliente_id AND contenedor_id = v_rec.contenedor_id;

            v_contenedores_procesados := v_contenedores_procesados + v_rec.total_retirados;
        END IF;
    END LOOP;

    v_inv_res := public.retorna_inventario_no_despachado_para_almacen(p_radar_id);

    WITH ordenes_devueltas AS (
        UPDATE public.ordenes_distribucion
        SET estado = 'anulada'
        WHERE radar_id = p_radar_id AND estado = 'devuelta'
        RETURNING id
    )
    SELECT COUNT(*) INTO v_ordenes_anuladas_count FROM ordenes_devueltas;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Radar aprobado exitosamente. Saldos de contenedores actualizados, inventario restituido a almacÃ©n y Ã³rdenes devueltas anuladas.',
        'data', jsonb_build_object(
            'radar_id', p_radar_id,
            'status_radar', TRUE,
            'aprobado', TRUE,
            'contenedores_procesados', v_contenedores_procesados,
            'ordenes_anuladas', v_ordenes_anuladas_count,
            'inventario_reintegrado', COALESCE(v_inv_res->'data', '[]'::jsonb)
        ),
        'error', NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', SQLSTATE,
                'message', SQLERRM
            )
        );
END;
$$;

GRANT EXECUTE ON FUNCTION public.solicita_aprobar_radar TO authenticated, service_role;
-- MigraciÃ³n: Asegurar existencia de columna 'aprobado' en public.radars, depuraciÃ³n de Ã³rdenes con camion_id o vendedor_id NULOS y actualizaciÃ³n de RPCs

-- =============================================================================
-- 1. DDL: Asegurar columna 'aprobado' en public.radars
-- =============================================================================
ALTER TABLE public.radars ADD COLUMN IF NOT EXISTS aprobado BOOLEAN DEFAULT FALSE;


-- =============================================================================
-- 2. DEPURACIÃ“N: Eliminar ordenes con camion_id IS NULL o vendedor_id IS NULL
-- =============================================================================
DELETE FROM public.detalle_distribucion
WHERE orden_id IN (
    SELECT id FROM public.ordenes_distribucion
    WHERE camion_id IS NULL OR vendedor_id IS NULL
);

DELETE FROM public.ordenes_distribucion
WHERE camion_id IS NULL OR vendedor_id IS NULL;


-- =============================================================================
-- 3. RPC: registrar_despacho_cliente_radar
-- =============================================================================
CREATE OR REPLACE FUNCTION public.registrar_despacho_cliente_radar(
    p_orden_id UUID,
    p_detalles_json JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_estado_orden TEXT;
    v_camion_id UUID;
    v_radar_id UUID;
    v_status_radar BOOLEAN;
    v_aprobado BOOLEAN;
    v_item JSONB;
    v_detalle_id UUID;
    v_cantidad_despachada INT;
    v_estado_entrega TEXT;
    v_motivo_rechazo TEXT;
    v_contenedores_retirados INT;
    v_contenedor_id UUID;
    v_producto_id UUID;
    v_cantidad_solicitada INT;
    v_devolucion INT;
    v_pendientes_count INT;
    v_total_despachado INT := 0;
    v_cliente_id UUID;
    v_despacho_permitido BOOLEAN;
    v_excepcion_gerencia BOOLEAN;
    v_nuevo_estado_orden TEXT;
BEGIN
    IF p_orden_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El parÃ¡metro p_orden_id es obligatorio.'
            )
        );
    END IF;

    SELECT o.estado, o.camion_id, o.cliente_id, o.radar_id,
           COALESCE(c.excepcion_despacho_gerencia, FALSE),
           (COALESCE(c.excepcion_despacho_gerencia, FALSE) = TRUE OR (
               COALESCE(c.permiso_despacho_manual, TRUE) = TRUE
               AND (COALESCE(c.limite_credito, 0.00) = 0.00 OR COALESCE(o.total_recaudar_bs, 0.00) <= COALESCE(c.limite_credito, 0.00))
           ))
    INTO v_estado_orden, v_camion_id, v_cliente_id, v_radar_id, v_excepcion_gerencia, v_despacho_permitido
    FROM public.ordenes_distribucion o
    JOIN public.clientes c ON o.cliente_id = c.id
    WHERE o.id = p_orden_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'ORDEN_INEXISTENTE',
                'message', 'No se encontrÃ³ la orden especificada.'
            )
        );
    END IF;

    IF v_radar_id IS NOT NULL THEN
        SELECT COALESCE(status_radar, FALSE), COALESCE(aprobado, FALSE)
        INTO v_status_radar, v_aprobado
        FROM public.radars
        WHERE id = v_radar_id;

        IF v_status_radar = TRUE OR v_aprobado = TRUE THEN
            RETURN jsonb_build_object(
                'success', FALSE,
                'error', jsonb_build_object(
                    'code', 'RADAR_APROBADO_BLOQUEADO',
                    'message', 'El radar correspondiente ya ha sido aprobado por la Gerencia y se encuentra bloqueado para modificaciones.'
                )
            );
        END IF;
    END IF;

    IF NOT v_despacho_permitido THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'DESPACHO_BLOQUEADO_CREDITO',
                'message', 'No se puede despachar la orden: El cliente se encuentra bloqueado por polÃ­tica de crÃ©dito y no posee una excepciÃ³n gerencial activa.'
            )
        );
    END IF;

    IF v_estado_orden NOT IN ('en_transito', 'despachada', 'por_liquidar', 'devuelta') THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo se pueden registrar entregas de Ã³rdenes activas en ruta.'
            )
        );
    END IF;

    IF p_detalles_json IS NOT NULL AND jsonb_array_length(p_detalles_json) > 0 THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(p_detalles_json) LOOP
            v_detalle_id := (v_item->>'detalle_id')::UUID;
            v_cantidad_despachada := COALESCE((v_item->>'cantidad_despachada')::INT, 0);
            v_estado_entrega := v_item->>'estado_entrega';
            v_motivo_rechazo := v_item->>'motivo_rechazo';
            v_contenedores_retirados := COALESCE((v_item->>'contenedores_retirados')::INT, 0);
            v_contenedor_id := (v_item->>'contenedor_id')::UUID;

            SELECT producto_id, cantidad_solicitada INTO v_producto_id, v_cantidad_solicitada
            FROM public.detalle_distribucion
            WHERE id = v_detalle_id AND orden_id = p_orden_id;

            IF FOUND THEN
                v_devolucion := GREATEST(0, v_cantidad_solicitada - v_cantidad_despachada);

                IF v_camion_id IS NOT NULL THEN
                    UPDATE public.inventario_movil
                    SET cantidad_entregada = cantidad_entregada + v_cantidad_despachada,
                        cantidad_devolucion = cantidad_devolucion + v_devolucion,
                        updated_at = NOW()
                    WHERE camion_id = v_camion_id AND producto_id = v_producto_id;
                END IF;

                UPDATE public.detalle_distribucion
                SET cantidad_despachada = v_cantidad_despachada,
                    estado_entrega = COALESCE(v_estado_entrega, CASE WHEN v_cantidad_despachada > 0 THEN 'entregado' ELSE 'rechazado' END),
                    motivo_rechazo = v_motivo_rechazo,
                    contenedores_retirados = v_contenedores_retirados,
                    contenedor_id = v_contenedor_id
                WHERE id = v_detalle_id;
            END IF;
        END LOOP;
    END IF;

    SELECT COUNT(*) INTO v_pendientes_count
    FROM public.detalle_distribucion
    WHERE orden_id = p_orden_id AND (estado_entrega IS NULL OR estado_entrega = 'pendiente');

    IF v_pendientes_count = 0 THEN
        SELECT COALESCE(SUM(cantidad_despachada), 0) INTO v_total_despachado
        FROM public.detalle_distribucion
        WHERE orden_id = p_orden_id;

        IF v_total_despachado = 0 THEN
            v_nuevo_estado_orden := 'devuelta';
        ELSE
            v_nuevo_estado_orden := 'por_liquidar';
        END IF;

        UPDATE public.ordenes_distribucion
        SET estado = v_nuevo_estado_orden
        WHERE id = p_orden_id;

        IF v_excepcion_gerencia THEN
            UPDATE public.clientes
            SET excepcion_despacho_gerencia = FALSE
            WHERE id = v_cliente_id;
        END IF;
    ELSE
        v_nuevo_estado_orden := v_estado_orden;
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Despacho registrado en radar exitosamente.',
        'data', jsonb_build_object(
            'orden_id', p_orden_id,
            'nuevo_estado', v_nuevo_estado_orden,
            'total_despachado', v_total_despachado
        ),
        'error', NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', SQLSTATE,
                'message', SQLERRM
            )
        );
END;
$$;

GRANT EXECUTE ON FUNCTION public.registrar_despacho_cliente_radar TO authenticated, service_role;
-- MigraciÃ³n: EstandarizaciÃ³n de status_radar como Ãºnico campo de aprobaciÃ³n y eliminaciÃ³n de la columna aprobado

-- =============================================================================
-- 1. DDL: Eliminar la columna aprobado de la tabla public.radars
-- =============================================================================
ALTER TABLE public.radars DROP COLUMN IF EXISTS aprobado;


-- =============================================================================
-- 2. RPC: crear_o_obtener_radar
-- =============================================================================
CREATE OR REPLACE FUNCTION public.crear_o_obtener_radar(
    p_despachador_id UUID DEFAULT NULL,
    p_fecha_despacho DATE DEFAULT CURRENT_DATE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_despachador_id UUID;
    v_radar_id UUID;
    v_correlativo INT;
    v_status_radar BOOLEAN;
    v_tot_solicitada NUMERIC(10,0);
    v_tot_despachada NUMERIC(10,0);
    v_tot_retirados NUMERIC(10,0);
    v_total_ordenes INT;
    v_resultado JSONB;
BEGIN
    v_despachador_id := COALESCE(p_despachador_id, auth.uid());

    IF v_despachador_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_REQUERIDO',
                'message', 'Se requiere especificar un despachador_id o estar autenticado.'
            )
        );
    END IF;

    SELECT id, correlativo, status_radar
    INTO v_radar_id, v_correlativo, v_status_radar
    FROM public.radars
    WHERE despachador_id = v_despachador_id
      AND fecha_despacho = p_fecha_despacho
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_radar_id IS NULL THEN
        INSERT INTO public.radars (despachador_id, fecha_despacho, status_radar)
        VALUES (v_despachador_id, p_fecha_despacho, FALSE)
        RETURNING id, correlativo, status_radar INTO v_radar_id, v_correlativo, v_status_radar;
    END IF;

    UPDATE public.ordenes_distribucion o
    SET radar_id = v_radar_id
    FROM public.clientes c
    WHERE o.cliente_id = c.id
      AND c.despachador_id = v_despachador_id
      AND o.fecha_despacho::date = p_fecha_despacho
      AND o.estado IN ('aprobada', 'en_transito', 'por_liquidar', 'liquidada', 'devuelta')
      AND (o.radar_id IS NULL OR o.radar_id = v_radar_id);

    SELECT 
        COALESCE(SUM(d.cantidad_solicitada), 0),
        COALESCE(SUM(d.cantidad_despachada), 0),
        COALESCE(SUM(d.contenedores_retirados), 0),
        COUNT(DISTINCT o.id)
    INTO v_tot_solicitada, v_tot_despachada, v_tot_retirados, v_total_ordenes
    FROM public.ordenes_distribucion o
    JOIN public.detalle_distribucion d ON d.orden_id = o.id
    WHERE o.radar_id = v_radar_id;

    UPDATE public.radars
    SET total_cantidad_solicitada = v_tot_solicitada,
        total_cantidad_despachada = v_tot_despachada,
        total_contenedores_retirados = v_tot_retirados
    WHERE id = v_radar_id;

    SELECT jsonb_build_object(
        'success', TRUE,
        'message', 'Radar obtenido/creado exitosamente.',
        'data', jsonb_build_object(
            'id', v_radar_id,
            'correlativo', v_correlativo,
            'despachador_id', v_despachador_id,
            'fecha_despacho', p_fecha_despacho,
            'status_radar', v_status_radar,
            'total_cantidad_solicitada', v_tot_solicitada,
            'total_cantidad_despachada', v_tot_despachada,
            'total_contenedores_retirados', v_tot_retirados,
            'total_ordenes', v_total_ordenes
        )
    ) INTO v_resultado;

    RETURN v_resultado;
END;
$$;

GRANT EXECUTE ON FUNCTION public.crear_o_obtener_radar TO authenticated, service_role;


-- =============================================================================
-- 3. RPC: retorna_lista_radars_segun_rango_fechas
-- =============================================================================
CREATE OR REPLACE FUNCTION public.retorna_lista_radars_segun_rango_fechas(
    p_despachador_id UUID DEFAULT NULL,
    p_fecha_inicial DATE DEFAULT NULL,
    p_fecha_limite DATE DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_despachador_id UUID;
    v_resultado JSONB;
BEGIN
    v_despachador_id := COALESCE(p_despachador_id, auth.uid());

    IF v_despachador_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'Se requiere el ID de despachador o estar autenticado.'
            )
        );
    END IF;

    SELECT jsonb_build_object(
        'success', TRUE,
        'data', COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'fecha_despacho', r.fecha_despacho,
                    'id_radar', r.id,
                    'correlativo', r.correlativo,
                    'total_paradas', COALESCE(ord_stats.total_paradas, 0),
                    'items', COALESCE(ord_stats.total_items, 0),
                    'sku', COALESCE(ord_stats.total_sku, 0),
                    'status_radar', COALESCE(r.status_radar, FALSE)
                ) ORDER BY r.fecha_despacho DESC, r.correlativo DESC
            ),
            '[]'::jsonb
        ),
        'error', NULL
    ) INTO v_resultado
    FROM public.radars r
    LEFT JOIN LATERAL (
        SELECT 
            COUNT(DISTINCT o.id) AS total_paradas,
            SUM(COALESCE(d.cantidad_despachada, d.cantidad_solicitada, 0)) AS total_items,
            COUNT(DISTINCT d.producto_id) AS total_sku
        FROM public.ordenes_distribucion o
        LEFT JOIN public.detalle_distribucion d ON d.orden_id = o.id
        WHERE o.radar_id = r.id
    ) ord_stats ON TRUE
    WHERE r.despachador_id = v_despachador_id
      AND (p_fecha_inicial IS NULL OR r.fecha_despacho >= p_fecha_inicial)
      AND (p_fecha_limite IS NULL OR r.fecha_despacho <= p_fecha_limite);

    RETURN v_resultado;

EXCEPTION WHEN OTHERS THEN
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

GRANT EXECUTE ON FUNCTION public.retorna_lista_radars_segun_rango_fechas TO authenticated, service_role;


-- =============================================================================
-- 4. RPC: registrar_despacho_cliente_radar
-- =============================================================================
CREATE OR REPLACE FUNCTION public.registrar_despacho_cliente_radar(
    p_orden_id UUID,
    p_detalles_json JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_estado_orden TEXT;
    v_camion_id UUID;
    v_radar_id UUID;
    v_status_radar BOOLEAN;
    v_item JSONB;
    v_detalle_id UUID;
    v_cantidad_despachada INT;
    v_estado_entrega TEXT;
    v_motivo_rechazo TEXT;
    v_contenedores_retirados INT;
    v_contenedor_id UUID;
    v_producto_id UUID;
    v_cantidad_solicitada INT;
    v_devolucion INT;
    v_pendientes_count INT;
    v_total_despachado INT := 0;
    v_cliente_id UUID;
    v_despacho_permitido BOOLEAN;
    v_excepcion_gerencia BOOLEAN;
    v_nuevo_estado_orden TEXT;
BEGIN
    IF p_orden_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El parÃ¡metro p_orden_id es obligatorio.'
            )
        );
    END IF;

    SELECT o.estado, o.camion_id, o.cliente_id, o.radar_id,
           COALESCE(c.excepcion_despacho_gerencia, FALSE),
           (COALESCE(c.excepcion_despacho_gerencia, FALSE) = TRUE OR (
               COALESCE(c.permiso_despacho_manual, TRUE) = TRUE
               AND (COALESCE(c.limite_credito, 0.00) = 0.00 OR COALESCE(o.total_recaudar_bs, 0.00) <= COALESCE(c.limite_credito, 0.00))
           ))
    INTO v_estado_orden, v_camion_id, v_cliente_id, v_radar_id, v_excepcion_gerencia, v_despacho_permitido
    FROM public.ordenes_distribucion o
    JOIN public.clientes c ON o.cliente_id = c.id
    WHERE o.id = p_orden_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'ORDEN_INEXISTENTE',
                'message', 'No se encontrÃ³ la orden especificada.'
            )
        );
    END IF;

    IF v_radar_id IS NOT NULL THEN
        SELECT COALESCE(status_radar, FALSE)
        INTO v_status_radar
        FROM public.radars
        WHERE id = v_radar_id;

        IF v_status_radar = TRUE THEN
            RETURN jsonb_build_object(
                'success', FALSE,
                'error', jsonb_build_object(
                    'code', 'RADAR_APROBADO_BLOQUEADO',
                    'message', 'El radar correspondiente ya ha sido aprobado por la Gerencia y se encuentra bloqueado para modificaciones.'
                )
            );
        END IF;
    END IF;

    IF NOT v_despacho_permitido THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'DESPACHO_BLOQUEADO_CREDITO',
                'message', 'No se puede despachar la orden: El cliente se encuentra bloqueado por polÃ­tica de crÃ©dito y no posee una excepciÃ³n gerencial activa.'
            )
        );
    END IF;

    IF v_estado_orden NOT IN ('en_transito', 'despachada', 'por_liquidar', 'devuelta') THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo se pueden registrar entregas de Ã³rdenes activas en ruta.'
            )
        );
    END IF;

    IF p_detalles_json IS NOT NULL AND jsonb_array_length(p_detalles_json) > 0 THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(p_detalles_json) LOOP
            v_detalle_id := (v_item->>'detalle_id')::UUID;
            v_cantidad_despachada := COALESCE((v_item->>'cantidad_despachada')::INT, 0);
            v_estado_entrega := v_item->>'estado_entrega';
            v_motivo_rechazo := v_item->>'motivo_rechazo';
            v_contenedores_retirados := COALESCE((v_item->>'contenedores_retirados')::INT, 0);
            v_contenedor_id := (v_item->>'contenedor_id')::UUID;

            SELECT producto_id, cantidad_solicitada INTO v_producto_id, v_cantidad_solicitada
            FROM public.detalle_distribucion
            WHERE id = v_detalle_id AND orden_id = p_orden_id;

            IF FOUND THEN
                v_devolucion := GREATEST(0, v_cantidad_solicitada - v_cantidad_despachada);

                IF v_camion_id IS NOT NULL THEN
                    UPDATE public.inventario_movil
                    SET cantidad_entregada = cantidad_entregada + v_cantidad_despachada,
                        cantidad_devolucion = cantidad_devolucion + v_devolucion,
                        updated_at = NOW()
                    WHERE camion_id = v_camion_id AND producto_id = v_producto_id;
                END IF;

                UPDATE public.detalle_distribucion
                SET cantidad_despachada = v_cantidad_despachada,
                    estado_entrega = COALESCE(v_estado_entrega, CASE WHEN v_cantidad_despachada > 0 THEN 'entregado' ELSE 'rechazado' END),
                    motivo_rechazo = v_motivo_rechazo,
                    contenedores_retirados = v_contenedores_retirados,
                    contenedor_id = v_contenedor_id
                WHERE id = v_detalle_id;
            END IF;
        END LOOP;
    END IF;

    SELECT COUNT(*) INTO v_pendientes_count
    FROM public.detalle_distribucion
    WHERE orden_id = p_orden_id AND (estado_entrega IS NULL OR estado_entrega = 'pendiente');

    IF v_pendientes_count = 0 THEN
        SELECT COALESCE(SUM(cantidad_despachada), 0) INTO v_total_despachado
        FROM public.detalle_distribucion
        WHERE orden_id = p_orden_id;

        IF v_total_despachado = 0 THEN
            v_nuevo_estado_orden := 'devuelta';
        ELSE
            v_nuevo_estado_orden := 'por_liquidar';
        END IF;

        UPDATE public.ordenes_distribucion
        SET estado = v_nuevo_estado_orden
        WHERE id = p_orden_id;

        IF v_excepcion_gerencia THEN
            UPDATE public.clientes
            SET excepcion_despacho_gerencia = FALSE
            WHERE id = v_cliente_id;
        END IF;
    ELSE
        v_nuevo_estado_orden := v_estado_orden;
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Despacho registrado en radar exitosamente.',
        'data', jsonb_build_object(
            'orden_id', p_orden_id,
            'nuevo_estado', v_nuevo_estado_orden,
            'total_despachado', v_total_despachado
        ),
        'error', NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', SQLSTATE,
                'message', SQLERRM
            )
        );
END;
$$;

GRANT EXECUTE ON FUNCTION public.registrar_despacho_cliente_radar TO authenticated, service_role;


-- =============================================================================
-- 5. RPC: solicita_aprobar_radar
-- =============================================================================
CREATE OR REPLACE FUNCTION public.solicita_aprobar_radar(
    p_radar_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_despachador_id UUID;
    v_fecha_despacho DATE;
    v_status_radar BOOLEAN;
    v_rec RECORD;
    v_inv_res JSONB;
    v_ordenes_anuladas_count INT := 0;
    v_contenedores_procesados INT := 0;
BEGIN
    IF p_radar_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID del radar es obligatorio.'
            )
        );
    END IF;

    SELECT despachador_id, fecha_despacho, COALESCE(status_radar, FALSE)
    INTO v_despachador_id, v_fecha_despacho, v_status_radar
    FROM public.radars
    WHERE id = p_radar_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'RADAR_INEXISTENTE',
                'message', 'El radar especificado no existe.'
            )
        );
    END IF;

    IF v_status_radar = TRUE THEN
        RETURN jsonb_build_object(
            'success', TRUE,
            'message', 'El radar ya se encuentra previamente aprobado.',
            'data', jsonb_build_object(
                'radar_id', p_radar_id,
                'status_radar', TRUE
            ),
            'error', NULL
        );
    END IF;

    UPDATE public.radars
    SET status_radar = TRUE
    WHERE id = p_radar_id;

    FOR v_rec IN
        SELECT 
            o.cliente_id,
            d.orden_id,
            COALESCE(d.contenedor_id, p.contenedor_id) AS contenedor_id,
            SUM(COALESCE(d.contenedores_retirados, 0)) AS total_retirados
        FROM public.ordenes_distribucion o
        JOIN public.detalle_distribucion d ON d.orden_id = o.id
        LEFT JOIN public.productos p ON p.id = d.producto_id
        WHERE o.radar_id = p_radar_id
          AND COALESCE(d.contenedores_retirados, 0) > 0
        GROUP BY o.cliente_id, d.orden_id, COALESCE(d.contenedor_id, p.contenedor_id)
    LOOP
        IF v_rec.contenedor_id IS NOT NULL THEN
            INSERT INTO public.movimientos_contenedores (
                cliente_id, orden_id, contenedor_id, cantidad_entregada, cantidad_retirada, creado_por
            ) VALUES (
                v_rec.cliente_id, v_rec.orden_id, v_rec.contenedor_id, 0, v_rec.total_retirados, auth.uid()
            );

            UPDATE public.saldo_contenedores_clientes
            SET saldo_pendiente = GREATEST(0, saldo_pendiente - v_rec.total_retirados),
                updated_at = NOW()
            WHERE cliente_id = v_rec.cliente_id AND contenedor_id = v_rec.contenedor_id;

            v_contenedores_procesados := v_contenedores_procesados + v_rec.total_retirados;
        END IF;
    END LOOP;

    v_inv_res := public.retorna_inventario_no_despachado_para_almacen(p_radar_id);

    WITH ordenes_devueltas AS (
        UPDATE public.ordenes_distribucion
        SET estado = 'anulada'
        WHERE radar_id = p_radar_id AND estado = 'devuelta'
        RETURNING id
    )
    SELECT COUNT(*) INTO v_ordenes_anuladas_count FROM ordenes_devueltas;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Radar aprobado exitosamente. Saldos de contenedores actualizados, inventario restituido a almacÃ©n y Ã³rdenes devueltas anuladas.',
        'data', jsonb_build_object(
            'radar_id', p_radar_id,
            'status_radar', TRUE,
            'contenedores_procesados', v_contenedores_procesados,
            'ordenes_anuladas', v_ordenes_anuladas_count,
            'inventario_reintegrado', COALESCE(v_inv_res->'data', '[]'::jsonb)
        ),
        'error', NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', SQLSTATE,
                'message', SQLERRM
            )
        );
END;
$$;

GRANT EXECUTE ON FUNCTION public.solicita_aprobar_radar TO authenticated, service_role;
-- Migration: 20260909170000_fix_totales_multimoneda_ordenes.sql
-- Description: Fix unit price assignment and currency conversion in crear_orden_distribucion and actualiza_orden_distribucion_segun_correlativo, and update existing order records in database.

-- 1. Actualizar crear_orden_distribucion
CREATE OR REPLACE FUNCTION public.crear_orden_distribucion(
    p_vendedor_id UUID,
    p_cliente_id UUID,
    p_camion_id UUID,
    p_tasa_cambio NUMERIC DEFAULT NULL,
    p_productos_json JSONB DEFAULT '[]'::jsonb,
    p_despachador_id UUID DEFAULT NULL,
    p_id_ruta UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_orden_id UUID;
    v_correlativo INT;
    v_factura_origen VARCHAR(30);
    v_tasa_cambio NUMERIC(14,4);
    
    v_vendedor_id UUID;
    v_despachador_id UUID;
    v_id_ruta UUID;
    
    v_peso_total NUMERIC(10,2) := 0.00;
    v_total_recaudar_bs NUMERIC(14,2) := 0.00;
    v_total_recaudar_usd NUMERIC(14,2) := 0.00;
    
    v_item JSONB;
    v_secuencia INT := 1;
    v_producto_id UUID;
    v_cantidad INT;
    v_val_recaudar_bs NUMERIC(14,2);
    v_val_usd NUMERIC(14,2);
    v_subtotal_bs NUMERIC(14,2);
    v_subtotal_usd NUMERIC(14,2);
    v_peso_unitario NUMERIC(10,2);
BEGIN
    -- Validaciones bÃ¡sicas
    IF p_vendedor_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del vendedor es requerido.');
    END IF;

    IF p_cliente_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del cliente es requerido.');
    END IF;

    IF p_camion_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del camiÃ³n es requerido.');
    END IF;

    IF p_productos_json IS NULL OR jsonb_array_length(p_productos_json) = 0 THEN
        RETURN jsonb_build_object('success', false, 'message', 'Debe incluir al menos un producto en la orden.');
    END IF;

    -- Obtener informaciÃ³n del cliente (vendedor_id, despachador_id, id_ruta)
    SELECT c.vendedor_id, c.despachador_id, c.id_ruta
    INTO v_vendedor_id, v_despachador_id, v_id_ruta
    FROM public.clientes c
    WHERE c.id = p_cliente_id;

    -- Priorizar parÃ¡metros explÃ­citos si fueron proporcionados
    v_vendedor_id := COALESCE(p_vendedor_id, v_vendedor_id);
    v_despachador_id := COALESCE(p_despachador_id, v_despachador_id);
    v_id_ruta := COALESCE(p_id_ruta, v_id_ruta);

    -- Validar existencia de entidades
    IF NOT EXISTS (SELECT 1 FROM public.perfiles_usuario WHERE id = p_vendedor_id) THEN
        RETURN jsonb_build_object('success', false, 'message', 'El vendedor especificado no existe.');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.clientes WHERE id = p_cliente_id) THEN
        RETURN jsonb_build_object('success', false, 'message', 'El cliente especificado no existe.');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.camiones WHERE id = p_camion_id) THEN
        RETURN jsonb_build_object('success', false, 'message', 'El camiÃ³n especificado no existe.');
    END IF;

    -- Determinar / validar la tasa de cambio
    IF p_tasa_cambio IS NOT NULL AND p_tasa_cambio > 0 THEN
        v_tasa_cambio := p_tasa_cambio;
    ELSE
        SELECT tasa_cambio INTO v_tasa_cambio
        FROM public.tasa_cambio
        WHERE fecha_tasa = CURRENT_DATE;

        IF v_tasa_cambio IS NULL THEN
            SELECT tasa_cambio INTO v_tasa_cambio
            FROM public.tasa_cambio
            ORDER BY fecha_tasa DESC
            LIMIT 1;
        END IF;

        IF v_tasa_cambio IS NULL THEN
            RETURN jsonb_build_object(
                'success', false, 
                'message', 'No hay tasa de cambio registrada. Debe proporcionar p_tasa_cambio o registrar una tasa oficial en el sistema.'
            );
        END IF;
    END IF;

    -- Generar correlativo y nÃºmero de factura de origen automÃ¡ticamente
    v_correlativo := nextval('public.ordenes_distribucion_correlativo_seq');
    v_factura_origen := 'FAC-' || LPAD(v_correlativo::text, 6, '0');
    v_orden_id := gen_random_uuid();

    -- Validar productos y calcular totales multimoneda y peso total
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;
        
        IF v_cantidad IS NULL OR v_cantidad <= 0 THEN
            RETURN jsonb_build_object('success', false, 'message', 'La cantidad del producto debe ser mayor a cero.');
        END IF;

        SELECT peso_unitario_kg INTO v_peso_unitario
        FROM public.productos
        WHERE id = v_producto_id;

        IF NOT FOUND THEN
            RETURN jsonb_build_object('success', false, 'message', 'El producto con ID ' || v_producto_id::text || ' no existe.');
        END IF;

        -- Resolver precio unitario en USD y Bs
        v_val_usd := COALESCE((v_item->>'valor_unitario_usd')::NUMERIC, (v_item->>'precio_unitario')::NUMERIC, 0.00);
        v_val_recaudar_bs := COALESCE((v_item->>'valor_unitario_recaudar')::NUMERIC, 0.00);

        IF v_val_usd > 0 AND (v_val_recaudar_bs IS NULL OR v_val_recaudar_bs = 0) THEN
            v_val_recaudar_bs := ROUND(v_val_usd * v_tasa_cambio, 2);
        ELSIF v_val_recaudar_bs > 0 AND (v_val_usd IS NULL OR v_val_usd = 0) THEN
            v_val_usd := ROUND(v_val_recaudar_bs / v_tasa_cambio, 2);
        ELSIF v_val_usd > 0 AND v_val_recaudar_bs > 0 THEN
            v_val_recaudar_bs := ROUND(v_val_usd * v_tasa_cambio, 2);
        END IF;

        v_subtotal_usd := ROUND(v_cantidad * v_val_usd, 2);
        v_subtotal_bs := ROUND(v_cantidad * v_val_recaudar_bs, 2);

        v_peso_total := v_peso_total + (COALESCE(v_peso_unitario, 0.00) * v_cantidad);
        v_total_recaudar_usd := v_total_recaudar_usd + v_subtotal_usd;
        v_total_recaudar_bs := v_total_recaudar_bs + v_subtotal_bs;
    END LOOP;

    -- Insertar Cabecera de la Orden con estado 'aprobada'
    INSERT INTO public.ordenes_distribucion (
        id,
        correlativo,
        cliente_id,
        camion_id,
        vendedor_id,
        despachador_id,
        id_ruta,
        estado,
        fecha_despacho,
        peso_total_calculado,
        factura_origen_numero,
        creado_por,
        created_at,
        tasa_cambio,
        total_recaudar_bs,
        total_recaudar_usd
    ) VALUES (
        v_orden_id,
        v_correlativo,
        p_cliente_id,
        p_camion_id,
        v_vendedor_id,
        v_despachador_id,
        v_id_ruta,
        'aprobada',
        NULL,
        v_peso_total,
        v_factura_origen,
        p_vendedor_id,
        NOW(),
        v_tasa_cambio,
        v_total_recaudar_bs,
        v_total_recaudar_usd
    );

    -- Insertar Detalles de la Orden
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;
        
        v_val_usd := COALESCE((v_item->>'valor_unitario_usd')::NUMERIC, (v_item->>'precio_unitario')::NUMERIC, 0.00);
        v_val_recaudar_bs := COALESCE((v_item->>'valor_unitario_recaudar')::NUMERIC, 0.00);

        IF v_val_usd > 0 AND (v_val_recaudar_bs IS NULL OR v_val_recaudar_bs = 0) THEN
            v_val_recaudar_bs := ROUND(v_val_usd * v_tasa_cambio, 2);
        ELSIF v_val_recaudar_bs > 0 AND (v_val_usd IS NULL OR v_val_usd = 0) THEN
            v_val_usd := ROUND(v_val_recaudar_bs / v_tasa_cambio, 2);
        ELSIF v_val_usd > 0 AND v_val_recaudar_bs > 0 THEN
            v_val_recaudar_bs := ROUND(v_val_usd * v_tasa_cambio, 2);
        END IF;

        v_subtotal_usd := ROUND(v_cantidad * v_val_usd, 2);
        v_subtotal_bs := ROUND(v_cantidad * v_val_recaudar_bs, 2);

        INSERT INTO public.detalle_distribucion (
            id,
            orden_id,
            producto_id,
            cantidad_solicitada,
            cantidad_despachada,
            valor_unitario_recaudar,
            subtotal_recaudar,
            secuencia_entrega,
            estado_entrega,
            motivo_rechazo,
            valor_unitario_usd,
            subtotal_recaudar_usd
        ) VALUES (
            gen_random_uuid(),
            v_orden_id,
            v_producto_id,
            v_cantidad,
            0,
            v_val_recaudar_bs,
            v_subtotal_bs,
            v_secuencia,
            'pendiente',
            NULL,
            v_val_usd,
            v_subtotal_usd
        );
        
        v_secuencia := v_secuencia + 1;
    END LOOP;

    RETURN jsonb_build_object(
        'success', true, 
        'message', 'Orden de distribuciÃ³n creada exitosamente.', 
        'orden_id', v_orden_id,
        'data', jsonb_build_object(
            'orden_id', v_orden_id,
            'correlativo', v_correlativo,
            'tasa_cambio', v_tasa_cambio,
            'total_recaudar_bs', v_total_recaudar_bs,
            'total_recaudar_usd', v_total_recaudar_usd,
            'peso_total_calculado', v_peso_total
        )
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false, 
        'message', 'Error al crear la orden: ' || SQLERRM
    );
END;
$$;

-- 2. Actualizar actualiza_orden_distribucion_segun_correlativo
CREATE OR REPLACE FUNCTION public.actualiza_orden_distribucion_segun_correlativo(
    p_correlativo INT,
    p_header JSONB,
    p_detalle JSONB
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_orden_id UUID;
    v_estado_actual TEXT;
    v_creado_por UUID;
    v_vendedor_cliente_id UUID;
    v_user_id UUID := auth.uid();
    
    v_cliente_id UUID;
    v_camion_id UUID;
    v_fecha_despacho TIMESTAMPTZ;
    v_factura_origen TEXT;
    v_fecha_tasa DATE;
    v_tasa_cambio NUMERIC(14,4);
    
    v_peso_total NUMERIC(14,2) := 0.00;
    v_total_bs NUMERIC(14,2) := 0.00;
    v_total_usd NUMERIC(14,2) := 0.00;
    
    v_item JSONB;
    v_secuencia INT := 1;
    v_producto_id UUID;
    v_cantidad INT;
    v_val_recaudar_bs NUMERIC(14,2);
    v_val_usd NUMERIC(14,2);
    v_subtotal_bs NUMERIC(14,2);
    v_subtotal_usd NUMERIC(14,2);
    v_peso_unitario NUMERIC(14,2);
BEGIN
    -- 1. Validar parÃ¡metros principales
    IF p_correlativo IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El correlativo de la orden es requerido.',
                'details', NULL
            )
        );
    END IF;

    -- Obtener orden actual
    SELECT id, estado, creado_por
    INTO v_orden_id, v_estado_actual, v_creado_por
    FROM public.ordenes_distribucion
    WHERE correlativo = p_correlativo;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ORDEN_NO_ENCONTRADA',
                'message', 'No se encontrÃ³ la orden con correlativo ' || p_correlativo::text,
                'details', NULL
            )
        );
    END IF;

    -- Validar que la orden estÃ© en estado borrador para modificaciÃ³n
    IF v_estado_actual NOT IN ('borrador') THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo se pueden actualizar Ã³rdenes en estado borrador. Estado actual: ' || v_estado_actual,
                'details', NULL
            )
        );
    END IF;

    -- Validar permisos por rol (DB-012)
    IF public.user_has_role(ARRAY['vendedor']) AND NOT public.user_has_role(ARRAY['admin', 'gerente', 'despachador']) THEN
        IF v_user_id IS NOT NULL AND v_creado_por IS DISTINCT FROM v_user_id THEN
            RETURN json_build_object(
                'success', false,
                'data', NULL,
                'error', json_build_object(
                    'code', 'ACCESO_DENEGADO',
                    'message', 'Un vendedor solo puede actualizar las Ã³rdenes que Ã©l mismo ha registrado.',
                    'details', NULL
                )
            );
        END IF;
    END IF;

    -- Extract header values
    v_cliente_id := (p_header->>'cliente_id')::UUID;
    v_camion_id := (p_header->>'camion_id')::UUID;
    v_fecha_despacho := (p_header->>'fecha_despacho')::TIMESTAMPTZ;
    v_factura_origen := p_header->>'factura_origen_numero';
    v_fecha_tasa := COALESCE(v_fecha_despacho::date, CURRENT_DATE);

    -- Validar existencia de tasa de cambio para la fecha de la orden
    SELECT tasa_cambio INTO v_tasa_cambio
    FROM public.tasa_cambio
    WHERE fecha_tasa = v_fecha_tasa;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'EXCEPCION_TASA_NO_ENCONTRADA',
                'message', 'No existe tasa de cambio registrada para la fecha ' || v_fecha_tasa::text,
                'details', NULL
            )
        );
    END IF;

    -- Re-calcular totales recorriendo el detalle
    IF p_detalle IS NOT NULL AND jsonb_array_length(p_detalle) > 0 THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(p_detalle) LOOP
            v_producto_id := (v_item->>'producto_id')::UUID;
            v_cantidad := (v_item->>'cantidad_solicitada')::INT;
            
            v_val_usd := COALESCE((v_item->>'valor_unitario_usd')::NUMERIC, (v_item->>'precio_unitario')::NUMERIC, 0.00);
            v_val_recaudar_bs := COALESCE((v_item->>'valor_unitario_recaudar')::NUMERIC, 0.00);

            IF v_val_usd > 0 AND (v_val_recaudar_bs IS NULL OR v_val_recaudar_bs = 0) THEN
                v_val_recaudar_bs := ROUND(v_val_usd * v_tasa_cambio, 2);
            ELSIF v_val_recaudar_bs > 0 AND (v_val_usd IS NULL OR v_val_usd = 0) THEN
                v_val_usd := ROUND(v_val_recaudar_bs / v_tasa_cambio, 2);
            ELSIF v_val_usd > 0 AND v_val_recaudar_bs > 0 THEN
                v_val_recaudar_bs := ROUND(v_val_usd * v_tasa_cambio, 2);
            END IF;

            v_subtotal_usd := ROUND(v_cantidad * v_val_usd, 2);
            v_subtotal_bs := ROUND(v_cantidad * v_val_recaudar_bs, 2);

            v_total_usd := v_total_usd + v_subtotal_usd;
            v_total_bs := v_total_bs + v_subtotal_bs;

            -- Peso unitario
            SELECT COALESCE(peso_unitario_kg, 0) INTO v_peso_unitario
            FROM public.productos WHERE id = v_producto_id;

            v_peso_total := v_peso_total + (v_peso_unitario * v_cantidad);
        END LOOP;
    END IF;

    -- Actualizar Cabecera de la Orden
    UPDATE public.ordenes_distribucion
    SET cliente_id = COALESCE(v_cliente_id, cliente_id),
        camion_id = COALESCE(v_camion_id, camion_id),
        fecha_despacho = COALESCE(v_fecha_despacho, fecha_despacho),
        factura_origen_numero = COALESCE(v_factura_origen, factura_origen_numero),
        tasa_cambio = v_tasa_cambio,
        peso_total_calculado = v_peso_total,
        total_recaudar_bs = v_total_bs,
        total_recaudar_usd = v_total_usd
    WHERE id = v_orden_id;

    -- Reemplazar Detalle si fue provisto
    IF p_detalle IS NOT NULL AND jsonb_array_length(p_detalle) > 0 THEN
        DELETE FROM public.detalle_distribucion WHERE orden_id = v_orden_id;

        FOR v_item IN SELECT * FROM jsonb_array_elements(p_detalle) LOOP
            v_producto_id := (v_item->>'producto_id')::UUID;
            v_cantidad := (v_item->>'cantidad_solicitada')::INT;
            
            v_val_usd := COALESCE((v_item->>'valor_unitario_usd')::NUMERIC, (v_item->>'precio_unitario')::NUMERIC, 0.00);
            v_val_recaudar_bs := COALESCE((v_item->>'valor_unitario_recaudar')::NUMERIC, 0.00);

            IF v_val_usd > 0 AND (v_val_recaudar_bs IS NULL OR v_val_recaudar_bs = 0) THEN
                v_val_recaudar_bs := ROUND(v_val_usd * v_tasa_cambio, 2);
            ELSIF v_val_recaudar_bs > 0 AND (v_val_usd IS NULL OR v_val_usd = 0) THEN
                v_val_usd := ROUND(v_val_recaudar_bs / v_tasa_cambio, 2);
            ELSIF v_val_usd > 0 AND v_val_recaudar_bs > 0 THEN
                v_val_recaudar_bs := ROUND(v_val_usd * v_tasa_cambio, 2);
            END IF;

            v_subtotal_usd := ROUND(v_cantidad * v_val_usd, 2);
            v_subtotal_bs := ROUND(v_cantidad * v_val_recaudar_bs, 2);

            INSERT INTO public.detalle_distribucion (
                id,
                orden_id,
                producto_id,
                cantidad_solicitada,
                cantidad_despachada,
                valor_unitario_recaudar,
                subtotal_recaudar,
                valor_unitario_usd,
                subtotal_recaudar_usd,
                secuencia_entrega,
                estado_entrega
            ) VALUES (
                gen_random_uuid(),
                v_orden_id,
                v_producto_id,
                v_cantidad,
                0,
                v_val_recaudar_bs,
                v_subtotal_bs,
                v_val_usd,
                v_subtotal_usd,
                v_secuencia,
                'pendiente'
            );

            v_secuencia := v_secuencia + 1;
        END LOOP;
    END IF;

    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'correlativo', p_correlativo,
            'orden_id', v_orden_id,
            'tasa_cambio', v_tasa_cambio,
            'total_recaudar_bs', v_total_bs,
            'total_recaudar_usd', v_total_usd
        ),
        'error', NULL
    );

EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object(
        'success', false,
        'data', NULL,
        'error', json_build_object(
            'code', 'SQL_ERROR',
            'message', SQLERRM,
            'details', NULL
        )
    );
END;
$$;

-- 3. Script de CorrecciÃ³n de Datos HistÃ³ricos en la Base de Datos
-- Corregir filas de detalle donde valor_unitario_usd era < 1 y valor_unitario_recaudar contenÃ­a el monto en USD
UPDATE public.detalle_distribucion dd
SET 
    valor_unitario_usd = dd.valor_unitario_recaudar,
    subtotal_recaudar_usd = ROUND(dd.cantidad_solicitada * dd.valor_unitario_recaudar, 2),
    valor_unitario_recaudar = ROUND(dd.valor_unitario_recaudar * od.tasa_cambio, 2),
    subtotal_recaudar = ROUND(dd.cantidad_solicitada * dd.valor_unitario_recaudar * od.tasa_cambio, 2)
FROM public.ordenes_distribucion od
WHERE dd.orden_id = od.id
  AND dd.valor_unitario_usd < 1.00
  AND dd.valor_unitario_recaudar >= 1.00;

-- Corregir cabecera de ordenes_distribucion sumando los detalles recalculados
UPDATE public.ordenes_distribucion od
SET 
    total_recaudar_usd = COALESCE(d.sum_usd, 0.00),
    total_recaudar_bs  = COALESCE(d.sum_bs, 0.00)
FROM (
    SELECT 
        orden_id,
        SUM(subtotal_recaudar_usd) AS sum_usd,
        SUM(subtotal_recaudar) AS sum_bs
    FROM public.detalle_distribucion
    GROUP BY orden_id
) d
WHERE od.id = d.orden_id;
-- Migration: 20260910123500_campos_calculados_ordenes_usd_only.sql
-- Description: Omit calculation/storage of BolÃ­vares fields (valor_unitario_recaudar, subtotal_recaudar, total_recaudar_bs) in order creation and update RPCs, maintaining calculations exclusively in USD, and update existing order records in database.

-- 0. Permitir valores NULL en los campos de BolÃ­vares
ALTER TABLE public.detalle_distribucion ALTER COLUMN valor_unitario_recaudar DROP NOT NULL;
ALTER TABLE public.detalle_distribucion ALTER COLUMN subtotal_recaudar DROP NOT NULL;
ALTER TABLE public.ordenes_distribucion ALTER COLUMN total_recaudar_bs DROP NOT NULL;

-- 1. Actualizar crear_orden_distribucion
CREATE OR REPLACE FUNCTION public.crear_orden_distribucion(
    p_vendedor_id UUID,
    p_cliente_id UUID,
    p_camion_id UUID,
    p_tasa_cambio NUMERIC DEFAULT NULL,
    p_productos_json JSONB DEFAULT '[]'::jsonb,
    p_despachador_id UUID DEFAULT NULL,
    p_id_ruta UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_orden_id UUID;
    v_correlativo INT;
    v_factura_origen VARCHAR(30);
    v_tasa_cambio NUMERIC(14,4);
    
    v_vendedor_id UUID;
    v_despachador_id UUID;
    v_id_ruta UUID;
    
    v_peso_total NUMERIC(10,2) := 0.00;
    v_total_recaudar_usd NUMERIC(14,2) := 0.00;
    
    v_item JSONB;
    v_secuencia INT := 1;
    v_producto_id UUID;
    v_cantidad INT;
    v_val_usd NUMERIC(14,2);
    v_val_usd_prod NUMERIC(14,2);
    v_subtotal_usd NUMERIC(14,2);
    v_peso_unitario NUMERIC(10,2);
BEGIN
    -- Validaciones bÃ¡sicas
    IF p_vendedor_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del vendedor es requerido.');
    END IF;

    IF p_cliente_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del cliente es requerido.');
    END IF;

    IF p_camion_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del camiÃ³n es requerido.');
    END IF;

    IF p_productos_json IS NULL OR jsonb_array_length(p_productos_json) = 0 THEN
        RETURN jsonb_build_object('success', false, 'message', 'Debe incluir al menos un producto en la orden.');
    END IF;

    -- Obtener informaciÃ³n del cliente (vendedor_id, despachador_id, id_ruta)
    SELECT c.vendedor_id, c.despachador_id, c.id_ruta
    INTO v_vendedor_id, v_despachador_id, v_id_ruta
    FROM public.clientes c
    WHERE c.id = p_cliente_id;

    -- Priorizar parÃ¡metros explÃ­citos si fueron proporcionados
    v_vendedor_id := COALESCE(p_vendedor_id, v_vendedor_id);
    v_despachador_id := COALESCE(p_despachador_id, v_despachador_id);
    v_id_ruta := COALESCE(p_id_ruta, v_id_ruta);

    -- Validar existencia de entidades
    IF NOT EXISTS (SELECT 1 FROM public.perfiles_usuario WHERE id = p_vendedor_id) THEN
        RETURN jsonb_build_object('success', false, 'message', 'El vendedor especificado no existe.');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.clientes WHERE id = p_cliente_id) THEN
        RETURN jsonb_build_object('success', false, 'message', 'El cliente especificado no existe.');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.camiones WHERE id = p_camion_id) THEN
        RETURN jsonb_build_object('success', false, 'message', 'El camiÃ³n especificado no existe.');
    END IF;

    -- Determinar / validar la tasa de cambio
    IF p_tasa_cambio IS NOT NULL AND p_tasa_cambio > 0 THEN
        v_tasa_cambio := p_tasa_cambio;
    ELSE
        SELECT tasa_cambio INTO v_tasa_cambio
        FROM public.tasa_cambio
        WHERE fecha_tasa = CURRENT_DATE;

        IF v_tasa_cambio IS NULL THEN
            SELECT tasa_cambio INTO v_tasa_cambio
            FROM public.tasa_cambio
            ORDER BY fecha_tasa DESC
            LIMIT 1;
        END IF;

        IF v_tasa_cambio IS NULL THEN
            RETURN jsonb_build_object(
                'success', false, 
                'message', 'No hay tasa de cambio registrada. Debe proporcionar p_tasa_cambio o registrar una tasa oficial en el sistema.'
            );
        END IF;
    END IF;

    -- Generar correlativo y nÃºmero de factura de origen automÃ¡ticamente
    v_correlativo := nextval('public.ordenes_distribucion_correlativo_seq');
    v_factura_origen := 'FAC-' || LPAD(v_correlativo::text, 6, '0');
    v_orden_id := gen_random_uuid();

    -- Validar productos y calcular totales exclusivamente en USD y peso total
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;
        
        IF v_cantidad IS NULL OR v_cantidad <= 0 THEN
            RETURN jsonb_build_object('success', false, 'message', 'La cantidad del producto debe ser mayor a cero.');
        END IF;

        SELECT COALESCE(precio_lista1, 0.00), COALESCE(peso_unitario_kg, 0.00) 
        INTO v_val_usd_prod, v_peso_unitario
        FROM public.productos
        WHERE id = v_producto_id;

        IF NOT FOUND THEN
            RETURN jsonb_build_object('success', false, 'message', 'El producto con ID ' || v_producto_id::text || ' no existe.');
        END IF;

        -- Resolver precio unitario en USD priorizando precio de lista del producto
        v_val_usd := COALESCE((v_item->>'valor_unitario_usd')::NUMERIC, (v_item->>'precio_unitario')::NUMERIC, v_val_usd_prod);
        IF v_val_usd <= 0 THEN
            v_val_usd := v_val_usd_prod;
        END IF;

        v_subtotal_usd := ROUND(v_cantidad * v_val_usd, 2);

        v_peso_total := v_peso_total + (COALESCE(v_peso_unitario, 0.00) * v_cantidad);
        v_total_recaudar_usd := v_total_recaudar_usd + v_subtotal_usd;
    END LOOP;

    -- Insertar Cabecera de la Orden con estado 'aprobada' (total_recaudar_bs en NULL)
    INSERT INTO public.ordenes_distribucion (
        id,
        correlativo,
        cliente_id,
        camion_id,
        vendedor_id,
        despachador_id,
        id_ruta,
        estado,
        fecha_despacho,
        peso_total_calculado,
        factura_origen_numero,
        creado_por,
        created_at,
        tasa_cambio,
        total_recaudar_bs,
        total_recaudar_usd
    ) VALUES (
        v_orden_id,
        v_correlativo,
        p_cliente_id,
        p_camion_id,
        v_vendedor_id,
        v_despachador_id,
        v_id_ruta,
        'aprobada',
        NULL,
        v_peso_total,
        v_factura_origen,
        p_vendedor_id,
        NOW(),
        v_tasa_cambio,
        NULL,
        v_total_recaudar_usd
    );

    -- Insertar Detalles de la Orden (valor_unitario_recaudar y subtotal_recaudar en NULL)
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;
        
        SELECT COALESCE(precio_lista1, 0.00) INTO v_val_usd_prod
        FROM public.productos
        WHERE id = v_producto_id;

        v_val_usd := COALESCE((v_item->>'valor_unitario_usd')::NUMERIC, (v_item->>'precio_unitario')::NUMERIC, v_val_usd_prod);
        IF v_val_usd <= 0 THEN
            v_val_usd := v_val_usd_prod;
        END IF;

        v_subtotal_usd := ROUND(v_cantidad * v_val_usd, 2);

        INSERT INTO public.detalle_distribucion (
            id,
            orden_id,
            producto_id,
            cantidad_solicitada,
            cantidad_despachada,
            valor_unitario_recaudar,
            subtotal_recaudar,
            secuencia_entrega,
            estado_entrega,
            motivo_rechazo,
            valor_unitario_usd,
            subtotal_recaudar_usd
        ) VALUES (
            gen_random_uuid(),
            v_orden_id,
            v_producto_id,
            v_cantidad,
            0,
            NULL,
            NULL,
            v_secuencia,
            'pendiente',
            NULL,
            v_val_usd,
            v_subtotal_usd
        );
        
        v_secuencia := v_secuencia + 1;
    END LOOP;

    RETURN jsonb_build_object(
        'success', true, 
        'message', 'Orden de distribuciÃ³n creada exitosamente.', 
        'orden_id', v_orden_id,
        'data', jsonb_build_object(
            'orden_id', v_orden_id,
            'correlativo', v_correlativo,
            'tasa_cambio', v_tasa_cambio,
            'total_recaudar_bs', NULL,
            'total_recaudar_usd', v_total_recaudar_usd,
            'peso_total_calculado', v_peso_total
        )
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false, 
        'message', 'Error al crear la orden: ' || SQLERRM
    );
END;
$$;

-- 2. Actualizar actualiza_orden_distribucion_segun_correlativo
CREATE OR REPLACE FUNCTION public.actualiza_orden_distribucion_segun_correlativo(
    p_correlativo INT,
    p_header JSONB,
    p_detalle JSONB
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_orden_id UUID;
    v_estado_actual TEXT;
    v_creado_por UUID;
    v_user_id UUID := auth.uid();
    
    v_cliente_id UUID;
    v_camion_id UUID;
    v_fecha_despacho TIMESTAMPTZ;
    v_factura_origen TEXT;
    v_fecha_tasa DATE;
    v_tasa_cambio NUMERIC(14,4);
    
    v_peso_total NUMERIC(14,2) := 0.00;
    v_total_usd NUMERIC(14,2) := 0.00;
    
    v_item JSONB;
    v_secuencia INT := 1;
    v_producto_id UUID;
    v_cantidad INT;
    v_val_usd NUMERIC(14,2);
    v_val_usd_prod NUMERIC(14,2);
    v_subtotal_usd NUMERIC(14,2);
    v_peso_unitario NUMERIC(14,2);
BEGIN
    -- 1. Validar parÃ¡metros principales
    IF p_correlativo IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El correlativo de la orden es requerido.',
                'details', NULL
            )
        );
    END IF;

    -- Obtener orden actual
    SELECT id, estado, creado_por
    INTO v_orden_id, v_estado_actual, v_creado_por
    FROM public.ordenes_distribucion
    WHERE correlativo = p_correlativo;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ORDEN_NO_ENCONTRADA',
                'message', 'No se encontrÃ³ la orden con correlativo ' || p_correlativo::text,
                'details', NULL
            )
        );
    END IF;

    -- Validar que la orden estÃ© en estado borrador para modificaciÃ³n
    IF v_estado_actual NOT IN ('borrador') THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo se pueden actualizar Ã³rdenes en estado borrador. Estado actual: ' || v_estado_actual,
                'details', NULL
            )
        );
    END IF;

    -- Validar permisos por rol
    IF public.user_has_role(ARRAY['vendedor']) AND NOT public.user_has_role(ARRAY['admin', 'gerente', 'despachador']) THEN
        IF v_user_id IS NOT NULL AND v_creado_por IS DISTINCT FROM v_user_id THEN
            RETURN json_build_object(
                'success', false,
                'data', NULL,
                'error', json_build_object(
                    'code', 'ACCESO_DENEGADO',
                    'message', 'Un vendedor solo puede actualizar las Ã³rdenes que Ã©l mismo ha registrado.',
                    'details', NULL
                )
            );
        END IF;
    END IF;

    -- Extract header values
    v_cliente_id := (p_header->>'cliente_id')::UUID;
    v_camion_id := (p_header->>'camion_id')::UUID;
    v_fecha_despacho := (p_header->>'fecha_despacho')::TIMESTAMPTZ;
    v_factura_origen := p_header->>'factura_origen_numero';
    v_fecha_tasa := COALESCE(v_fecha_despacho::date, CURRENT_DATE);

    -- Validar existencia de tasa de cambio para la fecha de la orden
    SELECT tasa_cambio INTO v_tasa_cambio
    FROM public.tasa_cambio
    WHERE fecha_tasa = v_fecha_tasa;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'EXCEPCION_TASA_NO_ENCONTRADA',
                'message', 'No existe tasa de cambio registrada para la fecha ' || v_fecha_tasa::text,
                'details', NULL
            )
        );
    END IF;

    -- Re-calcular totales recorriendo el detalle exclusivamente en USD
    IF p_detalle IS NOT NULL AND jsonb_array_length(p_detalle) > 0 THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(p_detalle) LOOP
            v_producto_id := (v_item->>'producto_id')::UUID;
            v_cantidad := (v_item->>'cantidad_solicitada')::INT;
            
            SELECT COALESCE(precio_lista1, 0.00), COALESCE(peso_unitario_kg, 0.00)
            INTO v_val_usd_prod, v_peso_unitario
            FROM public.productos WHERE id = v_producto_id;

            v_val_usd := COALESCE((v_item->>'valor_unitario_usd')::NUMERIC, (v_item->>'precio_unitario')::NUMERIC, v_val_usd_prod);
            IF v_val_usd <= 0 THEN
                v_val_usd := v_val_usd_prod;
            END IF;

            v_subtotal_usd := ROUND(v_cantidad * v_val_usd, 2);

            v_total_usd := v_total_usd + v_subtotal_usd;
            v_peso_total := v_peso_total + (v_peso_unitario * v_cantidad);
        END LOOP;
    END IF;

    -- Actualizar Cabecera de la Orden (total_recaudar_bs en NULL)
    UPDATE public.ordenes_distribucion
    SET cliente_id = COALESCE(v_cliente_id, cliente_id),
        camion_id = COALESCE(v_camion_id, camion_id),
        fecha_despacho = COALESCE(v_fecha_despacho, fecha_despacho),
        factura_origen_numero = COALESCE(v_factura_origen, factura_origen_numero),
        tasa_cambio = v_tasa_cambio,
        peso_total_calculado = v_peso_total,
        total_recaudar_bs = NULL,
        total_recaudar_usd = v_total_usd
    WHERE id = v_orden_id;

    -- Reemplazar Detalle si fue provisto (valor_unitario_recaudar y subtotal_recaudar en NULL)
    IF p_detalle IS NOT NULL AND jsonb_array_length(p_detalle) > 0 THEN
        DELETE FROM public.detalle_distribucion WHERE orden_id = v_orden_id;

        FOR v_item IN SELECT * FROM jsonb_array_elements(p_detalle) LOOP
            v_producto_id := (v_item->>'producto_id')::UUID;
            v_cantidad := (v_item->>'cantidad_solicitada')::INT;
            
            SELECT COALESCE(precio_lista1, 0.00) INTO v_val_usd_prod
            FROM public.productos WHERE id = v_producto_id;

            v_val_usd := COALESCE((v_item->>'valor_unitario_usd')::NUMERIC, (v_item->>'precio_unitario')::NUMERIC, v_val_usd_prod);
            IF v_val_usd <= 0 THEN
                v_val_usd := v_val_usd_prod;
            END IF;

            v_subtotal_usd := ROUND(v_cantidad * v_val_usd, 2);

            INSERT INTO public.detalle_distribucion (
                id,
                orden_id,
                producto_id,
                cantidad_solicitada,
                cantidad_despachada,
                valor_unitario_recaudar,
                subtotal_recaudar,
                valor_unitario_usd,
                subtotal_recaudar_usd,
                secuencia_entrega,
                estado_entrega
            ) VALUES (
                gen_random_uuid(),
                v_orden_id,
                v_producto_id,
                v_cantidad,
                0,
                NULL,
                NULL,
                v_val_usd,
                v_subtotal_usd,
                v_secuencia,
                'pendiente'
            );

            v_secuencia := v_secuencia + 1;
        END LOOP;
    END IF;

    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'correlativo', p_correlativo,
            'orden_id', v_orden_id,
            'tasa_cambio', v_tasa_cambio,
            'total_recaudar_bs', NULL,
            'total_recaudar_usd', v_total_usd
        ),
        'error', NULL
    );

EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object(
        'success', false,
        'data', NULL,
        'error', json_build_object(
            'code', 'SQL_ERROR',
            'message', SQLERRM,
            'details', NULL
        )
    );
END;
$$;

-- 3. Script de CorrecciÃ³n de Registros Existentes en la Base de Datos
-- Actualizar detalle_distribucion: asegurar valor_unitario_usd desde productos.precio_lista1 y fijar campos en Bs a NULL
UPDATE public.detalle_distribucion dd
SET 
    valor_unitario_usd = COALESCE(NULLIF(dd.valor_unitario_usd, 0.00), p.precio_lista1, 0.00),
    subtotal_recaudar_usd = ROUND(dd.cantidad_solicitada * COALESCE(NULLIF(dd.valor_unitario_usd, 0.00), p.precio_lista1, 0.00), 2),
    valor_unitario_recaudar = NULL,
    subtotal_recaudar = NULL
FROM public.productos p
WHERE dd.producto_id = p.id;

-- Actualizar cabecera de ordenes_distribucion: recalcular total_recaudar_usd y fijar total_recaudar_bs a NULL
UPDATE public.ordenes_distribucion od
SET 
    total_recaudar_usd = COALESCE(d.sum_usd, 0.00),
    total_recaudar_bs  = NULL
FROM (
    SELECT 
        orden_id,
        SUM(subtotal_recaudar_usd) AS sum_usd
    FROM public.detalle_distribucion
    GROUP BY orden_id
) d
WHERE od.id = d.orden_id;
-- Migration: 20260910133000_fix_precios_usd_correctos.sql
-- Description: Fix unit price assignment in USD by prioritizing productos.precio_lista1 over corrupted fraction prices, recalculate order totals exclusively in USD, set Bs fields to NULL, and update all existing database records.

-- 1. Redefinir crear_orden_distribucion
CREATE OR REPLACE FUNCTION public.crear_orden_distribucion(
    p_vendedor_id UUID,
    p_cliente_id UUID,
    p_camion_id UUID,
    p_tasa_cambio NUMERIC DEFAULT NULL,
    p_productos_json JSONB DEFAULT '[]'::jsonb,
    p_despachador_id UUID DEFAULT NULL,
    p_id_ruta UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_orden_id UUID;
    v_correlativo INT;
    v_factura_origen VARCHAR(30);
    v_tasa_cambio NUMERIC(14,4);
    
    v_vendedor_id UUID;
    v_despachador_id UUID;
    v_id_ruta UUID;
    
    v_peso_total NUMERIC(10,2) := 0.00;
    v_total_recaudar_usd NUMERIC(14,2) := 0.00;
    
    v_item JSONB;
    v_secuencia INT := 1;
    v_producto_id UUID;
    v_cantidad INT;
    v_val_usd NUMERIC(14,2);
    v_val_usd_prod NUMERIC(14,2);
    v_subtotal_usd NUMERIC(14,2);
    v_peso_unitario NUMERIC(10,2);
BEGIN
    -- Validaciones bÃ¡sicas
    IF p_vendedor_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del vendedor es requerido.');
    END IF;

    IF p_cliente_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del cliente es requerido.');
    END IF;

    IF p_camion_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del camiÃ³n es requerido.');
    END IF;

    IF p_productos_json IS NULL OR jsonb_array_length(p_productos_json) = 0 THEN
        RETURN jsonb_build_object('success', false, 'message', 'Debe incluir al menos un producto en la orden.');
    END IF;

    -- Obtener informaciÃ³n del cliente (vendedor_id, despachador_id, id_ruta)
    SELECT c.vendedor_id, c.despachador_id, c.id_ruta
    INTO v_vendedor_id, v_despachador_id, v_id_ruta
    FROM public.clientes c
    WHERE c.id = p_cliente_id;

    -- Priorizar parÃ¡metros explÃ­citos si fueron proporcionados
    v_vendedor_id := COALESCE(p_vendedor_id, v_vendedor_id);
    v_despachador_id := COALESCE(p_despachador_id, v_despachador_id);
    v_id_ruta := COALESCE(p_id_ruta, v_id_ruta);

    -- Validar existencia de entidades
    IF NOT EXISTS (SELECT 1 FROM public.perfiles_usuario WHERE id = p_vendedor_id) THEN
        RETURN jsonb_build_object('success', false, 'message', 'El vendedor especificado no existe.');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.clientes WHERE id = p_cliente_id) THEN
        RETURN jsonb_build_object('success', false, 'message', 'El cliente especificado no existe.');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.camiones WHERE id = p_camion_id) THEN
        RETURN jsonb_build_object('success', false, 'message', 'El camiÃ³n especificado no existe.');
    END IF;

    -- Determinar / validar la tasa de cambio
    IF p_tasa_cambio IS NOT NULL AND p_tasa_cambio > 0 THEN
        v_tasa_cambio := p_tasa_cambio;
    ELSE
        SELECT tasa_cambio INTO v_tasa_cambio
        FROM public.tasa_cambio
        WHERE fecha_tasa = CURRENT_DATE;

        IF v_tasa_cambio IS NULL THEN
            SELECT tasa_cambio INTO v_tasa_cambio
            FROM public.tasa_cambio
            ORDER BY fecha_tasa DESC
            LIMIT 1;
        END IF;

        IF v_tasa_cambio IS NULL THEN
            RETURN jsonb_build_object(
                'success', false, 
                'message', 'No hay tasa de cambio registrada. Debe proporcionar p_tasa_cambio o registrar una tasa oficial en el sistema.'
            );
        END IF;
    END IF;

    -- Generar correlativo y nÃºmero de factura de origen automÃ¡ticamente
    v_correlativo := nextval('public.ordenes_distribucion_correlativo_seq');
    v_factura_origen := 'FAC-' || LPAD(v_correlativo::text, 6, '0');
    v_orden_id := gen_random_uuid();

    -- Validar productos y calcular totales exclusivamente en USD y peso total
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;
        
        IF v_cantidad IS NULL OR v_cantidad <= 0 THEN
            RETURN jsonb_build_object('success', false, 'message', 'La cantidad del producto debe ser mayor a cero.');
        END IF;

        SELECT COALESCE(precio_lista1, 0.00), COALESCE(peso_unitario_kg, 0.00) 
        INTO v_val_usd_prod, v_peso_unitario
        FROM public.productos
        WHERE id = v_producto_id;

        IF NOT FOUND THEN
            RETURN jsonb_build_object('success', false, 'message', 'El producto con ID ' || v_producto_id::text || ' no existe.');
        END IF;

        -- Resolver precio unitario en USD priorizando precio de lista del producto
        v_val_usd := COALESCE((v_item->>'valor_unitario_usd')::NUMERIC, (v_item->>'precio_unitario')::NUMERIC, v_val_usd_prod);
        IF v_val_usd <= 0 OR (v_val_usd < 1.00 AND v_val_usd_prod >= 1.00) THEN
            v_val_usd := v_val_usd_prod;
        END IF;

        v_subtotal_usd := ROUND(v_cantidad * v_val_usd, 2);

        v_peso_total := v_peso_total + (COALESCE(v_peso_unitario, 0.00) * v_cantidad);
        v_total_recaudar_usd := v_total_recaudar_usd + v_subtotal_usd;
    END LOOP;

    -- Insertar Cabecera de la Orden con estado 'aprobada' (total_recaudar_bs en NULL)
    INSERT INTO public.ordenes_distribucion (
        id,
        correlativo,
        cliente_id,
        camion_id,
        vendedor_id,
        despachador_id,
        id_ruta,
        estado,
        fecha_despacho,
        peso_total_calculado,
        factura_origen_numero,
        creado_por,
        created_at,
        tasa_cambio,
        total_recaudar_bs,
        total_recaudar_usd
    ) VALUES (
        v_orden_id,
        v_correlativo,
        p_cliente_id,
        p_camion_id,
        v_vendedor_id,
        v_despachador_id,
        v_id_ruta,
        'aprobada',
        NULL,
        v_peso_total,
        v_factura_origen,
        p_vendedor_id,
        NOW(),
        v_tasa_cambio,
        NULL,
        v_total_recaudar_usd
    );

    -- Insertar Detalles de la Orden (valor_unitario_recaudar y subtotal_recaudar en NULL)
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;
        
        SELECT COALESCE(precio_lista1, 0.00) INTO v_val_usd_prod
        FROM public.productos
        WHERE id = v_producto_id;

        v_val_usd := COALESCE((v_item->>'valor_unitario_usd')::NUMERIC, (v_item->>'precio_unitario')::NUMERIC, v_val_usd_prod);
        IF v_val_usd <= 0 OR (v_val_usd < 1.00 AND v_val_usd_prod >= 1.00) THEN
            v_val_usd := v_val_usd_prod;
        END IF;

        v_subtotal_usd := ROUND(v_cantidad * v_val_usd, 2);

        INSERT INTO public.detalle_distribucion (
            id,
            orden_id,
            producto_id,
            cantidad_solicitada,
            cantidad_despachada,
            valor_unitario_recaudar,
            subtotal_recaudar,
            secuencia_entrega,
            estado_entrega,
            motivo_rechazo,
            valor_unitario_usd,
            subtotal_recaudar_usd
        ) VALUES (
            gen_random_uuid(),
            v_orden_id,
            v_producto_id,
            v_cantidad,
            0,
            NULL,
            NULL,
            v_secuencia,
            'pendiente',
            NULL,
            v_val_usd,
            v_subtotal_usd
        );
        
        v_secuencia := v_secuencia + 1;
    END LOOP;

    RETURN jsonb_build_object(
        'success', true, 
        'message', 'Orden de distribuciÃ³n creada exitosamente.', 
        'orden_id', v_orden_id,
        'data', jsonb_build_object(
            'orden_id', v_orden_id,
            'correlativo', v_correlativo,
            'tasa_cambio', v_tasa_cambio,
            'total_recaudar_bs', NULL,
            'total_recaudar_usd', v_total_recaudar_usd,
            'peso_total_calculado', v_peso_total
        )
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false, 
        'message', 'Error al crear la orden: ' || SQLERRM
    );
END;
$$;

-- 2. Redefinir actualiza_orden_distribucion_segun_correlativo
CREATE OR REPLACE FUNCTION public.actualiza_orden_distribucion_segun_correlativo(
    p_correlativo INT,
    p_header JSONB,
    p_detalle JSONB
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_orden_id UUID;
    v_estado_actual TEXT;
    v_creado_por UUID;
    v_user_id UUID := auth.uid();
    
    v_cliente_id UUID;
    v_camion_id UUID;
    v_fecha_despacho TIMESTAMPTZ;
    v_factura_origen TEXT;
    v_fecha_tasa DATE;
    v_tasa_cambio NUMERIC(14,4);
    
    v_peso_total NUMERIC(14,2) := 0.00;
    v_total_usd NUMERIC(14,2) := 0.00;
    
    v_item JSONB;
    v_secuencia INT := 1;
    v_producto_id UUID;
    v_cantidad INT;
    v_val_usd NUMERIC(14,2);
    v_val_usd_prod NUMERIC(14,2);
    v_subtotal_usd NUMERIC(14,2);
    v_peso_unitario NUMERIC(14,2);
BEGIN
    -- 1. Validar parÃ¡metros principales
    IF p_correlativo IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El correlativo de la orden es requerido.',
                'details', NULL
            )
        );
    END IF;

    -- Obtener orden actual
    SELECT id, estado, creado_por
    INTO v_orden_id, v_estado_actual, v_creado_por
    FROM public.ordenes_distribucion
    WHERE correlativo = p_correlativo;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ORDEN_NO_ENCONTRADA',
                'message', 'No se encontrÃ³ la orden con correlativo ' || p_correlativo::text,
                'details', NULL
            )
        );
    END IF;

    -- Validar que la orden estÃ© en estado borrador para modificaciÃ³n
    IF v_estado_actual NOT IN ('borrador') THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo se pueden actualizar Ã³rdenes en estado borrador. Estado actual: ' || v_estado_actual,
                'details', NULL
            )
        );
    END IF;

    -- Validar permisos por rol
    IF public.user_has_role(ARRAY['vendedor']) AND NOT public.user_has_role(ARRAY['admin', 'gerente', 'despachador']) THEN
        IF v_user_id IS NOT NULL AND v_creado_por IS DISTINCT FROM v_user_id THEN
            RETURN json_build_object(
                'success', false,
                'data', NULL,
                'error', json_build_object(
                    'code', 'ACCESO_DENEGADO',
                    'message', 'Un vendedor solo puede actualizar las Ã³rdenes que Ã©l mismo ha registrado.',
                    'details', NULL
                )
            );
        END IF;
    END IF;

    -- Extract header values
    v_cliente_id := (p_header->>'cliente_id')::UUID;
    v_camion_id := (p_header->>'camion_id')::UUID;
    v_fecha_despacho := (p_header->>'fecha_despacho')::TIMESTAMPTZ;
    v_factura_origen := p_header->>'factura_origen_numero';
    v_fecha_tasa := COALESCE(v_fecha_despacho::date, CURRENT_DATE);

    -- Validar existencia de tasa de cambio para la fecha de la orden
    SELECT tasa_cambio INTO v_tasa_cambio
    FROM public.tasa_cambio
    WHERE fecha_tasa = v_fecha_tasa;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'EXCEPCION_TASA_NO_ENCONTRADA',
                'message', 'No existe tasa de cambio registrada para la fecha ' || v_fecha_tasa::text,
                'details', NULL
            )
        );
    END IF;

    -- Re-calcular totales recorriendo el detalle exclusivamente en USD
    IF p_detalle IS NOT NULL AND jsonb_array_length(p_detalle) > 0 THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(p_detalle) LOOP
            v_producto_id := (v_item->>'producto_id')::UUID;
            v_cantidad := (v_item->>'cantidad_solicitada')::INT;
            
            SELECT COALESCE(precio_lista1, 0.00), COALESCE(peso_unitario_kg, 0.00)
            INTO v_val_usd_prod, v_peso_unitario
            FROM public.productos WHERE id = v_producto_id;

            v_val_usd := COALESCE((v_item->>'valor_unitario_usd')::NUMERIC, (v_item->>'precio_unitario')::NUMERIC, v_val_usd_prod);
            IF v_val_usd <= 0 OR (v_val_usd < 1.00 AND v_val_usd_prod >= 1.00) THEN
                v_val_usd := v_val_usd_prod;
            END IF;

            v_subtotal_usd := ROUND(v_cantidad * v_val_usd, 2);

            v_total_usd := v_total_usd + v_subtotal_usd;
            v_peso_total := v_peso_total + (v_peso_unitario * v_cantidad);
        END LOOP;
    END IF;

    -- Actualizar Cabecera de la Orden (total_recaudar_bs en NULL)
    UPDATE public.ordenes_distribucion
    SET cliente_id = COALESCE(v_cliente_id, cliente_id),
        camion_id = COALESCE(v_camion_id, camion_id),
        fecha_despacho = COALESCE(v_fecha_despacho, fecha_despacho),
        factura_origen_numero = COALESCE(v_factura_origen, factura_origen_numero),
        tasa_cambio = v_tasa_cambio,
        peso_total_calculado = v_peso_total,
        total_recaudar_bs = NULL,
        total_recaudar_usd = v_total_usd
    WHERE id = v_orden_id;

    -- Reemplazar Detalle si fue provisto (valor_unitario_recaudar y subtotal_recaudar en NULL)
    IF p_detalle IS NOT NULL AND jsonb_array_length(p_detalle) > 0 THEN
        DELETE FROM public.detalle_distribucion WHERE orden_id = v_orden_id;

        FOR v_item IN SELECT * FROM jsonb_array_elements(p_detalle) LOOP
            v_producto_id := (v_item->>'producto_id')::UUID;
            v_cantidad := (v_item->>'cantidad_solicitada')::INT;
            
            SELECT COALESCE(precio_lista1, 0.00) INTO v_val_usd_prod
            FROM public.productos WHERE id = v_producto_id;

            v_val_usd := COALESCE((v_item->>'valor_unitario_usd')::NUMERIC, (v_item->>'precio_unitario')::NUMERIC, v_val_usd_prod);
            IF v_val_usd <= 0 OR (v_val_usd < 1.00 AND v_val_usd_prod >= 1.00) THEN
                v_val_usd := v_val_usd_prod;
            END IF;

            v_subtotal_usd := ROUND(v_cantidad * v_val_usd, 2);

            INSERT INTO public.detalle_distribucion (
                id,
                orden_id,
                producto_id,
                cantidad_solicitada,
                cantidad_despachada,
                valor_unitario_recaudar,
                subtotal_recaudar,
                valor_unitario_usd,
                subtotal_recaudar_usd,
                secuencia_entrega,
                estado_entrega
            ) VALUES (
                gen_random_uuid(),
                v_orden_id,
                v_producto_id,
                v_cantidad,
                0,
                NULL,
                NULL,
                v_val_usd,
                v_subtotal_usd,
                v_secuencia,
                'pendiente'
            );

            v_secuencia := v_secuencia + 1;
        END LOOP;
    END IF;

    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'correlativo', p_correlativo,
            'orden_id', v_orden_id,
            'tasa_cambio', v_tasa_cambio,
            'total_recaudar_bs', NULL,
            'total_recaudar_usd', v_total_usd
        ),
        'error', NULL
    );

EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object(
        'success', false,
        'data', NULL,
        'error', json_build_object(
            'code', 'SQL_ERROR',
            'message', SQLERRM,
            'details', NULL
        )
    );
END;
$$;

-- 3. CorrecciÃ³n Exhaustiva de Datos en la Base de Datos Remota
-- Restaurar el precio real en USD (productos.precio_lista1) en todas las filas de detalle_distribucion
UPDATE public.detalle_distribucion dd
SET 
    valor_unitario_usd = COALESCE(NULLIF(p.precio_lista1, 0.00), dd.valor_unitario_usd, 0.00),
    subtotal_recaudar_usd = ROUND(dd.cantidad_solicitada * COALESCE(NULLIF(p.precio_lista1, 0.00), dd.valor_unitario_usd, 0.00), 2),
    valor_unitario_recaudar = NULL,
    subtotal_recaudar = NULL
FROM public.productos p
WHERE dd.producto_id = p.id;

-- Recalcular total_recaudar_usd en ordenes_distribucion y blanquear total_recaudar_bs a NULL
UPDATE public.ordenes_distribucion od
SET 
    total_recaudar_usd = COALESCE(d.sum_usd, 0.00),
    total_recaudar_bs = NULL
FROM (
    SELECT 
        orden_id,
        SUM(subtotal_recaudar_usd) AS sum_usd
    FROM public.detalle_distribucion
    GROUP BY orden_id
) d
WHERE od.id = d.orden_id;
-- MigraciÃ³n: Crear RPC registra_nuevo_producto_retorna_id y actualizar RPC actualizar_registro_productos_segun_id

-- 1. FunciÃ³n para registrar nuevo producto y retornar su ID
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
    -- Tratar cadena vacÃ­a como NULL en codigo_barras para evitar violaciones de UNIQUE
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

-- 2. FunciÃ³n para actualizar producto segÃºn ID
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
    -- Tratar cadena vacÃ­a como NULL en codigo_barras para evitar violaciones de UNIQUE
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
-- MigraciÃ³n: Actualizar RPC solicita_aprobar_radar para carga de contenedores entregados y polÃ­ticas de crÃ©dito por max_facturas_vencidas

CREATE OR REPLACE FUNCTION public.solicita_aprobar_radar(
    p_radar_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_despachador_id UUID;
    v_fecha_despacho DATE;
    v_status_radar BOOLEAN;
    v_rec RECORD;
    v_rec_entregados RECORD;
    v_rec_cliente RECORD;
    v_inv_res JSONB;
    v_ordenes_anuladas_count INT := 0;
    v_contenedores_retirados_procesados INT := 0;
    v_contenedores_entregados_procesados INT := 0;
    v_clientes_deshabilitados_count INT := 0;
    v_ordenes_por_liquidar_count INT := 0;
    v_contenedores_entregados INT := 0;
BEGIN
    IF p_radar_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID del radar es obligatorio.'
            )
        );
    END IF;

    -- Verificar existencia del radar y su estado actual
    SELECT despachador_id, fecha_despacho, COALESCE(status_radar, FALSE)
    INTO v_despachador_id, v_fecha_despacho, v_status_radar
    FROM public.radars
    WHERE id = p_radar_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'RADAR_INEXISTENTE',
                'message', 'El radar especificado no existe.'
            )
        );
    END IF;

    IF v_status_radar = TRUE THEN
        RETURN jsonb_build_object(
            'success', TRUE,
            'message', 'El radar ya se encuentra previamente aprobado.',
            'data', jsonb_build_object(
                'radar_id', p_radar_id,
                'status_radar', TRUE
            ),
            'error', NULL
        );
    END IF;

    -- 1. Marcar el radar como aprobado y cerrado (.T.) mediante status_radar = TRUE
    UPDATE public.radars
    SET status_radar = TRUE
    WHERE id = p_radar_id;

    -- 2. Cargar en el estado de cuenta del cliente los contenedores ENTREGADOS en el despacho
    -- si el producto tiene un contenedor asignado: CEIL(cantidad_despachada * unidades_por_contenedor)
    FOR v_rec_entregados IN
        SELECT 
            o.cliente_id,
            d.orden_id,
            COALESCE(d.contenedor_id, p.contenedor_id) AS contenedor_id,
            SUM(CEIL(COALESCE(d.cantidad_despachada, 0)::numeric * COALESCE(p.unidades_por_contenedor, 1))) AS total_entregados
        FROM public.ordenes_distribucion o
        JOIN public.detalle_distribucion d ON d.orden_id = o.id
        JOIN public.productos p ON p.id = d.producto_id
        WHERE o.radar_id = p_radar_id
          AND COALESCE(d.cantidad_despachada, 0) > 0
          AND COALESCE(d.contenedor_id, p.contenedor_id) IS NOT NULL
        GROUP BY o.cliente_id, d.orden_id, COALESCE(d.contenedor_id, p.contenedor_id)
    LOOP
        v_contenedores_entregados := v_rec_entregados.total_entregados::INT;
        IF v_contenedores_entregados > 0 THEN
            INSERT INTO public.movimientos_contenedores (
                cliente_id, orden_id, contenedor_id, cantidad_entregada, cantidad_retirada, creado_por
            ) VALUES (
                v_rec_entregados.cliente_id, v_rec_entregados.orden_id, v_rec_entregados.contenedor_id, v_contenedores_entregados, 0, auth.uid()
            );

            INSERT INTO public.saldo_contenedores_clientes (
                cliente_id, contenedor_id, saldo_pendiente, updated_at
            ) VALUES (
                v_rec_entregados.cliente_id, v_rec_entregados.contenedor_id, v_contenedores_entregados, NOW()
            )
            ON CONFLICT (cliente_id, contenedor_id)
            DO UPDATE SET 
                saldo_pendiente = public.saldo_contenedores_clientes.saldo_pendiente + EXCLUDED.saldo_pendiente,
                updated_at = NOW();

            v_contenedores_entregados_procesados := v_contenedores_entregados_procesados + v_contenedores_entregados;
        END IF;
    END LOOP;

    -- 3. Procesar movimiento de envases RETIRADOS/DEVUELTOS por clientes (contenedores_retirados)
    FOR v_rec IN
        SELECT 
            o.cliente_id,
            d.orden_id,
            COALESCE(d.contenedor_id, p.contenedor_id) AS contenedor_id,
            SUM(COALESCE(d.contenedores_retirados, 0)) AS total_retirados
        FROM public.ordenes_distribucion o
        JOIN public.detalle_distribucion d ON d.orden_id = o.id
        LEFT JOIN public.productos p ON p.id = d.producto_id
        WHERE o.radar_id = p_radar_id
          AND COALESCE(d.contenedores_retirados, 0) > 0
        GROUP BY o.cliente_id, d.orden_id, COALESCE(d.contenedor_id, p.contenedor_id)
    LOOP
        IF v_rec.contenedor_id IS NOT NULL THEN
            INSERT INTO public.movimientos_contenedores (
                cliente_id, orden_id, contenedor_id, cantidad_entregada, cantidad_retirada, creado_por
            ) VALUES (
                v_rec.cliente_id, v_rec.orden_id, v_rec.contenedor_id, 0, v_rec.total_retirados, auth.uid()
            );

            INSERT INTO public.saldo_contenedores_clientes (
                cliente_id, contenedor_id, saldo_pendiente, updated_at
            ) VALUES (
                v_rec.cliente_id, v_rec.contenedor_id, 0, NOW()
            )
            ON CONFLICT (cliente_id, contenedor_id)
            DO UPDATE SET 
                saldo_pendiente = GREATEST(0, public.saldo_contenedores_clientes.saldo_pendiente - v_rec.total_retirados),
                updated_at = NOW();

            v_contenedores_retirados_procesados := v_contenedores_retirados_procesados + v_rec.total_retirados;
        END IF;
    END LOOP;

    -- 4. Devuelve el inventario no despachado del camiÃ³n al almacÃ©n principal
    v_inv_res := public.retorna_inventario_no_despachado_para_almacen(p_radar_id);

    -- 5. Las Ã³rdenes en estado 'devuelta' pasan al estado final 'anulada'
    WITH ordenes_devueltas AS (
        UPDATE public.ordenes_distribucion
        SET estado = 'anulada'
        WHERE radar_id = p_radar_id AND estado = 'devuelta'
        RETURNING id
    )
    SELECT COUNT(*) INTO v_ordenes_anuladas_count FROM ordenes_devueltas;

    -- 6. Evaluar polÃ­ticas de crÃ©dito respecto a clientes.max_facturas_vencidas
    -- Para cada cliente en el radar, si sus Ã³rdenes por liquidar >= max_facturas_vencidas (y max_facturas_vencidas > 0)
    -- deshabilitar permiso_despacho_manual = FALSE
    FOR v_rec_cliente IN
        SELECT DISTINCT c.id AS cliente_id, COALESCE(c.max_facturas_vencidas, 0) AS max_facturas_vencidas
        FROM public.ordenes_distribucion o
        JOIN public.clientes c ON c.id = o.cliente_id
        WHERE o.radar_id = p_radar_id
          AND COALESCE(c.max_facturas_vencidas, 0) > 0
    LOOP
        SELECT COUNT(*) INTO v_ordenes_por_liquidar_count
        FROM public.ordenes_distribucion
        WHERE cliente_id = v_rec_cliente.cliente_id
          AND estado = 'por_liquidar';

        IF v_ordenes_por_liquidar_count >= v_rec_cliente.max_facturas_vencidas THEN
            UPDATE public.clientes
            SET permiso_despacho_manual = FALSE
            WHERE id = v_rec_cliente.cliente_id;

            v_clientes_deshabilitados_count := v_clientes_deshabilitados_count + 1;
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Radar aprobado exitosamente. Saldos de contenedores actualizados, polÃ­ticas de crÃ©dito evaluadas, inventario restituido a almacÃ©n y Ã³rdenes devueltas anuladas.',
        'data', jsonb_build_object(
            'radar_id', p_radar_id,
            'status_radar', TRUE,
            'contenedores_entregados_procesados', v_contenedores_entregados_procesados,
            'contenedores_retirados_procesados', v_contenedores_retirados_procesados,
            'clientes_deshabilitados_credito', v_clientes_deshabilitados_count,
            'ordenes_anuladas', v_ordenes_anuladas_count,
            'inventario_reintegrado', COALESCE(v_inv_res->'data', '[]'::jsonb)
        ),
        'error', NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', SQLSTATE,
                'message', SQLERRM
            )
        );
END;
$$;

GRANT EXECUTE ON FUNCTION public.solicita_aprobar_radar TO authenticated, service_role;

COMMENT ON FUNCTION public.solicita_aprobar_radar(UUID) IS 'Aprueba el radar (status_radar = TRUE), carga envases entregados/retirados a saldos de clientes, evalÃºa polÃ­ticas de crÃ©dito (max_facturas_vencidas), reingresa inventario a almacÃ©n y anula Ã³rdenes devueltas.';
-- MigraciÃ³n: RecÃ¡lculo masivo de movimientos_contenedores y saldo_contenedores_clientes segÃºn Ã³rdenes despachadas

DO $$
DECLARE
    v_rec RECORD;
    v_rec_retirados RECORD;
    v_rec_saldo RECORD;
    v_entregados INT;
    v_mov_entregados_count INT := 0;
    v_mov_retirados_count INT := 0;
    v_saldos_actualizados_count INT := 0;
BEGIN
    RAISE NOTICE 'Iniciando recÃ¡lculo masivo de movimientos y saldos de contenedores...';

    -- 1. Limpiar registros de movimientos y saldos de contenedores para evitar duplicados
    DELETE FROM public.movimientos_contenedores;
    DELETE FROM public.saldo_contenedores_clientes;

    -- 2. Procesar contenedores ENTREGADOS para todas las Ã³rdenes despachadas en radares aprobados
    -- FÃ³rmula: CEIL(cantidad_despachada * unidades_por_contenedor)
    FOR v_rec IN
        SELECT 
            o.cliente_id,
            d.orden_id,
            COALESCE(d.contenedor_id, p.contenedor_id) AS contenedor_id,
            SUM(CEIL(COALESCE(d.cantidad_despachada, 0)::numeric * COALESCE(p.unidades_por_contenedor, 1))) AS total_entregados,
            o.creado_por
        FROM public.ordenes_distribucion o
        JOIN public.radars r ON r.id = o.radar_id
        JOIN public.detalle_distribucion d ON d.orden_id = o.id
        JOIN public.productos p ON p.id = d.producto_id
        WHERE r.status_radar = TRUE
          AND COALESCE(d.cantidad_despachada, 0) > 0
          AND COALESCE(d.contenedor_id, p.contenedor_id) IS NOT NULL
        GROUP BY o.cliente_id, d.orden_id, COALESCE(d.contenedor_id, p.contenedor_id), o.creado_por
    LOOP
        v_entregados := v_rec.total_entregados::INT;
        IF v_entregados > 0 THEN
            INSERT INTO public.movimientos_contenedores (
                cliente_id, orden_id, contenedor_id, cantidad_entregada, cantidad_retirada, creado_por
            ) VALUES (
                v_rec.cliente_id, v_rec.orden_id, v_rec.contenedor_id, v_entregados, 0, v_rec.creado_por
            );

            v_mov_entregados_count := v_mov_entregados_count + 1;
        END IF;
    END LOOP;

    -- 3. Procesar contenedores RETIRADOS/DEVUELTOS por clientes en radares aprobados
    FOR v_rec_retirados IN
        SELECT 
            o.cliente_id,
            d.orden_id,
            COALESCE(d.contenedor_id, p.contenedor_id) AS contenedor_id,
            SUM(COALESCE(d.contenedores_retirados, 0)) AS total_retirados,
            o.creado_por
        FROM public.ordenes_distribucion o
        JOIN public.radars r ON r.id = o.radar_id
        JOIN public.detalle_distribucion d ON d.orden_id = o.id
        LEFT JOIN public.productos p ON p.id = d.producto_id
        WHERE r.status_radar = TRUE
          AND COALESCE(d.contenedores_retirados, 0) > 0
        GROUP BY o.cliente_id, d.orden_id, COALESCE(d.contenedor_id, p.contenedor_id), o.creado_por
    LOOP
        IF v_rec_retirados.contenedor_id IS NOT NULL AND v_rec_retirados.total_retirados > 0 THEN
            INSERT INTO public.movimientos_contenedores (
                cliente_id, orden_id, contenedor_id, cantidad_entregada, cantidad_retirada, creado_por
            ) VALUES (
                v_rec_retirados.cliente_id, v_rec_retirados.orden_id, v_rec_retirados.contenedor_id, 0, v_rec_retirados.total_retirados, v_rec_retirados.creado_por
            );

            v_mov_retirados_count := v_mov_retirados_count + 1;
        END IF;
    END LOOP;

    -- 4. Recalcular el saldo neto acumulado por cliente y tipo de contenedor en saldo_contenedores_clientes
    FOR v_rec_saldo IN
        SELECT 
            cliente_id,
            contenedor_id,
            GREATEST(0, SUM(cantidad_entregada) - SUM(cantidad_retirada)) AS saldo_neto
        FROM public.movimientos_contenedores
        GROUP BY cliente_id, contenedor_id
    LOOP
        INSERT INTO public.saldo_contenedores_clientes (
            cliente_id, contenedor_id, saldo_pendiente, updated_at
        ) VALUES (
            v_rec_saldo.cliente_id, v_rec_saldo.contenedor_id, v_rec_saldo.saldo_neto, NOW()
        );

        v_saldos_actualizados_count := v_saldos_actualizados_count + 1;
    END LOOP;

    RAISE NOTICE 'RecÃ¡lculo masivo completado:';
    RAISE NOTICE '- Movimientos de entregas: %', v_mov_entregados_count;
    RAISE NOTICE '- Movimientos de retiros: %', v_mov_retirados_count;
    RAISE NOTICE '- Saldos de clientes actualizados: %', v_saldos_actualizados_count;
END;
$$;
-- Migration: 20260911120000_depuracion_tablas_y_ajustes_inventario.sql
-- Description: DepuraciÃ³n de tablas de Ã³rdenes y contenedores, reseteo de clientes a estado activo sin bloqueo por polÃ­ticas de crÃ©dito, y ajuste de movimientos de inventario.

-- 1. DepuraciÃ³n de tablas (Eliminar todos los registros)
TRUNCATE TABLE public.detalle_distribucion CASCADE;
TRUNCATE TABLE public.ordenes_distribucion CASCADE;
TRUNCATE TABLE public.movimientos_contenedores CASCADE;
TRUNCATE TABLE public.saldo_contenedores_clientes CASCADE;

-- 2. Asegurar que todos los clientes permanezcan activos y habilitados para Ã³rdenes
UPDATE public.clientes
SET activo = TRUE,
    permiso_despacho_manual = TRUE;

-- 3. Actualizar funciÃ³n `cargar_inventario_movil` para descontar stock del almacÃ©n al cargar el camiÃ³n
CREATE OR REPLACE FUNCTION public.cargar_inventario_movil(
    p_orden_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_estado_actual TEXT;
    v_camion_id UUID;
    v_item RECORD;
BEGIN
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

    SELECT estado, camion_id
    INTO v_estado_actual, v_camion_id
    FROM public.ordenes_distribucion
    WHERE id = p_orden_id;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ORDEN_INEXISTENTE',
                'message', 'La orden de distribuciÃ³n especificada no existe.',
                'details', 'ID: ' || p_orden_id
            )
        );
    END IF;

    IF v_estado_actual != 'aprobada' THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'La orden debe estar en estado aprobada para poder ser despachada.',
                'details', 'Estado actual: ' || v_estado_actual
            )
        );
    END IF;

    IF v_camion_id IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'CAMION_NO_ASIGNADO',
                'message', 'No se puede despachar la orden porque no tiene un camiÃ³n asignado.',
                'details', NULL
            )
        );
    END IF;

    FOR v_item IN 
        SELECT producto_id, cantidad_solicitada
        FROM public.detalle_distribucion
        WHERE orden_id = p_orden_id
    LOOP
        -- Descontar del almacÃ©n principal (sale fÃ­sicamente del centro de distribuciÃ³n)
        UPDATE public.inventario_almacen
        SET stock_comprometido = GREATEST(0, stock_comprometido - v_item.cantidad_solicitada),
            stock_disponible = CASE 
                WHEN stock_comprometido < v_item.cantidad_solicitada 
                THEN GREATEST(0, stock_disponible - (v_item.cantidad_solicitada - stock_comprometido))
                ELSE stock_disponible 
            END,
            updated_at = NOW()
        WHERE producto_id = v_item.producto_id;

        -- Upsert en el inventario mÃ³vil del camiÃ³n (suma a la cantidad cargada)
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

        UPDATE public.detalle_distribucion
        SET cantidad_despachada = v_item.cantidad_solicitada
        WHERE orden_id = p_orden_id AND producto_id = v_item.producto_id;
    END LOOP;

    UPDATE public.camiones
    SET estado = 'en_ruta'
    WHERE id = v_camion_id;

    UPDATE public.ordenes_distribucion
    SET estado = 'en_transito',
        fecha_despacho = NOW()
    WHERE id = p_orden_id;

    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'orden_id', p_orden_id,
            'nuevo_estado', 'en_transito'
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

-- 4. Actualizar funciÃ³n `retorna_inventario_no_despachado_para_almacen` para devolver mercancÃ­a no entregada al almacÃ©n y descontarla del camiÃ³n
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
        -- 1. Reingresar el stock no despachado al almacÃ©n principal (inventario_almacen.stock_disponible)
        INSERT INTO public.inventario_almacen (producto_id, stock_disponible, stock_comprometido, updated_at)
        VALUES (v_rec.producto_id, v_rec.total_devuelto, 0, NOW())
        ON CONFLICT (producto_id)
        DO UPDATE SET 
            stock_disponible = public.inventario_almacen.stock_disponible + v_rec.total_devuelto,
            updated_at = NOW();

        BEGIN
            UPDATE public.productos
            SET stock_disponible = COALESCE(stock_disponible, 0) + v_rec.total_devuelto,
                updated_at = NOW()
            WHERE id = v_rec.producto_id;
        EXCEPTION WHEN OTHERS THEN
            NULL;
        END;

        -- 2. Descontar / rebajar del inventario mÃ³vil del camiÃ³n la mercancÃ­a no entregada (devuelta)
        IF v_rec.camion_id IS NOT NULL THEN
            UPDATE public.inventario_movil
            SET cantidad_cargada = GREATEST(0, cantidad_cargada - v_rec.total_devuelto),
                updated_at = NOW()
            WHERE camion_id = v_rec.camion_id AND producto_id = v_rec.producto_id;
        END IF;

        v_detalles := v_detalles || jsonb_build_object(
            'producto_id', v_rec.producto_id,
            'codigo_producto', v_rec.codigo_producto,
            'nombre_producto', v_rec.nombre_producto,
            'cantidad_devuelta', v_rec.total_devuelto
        );
    END LOOP;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Inventario no despachado retornado exitosamente al almacÃ©n principal.',
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

-- 5. Actualizar `solicita_aprobar_radar` omitiendo el bloqueo de clientes por facturas vencidas
CREATE OR REPLACE FUNCTION public.solicita_aprobar_radar(
    p_radar_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_despachador_id UUID;
    v_fecha_despacho DATE;
    v_status_radar BOOLEAN;
    v_rec RECORD;
    v_rec_entregados RECORD;
    v_rec_cliente RECORD;
    v_inv_res JSONB;
    v_ordenes_anuladas_count INT := 0;
    v_contenedores_retirados_procesados INT := 0;
    v_contenedores_entregados_procesados INT := 0;
    v_clientes_deshabilitados_count INT := 0;
    v_ordenes_por_liquidar_count INT := 0;
    v_contenedores_entregados INT := 0;
BEGIN
    IF p_radar_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID del radar es obligatorio.'
            )
        );
    END IF;

    SELECT despachador_id, fecha_despacho, COALESCE(status_radar, FALSE)
    INTO v_despachador_id, v_fecha_despacho, v_status_radar
    FROM public.radars
    WHERE id = p_radar_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'RADAR_INEXISTENTE',
                'message', 'El radar especificado no existe.'
            )
        );
    END IF;

    IF v_status_radar = TRUE THEN
        RETURN jsonb_build_object(
            'success', TRUE,
            'message', 'El radar ya se encuentra previamente aprobado.',
            'data', jsonb_build_object(
                'radar_id', p_radar_id,
                'status_radar', TRUE
            ),
            'error', NULL
        );
    END IF;

    -- 1. Marcar el radar como aprobado y cerrado (.T.) mediante status_radar = TRUE
    UPDATE public.radars
    SET status_radar = TRUE
    WHERE id = p_radar_id;

    -- 2. Cargar en el estado de cuenta del cliente los contenedores ENTREGADOS en el despacho
    FOR v_rec_entregados IN
        SELECT 
            o.cliente_id,
            d.orden_id,
            COALESCE(d.contenedor_id, p.contenedor_id) AS contenedor_id,
            SUM(CEIL(COALESCE(d.cantidad_despachada, 0)::numeric * COALESCE(p.unidades_por_contenedor, 1))) AS total_entregados
        FROM public.ordenes_distribucion o
        JOIN public.detalle_distribucion d ON d.orden_id = o.id
        JOIN public.productos p ON p.id = d.producto_id
        WHERE o.radar_id = p_radar_id
          AND COALESCE(d.cantidad_despachada, 0) > 0
          AND COALESCE(d.contenedor_id, p.contenedor_id) IS NOT NULL
        GROUP BY o.cliente_id, d.orden_id, COALESCE(d.contenedor_id, p.contenedor_id)
    LOOP
        v_contenedores_entregados := v_rec_entregados.total_entregados::INT;
        IF v_contenedores_entregados > 0 THEN
            INSERT INTO public.movimientos_contenedores (
                cliente_id, orden_id, contenedor_id, cantidad_entregada, cantidad_retirada, creado_por
            ) VALUES (
                v_rec_entregados.cliente_id, v_rec_entregados.orden_id, v_rec_entregados.contenedor_id, v_contenedores_entregados, 0, auth.uid()
            );

            INSERT INTO public.saldo_contenedores_clientes (
                cliente_id, contenedor_id, saldo_pendiente, updated_at
            ) VALUES (
                v_rec_entregados.cliente_id, v_rec_entregados.contenedor_id, v_contenedores_entregados, NOW()
            )
            ON CONFLICT (cliente_id, contenedor_id)
            DO UPDATE SET 
                saldo_pendiente = public.saldo_contenedores_clientes.saldo_pendiente + EXCLUDED.saldo_pendiente,
                updated_at = NOW();

            v_contenedores_entregados_procesados := v_contenedores_entregados_procesados + v_contenedores_entregados;
        END IF;
    END LOOP;

    -- 3. Procesar movimiento de envases RETIRADOS/DEVUELTOS por clientes
    FOR v_rec IN
        SELECT 
            o.cliente_id,
            d.orden_id,
            COALESCE(d.contenedor_id, p.contenedor_id) AS contenedor_id,
            SUM(COALESCE(d.contenedores_retirados, 0)) AS total_retirados
        FROM public.ordenes_distribucion o
        JOIN public.detalle_distribucion d ON d.orden_id = o.id
        LEFT JOIN public.productos p ON p.id = d.producto_id
        WHERE o.radar_id = p_radar_id
          AND COALESCE(d.contenedores_retirados, 0) > 0
        GROUP BY o.cliente_id, d.orden_id, COALESCE(d.contenedor_id, p.contenedor_id)
    LOOP
        IF v_rec.contenedor_id IS NOT NULL THEN
            INSERT INTO public.movimientos_contenedores (
                cliente_id, orden_id, contenedor_id, cantidad_entregada, cantidad_retirada, creado_por
            ) VALUES (
                v_rec.cliente_id, v_rec.orden_id, v_rec.contenedor_id, 0, v_rec.total_retirados, auth.uid()
            );

            INSERT INTO public.saldo_contenedores_clientes (
                cliente_id, contenedor_id, saldo_pendiente, updated_at
            ) VALUES (
                v_rec.cliente_id, v_rec.contenedor_id, 0, NOW()
            )
            ON CONFLICT (cliente_id, contenedor_id)
            DO UPDATE SET 
                saldo_pendiente = GREATEST(0, public.saldo_contenedores_clientes.saldo_pendiente - v_rec.total_retirados),
                updated_at = NOW();

            v_contenedores_retirados_procesados := v_contenedores_retirados_procesados + v_rec.total_retirados;
        END IF;
    END LOOP;

    -- 4. Devuelve el inventario no despachado del camiÃ³n al almacÃ©n principal
    v_inv_res := public.retorna_inventario_no_despachado_para_almacen(p_radar_id);

    -- 5. Las Ã³rdenes en estado 'devuelta' pasan al estado final 'anulada'
    WITH ordenes_devueltas AS (
        UPDATE public.ordenes_distribucion
        SET estado = 'anulada'
        WHERE radar_id = p_radar_id AND estado = 'devuelta'
        RETURNING id
    )
    SELECT COUNT(*) INTO v_ordenes_anuladas_count FROM ordenes_devueltas;

    -- 6. PolÃ­ticas de crÃ©dito desactivadas temporalmente (todos los clientes activos)
    v_clientes_deshabilitados_count := 0;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Radar aprobado exitosamente. Saldos de contenedores actualizados, inventario restituido a almacÃ©n y Ã³rdenes devueltas anuladas.',
        'data', jsonb_build_object(
            'radar_id', p_radar_id,
            'status_radar', TRUE,
            'contenedores_entregados_procesados', v_contenedores_entregados_procesados,
            'contenedores_retirados_procesados', v_contenedores_retirados_procesados,
            'clientes_deshabilitados_credito', v_clientes_deshabilitados_count,
            'ordenes_anuladas', v_ordenes_anuladas_count,
            'inventario_reintegrado', COALESCE(v_inv_res->'data', '[]'::jsonb)
        ),
        'error', NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', SQLSTATE,
                'message', SQLERRM
            )
        );
END;
$$;

-- 6. Actualizar `registrar_despacho_cliente_radar` omitiendo bloqueo de despacho por crÃ©dito
CREATE OR REPLACE FUNCTION public.registrar_despacho_cliente_radar(
    p_orden_id UUID,
    p_detalles_json JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_estado_orden TEXT;
    v_camion_id UUID;
    v_radar_id UUID;
    v_status_radar BOOLEAN;
    v_item JSONB;
    v_detalle_id UUID;
    v_cantidad_despachada INT;
    v_estado_entrega TEXT;
    v_motivo_rechazo TEXT;
    v_contenedores_retirados INT;
    v_contenedor_id UUID;
    v_producto_id UUID;
    v_cantidad_solicitada INT;
    v_devolucion INT;
    v_pendientes_count INT;
    v_total_despachado INT := 0;
    v_cliente_id UUID;
    v_despacho_permitido BOOLEAN;
    v_excepcion_gerencia BOOLEAN;
    v_nuevo_estado_orden TEXT;
BEGIN
    IF p_orden_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El parÃ¡metro p_orden_id es obligatorio.'
            )
        );
    END IF;

    SELECT o.estado, o.camion_id, o.cliente_id, o.radar_id,
           COALESCE(c.excepcion_despacho_gerencia, FALSE),
           TRUE
    INTO v_estado_orden, v_camion_id, v_cliente_id, v_radar_id, v_excepcion_gerencia, v_despacho_permitido
    FROM public.ordenes_distribucion o
    JOIN public.clientes c ON o.cliente_id = c.id
    WHERE o.id = p_orden_id;

    v_despacho_permitido := TRUE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'ORDEN_INEXISTENTE',
                'message', 'No se encontrÃ³ la orden especificada.'
            )
        );
    END IF;

    IF v_radar_id IS NOT NULL THEN
        SELECT COALESCE(status_radar, FALSE)
        INTO v_status_radar
        FROM public.radars
        WHERE id = v_radar_id;

        IF v_status_radar = TRUE THEN
            RETURN jsonb_build_object(
                'success', FALSE,
                'error', jsonb_build_object(
                    'code', 'RADAR_APROBADO_BLOQUEADO',
                    'message', 'El radar correspondiente ya ha sido aprobado por la Gerencia y se encuentra bloqueado para modificaciones.'
                )
            );
        END IF;
    END IF;

    IF v_estado_orden NOT IN ('en_transito', 'despachada', 'por_liquidar', 'devuelta') THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo se pueden registrar entregas de Ã³rdenes activas en ruta.'
            )
        );
    END IF;

    IF p_detalles_json IS NOT NULL AND jsonb_array_length(p_detalles_json) > 0 THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(p_detalles_json) LOOP
            v_detalle_id := (v_item->>'detalle_id')::UUID;
            v_cantidad_despachada := COALESCE((v_item->>'cantidad_despachada')::INT, 0);
            v_estado_entrega := v_item->>'estado_entrega';
            v_motivo_rechazo := v_item->>'motivo_rechazo';
            v_contenedores_retirados := COALESCE((v_item->>'contenedores_retirados')::INT, 0);
            v_contenedor_id := (v_item->>'contenedor_id')::UUID;

            SELECT producto_id, cantidad_solicitada INTO v_producto_id, v_cantidad_solicitada
            FROM public.detalle_distribucion
            WHERE id = v_detalle_id AND orden_id = p_orden_id;

            IF FOUND THEN
                v_devolucion := GREATEST(0, v_cantidad_solicitada - v_cantidad_despachada);

                IF v_camion_id IS NOT NULL THEN
                    UPDATE public.inventario_movil
                    SET cantidad_entregada = cantidad_entregada + v_cantidad_despachada,
                        cantidad_devolucion = cantidad_devolucion + v_devolucion,
                        updated_at = NOW()
                    WHERE camion_id = v_camion_id AND producto_id = v_producto_id;
                END IF;

                UPDATE public.detalle_distribucion
                SET cantidad_despachada = v_cantidad_despachada,
                    estado_entrega = COALESCE(v_estado_entrega, CASE WHEN v_cantidad_despachada > 0 THEN 'entregado' ELSE 'rechazado' END),
                    motivo_rechazo = v_motivo_rechazo,
                    contenedores_retirados = v_contenedores_retirados,
                    contenedor_id = v_contenedor_id
                WHERE id = v_detalle_id;
            END IF;
        END LOOP;
    END IF;

    SELECT COUNT(*) INTO v_pendientes_count
    FROM public.detalle_distribucion
    WHERE orden_id = p_orden_id AND (estado_entrega IS NULL OR estado_entrega = 'pendiente');

    IF v_pendientes_count = 0 THEN
        SELECT COALESCE(SUM(cantidad_despachada), 0) INTO v_total_despachado
        FROM public.detalle_distribucion
        WHERE orden_id = p_orden_id;

        IF v_total_despachado = 0 THEN
            v_nuevo_estado_orden := 'devuelta';
        ELSE
            v_nuevo_estado_orden := 'por_liquidar';
        END IF;

        UPDATE public.ordenes_distribucion
        SET estado = v_nuevo_estado_orden
        WHERE id = p_orden_id;

        IF v_excepcion_gerencia THEN
            UPDATE public.clientes
            SET excepcion_despacho_gerencia = FALSE
            WHERE id = v_cliente_id;
        END IF;
    ELSE
        v_nuevo_estado_orden := v_estado_orden;
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Despacho registrado en radar exitosamente.',
        'data', jsonb_build_object(
            'orden_id', p_orden_id,
            'nuevo_estado', v_nuevo_estado_orden,
            'total_despachado', v_total_despachado
        ),
        'error', NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', SQLSTATE,
                'message', SQLERRM
            )
        );
END;
$$;
-- Migration: 20260911130000_limpieza_ordenes_y_radars.sql
-- Description: Limpieza completa de las tablas detalle_distribucion, ordenes_distribucion y radars.

TRUNCATE TABLE public.detalle_distribucion CASCADE;
TRUNCATE TABLE public.ordenes_distribucion CASCADE;
TRUNCATE TABLE public.radars CASCADE;
-- Migration: 20260911133000_permitir_edicion_ordenes_aprobadas.sql
-- Description: Permitir la actualizaciÃ³n y ediciÃ³n de Ã³rdenes de distribuciÃ³n que estÃ©n en estado 'aprobada' (ademÃ¡s de 'borrador').

CREATE OR REPLACE FUNCTION public.actualiza_orden_distribucion_segun_correlativo(
    p_correlativo INT,
    p_header JSONB,
    p_detalle JSONB
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_orden_id UUID;
    v_estado_actual TEXT;
    v_creado_por UUID;
    v_user_id UUID := auth.uid();
    
    v_cliente_id UUID;
    v_camion_id UUID;
    v_fecha_despacho TIMESTAMPTZ;
    v_factura_origen TEXT;
    v_fecha_tasa DATE;
    v_tasa_cambio NUMERIC(14,4);
    
    v_peso_total NUMERIC(14,2) := 0.00;
    v_total_usd NUMERIC(14,2) := 0.00;
    
    v_item JSONB;
    v_secuencia INT := 1;
    v_producto_id UUID;
    v_cantidad INT;
    v_val_usd NUMERIC(14,2);
    v_val_usd_prod NUMERIC(14,2);
    v_subtotal_usd NUMERIC(14,2);
    v_peso_unitario NUMERIC(14,2);
BEGIN
    -- 1. Validar parÃ¡metros principales
    IF p_correlativo IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El correlativo de la orden es requerido.',
                'details', NULL
            )
        );
    END IF;

    -- Obtener orden actual
    SELECT id, estado, creado_por
    INTO v_orden_id, v_estado_actual, v_creado_por
    FROM public.ordenes_distribucion
    WHERE correlativo = p_correlativo;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ORDEN_NO_ENCONTRADA',
                'message', 'No se encontrÃ³ la orden con correlativo ' || p_correlativo::text,
                'details', NULL
            )
        );
    END IF;

    -- Validar que la orden estÃ© en estado borrador o aprobada para modificaciÃ³n
    IF v_estado_actual NOT IN ('borrador', 'aprobada') THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo se pueden actualizar Ã³rdenes en estado borrador o aprobada. Estado actual: ' || v_estado_actual,
                'details', NULL
            )
        );
    END IF;

    -- Validar permisos por rol
    IF public.user_has_role(ARRAY['vendedor']) AND NOT public.user_has_role(ARRAY['admin', 'gerente', 'despachador']) THEN
        IF v_user_id IS NOT NULL AND v_creado_por IS DISTINCT FROM v_user_id THEN
            RETURN json_build_object(
                'success', false,
                'data', NULL,
                'error', json_build_object(
                    'code', 'ACCESO_DENEGADO',
                    'message', 'Un vendedor solo puede actualizar las Ã³rdenes que Ã©l mismo ha registrado.',
                    'details', NULL
                )
            );
        END IF;
    END IF;

    -- Extract header values
    v_cliente_id := (p_header->>'cliente_id')::UUID;
    v_camion_id := (p_header->>'camion_id')::UUID;
    v_fecha_despacho := (p_header->>'fecha_despacho')::TIMESTAMPTZ;
    v_factura_origen := p_header->>'factura_origen_numero';
    v_fecha_tasa := COALESCE(v_fecha_despacho::date, CURRENT_DATE);

    -- Validar existencia de tasa de cambio para la fecha de la orden
    SELECT tasa_cambio INTO v_tasa_cambio
    FROM public.tasa_cambio
    WHERE fecha_tasa = v_fecha_tasa;

    IF NOT FOUND THEN
        SELECT tasa_cambio INTO v_tasa_cambio
        FROM public.tasa_cambio
        ORDER BY fecha_tasa DESC
        LIMIT 1;
    END IF;

    IF v_tasa_cambio IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'EXCEPCION_TASA_NO_ENCONTRADA',
                'message', 'No existe tasa de cambio registrada para la fecha ' || v_fecha_tasa::text,
                'details', NULL
            )
        );
    END IF;

    -- Re-calcular totales recorriendo el detalle exclusivamente en USD
    IF p_detalle IS NOT NULL AND jsonb_array_length(p_detalle) > 0 THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(p_detalle) LOOP
            v_producto_id := (v_item->>'producto_id')::UUID;
            v_cantidad := (v_item->>'cantidad_solicitada')::INT;
            
            SELECT COALESCE(precio_lista1, 0.00), COALESCE(peso_unitario_kg, 0.00)
            INTO v_val_usd_prod, v_peso_unitario
            FROM public.productos WHERE id = v_producto_id;

            v_val_usd := COALESCE((v_item->>'valor_unitario_usd')::NUMERIC, (v_item->>'precio_unitario')::NUMERIC, v_val_usd_prod);
            IF v_val_usd <= 0 OR (v_val_usd < 1.00 AND v_val_usd_prod >= 1.00) THEN
                v_val_usd := v_val_usd_prod;
            END IF;

            v_subtotal_usd := ROUND(v_cantidad * v_val_usd, 2);

            v_total_usd := v_total_usd + v_subtotal_usd;
            v_peso_total := v_peso_total + (v_peso_unitario * v_cantidad);
        END LOOP;
    END IF;

    -- Actualizar Cabecera de la Orden (total_recaudar_bs en NULL)
    UPDATE public.ordenes_distribucion
    SET cliente_id = COALESCE(v_cliente_id, cliente_id),
        camion_id = COALESCE(v_camion_id, camion_id),
        fecha_despacho = COALESCE(v_fecha_despacho, fecha_despacho),
        factura_origen_numero = COALESCE(v_factura_origen, factura_origen_numero),
        tasa_cambio = v_tasa_cambio,
        peso_total_calculado = v_peso_total,
        total_recaudar_bs = NULL,
        total_recaudar_usd = v_total_usd
    WHERE id = v_orden_id;

    -- Reemplazar Detalle si fue provisto (valor_unitario_recaudar y subtotal_recaudar en NULL)
    IF p_detalle IS NOT NULL AND jsonb_array_length(p_detalle) > 0 THEN
        DELETE FROM public.detalle_distribucion WHERE orden_id = v_orden_id;

        FOR v_item IN SELECT * FROM jsonb_array_elements(p_detalle) LOOP
            v_producto_id := (v_item->>'producto_id')::UUID;
            v_cantidad := (v_item->>'cantidad_solicitada')::INT;
            
            SELECT COALESCE(precio_lista1, 0.00) INTO v_val_usd_prod
            FROM public.productos WHERE id = v_producto_id;

            v_val_usd := COALESCE((v_item->>'valor_unitario_usd')::NUMERIC, (v_item->>'precio_unitario')::NUMERIC, v_val_usd_prod);
            IF v_val_usd <= 0 OR (v_val_usd < 1.00 AND v_val_usd_prod >= 1.00) THEN
                v_val_usd := v_val_usd_prod;
            END IF;

            v_subtotal_usd := ROUND(v_cantidad * v_val_usd, 2);

            INSERT INTO public.detalle_distribucion (
                id,
                orden_id,
                producto_id,
                cantidad_solicitada,
                cantidad_despachada,
                valor_unitario_recaudar,
                subtotal_recaudar,
                valor_unitario_usd,
                subtotal_recaudar_usd,
                secuencia_entrega,
                estado_entrega
            ) VALUES (
                gen_random_uuid(),
                v_orden_id,
                v_producto_id,
                v_cantidad,
                0,
                NULL,
                NULL,
                v_val_usd,
                v_subtotal_usd,
                v_secuencia,
                'pendiente'
            );

            v_secuencia := v_secuencia + 1;
        END LOOP;
    END IF;

    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'correlativo', p_correlativo,
            'orden_id', v_orden_id,
            'tasa_cambio', v_tasa_cambio,
            'total_recaudar_bs', NULL,
            'total_recaudar_usd', v_total_usd
        ),
        'error', NULL
    );

EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object(
        'success', false,
        'data', NULL,
        'error', json_build_object(
            'code', 'SQL_ERROR',
            'message', SQLERRM,
            'details', NULL
        )
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.actualiza_orden_distribucion_segun_correlativo TO authenticated, service_role;
-- Migration: 20260915130000_solicita_cargar_inventario_movil_desde_almacen.sql
-- Description: FunciÃ³n RPC para realizar la carga consolidada de inventario mÃ³vil por camiÃ³n desde el resumen del radar

CREATE OR REPLACE FUNCTION public.solicita_cargar_inventario_movil_desde_almacen(
    p_camion_id UUID,
    p_resumen_productos JSONB,
    p_radar_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_item JSONB;
    v_items_array JSONB;
    v_producto_id UUID;
    v_cantidad_solicitada INT;
    v_total_productos_cargados INT := 0;
    v_unidades_totales INT := 0;
    v_camion_existe BOOLEAN;
    v_ordenes_actualizadas INT := 0;
BEGIN
    -- 1. Validaciones bÃ¡sicas
    IF p_camion_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID del camiÃ³n es requerido.'
            )
        );
    END IF;

    SELECT EXISTS(SELECT 1 FROM public.camiones WHERE id = p_camion_id) INTO v_camion_existe;
    IF NOT v_camion_existe THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'CAMION_INEXISTENTE',
                'message', 'El camiÃ³n especificado no existe.'
            )
        );
    END IF;

    -- Extraer el arreglo de productos (soporta directo [...] u objeto {"resumen_productos": [...]})
    IF jsonb_typeof(p_resumen_productos) = 'array' THEN
        v_items_array := p_resumen_productos;
    ELSIF jsonb_typeof(p_resumen_productos) = 'object' AND p_resumen_productos ? 'resumen_productos' THEN
        v_items_array := p_resumen_productos->'resumen_productos';
    ELSE
        v_items_array := '[]'::jsonb;
    END IF;

    IF v_items_array IS NULL OR jsonb_array_length(v_items_array) = 0 THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'DATOS_VACIOS',
                'message', 'El resumen de productos a cargar no contiene elementos vÃ¡lidos.'
            )
        );
    END IF;

    -- 2. Procesamiento de Carga de Inventario
    FOR v_item IN SELECT * FROM jsonb_array_elements(v_items_array) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad_solicitada := COALESCE((v_item->>'cantidad_solicitada')::INT, 0);

        IF v_producto_id IS NOT NULL AND v_cantidad_solicitada > 0 THEN
            -- Descontar del almacÃ©n principal (reducir stock_comprometido y/o stock_disponible)
            UPDATE public.inventario_almacen
            SET stock_comprometido = GREATEST(0, stock_comprometido - v_cantidad_solicitada),
                stock_disponible = CASE 
                    WHEN stock_comprometido < v_cantidad_solicitada 
                    THEN GREATEST(0, stock_disponible - (v_cantidad_solicitada - stock_comprometido))
                    ELSE stock_disponible 
                END,
                updated_at = NOW()
            WHERE producto_id = v_producto_id;

            -- Upsert en inventario mÃ³vil del camiÃ³n (sumar a cantidad_cargada)
            INSERT INTO public.inventario_movil (
                camion_id,
                producto_id,
                cantidad_cargada,
                cantidad_entregada,
                cantidad_devolucion,
                updated_at
            ) VALUES (
                p_camion_id,
                v_producto_id,
                v_cantidad_solicitada,
                0,
                0,
                NOW()
            )
            ON CONFLICT (camion_id, producto_id)
            DO UPDATE SET
                cantidad_cargada = public.inventario_movil.cantidad_cargada + v_cantidad_solicitada,
                updated_at = NOW();

            v_total_productos_cargados := v_total_productos_cargados + 1;
            v_unidades_totales := v_unidades_totales + v_cantidad_solicitada;
        END IF;
    END LOOP;

    -- 3. Actualizar estado del camiÃ³n a 'en_ruta'
    UPDATE public.camiones
    SET estado = 'en_ruta'
    WHERE id = p_camion_id;


    -- 4. Transicionar Ã³rdenes vinculadas a 'en_transito' y fijar fecha_despacho = NOW()
    IF p_radar_id IS NOT NULL THEN
        UPDATE public.ordenes_distribucion
        SET estado = 'en_transito',
            fecha_despacho = NOW(),
            updated_at = NOW()
        WHERE radar_id = p_radar_id AND estado = 'aprobada';
        
        GET DIAGNOSTICS v_ordenes_actualizadas = ROW_COUNT;
    ELSE
        UPDATE public.ordenes_distribucion
        SET estado = 'en_transito',
            fecha_despacho = NOW(),
            updated_at = NOW()
        WHERE camion_id = p_camion_id AND estado = 'aprobada';
        
        GET DIAGNOSTICS v_ordenes_actualizadas = ROW_COUNT;
    END IF;

    -- 5. Inicializar cantidad_despachada = cantidad_solicitada en detalle_distribucion para las Ã³rdenes en_transito
    IF p_radar_id IS NOT NULL THEN
        UPDATE public.detalle_distribucion dd
        SET cantidad_despachada = dd.cantidad_solicitada
        FROM public.ordenes_distribucion od
        WHERE dd.orden_id = od.id
          AND od.radar_id = p_radar_id
          AND od.estado = 'en_transito';
    ELSE
        UPDATE public.detalle_distribucion dd
        SET cantidad_despachada = dd.cantidad_solicitada
        FROM public.ordenes_distribucion od
        WHERE dd.orden_id = od.id
          AND od.camion_id = p_camion_id
          AND od.estado = 'en_transito';
    END IF;

    -- 6. Respuesta Exitosa
    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Carga a inventario mÃ³vil procesada exitosamente desde el almacÃ©n.',
        'data', jsonb_build_object(
            'camion_id', p_camion_id,
            'radar_id', p_radar_id,
            'total_productos_cargados', v_total_productos_cargados,
            'unidades_totales', v_unidades_totales,
            'ordenes_despachadas', v_ordenes_actualizadas
        ),
        'error', NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'SQL_ERROR',
                'message', SQLERRM,
                'details', 'SQLSTATE: ' || SQLSTATE
            )
        );
END;
$$;

GRANT EXECUTE ON FUNCTION public.solicita_cargar_inventario_movil_desde_almacen(UUID, JSONB, UUID) TO authenticated, service_role;
-- Migration: 20260915140000_reversar_carga_y_bandera_radars.sql
-- Description: Agregar columna carga_inventario_movil a public.radars y crear las funciones RPC solicita_cargar_inventario_movil_desde_almacen y solicita_reversar_carga_inventario_movil_a_almacen

-- 1. DDL: Agregar columna carga_inventario_movil a public.radars
ALTER TABLE public.radars ADD COLUMN IF NOT EXISTS carga_inventario_movil BOOLEAN DEFAULT FALSE;

-- 2. RPC: solicita_cargar_inventario_movil_desde_almacen
CREATE OR REPLACE FUNCTION public.solicita_cargar_inventario_movil_desde_almacen(
    p_camion_id UUID,
    p_resumen_productos JSONB,
    p_radar_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_item JSONB;
    v_items_array JSONB;
    v_producto_id UUID;
    v_cantidad_solicitada INT;
    v_total_productos_cargados INT := 0;
    v_unidades_totales INT := 0;
    v_camion_existe BOOLEAN;
    v_ordenes_actualizadas INT := 0;
    v_radar_id UUID;
BEGIN
    -- Validaciones bÃ¡sicas
    IF p_camion_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID del camiÃ³n es requerido.'
            )
        );
    END IF;

    SELECT EXISTS(SELECT 1 FROM public.camiones WHERE id = p_camion_id) INTO v_camion_existe;
    IF NOT v_camion_existe THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'CAMION_INEXISTENTE',
                'message', 'El camiÃ³n especificado no existe.'
            )
        );
    END IF;

    v_radar_id := p_radar_id;
    IF v_radar_id IS NULL THEN
        SELECT radar_id INTO v_radar_id
        FROM public.ordenes_distribucion
        WHERE camion_id = p_camion_id AND radar_id IS NOT NULL
        ORDER BY updated_at DESC
        LIMIT 1;
    END IF;

    IF jsonb_typeof(p_resumen_productos) = 'array' THEN
        v_items_array := p_resumen_productos;
    ELSIF jsonb_typeof(p_resumen_productos) = 'object' AND p_resumen_productos ? 'resumen_productos' THEN
        v_items_array := p_resumen_productos->'resumen_productos';
    ELSE
        v_items_array := '[]'::jsonb;
    END IF;

    IF v_items_array IS NULL OR jsonb_array_length(v_items_array) = 0 THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'DATOS_VACIOS',
                'message', 'El resumen de productos a cargar no contiene elementos vÃ¡lidos.'
            )
        );
    END IF;

    FOR v_item IN SELECT * FROM jsonb_array_elements(v_items_array) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad_solicitada := COALESCE((v_item->>'cantidad_solicitada')::INT, 0);

        IF v_producto_id IS NOT NULL AND v_cantidad_solicitada > 0 THEN
            UPDATE public.inventario_almacen
            SET stock_comprometido = GREATEST(0, stock_comprometido - v_cantidad_solicitada),
                stock_disponible = CASE 
                    WHEN stock_comprometido < v_cantidad_solicitada 
                    THEN GREATEST(0, stock_disponible - (v_cantidad_solicitada - stock_comprometido))
                    ELSE stock_disponible 
                END,
                updated_at = NOW()
            WHERE producto_id = v_producto_id;

            INSERT INTO public.inventario_movil (
                camion_id,
                producto_id,
                cantidad_cargada,
                cantidad_entregada,
                cantidad_devolucion,
                updated_at
            ) VALUES (
                p_camion_id,
                v_producto_id,
                v_cantidad_solicitada,
                0,
                0,
                NOW()
            )
            ON CONFLICT (camion_id, producto_id)
            DO UPDATE SET
                cantidad_cargada = public.inventario_movil.cantidad_cargada + v_cantidad_solicitada,
                updated_at = NOW();

            v_total_productos_cargados := v_total_productos_cargados + 1;
            v_unidades_totales := v_unidades_totales + v_cantidad_solicitada;
        END IF;
    END LOOP;

    UPDATE public.camiones
    SET estado = 'en_ruta'
    WHERE id = p_camion_id;


    IF v_radar_id IS NOT NULL THEN
        UPDATE public.ordenes_distribucion
        SET estado = 'en_transito',
            updated_at = NOW()
        WHERE radar_id = v_radar_id AND estado = 'aprobada';
        
        GET DIAGNOSTICS v_ordenes_actualizadas = ROW_COUNT;
    ELSE
        UPDATE public.ordenes_distribucion
        SET estado = 'en_transito',
            updated_at = NOW()
        WHERE camion_id = p_camion_id AND estado = 'aprobada';
        
        GET DIAGNOSTICS v_ordenes_actualizadas = ROW_COUNT;
    END IF;

    IF v_radar_id IS NOT NULL THEN
        UPDATE public.detalle_distribucion dd
        SET cantidad_despachada = dd.cantidad_solicitada
        FROM public.ordenes_distribucion od
        WHERE dd.orden_id = od.id
          AND od.radar_id = v_radar_id
          AND od.estado = 'en_transito';
    ELSE
        UPDATE public.detalle_distribucion dd
        SET cantidad_despachada = dd.cantidad_solicitada
        FROM public.ordenes_distribucion od
        WHERE dd.orden_id = od.id
          AND od.camion_id = p_camion_id
          AND od.estado = 'en_transito';
    END IF;

    IF v_radar_id IS NOT NULL THEN
        UPDATE public.radars
        SET carga_inventario_movil = TRUE,
            updated_at = NOW()
        WHERE id = v_radar_id;
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Carga a inventario mÃ³vil procesada exitosamente desde el almacÃ©n.',
        'data', jsonb_build_object(
            'camion_id', p_camion_id,
            'radar_id', v_radar_id,
            'carga_inventario_movil', TRUE,
            'total_productos_cargados', v_total_productos_cargados,
            'unidades_totales', v_unidades_totales,
            'ordenes_despachadas', v_ordenes_actualizadas
        ),
        'error', NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'SQL_ERROR',
                'message', SQLERRM,
                'details', 'SQLSTATE: ' || SQLSTATE
            )
        );
END;
$$;

GRANT EXECUTE ON FUNCTION public.solicita_cargar_inventario_movil_desde_almacen(UUID, JSONB, UUID) TO authenticated, service_role;


-- 3. RPC: solicita_reversar_carga_inventario_movil_a_almacen
CREATE OR REPLACE FUNCTION public.solicita_reversar_carga_inventario_movil_a_almacen(
    p_camion_id UUID,
    p_resumen_productos JSONB DEFAULT NULL,
    p_radar_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_item JSONB;
    v_items_array JSONB := '[]'::jsonb;
    v_producto_id UUID;
    v_cantidad INT;
    v_total_productos_reversados INT := 0;
    v_unidades_totales INT := 0;
    v_camion_existe BOOLEAN;
    v_radar_id UUID;
    v_carga_inventario BOOLEAN;
    v_entregas_existentes INT := 0;
    v_ordenes_reversadas INT := 0;
    v_rec RECORD;
BEGIN
    IF p_camion_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID del camiÃ³n es requerido.'
            )
        );
    END IF;

    SELECT EXISTS(SELECT 1 FROM public.camiones WHERE id = p_camion_id) INTO v_camion_existe;
    IF NOT v_camion_existe THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'CAMION_INEXISTENTE',
                'message', 'El camiÃ³n especificado no existe.'
            )
        );
    END IF;

    v_radar_id := p_radar_id;
    IF v_radar_id IS NULL THEN
        SELECT radar_id INTO v_radar_id
        FROM public.ordenes_distribucion
        WHERE camion_id = p_camion_id AND radar_id IS NOT NULL
        ORDER BY updated_at DESC
        LIMIT 1;
    END IF;

    IF v_radar_id IS NOT NULL THEN
        SELECT COALESCE(carga_inventario_movil, FALSE) INTO v_carga_inventario
        FROM public.radars
        WHERE id = v_radar_id;

        IF NOT v_carga_inventario THEN
            RETURN jsonb_build_object(
                'success', FALSE,
                'data', NULL,
                'error', jsonb_build_object(
                    'code', 'INVENTARIO_NO_CARGADO',
                    'message', 'El inventario mÃ³vil de este radar no ha sido cargado previamente o ya fue reversado.'
                )
            );
        END IF;

        SELECT COUNT(*) INTO v_entregas_existentes
        FROM public.ordenes_distribucion
        WHERE radar_id = v_radar_id AND estado IN ('despachada', 'por_liquidar', 'liquidada', 'devuelta');

        IF v_entregas_existentes > 0 THEN
            RETURN jsonb_build_object(
                'success', FALSE,
                'data', NULL,
                'error', jsonb_build_object(
                    'code', 'REVERSO_BLOQUEADO_POR_ENTREGAS',
                    'message', 'No se puede reversar la carga al almacÃ©n porque ya existen entregas o despachos registrados en esta ruta.'
                )
            );
        END IF;
    END IF;

    IF p_resumen_productos IS NOT NULL THEN
        IF jsonb_typeof(p_resumen_productos) = 'array' THEN
            v_items_array := p_resumen_productos;
        ELSIF jsonb_typeof(p_resumen_productos) = 'object' AND p_resumen_productos ? 'resumen_productos' THEN
            v_items_array := p_resumen_productos->'resumen_productos';
        END IF;
    END IF;

    IF jsonb_array_length(v_items_array) > 0 THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(v_items_array) LOOP
            v_producto_id := (v_item->>'producto_id')::UUID;
            v_cantidad := COALESCE((v_item->>'cantidad_solicitada')::INT, 0);

            IF v_producto_id IS NOT NULL AND v_cantidad > 0 THEN
                INSERT INTO public.inventario_almacen (producto_id, stock_disponible, stock_comprometido, updated_at)
                VALUES (v_producto_id, v_cantidad, 0, NOW())
                ON CONFLICT (producto_id)
                DO UPDATE SET
                    stock_disponible = public.inventario_almacen.stock_disponible + v_cantidad,
                    updated_at = NOW();

                UPDATE public.inventario_movil
                SET cantidad_cargada = GREATEST(0, cantidad_cargada - v_cantidad),
                    updated_at = NOW()
                WHERE camion_id = p_camion_id AND producto_id = v_producto_id;

                v_total_productos_reversados := v_total_productos_reversados + 1;
                v_unidades_totales := v_unidades_totales + v_cantidad;
            END IF;
        END LOOP;
    ELSE
        FOR v_rec IN 
            SELECT producto_id, cantidad_cargada
            FROM public.inventario_movil
            WHERE camion_id = p_camion_id AND cantidad_cargada > 0
        LOOP
            INSERT INTO public.inventario_almacen (producto_id, stock_disponible, stock_comprometido, updated_at)
            VALUES (v_rec.producto_id, v_rec.cantidad_cargada, 0, NOW())
            ON CONFLICT (producto_id)
            DO UPDATE SET
                stock_disponible = public.inventario_almacen.stock_disponible + v_rec.cantidad_cargada,
                updated_at = NOW();

            UPDATE public.inventario_movil
            SET cantidad_cargada = 0,
                updated_at = NOW()
            WHERE camion_id = p_camion_id AND producto_id = v_rec.producto_id;

            v_total_productos_reversados := v_total_productos_reversados + 1;
            v_unidades_totales := v_unidades_totales + v_rec.cantidad_cargada;
        END LOOP;
    END IF;

    IF v_radar_id IS NOT NULL THEN
        UPDATE public.ordenes_distribucion
        SET estado = 'aprobada',
            updated_at = NOW()
        WHERE radar_id = v_radar_id AND estado = 'en_transito';

        GET DIAGNOSTICS v_ordenes_reversadas = ROW_COUNT;
    ELSE
        UPDATE public.ordenes_distribucion
        SET estado = 'aprobada',
            updated_at = NOW()
        WHERE camion_id = p_camion_id AND estado = 'en_transito';

        GET DIAGNOSTICS v_ordenes_reversadas = ROW_COUNT;
    END IF;

    IF v_radar_id IS NOT NULL THEN
        UPDATE public.detalle_distribucion dd
        SET cantidad_despachada = 0
        FROM public.ordenes_distribucion od
        WHERE dd.orden_id = od.id AND od.radar_id = v_radar_id;
    ELSE
        UPDATE public.detalle_distribucion dd
        SET cantidad_despachada = 0
        FROM public.ordenes_distribucion od
        WHERE dd.orden_id = od.id AND od.camion_id = p_camion_id;
    END IF;

    UPDATE public.camiones
    SET estado = 'asignado'
    WHERE id = p_camion_id;


    IF v_radar_id IS NOT NULL THEN
        UPDATE public.radars
        SET carga_inventario_movil = FALSE,
            updated_at = NOW()
        WHERE id = v_radar_id;
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Reverso de inventario mÃ³vil al almacÃ©n procesado exitosamente.',
        'data', jsonb_build_object(
            'camion_id', p_camion_id,
            'radar_id', v_radar_id,
            'carga_inventario_movil', FALSE,
            'total_productos_reversados', v_total_productos_reversados,
            'unidades_totales', v_unidades_totales,
            'ordenes_reversadas', v_ordenes_reversadas
        ),
        'error', NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'SQL_ERROR',
                'message', SQLERRM,
                'details', 'SQLSTATE: ' || SQLSTATE
            )
        );
END;
$$;

GRANT EXECUTE ON FUNCTION public.solicita_reversar_carga_inventario_movil_a_almacen(UUID, JSONB, UUID) TO authenticated, service_role;
-- Migration: 20260915150000_sincronizar_y_editar_radar.sql
-- Description: RPC para re-sincronizar y editar las Ã³rdenes de un radar existente en dos fases (desvinculaciÃ³n y revinculaciÃ³n) con validaciÃ³n de inventario cargado

CREATE OR REPLACE FUNCTION public.solicita_editar_o_sincronizar_radar(
    p_radar_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_despachador_id UUID;
    v_fecha_despacho DATE;
    v_status_radar BOOLEAN;
    v_carga_inventario BOOLEAN;
    v_correlativo INT;
    v_tot_solicitada NUMERIC(10,0);
    v_tot_despachada NUMERIC(10,0);
    v_tot_retirados NUMERIC(10,0);
    v_total_ordenes INT;
    v_desvinculadas INT := 0;
    v_vinculadas INT := 0;
BEGIN
    -- 1. Validaciones bÃ¡sicas
    IF p_radar_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID del radar es obligatorio.'
            )
        );
    END IF;

    -- Obtener datos del radar
    SELECT despachador_id, fecha_despacho, correlativo,
           COALESCE(status_radar, FALSE), COALESCE(carga_inventario_movil, FALSE)
    INTO v_despachador_id, v_fecha_despacho, v_correlativo, v_status_radar, v_carga_inventario
    FROM public.radars
    WHERE id = p_radar_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'RADAR_INEXISTENTE',
                'message', 'El radar especificado no existe.'
            )
        );
    END IF;

    -- Validar bloqueos
    IF v_status_radar = TRUE THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'RADAR_APROBADO_BLOQUEADO',
                'message', 'El radar especificado ya ha sido aprobado por la Gerencia y no se puede modificar.'
            )
        );
    END IF;

    IF v_carga_inventario = TRUE THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'RADAR_INVENTARIO_CARGADO',
                'message', 'Para modificar el Radar debe reversar el inventario movil al almacÃ©n'
            )
        );
    END IF;

    -- Fase 1: Desvincular las Ã³rdenes de distribuciÃ³n actualmente vinculadas al radar en estado editable ('aprobada')
    UPDATE public.ordenes_distribucion
    SET radar_id = NULL
    WHERE radar_id = p_radar_id AND estado = 'aprobada';

    GET DIAGNOSTICS v_desvinculadas = ROW_COUNT;

    -- Fase 2: Volver a vincular las Ã³rdenes que tengan la fecha de despacho y despachador del radar
    UPDATE public.ordenes_distribucion o
    SET radar_id = p_radar_id
    FROM public.clientes c
    WHERE o.cliente_id = c.id
      AND c.despachador_id = v_despachador_id
      AND o.fecha_despacho::date = v_fecha_despacho
      AND o.estado IN ('aprobada', 'en_transito', 'por_liquidar', 'liquidada', 'devuelta')
      AND (o.radar_id IS NULL OR o.radar_id = p_radar_id);

    GET DIAGNOSTICS v_vinculadas = ROW_COUNT;

    -- Recalcular totales consolidado del radar
    SELECT 
        COALESCE(SUM(d.cantidad_solicitada), 0),
        COALESCE(SUM(d.cantidad_despachada), 0),
        COALESCE(SUM(d.contenedores_retirados), 0),
        COUNT(DISTINCT o.id)
    INTO v_tot_solicitada, v_tot_despachada, v_tot_retirados, v_total_ordenes
    FROM public.ordenes_distribucion o
    JOIN public.detalle_distribucion d ON d.orden_id = o.id
    WHERE o.radar_id = p_radar_id;

    UPDATE public.radars
    SET total_cantidad_solicitada = v_tot_solicitada,
        total_cantidad_despachada = v_tot_despachada,
        total_contenedores_retirados = v_tot_retirados,
        updated_at = NOW()
    WHERE id = p_radar_id;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Radar re-sincronizado y actualizado exitosamente.',
        'data', jsonb_build_object(
            'radar_id', p_radar_id,
            'correlativo', v_correlativo,
            'despachador_id', v_despachador_id,
            'fecha_despacho', v_fecha_despacho,
            'ordenes_desvinculadas', v_desvinculadas,
            'ordenes_vinculadas', v_total_ordenes,
            'total_cantidad_solicitada', v_tot_solicitada,
            'total_cantidad_despachada', v_tot_despachada,
            'total_contenedores_retirados', v_tot_retirados
        ),
        'error', NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'SQL_ERROR',
                'message', SQLERRM,
                'details', 'SQLSTATE: ' || SQLSTATE
            )
        );
END;
$$;

GRANT EXECUTE ON FUNCTION public.solicita_editar_o_sincronizar_radar(UUID) TO authenticated, service_role;
-- Migration: 20260915160000_lista_radars_por_status.sql
-- Description: Funciones RPC para consultar radares por status (pendientes y aprobados) en un rango de fechas

-- 1. RPC: retorna_lista_radars_pendiente_segun_rango_fechas
CREATE OR REPLACE FUNCTION public.retorna_lista_radars_pendiente_segun_rango_fechas(
    p_despachador_id UUID DEFAULT NULL,
    p_fecha_inicial DATE DEFAULT NULL,
    p_fecha_limite DATE DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_despachador_id UUID;
    v_resultado JSONB;
BEGIN
    v_despachador_id := COALESCE(p_despachador_id, auth.uid());

    IF v_despachador_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'Se requiere el ID de despachador o estar autenticado.'
            )
        );
    END IF;

    SELECT jsonb_build_object(
        'success', TRUE,
        'data', COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'fecha_despacho', r.fecha_despacho,
                    'id_radar', r.id,
                    'correlativo', r.correlativo,
                    'total_paradas', COALESCE(ord_stats.total_paradas, 0),
                    'items', COALESCE(ord_stats.total_items, 0),
                    'sku', COALESCE(ord_stats.total_sku, 0),
                    'status_radar', COALESCE(r.status_radar, FALSE),
                    'carga_inventario_movil', COALESCE(r.carga_inventario_movil, FALSE)
                ) ORDER BY r.fecha_despacho DESC, r.correlativo DESC
            ),
            '[]'::jsonb
        ),
        'error', NULL
    ) INTO v_resultado
    FROM public.radars r
    LEFT JOIN LATERAL (
        SELECT 
            COUNT(DISTINCT o.id) AS total_paradas,
            SUM(COALESCE(d.cantidad_despachada, d.cantidad_solicitada, 0)) AS total_items,
            COUNT(DISTINCT d.producto_id) AS total_sku
        FROM public.ordenes_distribucion o
        LEFT JOIN public.detalle_distribucion d ON d.orden_id = o.id
        WHERE o.radar_id = r.id
    ) ord_stats ON TRUE
    WHERE r.despachador_id = v_despachador_id
      AND COALESCE(r.status_radar, FALSE) = FALSE
      AND (p_fecha_inicial IS NULL OR r.fecha_despacho >= p_fecha_inicial)
      AND (p_fecha_limite IS NULL OR r.fecha_despacho <= p_fecha_limite);

    RETURN v_resultado;

EXCEPTION WHEN OTHERS THEN
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

GRANT EXECUTE ON FUNCTION public.retorna_lista_radars_pendiente_segun_rango_fechas TO authenticated, service_role;

COMMENT ON FUNCTION public.retorna_lista_radars_pendiente_segun_rango_fechas(UUID, DATE, DATE) IS 'Retorna la lista de radares en estado PENDIENTE (status_radar = FALSE) asignados a un despachador en un rango de fechas.';


-- 2. RPC: retorna_lista_radars_aprobado_segun_rango_fechas
CREATE OR REPLACE FUNCTION public.retorna_lista_radars_aprobado_segun_rango_fechas(
    p_despachador_id UUID DEFAULT NULL,
    p_fecha_inicial DATE DEFAULT NULL,
    p_fecha_limite DATE DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_despachador_id UUID;
    v_resultado JSONB;
BEGIN
    v_despachador_id := COALESCE(p_despachador_id, auth.uid());

    IF v_despachador_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'Se requiere el ID de despachador o estar autenticado.'
            )
        );
    END IF;

    SELECT jsonb_build_object(
        'success', TRUE,
        'data', COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'fecha_despacho', r.fecha_despacho,
                    'id_radar', r.id,
                    'correlativo', r.correlativo,
                    'total_paradas', COALESCE(ord_stats.total_paradas, 0),
                    'items', COALESCE(ord_stats.total_items, 0),
                    'sku', COALESCE(ord_stats.total_sku, 0),
                    'status_radar', COALESCE(r.status_radar, FALSE),
                    'carga_inventario_movil', COALESCE(r.carga_inventario_movil, FALSE)
                ) ORDER BY r.fecha_despacho DESC, r.correlativo DESC
            ),
            '[]'::jsonb
        ),
        'error', NULL
    ) INTO v_resultado
    FROM public.radars r
    LEFT JOIN LATERAL (
        SELECT 
            COUNT(DISTINCT o.id) AS total_paradas,
            SUM(COALESCE(d.cantidad_despachada, d.cantidad_solicitada, 0)) AS total_items,
            COUNT(DISTINCT d.producto_id) AS total_sku
        FROM public.ordenes_distribucion o
        LEFT JOIN public.detalle_distribucion d ON d.orden_id = o.id
        WHERE o.radar_id = r.id
    ) ord_stats ON TRUE
    WHERE r.despachador_id = v_despachador_id
      AND COALESCE(r.status_radar, FALSE) = TRUE
      AND (p_fecha_inicial IS NULL OR r.fecha_despacho >= p_fecha_inicial)
      AND (p_fecha_limite IS NULL OR r.fecha_despacho <= p_fecha_limite);

    RETURN v_resultado;

EXCEPTION WHEN OTHERS THEN
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

GRANT EXECUTE ON FUNCTION public.retorna_lista_radars_aprobado_segun_rango_fechas TO authenticated, service_role;

COMMENT ON FUNCTION public.retorna_lista_radars_aprobado_segun_rango_fechas(UUID, DATE, DATE) IS 'Retorna la lista de radares en estado APROBADO (status_radar = TRUE) asignados a un despachador en un rango de fechas.';
-- Migration: 20260915170000_limpieza_inventario_movil.sql
-- Description: Limpieza completa de la tabla inventario_movil.

TRUNCATE TABLE public.inventario_movil CASCADE;
-- Migration: 20260915180000_fix_camiones_sin_updated_at.sql
-- Description: Corregir funciones RPC eliminando referencias a updated_at inexistentes en las tablas public.camiones y public.ordenes_distribucion

-- 1. RPC: solicita_cargar_inventario_movil_desde_almacen
CREATE OR REPLACE FUNCTION public.solicita_cargar_inventario_movil_desde_almacen(
    p_camion_id UUID,
    p_resumen_productos JSONB,
    p_radar_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_item JSONB;
    v_items_array JSONB;
    v_producto_id UUID;
    v_cantidad_solicitada INT;
    v_total_productos_cargados INT := 0;
    v_unidades_totales INT := 0;
    v_camion_existe BOOLEAN;
    v_ordenes_actualizadas INT := 0;
    v_radar_id UUID;
BEGIN
    -- Validaciones bÃ¡sicas
    IF p_camion_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID del camiÃ³n es requerido.'
            )
        );
    END IF;

    SELECT EXISTS(SELECT 1 FROM public.camiones WHERE id = p_camion_id) INTO v_camion_existe;
    IF NOT v_camion_existe THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'CAMION_INEXISTENTE',
                'message', 'El camiÃ³n especificado no existe.'
            )
        );
    END IF;

    v_radar_id := p_radar_id;
    IF v_radar_id IS NULL THEN
        SELECT radar_id INTO v_radar_id
        FROM public.ordenes_distribucion
        WHERE camion_id = p_camion_id AND radar_id IS NOT NULL
        ORDER BY created_at DESC
        LIMIT 1;
    END IF;

    IF jsonb_typeof(p_resumen_productos) = 'array' THEN
        v_items_array := p_resumen_productos;
    ELSIF jsonb_typeof(p_resumen_productos) = 'object' AND p_resumen_productos ? 'resumen_productos' THEN
        v_items_array := p_resumen_productos->'resumen_productos';
    ELSE
        v_items_array := '[]'::jsonb;
    END IF;

    IF v_items_array IS NULL OR jsonb_array_length(v_items_array) = 0 THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'DATOS_VACIOS',
                'message', 'El resumen de productos a cargar no contiene elementos vÃ¡lidos.'
            )
        );
    END IF;

    FOR v_item IN SELECT * FROM jsonb_array_elements(v_items_array) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad_solicitada := COALESCE((v_item->>'cantidad_solicitada')::INT, 0);

        IF v_producto_id IS NOT NULL AND v_cantidad_solicitada > 0 THEN
            UPDATE public.inventario_almacen
            SET stock_comprometido = GREATEST(0, stock_comprometido - v_cantidad_solicitada),
                stock_disponible = CASE 
                    WHEN stock_comprometido < v_cantidad_solicitada 
                    THEN GREATEST(0, stock_disponible - (v_cantidad_solicitada - stock_comprometido))
                    ELSE stock_disponible 
                END,
                updated_at = NOW()
            WHERE producto_id = v_producto_id;

            INSERT INTO public.inventario_movil (
                camion_id,
                producto_id,
                cantidad_cargada,
                cantidad_entregada,
                cantidad_devolucion,
                updated_at
            ) VALUES (
                p_camion_id,
                v_producto_id,
                v_cantidad_solicitada,
                0,
                0,
                NOW()
            )
            ON CONFLICT (camion_id, producto_id)
            DO UPDATE SET
                cantidad_cargada = public.inventario_movil.cantidad_cargada + v_cantidad_solicitada,
                updated_at = NOW();

            v_total_productos_cargados := v_total_productos_cargados + 1;
            v_unidades_totales := v_unidades_totales + v_cantidad_solicitada;
        END IF;
    END LOOP;

    -- Actualizar estado del camiÃ³n (sin updated_at)
    UPDATE public.camiones
    SET estado = 'en_ruta'
    WHERE id = p_camion_id;

    -- Transicionar Ã³rdenes vinculadas (sin updated_at)
    IF v_radar_id IS NOT NULL THEN
        UPDATE public.ordenes_distribucion
        SET estado = 'en_transito'
        WHERE radar_id = v_radar_id AND estado = 'aprobada';
        
        GET DIAGNOSTICS v_ordenes_actualizadas = ROW_COUNT;
    ELSE
        UPDATE public.ordenes_distribucion
        SET estado = 'en_transito'
        WHERE camion_id = p_camion_id AND estado = 'aprobada';
        
        GET DIAGNOSTICS v_ordenes_actualizadas = ROW_COUNT;
    END IF;

    IF v_radar_id IS NOT NULL THEN
        UPDATE public.detalle_distribucion dd
        SET cantidad_despachada = dd.cantidad_solicitada
        FROM public.ordenes_distribucion od
        WHERE dd.orden_id = od.id
          AND od.radar_id = v_radar_id
          AND od.estado = 'en_transito';
    ELSE
        UPDATE public.detalle_distribucion dd
        SET cantidad_despachada = dd.cantidad_solicitada
        FROM public.ordenes_distribucion od
        WHERE dd.orden_id = od.id
          AND od.camion_id = p_camion_id
          AND od.estado = 'en_transito';
    END IF;

    IF v_radar_id IS NOT NULL THEN
        UPDATE public.radars
        SET carga_inventario_movil = TRUE,
            updated_at = NOW()
        WHERE id = v_radar_id;
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Carga a inventario mÃ³vil procesada exitosamente desde el almacÃ©n.',
        'data', jsonb_build_object(
            'camion_id', p_camion_id,
            'radar_id', v_radar_id,
            'carga_inventario_movil', TRUE,
            'total_productos_cargados', v_total_productos_cargados,
            'unidades_totales', v_unidades_totales,
            'ordenes_despachadas', v_ordenes_actualizadas
        ),
        'error', NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'SQL_ERROR',
                'message', SQLERRM,
                'details', 'SQLSTATE: ' || SQLSTATE
            )
        );
END;
$$;


-- 2. RPC: solicita_reversar_carga_inventario_movil_a_almacen
CREATE OR REPLACE FUNCTION public.solicita_reversar_carga_inventario_movil_a_almacen(
    p_camion_id UUID,
    p_resumen_productos JSONB DEFAULT NULL,
    p_radar_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_item JSONB;
    v_items_array JSONB := '[]'::jsonb;
    v_producto_id UUID;
    v_cantidad INT;
    v_total_productos_reversados INT := 0;
    v_unidades_totales INT := 0;
    v_camion_existe BOOLEAN;
    v_radar_id UUID;
    v_carga_inventario BOOLEAN;
    v_entregas_existentes INT := 0;
    v_ordenes_reversadas INT := 0;
    v_rec RECORD;
BEGIN
    IF p_camion_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID del camiÃ³n es requerido.'
            )
        );
    END IF;

    SELECT EXISTS(SELECT 1 FROM public.camiones WHERE id = p_camion_id) INTO v_camion_existe;
    IF NOT v_camion_existe THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'CAMION_INEXISTENTE',
                'message', 'El camiÃ³n especificado no existe.'
            )
        );
    END IF;

    v_radar_id := p_radar_id;
    IF v_radar_id IS NULL THEN
        SELECT radar_id INTO v_radar_id
        FROM public.ordenes_distribucion
        WHERE camion_id = p_camion_id AND radar_id IS NOT NULL
        ORDER BY created_at DESC
        LIMIT 1;
    END IF;

    IF v_radar_id IS NOT NULL THEN
        SELECT COALESCE(carga_inventario_movil, FALSE) INTO v_carga_inventario
        FROM public.radars
        WHERE id = v_radar_id;

        IF NOT v_carga_inventario THEN
            RETURN jsonb_build_object(
                'success', FALSE,
                'data', NULL,
                'error', jsonb_build_object(
                    'code', 'INVENTARIO_NO_CARGADO',
                    'message', 'El inventario mÃ³vil de este radar no ha sido cargado previamente o ya fue reversado.'
                )
            );
        END IF;

        SELECT COUNT(*) INTO v_entregas_existentes
        FROM public.ordenes_distribucion
        WHERE radar_id = v_radar_id AND estado IN ('despachada', 'por_liquidar', 'liquidada', 'devuelta');

        IF v_entregas_existentes > 0 THEN
            RETURN jsonb_build_object(
                'success', FALSE,
                'data', NULL,
                'error', jsonb_build_object(
                    'code', 'REVERSO_BLOQUEADO_POR_ENTREGAS',
                    'message', 'No se puede reversar la carga al almacÃ©n porque ya existen entregas o despachos registrados en esta ruta.'
                )
            );
        END IF;
    END IF;

    IF p_resumen_productos IS NOT NULL THEN
        IF jsonb_typeof(p_resumen_productos) = 'array' THEN
            v_items_array := p_resumen_productos;
        ELSIF jsonb_typeof(p_resumen_productos) = 'object' AND p_resumen_productos ? 'resumen_productos' THEN
            v_items_array := p_resumen_productos->'resumen_productos';
        END IF;
    END IF;

    IF jsonb_array_length(v_items_array) > 0 THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(v_items_array) LOOP
            v_producto_id := (v_item->>'producto_id')::UUID;
            v_cantidad := COALESCE((v_item->>'cantidad_solicitada')::INT, 0);

            IF v_producto_id IS NOT NULL AND v_cantidad > 0 THEN
                INSERT INTO public.inventario_almacen (producto_id, stock_disponible, stock_comprometido, updated_at)
                VALUES (v_producto_id, v_cantidad, 0, NOW())
                ON CONFLICT (producto_id)
                DO UPDATE SET
                    stock_disponible = public.inventario_almacen.stock_disponible + v_cantidad,
                    updated_at = NOW();

                UPDATE public.inventario_movil
                SET cantidad_cargada = GREATEST(0, cantidad_cargada - v_cantidad),
                    updated_at = NOW()
                WHERE camion_id = p_camion_id AND producto_id = v_producto_id;

                v_total_productos_reversados := v_total_productos_reversados + 1;
                v_unidades_totales := v_unidades_totales + v_cantidad;
            END IF;
        END LOOP;
    ELSE
        FOR v_rec IN 
            SELECT producto_id, cantidad_cargada
            FROM public.inventario_movil
            WHERE camion_id = p_camion_id AND cantidad_cargada > 0
        LOOP
            INSERT INTO public.inventario_almacen (producto_id, stock_disponible, stock_comprometido, updated_at)
            VALUES (v_rec.producto_id, v_rec.cantidad_cargada, 0, NOW())
            ON CONFLICT (producto_id)
            DO UPDATE SET
                stock_disponible = public.inventario_almacen.stock_disponible + v_rec.cantidad_cargada,
                updated_at = NOW();

            UPDATE public.inventario_movil
            SET cantidad_cargada = 0,
                updated_at = NOW()
            WHERE camion_id = p_camion_id AND producto_id = v_rec.producto_id;

            v_total_productos_reversados := v_total_productos_reversados + 1;
            v_unidades_totales := v_unidades_totales + v_rec.cantidad_cargada;
        END LOOP;
    END IF;

    -- Transicionar Ã³rdenes de vuelta a 'aprobada' (sin updated_at)
    IF v_radar_id IS NOT NULL THEN
        UPDATE public.ordenes_distribucion
        SET estado = 'aprobada'
        WHERE radar_id = v_radar_id AND estado = 'en_transito';

        GET DIAGNOSTICS v_ordenes_reversadas = ROW_COUNT;
    ELSE
        UPDATE public.ordenes_distribucion
        SET estado = 'aprobada'
        WHERE camion_id = p_camion_id AND estado = 'en_transito';

        GET DIAGNOSTICS v_ordenes_reversadas = ROW_COUNT;
    END IF;

    IF v_radar_id IS NOT NULL THEN
        UPDATE public.detalle_distribucion dd
        SET cantidad_despachada = 0
        FROM public.ordenes_distribucion od
        WHERE dd.orden_id = od.id AND od.radar_id = v_radar_id;
    ELSE
        UPDATE public.detalle_distribucion dd
        SET cantidad_despachada = 0
        FROM public.ordenes_distribucion od
        WHERE dd.orden_id = od.id AND od.camion_id = p_camion_id;
    END IF;

    -- Revertir estado del camiÃ³n (sin updated_at)
    UPDATE public.camiones
    SET estado = 'asignado'
    WHERE id = p_camion_id;

    IF v_radar_id IS NOT NULL THEN
        UPDATE public.radars
        SET carga_inventario_movil = FALSE,
            updated_at = NOW()
        WHERE id = v_radar_id;
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Reverso de inventario mÃ³vil al almacÃ©n procesado exitosamente.',
        'data', jsonb_build_object(
            'camion_id', p_camion_id,
            'radar_id', v_radar_id,
            'carga_inventario_movil', FALSE,
            'total_productos_reversados', v_total_productos_reversados,
            'unidades_totales', v_unidades_totales,
            'ordenes_reversadas', v_ordenes_reversadas
        ),
        'error', NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'SQL_ERROR',
                'message', SQLERRM,
                'details', 'SQLSTATE: ' || SQLSTATE
            )
        );
END;
$$;
-- Migration: 20260915183000_fix_ordenes_distribucion_sin_updated_at.sql
-- Description: Re-crear funciones RPC elimina la referencia a updated_at en ordenes_distribucion

-- 1. RPC: solicita_cargar_inventario_movil_desde_almacen
CREATE OR REPLACE FUNCTION public.solicita_cargar_inventario_movil_desde_almacen(
    p_camion_id UUID,
    p_resumen_productos JSONB,
    p_radar_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_item JSONB;
    v_items_array JSONB;
    v_producto_id UUID;
    v_cantidad_solicitada INT;
    v_total_productos_cargados INT := 0;
    v_unidades_totales INT := 0;
    v_camion_existe BOOLEAN;
    v_ordenes_actualizadas INT := 0;
    v_radar_id UUID;
BEGIN
    IF p_camion_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID del camiÃ³n es requerido.'
            )
        );
    END IF;

    SELECT EXISTS(SELECT 1 FROM public.camiones WHERE id = p_camion_id) INTO v_camion_existe;
    IF NOT v_camion_existe THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'CAMION_INEXISTENTE',
                'message', 'El camiÃ³n especificado no existe.'
            )
        );
    END IF;

    v_radar_id := p_radar_id;
    IF v_radar_id IS NULL THEN
        SELECT radar_id INTO v_radar_id
        FROM public.ordenes_distribucion
        WHERE camion_id = p_camion_id AND radar_id IS NOT NULL
        ORDER BY created_at DESC
        LIMIT 1;
    END IF;

    IF jsonb_typeof(p_resumen_productos) = 'array' THEN
        v_items_array := p_resumen_productos;
    ELSIF jsonb_typeof(p_resumen_productos) = 'object' AND p_resumen_productos ? 'resumen_productos' THEN
        v_items_array := p_resumen_productos->'resumen_productos';
    ELSE
        v_items_array := '[]'::jsonb;
    END IF;

    IF v_items_array IS NULL OR jsonb_array_length(v_items_array) = 0 THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'DATOS_VACIOS',
                'message', 'El resumen de productos a cargar no contiene elementos vÃ¡lidos.'
            )
        );
    END IF;

    FOR v_item IN SELECT * FROM jsonb_array_elements(v_items_array) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad_solicitada := COALESCE((v_item->>'cantidad_solicitada')::INT, 0);

        IF v_producto_id IS NOT NULL AND v_cantidad_solicitada > 0 THEN
            UPDATE public.inventario_almacen
            SET stock_comprometido = GREATEST(0, stock_comprometido - v_cantidad_solicitada),
                stock_disponible = CASE 
                    WHEN stock_comprometido < v_cantidad_solicitada 
                    THEN GREATEST(0, stock_disponible - (v_cantidad_solicitada - stock_comprometido))
                    ELSE stock_disponible 
                END,
                updated_at = NOW()
            WHERE producto_id = v_producto_id;

            INSERT INTO public.inventario_movil (
                camion_id,
                producto_id,
                cantidad_cargada,
                cantidad_entregada,
                cantidad_devolucion,
                updated_at
            ) VALUES (
                p_camion_id,
                v_producto_id,
                v_cantidad_solicitada,
                0,
                0,
                NOW()
            )
            ON CONFLICT (camion_id, producto_id)
            DO UPDATE SET
                cantidad_cargada = public.inventario_movil.cantidad_cargada + v_cantidad_solicitada,
                updated_at = NOW();

            v_total_productos_cargados := v_total_productos_cargados + 1;
            v_unidades_totales := v_unidades_totales + v_cantidad_solicitada;
        END IF;
    END LOOP;

    UPDATE public.camiones
    SET estado = 'en_ruta'
    WHERE id = p_camion_id;

    IF v_radar_id IS NOT NULL THEN
        UPDATE public.ordenes_distribucion
        SET estado = 'en_transito'
        WHERE radar_id = v_radar_id AND estado = 'aprobada';
        
        GET DIAGNOSTICS v_ordenes_actualizadas = ROW_COUNT;
    ELSE
        UPDATE public.ordenes_distribucion
        SET estado = 'en_transito'
        WHERE camion_id = p_camion_id AND estado = 'aprobada';
        
        GET DIAGNOSTICS v_ordenes_actualizadas = ROW_COUNT;
    END IF;

    IF v_radar_id IS NOT NULL THEN
        UPDATE public.detalle_distribucion dd
        SET cantidad_despachada = dd.cantidad_solicitada
        FROM public.ordenes_distribucion od
        WHERE dd.orden_id = od.id
          AND od.radar_id = v_radar_id
          AND od.estado = 'en_transito';
    ELSE
        UPDATE public.detalle_distribucion dd
        SET cantidad_despachada = dd.cantidad_solicitada
        FROM public.ordenes_distribucion od
        WHERE dd.orden_id = od.id
          AND od.camion_id = p_camion_id
          AND od.estado = 'en_transito';
    END IF;

    IF v_radar_id IS NOT NULL THEN
        UPDATE public.radars
        SET carga_inventario_movil = TRUE,
            updated_at = NOW()
        WHERE id = v_radar_id;
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Carga a inventario mÃ³vil procesada exitosamente desde el almacÃ©n.',
        'data', jsonb_build_object(
            'camion_id', p_camion_id,
            'radar_id', v_radar_id,
            'carga_inventario_movil', TRUE,
            'total_productos_cargados', v_total_productos_cargados,
            'unidades_totales', v_unidades_totales,
            'ordenes_despachadas', v_ordenes_actualizadas
        ),
        'error', NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'SQL_ERROR',
                'message', SQLERRM,
                'details', 'SQLSTATE: ' || SQLSTATE
            )
        );
END;
$$;


-- 2. RPC: solicita_reversar_carga_inventario_movil_a_almacen
CREATE OR REPLACE FUNCTION public.solicita_reversar_carga_inventario_movil_a_almacen(
    p_camion_id UUID,
    p_resumen_productos JSONB DEFAULT NULL,
    p_radar_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_item JSONB;
    v_items_array JSONB := '[]'::jsonb;
    v_producto_id UUID;
    v_cantidad INT;
    v_total_productos_reversados INT := 0;
    v_unidades_totales INT := 0;
    v_camion_existe BOOLEAN;
    v_radar_id UUID;
    v_carga_inventario BOOLEAN;
    v_entregas_existentes INT := 0;
    v_ordenes_reversadas INT := 0;
    v_rec RECORD;
BEGIN
    IF p_camion_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID del camiÃ³n es requerido.'
            )
        );
    END IF;

    SELECT EXISTS(SELECT 1 FROM public.camiones WHERE id = p_camion_id) INTO v_camion_existe;
    IF NOT v_camion_existe THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'CAMION_INEXISTENTE',
                'message', 'El camiÃ³n especificado no existe.'
            )
        );
    END IF;

    v_radar_id := p_radar_id;
    IF v_radar_id IS NULL THEN
        SELECT radar_id INTO v_radar_id
        FROM public.ordenes_distribucion
        WHERE camion_id = p_camion_id AND radar_id IS NOT NULL
        ORDER BY created_at DESC
        LIMIT 1;
    END IF;

    IF v_radar_id IS NOT NULL THEN
        SELECT COALESCE(carga_inventario_movil, FALSE) INTO v_carga_inventario
        FROM public.radars
        WHERE id = v_radar_id;

        IF NOT v_carga_inventario THEN
            RETURN jsonb_build_object(
                'success', FALSE,
                'data', NULL,
                'error', jsonb_build_object(
                    'code', 'INVENTARIO_NO_CARGADO',
                    'message', 'El inventario mÃ³vil de este radar no ha sido cargado previamente o ya fue reversado.'
                )
            );
        END IF;

        SELECT COUNT(*) INTO v_entregas_existentes
        FROM public.ordenes_distribucion
        WHERE radar_id = v_radar_id AND estado IN ('despachada', 'por_liquidar', 'liquidada', 'devuelta');

        IF v_entregas_existentes > 0 THEN
            RETURN jsonb_build_object(
                'success', FALSE,
                'data', NULL,
                'error', jsonb_build_object(
                    'code', 'REVERSO_BLOQUEADO_POR_ENTREGAS',
                    'message', 'No se puede reversar la carga al almacÃ©n porque ya existen entregas o despachos registrados en esta ruta.'
                )
            );
        END IF;
    END IF;

    IF p_resumen_productos IS NOT NULL THEN
        IF jsonb_typeof(p_resumen_productos) = 'array' THEN
            v_items_array := p_resumen_productos;
        ELSIF jsonb_typeof(p_resumen_productos) = 'object' AND p_resumen_productos ? 'resumen_productos' THEN
            v_items_array := p_resumen_productos->'resumen_productos';
        END IF;
    END IF;

    IF jsonb_array_length(v_items_array) > 0 THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(v_items_array) LOOP
            v_producto_id := (v_item->>'producto_id')::UUID;
            v_cantidad := COALESCE((v_item->>'cantidad_solicitada')::INT, 0);

            IF v_producto_id IS NOT NULL AND v_cantidad > 0 THEN
                INSERT INTO public.inventario_almacen (producto_id, stock_disponible, stock_comprometido, updated_at)
                VALUES (v_producto_id, v_cantidad, 0, NOW())
                ON CONFLICT (producto_id)
                DO UPDATE SET
                    stock_disponible = public.inventario_almacen.stock_disponible + v_cantidad,
                    updated_at = NOW();

                UPDATE public.inventario_movil
                SET cantidad_cargada = GREATEST(0, cantidad_cargada - v_cantidad),
                    updated_at = NOW()
                WHERE camion_id = p_camion_id AND producto_id = v_producto_id;

                v_total_productos_reversados := v_total_productos_reversados + 1;
                v_unidades_totales := v_unidades_totales + v_cantidad;
            END IF;
        END LOOP;
    ELSE
        FOR v_rec IN 
            SELECT producto_id, cantidad_cargada
            FROM public.inventario_movil
            WHERE camion_id = p_camion_id AND cantidad_cargada > 0
        LOOP
            INSERT INTO public.inventario_almacen (producto_id, stock_disponible, stock_comprometido, updated_at)
            VALUES (v_rec.producto_id, v_rec.cantidad_cargada, 0, NOW())
            ON CONFLICT (producto_id)
            DO UPDATE SET
                stock_disponible = public.inventario_almacen.stock_disponible + v_rec.cantidad_cargada,
                updated_at = NOW();

            UPDATE public.inventario_movil
            SET cantidad_cargada = 0,
                updated_at = NOW()
            WHERE camion_id = p_camion_id AND producto_id = v_rec.producto_id;

            v_total_productos_reversados := v_total_productos_reversados + 1;
            v_unidades_totales := v_unidades_totales + v_rec.cantidad_cargada;
        END LOOP;
    END IF;

    IF v_radar_id IS NOT NULL THEN
        UPDATE public.ordenes_distribucion
        SET estado = 'aprobada'
        WHERE radar_id = v_radar_id AND estado = 'en_transito';

        GET DIAGNOSTICS v_ordenes_reversadas = ROW_COUNT;
    ELSE
        UPDATE public.ordenes_distribucion
        SET estado = 'aprobada'
        WHERE camion_id = p_camion_id AND estado = 'en_transito';

        GET DIAGNOSTICS v_ordenes_reversadas = ROW_COUNT;
    END IF;

    IF v_radar_id IS NOT NULL THEN
        UPDATE public.detalle_distribucion dd
        SET cantidad_despachada = 0
        FROM public.ordenes_distribucion od
        WHERE dd.orden_id = od.id AND od.radar_id = v_radar_id;
    ELSE
        UPDATE public.detalle_distribucion dd
        SET cantidad_despachada = 0
        FROM public.ordenes_distribucion od
        WHERE dd.orden_id = od.id AND od.camion_id = p_camion_id;
    END IF;

    UPDATE public.camiones
    SET estado = 'asignado'
    WHERE id = p_camion_id;

    IF v_radar_id IS NOT NULL THEN
        UPDATE public.radars
        SET carga_inventario_movil = FALSE,
            updated_at = NOW()
        WHERE id = v_radar_id;
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Reverso de inventario mÃ³vil al almacÃ©n procesado exitosamente.',
        'data', jsonb_build_object(
            'camion_id', p_camion_id,
            'radar_id', v_radar_id,
            'carga_inventario_movil', FALSE,
            'total_productos_reversados', v_total_productos_reversados,
            'unidades_totales', v_unidades_totales,
            'ordenes_reversadas', v_ordenes_reversadas
        ),
        'error', NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'SQL_ERROR',
                'message', SQLERRM,
                'details', 'SQLSTATE: ' || SQLSTATE
            )
        );
END;
$$;
-- Migration: 20260915190000_fix_radars_sin_updated_at.sql
-- Description: Eliminar la referencia inexistente a updated_at en la tabla public.radars para todas las funciones RPC relativas a radares

-- 1. RPC: solicita_cargar_inventario_movil_desde_almacen
CREATE OR REPLACE FUNCTION public.solicita_cargar_inventario_movil_desde_almacen(
    p_camion_id UUID,
    p_resumen_productos JSONB,
    p_radar_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_item JSONB;
    v_items_array JSONB;
    v_producto_id UUID;
    v_cantidad_solicitada INT;
    v_total_productos_cargados INT := 0;
    v_unidades_totales INT := 0;
    v_camion_existe BOOLEAN;
    v_ordenes_actualizadas INT := 0;
    v_radar_id UUID;
BEGIN
    IF p_camion_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID del camiÃ³n es requerido.'
            )
        );
    END IF;

    SELECT EXISTS(SELECT 1 FROM public.camiones WHERE id = p_camion_id) INTO v_camion_existe;
    IF NOT v_camion_existe THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'CAMION_INEXISTENTE',
                'message', 'El camiÃ³n especificado no existe.'
            )
        );
    END IF;

    v_radar_id := p_radar_id;
    IF v_radar_id IS NULL THEN
        SELECT radar_id INTO v_radar_id
        FROM public.ordenes_distribucion
        WHERE camion_id = p_camion_id AND radar_id IS NOT NULL
        ORDER BY created_at DESC
        LIMIT 1;
    END IF;

    IF jsonb_typeof(p_resumen_productos) = 'array' THEN
        v_items_array := p_resumen_productos;
    ELSIF jsonb_typeof(p_resumen_productos) = 'object' AND p_resumen_productos ? 'resumen_productos' THEN
        v_items_array := p_resumen_productos->'resumen_productos';
    ELSE
        v_items_array := '[]'::jsonb;
    END IF;

    IF v_items_array IS NULL OR jsonb_array_length(v_items_array) = 0 THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'DATOS_VACIOS',
                'message', 'El resumen de productos a cargar no contiene elementos vÃ¡lidos.'
            )
        );
    END IF;

    FOR v_item IN SELECT * FROM jsonb_array_elements(v_items_array) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad_solicitada := COALESCE((v_item->>'cantidad_solicitada')::INT, 0);

        IF v_producto_id IS NOT NULL AND v_cantidad_solicitada > 0 THEN
            UPDATE public.inventario_almacen
            SET stock_comprometido = GREATEST(0, stock_comprometido - v_cantidad_solicitada),
                stock_disponible = CASE 
                    WHEN stock_comprometido < v_cantidad_solicitada 
                    THEN GREATEST(0, stock_disponible - (v_cantidad_solicitada - stock_comprometido))
                    ELSE stock_disponible 
                END,
                updated_at = NOW()
            WHERE producto_id = v_producto_id;

            INSERT INTO public.inventario_movil (
                camion_id,
                producto_id,
                cantidad_cargada,
                cantidad_entregada,
                cantidad_devolucion,
                updated_at
            ) VALUES (
                p_camion_id,
                v_producto_id,
                v_cantidad_solicitada,
                0,
                0,
                NOW()
            )
            ON CONFLICT (camion_id, producto_id)
            DO UPDATE SET
                cantidad_cargada = public.inventario_movil.cantidad_cargada + v_cantidad_solicitada,
                updated_at = NOW();

            v_total_productos_cargados := v_total_productos_cargados + 1;
            v_unidades_totales := v_unidades_totales + v_cantidad_solicitada;
        END IF;
    END LOOP;

    UPDATE public.camiones
    SET estado = 'en_ruta'
    WHERE id = p_camion_id;

    IF v_radar_id IS NOT NULL THEN
        UPDATE public.ordenes_distribucion
        SET estado = 'en_transito'
        WHERE radar_id = v_radar_id AND estado = 'aprobada';
        
        GET DIAGNOSTICS v_ordenes_actualizadas = ROW_COUNT;
    ELSE
        UPDATE public.ordenes_distribucion
        SET estado = 'en_transito'
        WHERE camion_id = p_camion_id AND estado = 'aprobada';
        
        GET DIAGNOSTICS v_ordenes_actualizadas = ROW_COUNT;
    END IF;

    IF v_radar_id IS NOT NULL THEN
        UPDATE public.detalle_distribucion dd
        SET cantidad_despachada = dd.cantidad_solicitada
        FROM public.ordenes_distribucion od
        WHERE dd.orden_id = od.id
          AND od.radar_id = v_radar_id
          AND od.estado = 'en_transito';
    ELSE
        UPDATE public.detalle_distribucion dd
        SET cantidad_despachada = dd.cantidad_solicitada
        FROM public.ordenes_distribucion od
        WHERE dd.orden_id = od.id
          AND od.camion_id = p_camion_id
          AND od.estado = 'en_transito';
    END IF;

    -- Actualizar radars (sin updated_at)
    IF v_radar_id IS NOT NULL THEN
        UPDATE public.radars
        SET carga_inventario_movil = TRUE
        WHERE id = v_radar_id;
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Carga a inventario mÃ³vil procesada exitosamente desde el almacÃ©n.',
        'data', jsonb_build_object(
            'camion_id', p_camion_id,
            'radar_id', v_radar_id,
            'carga_inventario_movil', TRUE,
            'total_productos_cargados', v_total_productos_cargados,
            'unidades_totales', v_unidades_totales,
            'ordenes_despachadas', v_ordenes_actualizadas
        ),
        'error', NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'SQL_ERROR',
                'message', SQLERRM,
                'details', 'SQLSTATE: ' || SQLSTATE
            )
        );
END;
$$;


-- 2. RPC: solicita_reversar_carga_inventario_movil_a_almacen
CREATE OR REPLACE FUNCTION public.solicita_reversar_carga_inventario_movil_a_almacen(
    p_camion_id UUID,
    p_resumen_productos JSONB DEFAULT NULL,
    p_radar_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_item JSONB;
    v_items_array JSONB := '[]'::jsonb;
    v_producto_id UUID;
    v_cantidad INT;
    v_total_productos_reversados INT := 0;
    v_unidades_totales INT := 0;
    v_camion_existe BOOLEAN;
    v_radar_id UUID;
    v_carga_inventario BOOLEAN;
    v_entregas_existentes INT := 0;
    v_ordenes_reversadas INT := 0;
    v_rec RECORD;
BEGIN
    IF p_camion_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID del camiÃ³n es requerido.'
            )
        );
    END IF;

    SELECT EXISTS(SELECT 1 FROM public.camiones WHERE id = p_camion_id) INTO v_camion_existe;
    IF NOT v_camion_existe THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'CAMION_INEXISTENTE',
                'message', 'El camiÃ³n especificado no existe.'
            )
        );
    END IF;

    v_radar_id := p_radar_id;
    IF v_radar_id IS NULL THEN
        SELECT radar_id INTO v_radar_id
        FROM public.ordenes_distribucion
        WHERE camion_id = p_camion_id AND radar_id IS NOT NULL
        ORDER BY created_at DESC
        LIMIT 1;
    END IF;

    IF v_radar_id IS NOT NULL THEN
        SELECT COALESCE(carga_inventario_movil, FALSE) INTO v_carga_inventario
        FROM public.radars
        WHERE id = v_radar_id;

        IF NOT v_carga_inventario THEN
            RETURN jsonb_build_object(
                'success', FALSE,
                'data', NULL,
                'error', jsonb_build_object(
                    'code', 'INVENTARIO_NO_CARGADO',
                    'message', 'El inventario mÃ³vil de este radar no ha sido cargado previamente o ya fue reversado.'
                )
            );
        END IF;

        SELECT COUNT(*) INTO v_entregas_existentes
        FROM public.ordenes_distribucion
        WHERE radar_id = v_radar_id AND estado IN ('despachada', 'por_liquidar', 'liquidada', 'devuelta');

        IF v_entregas_existentes > 0 THEN
            RETURN jsonb_build_object(
                'success', FALSE,
                'data', NULL,
                'error', jsonb_build_object(
                    'code', 'REVERSO_BLOQUEADO_POR_ENTREGAS',
                    'message', 'No se puede reversar la carga al almacÃ©n porque ya existen entregas o despachos registrados en esta ruta.'
                )
            );
        END IF;
    END IF;

    IF p_resumen_productos IS NOT NULL THEN
        IF jsonb_typeof(p_resumen_productos) = 'array' THEN
            v_items_array := p_resumen_productos;
        ELSIF jsonb_typeof(p_resumen_productos) = 'object' AND p_resumen_productos ? 'resumen_productos' THEN
            v_items_array := p_resumen_productos->'resumen_productos';
        END IF;
    END IF;

    IF jsonb_array_length(v_items_array) > 0 THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(v_items_array) LOOP
            v_producto_id := (v_item->>'producto_id')::UUID;
            v_cantidad := COALESCE((v_item->>'cantidad_solicitada')::INT, 0);

            IF v_producto_id IS NOT NULL AND v_cantidad > 0 THEN
                INSERT INTO public.inventario_almacen (producto_id, stock_disponible, stock_comprometido, updated_at)
                VALUES (v_producto_id, v_cantidad, 0, NOW())
                ON CONFLICT (producto_id)
                DO UPDATE SET
                    stock_disponible = public.inventario_almacen.stock_disponible + v_cantidad,
                    updated_at = NOW();

                UPDATE public.inventario_movil
                SET cantidad_cargada = GREATEST(0, cantidad_cargada - v_cantidad),
                    updated_at = NOW()
                WHERE camion_id = p_camion_id AND producto_id = v_producto_id;

                v_total_productos_reversados := v_total_productos_reversados + 1;
                v_unidades_totales := v_unidades_totales + v_cantidad;
            END IF;
        END LOOP;
    ELSE
        FOR v_rec IN 
            SELECT producto_id, cantidad_cargada
            FROM public.inventario_movil
            WHERE camion_id = p_camion_id AND cantidad_cargada > 0
        LOOP
            INSERT INTO public.inventario_almacen (producto_id, stock_disponible, stock_comprometido, updated_at)
            VALUES (v_rec.producto_id, v_rec.cantidad_cargada, 0, NOW())
            ON CONFLICT (producto_id)
            DO UPDATE SET
                stock_disponible = public.inventario_almacen.stock_disponible + v_rec.cantidad_cargada,
                updated_at = NOW();

            UPDATE public.inventario_movil
            SET cantidad_cargada = 0,
                updated_at = NOW()
            WHERE camion_id = p_camion_id AND producto_id = v_rec.producto_id;

            v_total_productos_reversados := v_total_productos_reversados + 1;
            v_unidades_totales := v_unidades_totales + v_rec.cantidad_cargada;
        END LOOP;
    END IF;

    IF v_radar_id IS NOT NULL THEN
        UPDATE public.ordenes_distribucion
        SET estado = 'aprobada'
        WHERE radar_id = v_radar_id AND estado = 'en_transito';

        GET DIAGNOSTICS v_ordenes_reversadas = ROW_COUNT;
    ELSE
        UPDATE public.ordenes_distribucion
        SET estado = 'aprobada'
        WHERE camion_id = p_camion_id AND estado = 'en_transito';

        GET DIAGNOSTICS v_ordenes_reversadas = ROW_COUNT;
    END IF;

    IF v_radar_id IS NOT NULL THEN
        UPDATE public.detalle_distribucion dd
        SET cantidad_despachada = 0
        FROM public.ordenes_distribucion od
        WHERE dd.orden_id = od.id AND od.radar_id = v_radar_id;
    ELSE
        UPDATE public.detalle_distribucion dd
        SET cantidad_despachada = 0
        FROM public.ordenes_distribucion od
        WHERE dd.orden_id = od.id AND od.camion_id = p_camion_id;
    END IF;

    UPDATE public.camiones
    SET estado = 'asignado'
    WHERE id = p_camion_id;

    -- Actualizar radars (sin updated_at)
    IF v_radar_id IS NOT NULL THEN
        UPDATE public.radars
        SET carga_inventario_movil = FALSE
        WHERE id = v_radar_id;
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Reverso de inventario mÃ³vil al almacÃ©n procesado exitosamente.',
        'data', jsonb_build_object(
            'camion_id', p_camion_id,
            'radar_id', v_radar_id,
            'carga_inventario_movil', FALSE,
            'total_productos_reversados', v_total_productos_reversados,
            'unidades_totales', v_unidades_totales,
            'ordenes_reversadas', v_ordenes_reversadas
        ),
        'error', NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'SQL_ERROR',
                'message', SQLERRM,
                'details', 'SQLSTATE: ' || SQLSTATE
            )
        );
END;
$$;


-- 3. RPC: solicita_editar_o_sincronizar_radar
CREATE OR REPLACE FUNCTION public.solicita_editar_o_sincronizar_radar(
    p_radar_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_despachador_id UUID;
    v_fecha_despacho DATE;
    v_status_radar BOOLEAN;
    v_carga_inventario BOOLEAN;
    v_correlativo INT;
    v_tot_solicitada NUMERIC(10,0);
    v_tot_despachada NUMERIC(10,0);
    v_tot_retirados NUMERIC(10,0);
    v_total_ordenes INT;
    v_desvinculadas INT := 0;
    v_vinculadas INT := 0;
BEGIN
    IF p_radar_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID del radar es obligatorio.'
            )
        );
    END IF;

    SELECT despachador_id, fecha_despacho, correlativo,
           COALESCE(status_radar, FALSE), COALESCE(carga_inventario_movil, FALSE)
    INTO v_despachador_id, v_fecha_despacho, v_correlativo, v_status_radar, v_carga_inventario
    FROM public.radars
    WHERE id = p_radar_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'RADAR_INEXISTENTE',
                'message', 'El radar especificado no existe.'
            )
        );
    END IF;

    IF v_status_radar = TRUE THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'RADAR_APROBADO_BLOQUEADO',
                'message', 'El radar especificado ya ha sido aprobado por la Gerencia y no se puede modificar.'
            )
        );
    END IF;

    IF v_carga_inventario = TRUE THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'RADAR_INVENTARIO_CARGADO',
                'message', 'Para modificar el Radar debe reversar el inventario movil al almacÃ©n'
            )
        );
    END IF;

    UPDATE public.ordenes_distribucion
    SET radar_id = NULL
    WHERE radar_id = p_radar_id AND estado = 'aprobada';

    GET DIAGNOSTICS v_desvinculadas = ROW_COUNT;

    UPDATE public.ordenes_distribucion o
    SET radar_id = p_radar_id
    FROM public.clientes c
    WHERE o.cliente_id = c.id
      AND c.despachador_id = v_despachador_id
      AND o.fecha_despacho::date = v_fecha_despacho
      AND o.estado IN ('aprobada', 'en_transito', 'por_liquidar', 'liquidada', 'devuelta')
      AND (o.radar_id IS NULL OR o.radar_id = p_radar_id);

    GET DIAGNOSTICS v_vinculadas = ROW_COUNT;

    SELECT 
        COALESCE(SUM(d.cantidad_solicitada), 0),
        COALESCE(SUM(d.cantidad_despachada), 0),
        COALESCE(SUM(d.contenedores_retirados), 0),
        COUNT(DISTINCT o.id)
    INTO v_tot_solicitada, v_tot_despachada, v_tot_retirados, v_total_ordenes
    FROM public.ordenes_distribucion o
    JOIN public.detalle_distribucion d ON d.orden_id = o.id
    WHERE o.radar_id = p_radar_id;

    -- Actualizar radars (sin updated_at)
    UPDATE public.radars
    SET total_cantidad_solicitada = v_tot_solicitada,
        total_cantidad_despachada = v_tot_despachada,
        total_contenedores_retirados = v_tot_retirados
    WHERE id = p_radar_id;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Radar re-sincronizado y actualizado exitosamente.',
        'data', jsonb_build_object(
            'radar_id', p_radar_id,
            'correlativo', v_correlativo,
            'despachador_id', v_despachador_id,
            'fecha_despacho', v_fecha_despacho,
            'ordenes_desvinculadas', v_desvinculadas,
            'ordenes_vinculadas', v_total_ordenes,
            'total_cantidad_solicitada', v_tot_solicitada,
            'total_cantidad_despachada', v_tot_despachada,
            'total_contenedores_retirados', v_tot_retirados
        ),
        'error', NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'SQL_ERROR',
                'message', SQLERRM,
                'details', 'SQLSTATE: ' || SQLSTATE
            )
        );
END;
$$;
-- MigraciÃ³n: Actualizar asiento de envases/contenedores al despachar en registrar_despacho_cliente_radar y desacoplar de solicita_aprobar_radar

CREATE OR REPLACE FUNCTION public.registrar_despacho_cliente_radar(
    p_orden_id UUID,
    p_detalles_json JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_estado_orden TEXT;
    v_camion_id UUID;
    v_radar_id UUID;
    v_status_radar BOOLEAN;
    v_item JSONB;
    v_detalle_id UUID;
    v_cantidad_despachada INT;
    v_estado_entrega TEXT;
    v_motivo_rechazo TEXT;
    v_contenedores_retirados INT;
    v_contenedor_id UUID;
    v_producto_id UUID;
    v_cantidad_solicitada INT;
    v_devolucion INT;
    v_pendientes_count INT;
    v_total_despachado INT := 0;
    v_cliente_id UUID;
    v_despacho_permitido BOOLEAN;
    v_excepcion_gerencia BOOLEAN;
    v_nuevo_estado_orden TEXT;

    -- Variables para procesamiento y resumen de saldos de contenedores
    v_rec_prev RECORD;
    v_rec_cont RECORD;
    v_saldo_previo INT;
    v_saldo_nuevo INT;
    v_cant_entregada INT;
    v_cant_retirada INT;
    v_contenedores_resumen JSONB := '[]'::JSONB;
BEGIN
    IF p_orden_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El parÃ¡metro p_orden_id es obligatorio.'
            )
        );
    END IF;

    -- Obtener informaciÃ³n de la orden, cliente y radar asociado
    SELECT o.estado, o.camion_id, o.cliente_id, o.radar_id,
           COALESCE(c.excepcion_despacho_gerencia, FALSE),
           TRUE
    INTO v_estado_orden, v_camion_id, v_cliente_id, v_radar_id, v_excepcion_gerencia, v_despacho_permitido
    FROM public.ordenes_distribucion o
    JOIN public.clientes c ON o.cliente_id = c.id
    WHERE o.id = p_orden_id;

    -- Desactivar temporalmente bloqueos por crÃ©dito: permitir despacho siempre
    v_despacho_permitido := TRUE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'ORDEN_INEXISTENTE',
                'message', 'No se encontrÃ³ la orden especificada.'
            )
        );
    END IF;

    -- Validar si el radar asociado ya fue aprobado/cerrado por Gerencia (status_radar = TRUE)
    IF v_radar_id IS NOT NULL THEN
        SELECT COALESCE(status_radar, FALSE)
        INTO v_status_radar
        FROM public.radars
        WHERE id = v_radar_id;

        IF v_status_radar = TRUE THEN
            RETURN jsonb_build_object(
                'success', FALSE,
                'error', jsonb_build_object(
                    'code', 'RADAR_APROBADO_BLOQUEADO',
                    'message', 'El radar correspondiente ya ha sido aprobado por la Gerencia y se encuentra bloqueado para modificaciones.'
                )
            );
        END IF;
    END IF;

    IF NOT v_despacho_permitido THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'DESPACHO_BLOQUEADO_CREDITO',
                'message', 'No se puede despachar la orden: El cliente se encuentra bloqueado por polÃ­tica de crÃ©dito y no posee una excepciÃ³n gerencial activa.'
            )
        );
    END IF;

    IF v_estado_orden NOT IN ('en_transito', 'despachada', 'por_liquidar', 'devuelta') THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo se pueden registrar entregas de Ã³rdenes activas en ruta.'
            )
        );
    END IF;

    IF p_detalles_json IS NOT NULL AND jsonb_array_length(p_detalles_json) > 0 THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(p_detalles_json) LOOP
            v_detalle_id := (v_item->>'detalle_id')::UUID;
            v_cantidad_despachada := COALESCE((v_item->>'cantidad_despachada')::INT, 0);
            v_estado_entrega := v_item->>'estado_entrega';
            v_motivo_rechazo := v_item->>'motivo_rechazo';
            v_contenedores_retirados := COALESCE((v_item->>'contenedores_retirados')::INT, 0);
            v_contenedor_id := (v_item->>'contenedor_id')::UUID;

            SELECT producto_id, cantidad_solicitada INTO v_producto_id, v_cantidad_solicitada
            FROM public.detalle_distribucion
            WHERE id = v_detalle_id AND orden_id = p_orden_id;

            IF FOUND THEN
                v_devolucion := GREATEST(0, v_cantidad_solicitada - v_cantidad_despachada);

                IF v_camion_id IS NOT NULL THEN
                    UPDATE public.inventario_movil
                    SET cantidad_entregada = cantidad_entregada + v_cantidad_despachada,
                        cantidad_devolucion = cantidad_devolucion + v_devolucion,
                        updated_at = NOW()
                    WHERE camion_id = v_camion_id AND producto_id = v_producto_id;
                END IF;

                UPDATE public.detalle_distribucion
                SET cantidad_despachada = v_cantidad_despachada,
                    estado_entrega = COALESCE(v_estado_entrega, CASE WHEN v_cantidad_despachada > 0 THEN 'entregado' ELSE 'rechazado' END),
                    motivo_rechazo = v_motivo_rechazo,
                    contenedores_retirados = v_contenedores_retirados,
                    contenedor_id = v_contenedor_id
                WHERE id = v_detalle_id;
            END IF;
        END LOOP;
    END IF;

    -- =========================================================================
    -- PROCESAMIENTO Y ASIENTO DE SALDOS DE CONTENEDORES (AL MOMENTO DEL DESPACHO)
    -- =========================================================================
    -- 1. Reversar movimientos previos registrados para esta orden (para permitir re-ediciÃ³n idempotente)
    FOR v_rec_prev IN
        SELECT contenedor_id, cantidad_entregada, cantidad_retirada
        FROM public.movimientos_contenedores
        WHERE orden_id = p_orden_id
    LOOP
        UPDATE public.saldo_contenedores_clientes
        SET saldo_pendiente = GREATEST(0, saldo_pendiente - v_rec_prev.cantidad_entregada + v_rec_prev.cantidad_retirada),
            updated_at = NOW()
        WHERE cliente_id = v_cliente_id AND contenedor_id = v_rec_prev.contenedor_id;
    END LOOP;

    DELETE FROM public.movimientos_contenedores WHERE orden_id = p_orden_id;

    -- 2. Calcular entregas y retiros por tipo de contenedor asignado
    FOR v_rec_cont IN
        SELECT 
            COALESCE(d.contenedor_id, p.contenedor_id) AS contenedor_id,
            SUM(
                CASE 
                    WHEN COALESCE(d.contenedor_id, p.contenedor_id) IS NOT NULL AND COALESCE(d.cantidad_despachada, 0) > 0 THEN
                        CEIL(COALESCE(d.cantidad_despachada, 0)::numeric / GREATEST(COALESCE(p.unidades_por_contenedor, 1)::numeric, 1))
                    ELSE 0
                END
            )::INT AS total_entregados,
            SUM(COALESCE(d.contenedores_retirados, 0))::INT AS total_retirados
        FROM public.detalle_distribucion d
        LEFT JOIN public.productos p ON p.id = d.producto_id
        WHERE d.orden_id = p_orden_id
          AND COALESCE(d.contenedor_id, p.contenedor_id) IS NOT NULL
        GROUP BY COALESCE(d.contenedor_id, p.contenedor_id)
    LOOP
        v_cant_entregada := v_rec_cont.total_entregados;
        v_cant_retirada := v_rec_cont.total_retirados;

        IF v_cant_entregada > 0 OR v_cant_retirada > 0 THEN
            -- Obtener saldo anterior del cliente para este contenedor
            SELECT COALESCE(saldo_pendiente, 0)
            INTO v_saldo_previo
            FROM public.saldo_contenedores_clientes
            WHERE cliente_id = v_cliente_id AND contenedor_id = v_rec_cont.contenedor_id;

            IF NOT FOUND THEN
                v_saldo_previo := 0;
            END IF;

            v_saldo_nuevo := GREATEST(0, v_saldo_previo + v_cant_entregada - v_cant_retirada);

            -- Registrar movimiento individual
            INSERT INTO public.movimientos_contenedores (
                cliente_id, orden_id, contenedor_id, cantidad_entregada, cantidad_retirada, creado_por
            ) VALUES (
                v_cliente_id, p_orden_id, v_rec_cont.contenedor_id, v_cant_entregada, v_cant_retirada, auth.uid()
            );

            -- Upsert del saldo del cliente
            INSERT INTO public.saldo_contenedores_clientes (
                cliente_id, contenedor_id, saldo_pendiente, updated_at
            ) VALUES (
                v_cliente_id, v_rec_cont.contenedor_id, v_saldo_nuevo, NOW()
            )
            ON CONFLICT (cliente_id, contenedor_id)
            DO UPDATE SET
                saldo_pendiente = EXCLUDED.saldo_pendiente,
                updated_at = NOW();

            -- Construir resumen para el Frontend
            v_contenedores_resumen := v_contenedores_resumen || jsonb_build_object(
                'contenedor_id', v_rec_cont.contenedor_id,
                'saldo_anterior', v_saldo_previo,
                'cantidad_entregada', v_cant_entregada,
                'cantidad_retirada', v_cant_retirada,
                'saldo_actualizado', v_saldo_nuevo
            );
        END IF;
    END LOOP;

    -- Validar si quedan Ã­tems pendientes en la orden
    SELECT COUNT(*) INTO v_pendientes_count
    FROM public.detalle_distribucion
    WHERE orden_id = p_orden_id AND (estado_entrega IS NULL OR estado_entrega = 'pendiente');

    IF v_pendientes_count = 0 THEN
        SELECT COALESCE(SUM(cantidad_despachada), 0) INTO v_total_despachado
        FROM public.detalle_distribucion
        WHERE orden_id = p_orden_id;

        IF v_total_despachado = 0 THEN
            v_nuevo_estado_orden := 'devuelta';
        ELSE
            v_nuevo_estado_orden := 'por_liquidar';
        END IF;

        UPDATE public.ordenes_distribucion
        SET estado = v_nuevo_estado_orden
        WHERE id = p_orden_id;

        IF v_excepcion_gerencia THEN
            UPDATE public.clientes
            SET excepcion_despacho_gerencia = FALSE
            WHERE id = v_cliente_id;
        END IF;
    ELSE
        v_nuevo_estado_orden := v_estado_orden;
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Despacho registrado en radar exitosamente.',
        'data', jsonb_build_object(
            'orden_id', p_orden_id,
            'nuevo_estado', v_nuevo_estado_orden,
            'total_despachado', v_total_despachado,
            'contenedores_resumen', v_contenedores_resumen
        ),
        'error', NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', SQLSTATE,
                'message', SQLERRM
            )
        );
END;
$$;

GRANT EXECUTE ON FUNCTION public.registrar_despacho_cliente_radar TO authenticated, service_role;


CREATE OR REPLACE FUNCTION public.solicita_aprobar_radar(
    p_radar_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_despachador_id UUID;
    v_fecha_despacho DATE;
    v_status_radar BOOLEAN;
    v_rec RECORD;
    v_rec_entregados RECORD;
    v_rec_cliente RECORD;
    v_inv_res JSONB;
    v_ordenes_anuladas_count INT := 0;
    v_contenedores_retirados_procesados INT := 0;
    v_contenedores_entregados_procesados INT := 0;
    v_clientes_deshabilitados_count INT := 0;
    v_ordenes_por_liquidar_count INT := 0;
    v_contenedores_entregados INT := 0;
BEGIN
    IF p_radar_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID del radar es obligatorio.'
            )
        );
    END IF;

    -- Verificar existencia del radar y su estado actual
    SELECT despachador_id, fecha_despacho, COALESCE(status_radar, FALSE)
    INTO v_despachador_id, v_fecha_despacho, v_status_radar
    FROM public.radars
    WHERE id = p_radar_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'RADAR_INEXISTENTE',
                'message', 'El radar especificado no existe.'
            )
        );
    END IF;

    IF v_status_radar = TRUE THEN
        RETURN jsonb_build_object(
            'success', TRUE,
            'message', 'El radar ya se encuentra previamente aprobado.',
            'data', jsonb_build_object(
                'radar_id', p_radar_id,
                'status_radar', TRUE
            ),
            'error', NULL
        );
    END IF;

    -- 1. Marcar el radar como aprobado y cerrado (.T.) mediante status_radar = TRUE
    UPDATE public.radars
    SET status_radar = TRUE
    WHERE id = p_radar_id;

    -- Note: El cÃ¡lculo de contenedores entregados y retirados fue trasladado a registrar_despacho_cliente_radar
    -- para asentar los saldos al momento de confirmar el despacho.
    v_contenedores_entregados_procesados := 0;
    v_contenedores_retirados_procesados := 0;

    -- 2. Devuelve el inventario no despachado del camiÃ³n al almacÃ©n principal
    v_inv_res := public.retorna_inventario_no_despachado_para_almacen(p_radar_id);

    -- 3. Las Ã³rdenes en estado 'devuelta' pasan al estado final 'anulada'
    WITH ordenes_devueltas AS (
        UPDATE public.ordenes_distribucion
        SET estado = 'anulada'
        WHERE radar_id = p_radar_id AND estado = 'devuelta'
        RETURNING id
    )
    SELECT COUNT(*) INTO v_ordenes_anuladas_count FROM ordenes_devueltas;

    -- 4. PolÃ­ticas de crÃ©dito desactivadas temporalmente para mantener todos los clientes activos
    v_clientes_deshabilitados_count := 0;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Radar aprobado exitosamente. Saldos de contenedores actualizados al despachar, inventario restituido a almacÃ©n y Ã³rdenes devueltas anuladas.',
        'data', jsonb_build_object(
            'radar_id', p_radar_id,
            'status_radar', TRUE,
            'contenedores_entregados_procesados', v_contenedores_entregados_procesados,
            'contenedores_retirados_procesados', v_contenedores_retirados_procesados,
            'clientes_deshabilitados_credito', v_clientes_deshabilitados_count,
            'ordenes_anuladas', v_ordenes_anuladas_count,
            'inventario_reintegrado', COALESCE(v_inv_res->'data', '[]'::jsonb)
        ),
        'error', NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', SQLSTATE,
                'message', SQLERRM
            )
        );
END;
$$;

GRANT EXECUTE ON FUNCTION public.solicita_aprobar_radar TO authenticated, service_role;
-- Migración: Funciones RPC de Saldo e Historial de Movimientos de Contenedores por Cliente

-- 1. Función: retorna_saldo_contenedores_segun_clientes
CREATE OR REPLACE FUNCTION public.retorna_saldo_contenedores_segun_clientes(
    p_cliente_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSONB;
BEGIN
    IF p_cliente_id IS NULL THEN
        -- Retornar todos los clientes que poseen saldo_pendiente > 0
        SELECT jsonb_build_object(
            'success', TRUE,
            'data', COALESCE(jsonb_agg(
                jsonb_build_object(
                    'cliente_id', s.cliente_id,
                    'rif_nit', c.rif_nit,
                    'razon_social', c.razon_social,
                    'contenedor_id', s.contenedor_id,
                    'codigo_contenedor', t.codigo,
                    'nombre_contenedor', t.nombre,
                    'saldo_pendiente', s.saldo_pendiente,
                    'updated_at', s.updated_at
                ) ORDER BY c.razon_social, t.nombre
            ), '[]'::jsonb),
            'error', NULL
        ) INTO v_result
        FROM public.saldo_contenedores_clientes s
        JOIN public.clientes c ON s.cliente_id = c.id
        JOIN public.tipos_contenedores t ON s.contenedor_id = t.id
        WHERE s.saldo_pendiente > 0;

    ELSE
        -- Retornar el saldo del cliente especificado.
        -- Si posee registros en saldo_contenedores_clientes, retornarlos todos.
        IF EXISTS (
            SELECT 1 FROM public.saldo_contenedores_clientes WHERE cliente_id = p_cliente_id
        ) THEN
            SELECT jsonb_build_object(
                'success', TRUE,
                'data', COALESCE(jsonb_agg(
                    jsonb_build_object(
                        'cliente_id', s.cliente_id,
                        'rif_nit', c.rif_nit,
                        'razon_social', c.razon_social,
                        'contenedor_id', s.contenedor_id,
                        'codigo_contenedor', t.codigo,
                        'nombre_contenedor', t.nombre,
                        'saldo_pendiente', s.saldo_pendiente,
                        'updated_at', s.updated_at
                    ) ORDER BY t.nombre
                ), '[]'::jsonb),
                'error', NULL
            ) INTO v_result
            FROM public.saldo_contenedores_clientes s
            JOIN public.clientes c ON s.cliente_id = c.id
            JOIN public.tipos_contenedores t ON s.contenedor_id = t.id
            WHERE s.cliente_id = p_cliente_id;
        ELSE
            -- Verificar si el cliente existe
            IF NOT EXISTS (SELECT 1 FROM public.clientes WHERE id = p_cliente_id) THEN
                RETURN jsonb_build_object(
                    'success', FALSE,
                    'data', NULL,
                    'error', jsonb_build_object(
                        'code', 'CLIENTE_INEXISTENTE',
                        'message', 'El cliente especificado no existe.'
                    )
                );
            END IF;

            -- Retornar fila sintética con saldo_pendiente = 0 si el cliente no posee registros de saldo aún
            SELECT jsonb_build_object(
                'success', TRUE,
                'data', jsonb_build_array(
                    jsonb_build_object(
                        'cliente_id', c.id,
                        'rif_nit', c.rif_nit,
                        'razon_social', c.razon_social,
                        'contenedor_id', NULL,
                        'codigo_contenedor', NULL,
                        'nombre_contenedor', NULL,
                        'saldo_pendiente', 0,
                        'updated_at', c.created_at
                    )
                ),
                'error', NULL
            ) INTO v_result
            FROM public.clientes c
            WHERE c.id = p_cliente_id;
        END IF;
    END IF;

    RETURN v_result;
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', FALSE,
        'data', NULL,
        'error', jsonb_build_object(
            'code', 'SQL_ERROR',
            'message', SQLERRM
        )
    );
END;
$$;

-- 2. Función: retorna_movimientos_contenedores_segun_cliente_id_rango_fechas
CREATE OR REPLACE FUNCTION public.retorna_movimientos_contenedores_segun_cliente_id_rango_fechas(
    p_cliente_id UUID,
    p_fecha_inicial DATE DEFAULT NULL,
    p_fecha_limite DATE DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_cliente RECORD;
    v_saldo_anterior INT := 0;
    v_total_entregados INT := 0;
    v_total_retirados INT := 0;
    v_saldo_final INT := 0;
    v_movimientos JSONB := '[]'::jsonb;
    v_result JSONB;
BEGIN
    -- Validar parámetro obligatorio p_cliente_id
    IF p_cliente_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El parámetro p_cliente_id es obligatorio.'
            )
        );
    END IF;

    -- Validar que el cliente exista
    SELECT id, rif_nit, razon_social INTO v_cliente
    FROM public.clientes
    WHERE id = p_cliente_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'CLIENTE_INEXISTENTE',
                'message', 'El cliente especificado no existe.'
            )
        );
    END IF;

    -- Si las fechas no vienen especificadas, asignar valores por defecto (últimos 30 días)
    IF p_fecha_inicial IS NULL THEN
        p_fecha_inicial := CURRENT_DATE - INTERVAL '30 days';
    END IF;

    IF p_fecha_limite IS NULL THEN
        p_fecha_limite := CURRENT_DATE;
    END IF;

    -- 1. Calcular Saldo Anterior acumulado antes de p_fecha_inicial
    SELECT COALESCE(SUM(cantidad_entregada - cantidad_retirada), 0)
    INTO v_saldo_anterior
    FROM public.movimientos_contenedores
    WHERE cliente_id = p_cliente_id
      AND created_at::DATE < p_fecha_inicial;

    -- 2. Calcular Totales entregados y retirados dentro del rango
    SELECT 
        COALESCE(SUM(cantidad_entregada), 0),
        COALESCE(SUM(cantidad_retirada), 0)
    INTO v_total_entregados, v_total_retirados
    FROM public.movimientos_contenedores
    WHERE cliente_id = p_cliente_id
      AND created_at::DATE BETWEEN p_fecha_inicial AND p_fecha_limite;

    v_saldo_final := v_saldo_anterior + v_total_entregados - v_total_retirados;

    -- 3. Extraer Detalle de Movimientos en el Rango
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', m.id,
            'fecha_movimiento', m.created_at,
            'orden_id', m.orden_id,
            'correlativo_orden', o.correlativo,
            'factura_origen_numero', o.factura_origen_numero,
            'contenedor_id', m.contenedor_id,
            'codigo_contenedor', t.codigo,
            'nombre_contenedor', t.nombre,
            'cantidad_entregada', m.cantidad_entregada,
            'cantidad_retirada', m.cantidad_retirada
        ) ORDER BY m.created_at ASC
    ), '[]'::jsonb)
    INTO v_movimientos
    FROM public.movimientos_contenedores m
    LEFT JOIN public.ordenes_distribucion o ON m.orden_id = o.id
    LEFT JOIN public.tipos_contenedores t ON m.contenedor_id = t.id
    WHERE m.cliente_id = p_cliente_id
      AND m.created_at::DATE BETWEEN p_fecha_inicial AND p_fecha_limite;

    -- Construir respuesta JSON exitosa
    SELECT jsonb_build_object(
        'success', TRUE,
        'data', jsonb_build_object(
            'cliente_id', v_cliente.id,
            'rif_nit', v_cliente.rif_nit,
            'razon_social', v_cliente.razon_social,
            'fecha_inicial', p_fecha_inicial,
            'fecha_limite', p_fecha_limite,
            'saldo_anterior', v_saldo_anterior,
            'total_entregados', v_total_entregados,
            'total_retirados', v_total_retirados,
            'saldo_final', v_saldo_final,
            'movimientos', v_movimientos
        ),
        'error', NULL
    ) INTO v_result;

    RETURN v_result;
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', FALSE,
        'data', NULL,
        'error', jsonb_build_object(
            'code', 'SQL_ERROR',
            'message', SQLERRM
        )
    );
END;
$$;

-- Otorgar permisos de ejecución a los roles de Supabase
GRANT EXECUTE ON FUNCTION public.retorna_saldo_contenedores_segun_clientes(UUID) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.retorna_movimientos_contenedores_segun_cliente_id_rango_fechas(UUID, DATE, DATE) TO anon, authenticated, service_role;
-- MigraciÃ³n: MÃ³dulo de AutoVentas (Venta en Ruta / AlmacÃ©n MÃ³vil sin Radar)

-- 1. ModificaciÃ³n de esquema: Agregar columna es_autoventa a public.ordenes_distribucion
ALTER TABLE public.ordenes_distribucion 
ADD COLUMN IF NOT EXISTS es_autoventa BOOLEAN DEFAULT FALSE;

COMMENT ON COLUMN public.ordenes_distribucion.es_autoventa IS 'Indica si la orden fue generada como venta en caliente en ruta de AutoVentas (sin radar).';

-- 2. Stored Procedure: registrar_venta_en_ruta_autoventa
CREATE OR REPLACE FUNCTION public.registrar_venta_en_ruta_autoventa(
    p_vendedor_id UUID,
    p_cliente_id UUID,
    p_camion_id UUID,
    p_productos_json JSONB DEFAULT '[]'::jsonb,
    p_contenedores_json JSONB DEFAULT '[]'::jsonb,
    p_observaciones TEXT DEFAULT NULL,
    p_tasa_cambio NUMERIC DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_orden_id UUID;
    v_correlativo INT;
    v_factura_origen VARCHAR(30);
    v_tasa_cambio NUMERIC(14,4);
    
    v_vendedor_id UUID;
    v_despachador_id UUID;
    v_id_ruta UUID;
    v_camion_estado TEXT;
    
    v_peso_total NUMERIC(10,2) := 0.00;
    v_total_recaudar_usd NUMERIC(14,2) := 0.00;
    v_total_recaudar_bs NUMERIC(14,2) := 0.00;
    
    v_item JSONB;
    v_secuencia INT := 1;
    v_producto_id UUID;
    v_cantidad INT;
    v_stock_disponible_movil INT := 0;
    v_val_usd NUMERIC(14,2);
    v_val_usd_prod NUMERIC(14,2);
    v_subtotal_usd NUMERIC(14,2);
    v_peso_unitario NUMERIC(10,2);
    
    v_cont_item JSONB;
    v_cont_id UUID;
    v_cant_entregada INT;
    v_cant_retirada INT;
BEGIN
    -- Validaciones de parÃ¡metros
    IF p_vendedor_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del vendedor es requerido.');
    END IF;

    IF p_cliente_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del cliente es requerido.');
    END IF;

    IF p_camion_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del camiÃ³n es requerido.');
    END IF;

    IF p_productos_json IS NULL OR jsonb_array_length(p_productos_json) = 0 THEN
        RETURN jsonb_build_object('success', false, 'message', 'Debe incluir al menos un producto en la orden de AutoVenta.');
    END IF;

    -- Validar existencia del camiÃ³n y estado ('en_ruta' o 'asignado')
    SELECT estado INTO v_camion_estado
    FROM public.camiones
    WHERE id = p_camion_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'message', 'El camiÃ³n especificado no existe.');
    END IF;

    IF v_camion_estado NOT IN ('en_ruta', 'asignado') THEN
        RETURN jsonb_build_object('success', false, 'message', 'El camiÃ³n debe estar en ruta para registrar AutoVentas. Estado actual: ' || v_camion_estado);
    END IF;

    -- Obtener datos del cliente (vendedor, despachador, ruta)
    SELECT c.vendedor_id, c.despachador_id, c.id_ruta
    INTO v_vendedor_id, v_despachador_id, v_id_ruta
    FROM public.clientes c
    WHERE c.id = p_cliente_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'message', 'El cliente especificado no existe.');
    END IF;

    v_vendedor_id := COALESCE(p_vendedor_id, v_vendedor_id);

    -- Determinar tasa de cambio
    IF p_tasa_cambio IS NOT NULL AND p_tasa_cambio > 0 THEN
        v_tasa_cambio := p_tasa_cambio;
    ELSE
        SELECT tasa_cambio INTO v_tasa_cambio
        FROM public.tasa_cambio
        WHERE fecha_tasa = CURRENT_DATE;

        IF v_tasa_cambio IS NULL THEN
            SELECT tasa_cambio INTO v_tasa_cambio
            FROM public.tasa_cambio
            ORDER BY fecha_tasa DESC, created_at DESC
            LIMIT 1;
        END IF;

        IF v_tasa_cambio IS NULL THEN
            v_tasa_cambio := 1.0000;
        END IF;
    END IF;

    -- 1. Validar disponibilidad de stock en inventario_movil para cada producto
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;

        IF v_cantidad IS NULL OR v_cantidad <= 0 THEN
            RETURN jsonb_build_object('success', false, 'message', 'La cantidad solicitada para cada producto debe ser mayor a cero.');
        END IF;

        -- Consultar disponibilidad real en inventario_movil (cargado - entregado)
        SELECT (COALESCE(cantidad_cargada, 0) - COALESCE(cantidad_entregada, 0))
        INTO v_stock_disponible_movil
        FROM public.inventario_movil
        WHERE camion_id = p_camion_id AND producto_id = v_producto_id;

        IF v_stock_disponible_movil IS NULL THEN
            v_stock_disponible_movil := 0;
        END IF;

        IF v_stock_disponible_movil < v_cantidad THEN
            RETURN jsonb_build_object(
                'success', false,
                'message', 'Stock insuficiente en el camiÃ³n para el producto seleccionado. Disponible: ' || v_stock_disponible_movil || ', Solicitado: ' || v_cantidad
            );
        END IF;
    END LOOP;

    -- 2. Generar correlativo e ID de orden
    v_correlativo := nextval('public.ordenes_distribucion_correlativo_seq');
    v_factura_origen := 'AV-' || LPAD(v_correlativo::text, 6, '0');
    v_orden_id := gen_random_uuid();

    -- 3. Calcular montos y pesos
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;

        SELECT COALESCE(precio_lista1, 0.00), COALESCE(peso_unitario_kg, 0.00) 
        INTO v_val_usd_prod, v_peso_unitario
        FROM public.productos
        WHERE id = v_producto_id;

        v_val_usd := COALESCE((v_item->>'valor_unitario_usd')::NUMERIC, (v_item->>'precio_unitario')::NUMERIC, v_val_usd_prod);
        IF v_val_usd <= 0 THEN
            v_val_usd := v_val_usd_prod;
        END IF;

        v_subtotal_usd := ROUND(v_cantidad * v_val_usd, 2);
        v_peso_total := v_peso_total + (COALESCE(v_peso_unitario, 0.00) * v_cantidad);
        v_total_recaudar_usd := v_total_recaudar_usd + v_subtotal_usd;
    END LOOP;

    v_total_recaudar_bs := ROUND(v_total_recaudar_usd * v_tasa_cambio, 2);

    -- 4. Insertar la orden en ordenes_distribucion (estado = 'por_liquidar', es_autoventa = TRUE, radar_id = NULL)
    INSERT INTO public.ordenes_distribucion (
        id,
        correlativo,
        cliente_id,
        camion_id,
        vendedor_id,
        despachador_id,
        id_ruta,
        estado,
        es_autoventa,
        radar_id,
        fecha_despacho,
        peso_total_calculado,
        factura_origen_numero,
        creado_por,
        created_at,
        tasa_cambio,
        total_recaudar_usd,
        total_recaudar_bs
    ) VALUES (
        v_orden_id,
        v_correlativo,
        p_cliente_id,
        p_camion_id,
        v_vendedor_id,
        v_despachador_id,
        v_id_ruta,
        'por_liquidar',
        TRUE,
        NULL,
        NOW(),
        v_peso_total,
        v_factura_origen,
        p_vendedor_id,
        NOW(),
        v_tasa_cambio,
        v_total_recaudar_usd,
        v_total_recaudar_bs
    );

    -- 5. Insertar detalles y actualizar inventario_movil (cantidad_entregada += v_cantidad)
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;

        SELECT COALESCE(precio_lista1, 0.00) INTO v_val_usd_prod FROM public.productos WHERE id = v_producto_id;
        v_val_usd := COALESCE((v_item->>'valor_unitario_usd')::NUMERIC, (v_item->>'precio_unitario')::NUMERIC, v_val_usd_prod);
        IF v_val_usd <= 0 THEN v_val_usd := v_val_usd_prod; END IF;
        v_subtotal_usd := ROUND(v_cantidad * v_val_usd, 2);

        INSERT INTO public.detalle_distribucion (
            id,
            orden_id,
            producto_id,
            cantidad_solicitada,
            cantidad_despachada,
            valor_unitario_usd,
            subtotal_recaudar_usd,
            secuencia_entrega,
            estado_entrega
        ) VALUES (
            gen_random_uuid(),
            v_orden_id,
            v_producto_id,
            v_cantidad,
            v_cantidad,
            v_val_usd,
            v_subtotal_usd,
            v_secuencia,
            'entregado'
        );

        v_secuencia := v_secuencia + 1;

        -- Incrementar cantidad_entregada en el inventario mÃ³vil del camiÃ³n
        UPDATE public.inventario_movil
        SET cantidad_entregada = cantidad_entregada + v_cantidad,
            updated_at = NOW()
        WHERE camion_id = p_camion_id AND producto_id = v_producto_id;
    END LOOP;

    -- 6. Procesar movimiento de envases / contenedores si fueron suministrados
    IF p_contenedores_json IS NOT NULL AND jsonb_array_length(p_contenedores_json) > 0 THEN
        FOR v_cont_item IN SELECT * FROM jsonb_array_elements(p_contenedores_json) LOOP
            v_cont_id := (v_cont_item->>'contenedor_id')::UUID;
            v_cant_entregada := COALESCE((v_cont_item->>'cantidad_entregada')::INT, 0);
            v_cant_retirada := COALESCE((v_cont_item->>'cantidad_retirada')::INT, 0);

            IF v_cont_id IS NOT NULL AND (v_cant_entregada > 0 OR v_cant_retirada > 0) THEN
                -- Registro histÃ³rico del movimiento
                INSERT INTO public.movimientos_contenedores (
                    cliente_id,
                    orden_id,
                    contenedor_id,
                    cantidad_entregada,
                    cantidad_retirada,
                    created_at
                ) VALUES (
                    p_cliente_id,
                    v_orden_id,
                    v_cont_id,
                    v_cant_entregada,
                    v_cant_retirada,
                    NOW()
                );

                -- ActualizaciÃ³n del saldo acumulado del cliente
                INSERT INTO public.saldo_contenedores_clientes (
                    cliente_id,
                    contenedor_id,
                    saldo_pendiente,
                    updated_at
                ) VALUES (
                    p_cliente_id,
                    v_cont_id,
                    GREATEST(0, v_cant_entregada - v_cant_retirada),
                    NOW()
                )
                ON CONFLICT (cliente_id, contenedor_id)
                DO UPDATE SET
                    saldo_pendiente = GREATEST(0, public.saldo_contenedores_clientes.saldo_pendiente + v_cant_entregada - v_cant_retirada),
                    updated_at = NOW();
            END IF;
        END LOOP;
    END IF;

    -- 7. Respuesta exitosa
    RETURN jsonb_build_object(
        'success', true,
        'message', 'Venta en ruta (AutoVenta) registrada exitosamente.',
        'data', jsonb_build_object(
            'orden_id', v_orden_id,
            'correlativo', v_correlativo,
            'factura_origen_numero', v_factura_origen,
            'cliente_id', p_cliente_id,
            'camion_id', p_camion_id,
            'estado', 'por_liquidar',
            'es_autoventa', true,
            'total_recaudar_usd', v_total_recaudar_usd,
            'total_recaudar_bs', v_total_recaudar_bs,
            'tasa_cambio', v_tasa_cambio
        ),
        'error', NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'SQL_ERROR',
                'message', SQLERRM,
                'details', 'SQLSTATE: ' || SQLSTATE
            )
        );
END;
$$;


-- 3. Stored Procedure: retorna_resumen_autoventas_jornada
CREATE OR REPLACE FUNCTION public.retorna_resumen_autoventas_jornada(
    p_camion_id UUID,
    p_fecha DATE DEFAULT CURRENT_DATE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_inventario_movil JSONB;
    v_ventas_jornada JSONB;
    v_total_ordenes INT := 0;
    v_total_facturado_usd NUMERIC(14,2) := 0.00;
    v_total_facturado_bs NUMERIC(14,2) := 0.00;
BEGIN
    IF p_camion_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del camiÃ³n es requerido.');
    END IF;

    -- Consultar estado del inventario mÃ³vil cargado vs entregado
    SELECT jsonb_agg(
        jsonb_build_object(
            'producto_id', p.id,
            'codigo', p.codigo,
            'nombre', p.nombre,
            'cantidad_cargada', COALESCE(im.cantidad_cargada, 0),
            'cantidad_entregada', COALESCE(im.cantidad_entregada, 0),
            'cantidad_disponible', GREATEST(0, COALESCE(im.cantidad_cargada, 0) - COALESCE(im.cantidad_entregada, 0))
        ) ORDER BY p.nombre ASC
    ) INTO v_inventario_movil
    FROM public.inventario_movil im
    JOIN public.productos p ON im.producto_id = p.id
    WHERE im.camion_id = p_camion_id;

    -- Consultar resumen de ventas registradas hoy en AutoVentas
    SELECT 
        COUNT(*)::INT,
        COALESCE(SUM(total_recaudar_usd), 0.00),
        COALESCE(SUM(total_recaudar_bs), 0.00)
    INTO v_total_ordenes, v_total_facturado_usd, v_total_facturado_bs
    FROM public.ordenes_distribucion
    WHERE camion_id = p_camion_id
      AND es_autoventa = TRUE
      AND DATE(created_at) = COALESCE(p_fecha, CURRENT_DATE);

    SELECT jsonb_agg(
        jsonb_build_object(
            'orden_id', od.id,
            'correlativo', od.correlativo,
            'factura_origen_numero', od.factura_origen_numero,
            'cliente_nombre', c.nombre_negocio,
            'estado', od.estado,
            'total_recaudar_usd', od.total_recaudar_usd,
            'total_recaudar_bs', od.total_recaudar_bs,
            'created_at', od.created_at
        ) ORDER BY od.created_at DESC
    ) INTO v_ventas_jornada
    FROM public.ordenes_distribucion od
    JOIN public.clientes c ON od.cliente_id = c.id
    WHERE od.camion_id = p_camion_id
      AND od.es_autoventa = TRUE
      AND DATE(od.created_at) = COALESCE(p_fecha, CURRENT_DATE);

    RETURN jsonb_build_object(
        'success', true,
        'data', jsonb_build_object(
            'camion_id', p_camion_id,
            'fecha', COALESCE(p_fecha, CURRENT_DATE),
            'total_ordenes_autoventa', v_total_ordenes,
            'total_facturado_usd', v_total_facturado_usd,
            'total_facturado_bs', v_total_facturado_bs,
            'inventario_movil', COALESCE(v_inventario_movil, '[]'::jsonb),
            'ventas', COALESCE(v_ventas_jornada, '[]'::jsonb)
        ),
        'error', NULL
    );
END;
$$;


-- 4. ProtecciÃ³n y Filtrado: Actualizar crear_o_obtener_radar para IGNORAR ordenes de AutoVentas
CREATE OR REPLACE FUNCTION public.crear_o_obtener_radar(
    p_despachador_id UUID DEFAULT NULL,
    p_fecha_despacho DATE DEFAULT CURRENT_DATE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_despachador_id UUID;
    v_radar_id UUID;
    v_correlativo INT;
    v_status_radar BOOLEAN;
    v_tot_solicitada NUMERIC(10,0);
    v_tot_despachada NUMERIC(10,0);
    v_tot_retirados NUMERIC(10,0);
    v_total_ordenes INT;
    v_resultado JSONB;
BEGIN
    v_despachador_id := COALESCE(p_despachador_id, auth.uid());

    IF v_despachador_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_REQUERIDO',
                'message', 'Se requiere especificar un despachador_id o estar autenticado.'
            )
        );
    END IF;

    -- Verificar si existe un radar para este despachador y fecha
    SELECT id, correlativo, status_radar
    INTO v_radar_id, v_correlativo, v_status_radar
    FROM public.radars
    WHERE despachador_id = v_despachador_id
      AND fecha_despacho = p_fecha_despacho
    ORDER BY created_at DESC
    LIMIT 1;

    -- Si no existe, crearlo
    IF v_radar_id IS NULL THEN
        INSERT INTO public.radars (despachador_id, fecha_despacho, status_radar)
        VALUES (v_despachador_id, p_fecha_despacho, FALSE)
        RETURNING id, correlativo, status_radar INTO v_radar_id, v_correlativo, v_status_radar;
    END IF;

    -- EXCLUIR VENTA EN RUTA (es_autoventa = TRUE): No asociar Ã³rdenes de AutoVentas al Radar
    UPDATE public.ordenes_distribucion o
    SET radar_id = v_radar_id
    FROM public.clientes c
    WHERE o.cliente_id = c.id
      AND c.despachador_id = v_despachador_id
      AND o.fecha_despacho::date = p_fecha_despacho
      AND o.estado IN ('aprobada', 'en_transito', 'por_liquidar', 'liquidada', 'devuelta')
      AND (o.radar_id IS NULL OR o.radar_id = v_radar_id)
      AND COALESCE(o.es_autoventa, FALSE) = FALSE;

    -- Recalcular totales del radar
    SELECT 
        COALESCE(SUM(d.cantidad_solicitada), 0),
        COALESCE(SUM(d.cantidad_despachada), 0),
        COALESCE(SUM(d.contenedores_retirados), 0),
        COUNT(DISTINCT o.id)
    INTO v_tot_solicitada, v_tot_despachada, v_tot_retirados, v_total_ordenes
    FROM public.ordenes_distribucion o
    JOIN public.detalle_distribucion d ON d.orden_id = o.id
    WHERE o.radar_id = v_radar_id;

    UPDATE public.radars
    SET total_cantidad_solicitada = v_tot_solicitada,
        total_cantidad_despachada = v_tot_despachada,
        total_contenedores_retirados = v_tot_retirados
    WHERE id = v_radar_id;

    SELECT jsonb_build_object(
        'success', TRUE,
        'message', 'Radar obtenido/creado exitosamente.',
        'data', jsonb_build_object(
            'id', v_radar_id,
            'correlativo', v_correlativo,
            'despachador_id', v_despachador_id,
            'fecha_despacho', p_fecha_despacho,
            'status_radar', v_status_radar,
            'total_cantidad_solicitada', v_tot_solicitada,
            'total_cantidad_despachada', v_tot_despachada,
            'total_contenedores_retirados', v_tot_retirados,
            'total_ordenes', v_total_ordenes
        )
    ) INTO v_resultado;

    RETURN v_resultado;
END;
$$;


-- 5. ProtecciÃ³n y Filtrado: Actualizar solicita_editar_o_sincronizar_radar para IGNORAR ordenes de AutoVentas
CREATE OR REPLACE FUNCTION public.solicita_editar_o_sincronizar_radar(
    p_radar_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_despachador_id UUID;
    v_fecha_despacho DATE;
    v_status_radar BOOLEAN;
    v_carga_inventario BOOLEAN;
    v_correlativo INT;
    v_tot_solicitada NUMERIC(10,0);
    v_tot_despachada NUMERIC(10,0);
    v_tot_retirados NUMERIC(10,0);
    v_total_ordenes INT;
    v_desvinculadas INT := 0;
    v_vinculadas INT := 0;
BEGIN
    IF p_radar_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID del radar es obligatorio.'
            )
        );
    END IF;

    SELECT despachador_id, fecha_despacho, correlativo,
           COALESCE(status_radar, FALSE), COALESCE(carga_inventario_movil, FALSE)
    INTO v_despachador_id, v_fecha_despacho, v_correlativo, v_status_radar, v_carga_inventario
    FROM public.radars
    WHERE id = p_radar_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'RADAR_INEXISTENTE',
                'message', 'El radar especificado no existe.'
            )
        );
    END IF;

    IF v_status_radar = TRUE THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'RADAR_APROBADO_BLOQUEADO',
                'message', 'El radar especificado ya ha sido aprobado por la Gerencia y no se puede modificar.'
            )
        );
    END IF;

    IF v_carga_inventario = TRUE THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'RADAR_INVENTARIO_CARGADO',
                'message', 'Para modificar el Radar debe reversar el inventario movil al almacÃ©n'
            )
        );
    END IF;

    -- Desvincular Ãºnicamente Ã³rdenes estÃ¡ndar en estado 'aprobada'
    UPDATE public.ordenes_distribucion
    SET radar_id = NULL
    WHERE radar_id = p_radar_id AND estado = 'aprobada';

    GET DIAGNOSTICS v_desvinculadas = ROW_COUNT;

    -- EXCLUIR VENTA EN RUTA (es_autoventa = TRUE): Volver a vincular Ãºnicamente Ã³rdenes estÃ¡ndar
    UPDATE public.ordenes_distribucion o
    SET radar_id = p_radar_id
    FROM public.clientes c
    WHERE o.cliente_id = c.id
      AND c.despachador_id = v_despachador_id
      AND o.fecha_despacho::date = v_fecha_despacho
      AND o.estado IN ('aprobada', 'en_transito', 'por_liquidar', 'liquidada', 'devuelta')
      AND (o.radar_id IS NULL OR o.radar_id = p_radar_id)
      AND COALESCE(o.es_autoventa, FALSE) = FALSE;

    GET DIAGNOSTICS v_vinculadas = ROW_COUNT;

    -- Recalcular totales consolidado del radar
    SELECT 
        COALESCE(SUM(d.cantidad_solicitada), 0),
        COALESCE(SUM(d.cantidad_despachada), 0),
        COALESCE(SUM(d.contenedores_retirados), 0),
        COUNT(DISTINCT o.id)
    INTO v_tot_solicitada, v_tot_despachada, v_tot_retirados, v_total_ordenes
    FROM public.ordenes_distribucion o
    JOIN public.detalle_distribucion d ON d.orden_id = o.id
    WHERE o.radar_id = p_radar_id;

    UPDATE public.radars
    SET total_cantidad_solicitada = v_tot_solicitada,
        total_cantidad_despachada = v_tot_despachada,
        total_contenedores_retirados = v_tot_retirados
    WHERE id = p_radar_id;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Radar re-sincronizado y actualizado exitosamente.',
        'data', jsonb_build_object(
            'radar_id', p_radar_id,
            'correlativo', v_correlativo,
            'despachador_id', v_despachador_id,
            'fecha_despacho', v_fecha_despacho,
            'ordenes_desvinculadas', v_desvinculadas,
            'ordenes_vinculadas', v_total_ordenes,
            'total_cantidad_solicitada', v_tot_solicitada,
            'total_cantidad_despachada', v_tot_despachada,
            'total_contenedores_retirados', v_tot_retirados
        ),
        'error', NULL
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.registrar_venta_en_ruta_autoventa(UUID, UUID, UUID, JSONB, JSONB, TEXT, NUMERIC) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.retorna_resumen_autoventas_jornada(UUID, DATE) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.crear_o_obtener_radar(UUID, DATE) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.solicita_editar_o_sincronizar_radar(UUID) TO authenticated, service_role;
-- MigraciÃ³n: MÃ³dulo de Reporte de Formas de Pago por Rango de Fechas (RendiciÃ³n de Cuentas)

-- 1. Agregar columna es_bancario a la tabla public.fpagos
ALTER TABLE public.fpagos 
ADD COLUMN IF NOT EXISTS es_bancario BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN public.fpagos.es_bancario IS 'Indica si la forma de pago corresponde a una transacciÃ³n bancaria/electrÃ³nica (Pago MÃ³vil, Transferencia, Zelle, Binance, etc.)';

-- 2. Marcar como bancarias/electrÃ³nicas las formas de pago correspondientes
UPDATE public.fpagos
SET es_bancario = TRUE
WHERE fpago_id IN (
    '1a5b84c8-47bc-4ee0-880c-7833215be11b', -- Pago movil
    '2b6c95d9-58cd-4ff1-991d-8944326cf22c', -- Transferencia
    '5e9fc80c-8bef-4224-cc4f-bc77659f255f', -- ZELLE
    '6fa0d91d-9c00-4335-dd5f-cd88760a366a'  -- BINANCE
) OR fpago_concepto ILIKE '%pago%movil%'
  OR fpago_concepto ILIKE '%transferencia%'
  OR fpago_concepto ILIKE '%zelle%'
  OR fpago_concepto ILIKE '%binance%';

-- 3. Stored Procedure: reporte_formas_pago_rendicion
CREATE OR REPLACE FUNCTION public.reporte_formas_pago_rendicion(
    p_fecha_desde DATE DEFAULT NULL,
    p_fecha_hasta DATE DEFAULT NULL,
    p_solo_bancarios BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_fecha_desde DATE;
    v_fecha_hasta DATE;
    v_movimientos JSONB;
    v_total_registros INT := 0;
    v_monto_total_bs NUMERIC(14,2) := 0.00;
    v_monto_total_usd NUMERIC(14,2) := 0.00;
BEGIN
    -- Determinar rango de fechas por defecto (mes actual si no se proporciona)
    v_fecha_desde := COALESCE(p_fecha_desde, date_trunc('month', CURRENT_DATE)::date);
    v_fecha_hasta := COALESCE(p_fecha_hasta, CURRENT_DATE);

    -- Consultar movimientos de detalle_rendicion_fpagos
    SELECT 
        COUNT(*)::INT,
        COALESCE(SUM(dfp.monto_bs), 0.00),
        COALESCE(SUM(dfp.monto_usd), 0.00)
    INTO v_total_registros, v_monto_total_bs, v_monto_total_usd
    FROM public.detalle_rendicion_fpagos dfp
    JOIN public.rendiciones_cuentas rc ON dfp.rendicion_id = rc.id
    JOIN public.fpagos fp ON dfp.fpago_id = fp.fpago_id
    WHERE rc.fecha_rendicion::date >= v_fecha_desde
      AND rc.fecha_rendicion::date <= v_fecha_hasta
      AND rc.estado = 'aprobada'
      AND (p_solo_bancarios = FALSE OR fp.es_bancario = TRUE);

    -- Construir la lista detallada de movimientos
    SELECT jsonb_agg(
        jsonb_build_object(
            'rendicion_id', rc.id,
            'fecha_rendicion', rc.fecha_rendicion,
            'tasa_cambio', rc.tasa_cambio,
            'cliente_id', c.id,
            'cliente_nombre', c.nombre_negocio,
            'cliente_rif', c.rif,
            'fpago_id', fp.fpago_id,
            'fpago_concepto', fp.fpago_concepto,
            'es_bancario', fp.es_bancario,
            'referencia_bancaria', dfp.referencia_bancaria,
            'cuenta_bancaria', dfp.cuenta_bancaria,
            'capture_url', dfp.capture_url,
            'monto_bs', COALESCE(dfp.monto_bs, (dfp.monto_usd * rc.tasa_cambio)),
            'monto_usd', dfp.monto_usd
        ) ORDER BY rc.fecha_rendicion DESC, dfp.created_at DESC
    ) INTO v_movimientos
    FROM public.detalle_rendicion_fpagos dfp
    JOIN public.rendiciones_cuentas rc ON dfp.rendicion_id = rc.id
    JOIN public.fpagos fp ON dfp.fpago_id = fp.fpago_id
    JOIN public.clientes c ON rc.cliente_id = c.id
    WHERE rc.fecha_rendicion::date >= v_fecha_desde
      AND rc.fecha_rendicion::date <= v_fecha_hasta
      AND rc.estado = 'aprobada'
      AND (p_solo_bancarios = FALSE OR fp.es_bancario = TRUE);

    RETURN jsonb_build_object(
        'success', true,
        'data', jsonb_build_object(
            'fecha_desde', v_fecha_desde,
            'fecha_hasta', v_fecha_hasta,
            'solo_bancarios', p_solo_bancarios,
            'total_registros', v_total_registros,
            'monto_total_bs', v_monto_total_bs,
            'monto_total_usd', v_monto_total_usd,
            'movimientos', COALESCE(v_movimientos, '[]'::jsonb)
        ),
        'error', NULL
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'SQL_ERROR',
                'message', SQLERRM,
                'details', 'SQLSTATE: ' || SQLSTATE
            )
        );
END;
$$;

GRANT EXECUTE ON FUNCTION public.reporte_formas_pago_rendicion(DATE, DATE, BOOLEAN) TO authenticated, service_role;
-- Migration: Rendiciones de cuentas se registran como aprobadas por defecto y liquidan automÃ¡ticamente las Ã³rdenes asociadas

CREATE OR REPLACE FUNCTION public.registrar_rendicion_cuentas(
    p_cliente_id UUID,
    p_observaciones TEXT,
    p_creado_por UUID,
    p_ordenes JSONB,  -- Array: [{"orden_id": "...", "monto_recaudado": 150.00, "monto_recaudado_bs": 7500.00}]
    p_pagos JSONB,     -- Array: [{"fpago_id": "...", "monto": 200.00, "monto_bs": 10000.00, "monto_usd": 200.00, "cuenta_bancaria_id": "...", "referencia_bancaria": "...", "cuenta_bancaria": "...", "capture_url": "..."}]
    p_tasa_cambio NUMERIC DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_rendicion_id UUID;
    v_tasa_cambio NUMERIC(10, 4);
    v_total_ordenes NUMERIC(12, 2) := 0.00;
    v_total_ordenes_bs NUMERIC(12, 2) := 0.00;
    v_total_pagos NUMERIC(12, 2) := 0.00;
    v_total_pagos_bs NUMERIC(12, 2) := 0.00;
    v_total_efectivo NUMERIC(12, 2) := 0.00;
    v_total_transferencias NUMERIC(12, 2) := 0.00;
    v_saldo_favor_usado NUMERIC(12, 2) := 0.00;
    v_cliente_saldo_favor NUMERIC(12, 2) := 0.00;
    v_item RECORD;
    v_pago RECORD;
    v_exceso NUMERIC(12, 2) := 0.00;
    v_exceso_bs NUMERIC(12, 2) := 0.00;
    v_fpago_concepto TEXT;
    v_fpago_info BOOLEAN;
    v_item_usd NUMERIC(12, 2);
    v_item_bs NUMERIC(12, 2);
    v_rec_usd NUMERIC(12, 2);
    v_rec_bs NUMERIC(12, 2);
BEGIN
    -- 1. Validaciones bÃ¡sicas
    IF p_cliente_id IS NULL OR p_creado_por IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID de cliente y el usuario creador son requeridos.',
                'details', NULL
            )
        );
    END IF;

    -- Determinar tasa de cambio
    IF p_tasa_cambio IS NOT NULL AND p_tasa_cambio > 0 THEN
        v_tasa_cambio := p_tasa_cambio;
    ELSE
        SELECT COALESCE(tasa_cambio, 1.0000) INTO v_tasa_cambio
        FROM public.tasa_cambio
        ORDER BY fecha_tasa DESC, created_at DESC
        LIMIT 1;

        IF v_tasa_cambio IS NULL THEN
            v_tasa_cambio := 1.0000;
        END IF;
    END IF;

    -- Validar que el cliente exista y obtener saldo a favor actual
    SELECT COALESCE(saldo_favor, 0.00) 
    INTO v_cliente_saldo_favor 
    FROM public.clientes 
    WHERE id = p_cliente_id;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'CLIENTE_INEXISTENTE',
                'message', 'El cliente especificado no existe.',
                'details', NULL
            )
        );
    END IF;

    -- Validar que las listas hijas tengan al menos un elemento
    IF p_ordenes IS NULL OR jsonb_array_length(p_ordenes) = 0 THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'DETALLE_REQUISITO_FALTANTE',
                'message', 'Debe registrar al menos una orden en el detalle de la rendiciÃ³n.',
                'details', NULL
            )
        );
    END IF;

    IF p_pagos IS NULL OR jsonb_array_length(p_pagos) = 0 THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'DETALLE_REQUISITO_FALTANTE',
                'message', 'Debe registrar al menos una forma de pago en la rendiciÃ³n.',
                'details', NULL
            )
        );
    END IF;

    -- 2. Calcular totales de Ã³rdenes
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_ordenes) AS x(orden_id UUID, monto_recaudado NUMERIC(12,2), monto_recaudado_bs NUMERIC(12,2)) LOOP
        v_rec_usd := COALESCE(v_item.monto_recaudado, 0.00);
        v_rec_bs := COALESCE(v_item.monto_recaudado_bs, v_rec_usd * v_tasa_cambio);

        v_total_ordenes := v_total_ordenes + v_rec_usd;
        v_total_ordenes_bs := v_total_ordenes_bs + v_rec_bs;
    END LOOP;

    -- 3. Validar y clasificar formas de pago (USD y Bs)
    FOR v_pago IN SELECT * FROM jsonb_to_recordset(p_pagos) AS y(fpago_id UUID, monto NUMERIC(12,2), monto_bs NUMERIC(12,2), monto_usd NUMERIC(12,2), cuenta_bancaria_id UUID, referencia_bancaria TEXT, cuenta_bancaria TEXT, capture_url TEXT) LOOP
        -- Calcular valores en ambas monedas
        IF v_pago.monto_bs IS NOT NULL AND v_pago.monto_bs > 0 THEN
            v_item_bs := v_pago.monto_bs;
            v_item_usd := COALESCE(v_pago.monto_usd, v_item_bs / v_tasa_cambio);
        ELSE
            v_item_usd := COALESCE(v_pago.monto_usd, v_pago.monto, 0.00);
            v_item_bs := COALESCE(v_pago.monto_bs, v_item_usd * v_tasa_cambio);
        END IF;

        v_total_pagos := v_total_pagos + v_item_usd;
        v_total_pagos_bs := v_total_pagos_bs + v_item_bs;
        
        -- Obtener informaciÃ³n de la forma de pago
        SELECT fpago_concepto, fpago_info 
        INTO v_fpago_concepto, v_fpago_info 
        FROM public.fpagos 
        WHERE fpago_id = v_pago.fpago_id;
        
        IF v_fpago_concepto IS NULL THEN
            RETURN json_build_object(
                'success', false,
                'data', NULL,
                'error', json_build_object(
                    'code', 'FORMA_PAGO_INEXISTENTE',
                    'message', 'La forma de pago especificada no existe.',
                    'details', 'fpago_id: ' || v_pago.fpago_id
                )
            );
        END IF;

        -- Verificar si es uso de Saldo a Favor
        IF v_fpago_concepto ILIKE '%saldo%favor%' THEN
            v_saldo_favor_usado := v_saldo_favor_usado + v_item_usd;
        ELSIF v_fpago_info = FALSE THEN
            v_total_efectivo := v_total_efectivo + v_item_usd;
        ELSE
            v_total_transferencias := v_total_transferencias + v_item_usd;
        END IF;
    END LOOP;

    -- Validar si el saldo a favor usado excede el disponible del cliente
    IF v_saldo_favor_usado > v_cliente_saldo_favor THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'SALDO_FAVOR_INSUFICIENTE',
                'message', 'El saldo a favor utilizado (' || v_saldo_favor_usado || ') supera el saldo a favor disponible del cliente (' || v_cliente_saldo_favor || ').',
                'details', NULL
            )
        );
    END IF;

    -- 4. Crear el registro principal (Cabecera) en rendiciones_cuentas con estado = 'aprobada'
    INSERT INTO public.rendiciones_cuentas (
        cliente_id,
        fecha_rendicion,
        tasa_cambio,
        total_efectivo_recaudado,
        total_transferencias_recaudado,
        total_recaudado_bs,
        total_recaudado_usd,
        total_devoluciones_valoradas,
        estado,
        observaciones,
        auditado_por
    ) VALUES (
        p_cliente_id,
        NOW(),
        v_tasa_cambio,
        v_total_efectivo,
        v_total_transferencias,
        v_total_pagos_bs,
        v_total_pagos,
        0.00,
        'aprobada',
        p_observaciones,
        NULL
    ) RETURNING id INTO v_rendicion_id;

    -- 5. Registrar detalle de Ã³rdenes asociadas y actualizar estado de las Ã³rdenes
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_ordenes) AS x(orden_id UUID, monto_recaudado NUMERIC(12,2), monto_recaudado_bs NUMERIC(12,2)) LOOP
        v_rec_usd := COALESCE(v_item.monto_recaudado, 0.00);
        v_rec_bs := COALESCE(v_item.monto_recaudado_bs, v_rec_usd * v_tasa_cambio);

        INSERT INTO public.detalle_rendicion_ordenes (
            rendicion_id,
            orden_distribucion_id,
            recaudado,
            recaudado_bs
        ) VALUES (
            v_rendicion_id,
            v_item.orden_id,
            v_rec_usd,
            v_rec_bs
        );

        -- Evaluar y liquidar financieramente la orden de distribuciÃ³n
        PERFORM public.liquidar_orden_distribucion(v_item.orden_id);
    END LOOP;

    -- 6. Registrar formas de pago (detalle_rendicion_fpagos)
    FOR v_pago IN SELECT * FROM jsonb_to_recordset(p_pagos) AS y(fpago_id UUID, monto NUMERIC(12,2), monto_bs NUMERIC(12,2), monto_usd NUMERIC(12,2), cuenta_bancaria_id UUID, referencia_bancaria TEXT, cuenta_bancaria TEXT, capture_url TEXT) LOOP
        IF v_pago.monto_bs IS NOT NULL AND v_pago.monto_bs > 0 THEN
            v_item_bs := v_pago.monto_bs;
            v_item_usd := COALESCE(v_pago.monto_usd, v_item_bs / v_tasa_cambio);
        ELSE
            v_item_usd := COALESCE(v_pago.monto_usd, v_pago.monto, 0.00);
            v_item_bs := COALESCE(v_pago.monto_bs, v_item_usd * v_tasa_cambio);
        END IF;

        INSERT INTO public.detalle_rendicion_fpagos (
            rendicion_id,
            fpago_id,
            cuenta_bancaria_id,
            monto,
            monto_bs,
            monto_usd,
            referencia_bancaria,
            cuenta_bancaria,
            capture_url
        ) VALUES (
            v_rendicion_id,
            v_pago.fpago_id,
            v_pago.cuenta_bancaria_id,
            v_item_usd,
            v_item_bs,
            v_item_usd,
            v_pago.referencia_bancaria,
            v_pago.cuenta_bancaria,
            v_pago.capture_url
        );
    END LOOP;

    -- 7. Procesar uso de Saldo a Favor si aplica
    IF v_saldo_favor_usado > 0 THEN
        UPDATE public.clientes
        SET saldo_favor = saldo_favor - v_saldo_favor_usado
        WHERE id = p_cliente_id;

        INSERT INTO public.movimientos_saldo_favor (
            cliente_id,
            rendicion_id,
            orden_id,
            monto,
            tipo,
            observaciones,
            created_at
        ) VALUES (
            p_cliente_id,
            v_rendicion_id,
            NULL,
            -v_saldo_favor_usado,
            'cargo_pago_orden',
            'Uso de saldo a favor en rendiciÃ³n de cuentas ID: ' || v_rendicion_id,
            NOW()
        );
    END IF;

    -- 8. Manejo de Excedente de Pago (CrÃ©dito a Favor Generado)
    IF v_total_pagos > v_total_ordenes THEN
        v_exceso := v_total_pagos - v_total_ordenes;
        v_exceso_bs := v_total_pagos_bs - v_total_ordenes_bs;

        INSERT INTO public.movimientos_saldo_favor (
            cliente_id,
            rendicion_id,
            orden_id,
            monto,
            tipo,
            observaciones,
            created_at
        ) VALUES (
            p_cliente_id,
            v_rendicion_id,
            NULL,
            v_exceso,
            'abono_recaudacion',
            'Excedente en formas de pago de rendiciÃ³n de cuentas ID: ' || v_rendicion_id,
            NOW()
        );

        UPDATE public.clientes
        SET saldo_favor = COALESCE(saldo_favor, 0.00) + v_exceso
        WHERE id = p_cliente_id;
    END IF;

    -- 9. Retorno Exitoso
    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'rendicion_id', v_rendicion_id,
            'tasa_cambio', v_tasa_cambio,
            'total_ordenes', v_total_ordenes,
            'total_ordenes_bs', v_total_ordenes_bs,
            'total_pagos', v_total_pagos,
            'total_pagos_bs', v_total_pagos_bs,
            'saldo_favor_usado', v_saldo_favor_usado,
            'saldo_favor_generado', v_exceso
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
-- Migration: 20260921000000_descuentos_cliente_producto.sql
-- Description: MÃ³dulo de descuentos de clientes por producto y actualizaciÃ³n de RPCs crear_orden_distribucion y retorna_lista_productos_segun_parametros

-- 1. Crear tabla de descuentos por cliente y producto
CREATE TABLE IF NOT EXISTS public.descuentos_cliente_producto (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cliente_id UUID NOT NULL REFERENCES public.clientes(id) ON DELETE CASCADE,
    producto_id UUID NOT NULL REFERENCES public.productos(id) ON DELETE CASCADE,
    porcentaje_descuento NUMERIC(5,2) NOT NULL DEFAULT 0.00,
    precio_pactado_usd NUMERIC(14,2) DEFAULT NULL,
    activo BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_cliente_producto_descuento UNIQUE (cliente_id, producto_id)
);

-- RLS y Permisos
ALTER TABLE public.descuentos_cliente_producto ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Permitir lectura publica a autenticados en descuentos_cliente_producto" ON public.descuentos_cliente_producto;
CREATE POLICY "Permitir lectura publica a autenticados en descuentos_cliente_producto"
    ON public.descuentos_cliente_producto FOR SELECT
    TO authenticated
    USING (true);

DROP POLICY IF EXISTS "Permitir todo a autenticados en descuentos_cliente_producto" ON public.descuentos_cliente_producto;
CREATE POLICY "Permitir todo a autenticados en descuentos_cliente_producto"
    ON public.descuentos_cliente_producto FOR ALL
    TO authenticated
    USING (true)
    WITH CHECK (true);

-- Ãndices
CREATE INDEX IF NOT EXISTS idx_descuentos_cliente_id ON public.descuentos_cliente_producto(cliente_id);
CREATE INDEX IF NOT EXISTS idx_descuentos_producto_id ON public.descuentos_cliente_producto(producto_id);

-- 2. Alterar detalle_distribucion para agregar columnas de auditoria de descuento
ALTER TABLE public.detalle_distribucion 
    ADD COLUMN IF NOT EXISTS precio_lista_usd NUMERIC(14,2) DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS porcentaje_descuento NUMERIC(5,2) DEFAULT 0.00,
    ADD COLUMN IF NOT EXISTS monto_descuento_usd NUMERIC(14,2) DEFAULT 0.00;

-- 3. Actualizar funciÃ³n RPC retorna_lista_productos_segun_parametros
DROP FUNCTION IF EXISTS public.retorna_lista_productos_segun_parametros(TEXT);
DROP FUNCTION IF EXISTS public.retorna_lista_productos_segun_parametros(TEXT, UUID);

CREATE OR REPLACE FUNCTION public.retorna_lista_productos_segun_parametros(
    p_parametro TEXT,
    p_cliente_id UUID DEFAULT NULL
)
RETURNS TABLE (
    id UUID,
    nombre TEXT,
    codigo_barras TEXT,
    precio NUMERIC, 
    stock_disponible INT,
    imagen_path TEXT,
    precio_lista NUMERIC,
    porcentaje_descuento NUMERIC,
    precio_final_usd NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY 
    SELECT 
        p.id, 
        p.nombre, 
        p.codigo_barras, 
        ROUND(
            CASE 
                WHEN d.id IS NOT NULL AND d.activo = true AND d.precio_pactado_usd IS NOT NULL THEN d.precio_pactado_usd
                WHEN d.id IS NOT NULL AND d.activo = true AND d.porcentaje_descuento > 0 THEN COALESCE(p.precio_lista1, 0.00) * (1.00 - (d.porcentaje_descuento / 100.00))
                ELSE COALESCE(p.precio_lista1, 0.00)
            END,
            2
        ) AS precio,
        COALESCE(i.stock_disponible, 0)::INT AS stock_disponible,
        p.imagen_path,
        COALESCE(p.precio_lista1, 0.00) AS precio_lista,
        CASE 
            WHEN d.id IS NOT NULL AND d.activo = true THEN COALESCE(d.porcentaje_descuento, 0.00)
            ELSE 0.00
        END AS porcentaje_descuento,
        ROUND(
            CASE 
                WHEN d.id IS NOT NULL AND d.activo = true AND d.precio_pactado_usd IS NOT NULL THEN d.precio_pactado_usd
                WHEN d.id IS NOT NULL AND d.activo = true AND d.porcentaje_descuento > 0 THEN COALESCE(p.precio_lista1, 0.00) * (1.00 - (d.porcentaje_descuento / 100.00))
                ELSE COALESCE(p.precio_lista1, 0.00)
            END,
            2
        ) AS precio_final_usd
    FROM public.productos p
    LEFT JOIN public.inventario_almacen i ON p.id = i.producto_id
    LEFT JOIN public.descuentos_cliente_producto d ON p.id = d.producto_id AND d.cliente_id = p_cliente_id AND d.activo = true
    WHERE 
        (p_parametro = '.F.' OR p.nombre ILIKE '%' || p_parametro || '%' OR p.codigo_barras ILIKE '%' || p_parametro || '%');
END;
$$;

-- 4. Actualizar funciÃ³n RPC crear_orden_distribucion
CREATE OR REPLACE FUNCTION public.crear_orden_distribucion(
    p_vendedor_id UUID,
    p_cliente_id UUID,
    p_camion_id UUID,
    p_tasa_cambio NUMERIC DEFAULT NULL,
    p_productos_json JSONB DEFAULT '[]'::jsonb,
    p_despachador_id UUID DEFAULT NULL,
    p_id_ruta UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_orden_id UUID;
    v_correlativo INT;
    v_factura_origen VARCHAR(30);
    v_tasa_cambio NUMERIC(14,4);
    
    v_vendedor_id UUID;
    v_despachador_id UUID;
    v_id_ruta UUID;
    
    v_peso_total NUMERIC(10,2) := 0.00;
    v_total_recaudar_usd NUMERIC(14,2) := 0.00;
    
    v_item JSONB;
    v_secuencia INT := 1;
    v_producto_id UUID;
    v_cantidad INT;
    
    v_val_usd_prod NUMERIC(14,2);
    v_val_usd NUMERIC(14,2);
    v_pct_desc NUMERIC(5,2) := 0.00;
    v_monto_desc_unit NUMERIC(14,2) := 0.00;
    v_subtotal_usd NUMERIC(14,2);
    v_peso_unitario NUMERIC(10,2);

    v_desc_rec RECORD;
BEGIN
    -- Validaciones bÃ¡sicas
    IF p_vendedor_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del vendedor es requerido.');
    END IF;

    IF p_cliente_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del cliente es requerido.');
    END IF;

    IF p_camion_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del camiÃ³n es requerido.');
    END IF;

    IF p_productos_json IS NULL OR jsonb_array_length(p_productos_json) = 0 THEN
        RETURN jsonb_build_object('success', false, 'message', 'Debe incluir al menos un producto en la orden.');
    END IF;

    -- Obtener informaciÃ³n del cliente (vendedor_id, despachador_id, id_ruta)
    SELECT c.vendedor_id, c.despachador_id, c.id_ruta
    INTO v_vendedor_id, v_despachador_id, v_id_ruta
    FROM public.clientes c
    WHERE c.id = p_cliente_id;

    -- Priorizar parÃ¡metros explÃ­citos si fueron proporcionados
    v_vendedor_id := COALESCE(p_vendedor_id, v_vendedor_id);
    v_despachador_id := COALESCE(p_despachador_id, v_despachador_id);
    v_id_ruta := COALESCE(p_id_ruta, v_id_ruta);

    -- Validar existencia de entidades
    IF NOT EXISTS (SELECT 1 FROM public.perfiles_usuario WHERE id = p_vendedor_id) THEN
        RETURN jsonb_build_object('success', false, 'message', 'El vendedor especificado no existe.');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.clientes WHERE id = p_cliente_id) THEN
        RETURN jsonb_build_object('success', false, 'message', 'El cliente especificado no existe.');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.camiones WHERE id = p_camion_id) THEN
        RETURN jsonb_build_object('success', false, 'message', 'El camiÃ³n especificado no existe.');
    END IF;

    -- Determinar / validar la tasa de cambio
    IF p_tasa_cambio IS NOT NULL AND p_tasa_cambio > 0 THEN
        v_tasa_cambio := p_tasa_cambio;
    ELSE
        SELECT tasa_cambio INTO v_tasa_cambio
        FROM public.tasa_cambio
        WHERE fecha_tasa = CURRENT_DATE;

        IF v_tasa_cambio IS NULL THEN
            SELECT tasa_cambio INTO v_tasa_cambio
            FROM public.tasa_cambio
            ORDER BY fecha_tasa DESC
            LIMIT 1;
        END IF;

        IF v_tasa_cambio IS NULL THEN
            RETURN jsonb_build_object(
                'success', false, 
                'message', 'No hay tasa de cambio registrada. Debe proporcionar p_tasa_cambio o registrar una tasa oficial en el sistema.'
            );
        END IF;
    END IF;

    -- Generar correlativo y nÃºmero de factura de origen automÃ¡ticamente
    v_correlativo := nextval('public.ordenes_distribucion_correlativo_seq');
    v_factura_origen := 'FAC-' || LPAD(v_correlativo::text, 6, '0');
    v_orden_id := gen_random_uuid();

    -- Validar productos y calcular totales exclusivamente en USD y peso total
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;
        
        IF v_cantidad IS NULL OR v_cantidad <= 0 THEN
            RETURN jsonb_build_object('success', false, 'message', 'La cantidad del producto debe ser mayor a cero.');
        END IF;

        SELECT COALESCE(precio_lista1, 0.00), COALESCE(peso_unitario_kg, 0.00) 
        INTO v_val_usd_prod, v_peso_unitario
        FROM public.productos
        WHERE id = v_producto_id;

        IF NOT FOUND THEN
            RETURN jsonb_build_object('success', false, 'message', 'El producto con ID ' || v_producto_id::text || ' no existe.');
        END IF;

        -- Buscar descuento especÃ­fico del cliente para este producto
        SELECT * INTO v_desc_rec
        FROM public.descuentos_cliente_producto
        WHERE cliente_id = p_cliente_id AND producto_id = v_producto_id AND activo = true;

        -- Resolver precio unitario en USD
        IF (v_item->>'valor_unitario_usd') IS NOT NULL THEN
            v_val_usd := (v_item->>'valor_unitario_usd')::NUMERIC;
        ELSIF (v_item->>'precio_unitario') IS NOT NULL THEN
            v_val_usd := (v_item->>'precio_unitario')::NUMERIC;
        ELSIF v_desc_rec.id IS NOT NULL THEN
            IF v_desc_rec.precio_pactado_usd IS NOT NULL THEN
                v_val_usd := v_desc_rec.precio_pactado_usd;
            ELSIF v_desc_rec.porcentaje_descuento > 0 THEN
                v_val_usd := ROUND(v_val_usd_prod * (1.00 - (v_desc_rec.porcentaje_descuento / 100.00)), 2);
            ELSE
                v_val_usd := v_val_usd_prod;
            END IF;
        ELSE
            v_val_usd := v_val_usd_prod;
        END IF;

        IF v_val_usd <= 0 OR (v_val_usd < 1.00 AND v_val_usd_prod >= 1.00) THEN
            v_val_usd := v_val_usd_prod;
        END IF;

        v_subtotal_usd := ROUND(v_cantidad * v_val_usd, 2);

        v_peso_total := v_peso_total + (COALESCE(v_peso_unitario, 0.00) * v_cantidad);
        v_total_recaudar_usd := v_total_recaudar_usd + v_subtotal_usd;
    END LOOP;

    -- Insertar Cabecera de la Orden con estado 'aprobada'
    INSERT INTO public.ordenes_distribucion (
        id,
        correlativo,
        cliente_id,
        camion_id,
        vendedor_id,
        despachador_id,
        id_ruta,
        estado,
        fecha_despacho,
        peso_total_calculado,
        factura_origen_numero,
        creado_por,
        created_at,
        tasa_cambio,
        total_recaudar_bs,
        total_recaudar_usd
    ) VALUES (
        v_orden_id,
        v_correlativo,
        p_cliente_id,
        p_camion_id,
        v_vendedor_id,
        v_despachador_id,
        v_id_ruta,
        'aprobada',
        NULL,
        v_peso_total,
        v_factura_origen,
        p_vendedor_id,
        NOW(),
        v_tasa_cambio,
        NULL,
        v_total_recaudar_usd
    );

    -- Insertar Detalles de la Orden
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;
        
        SELECT COALESCE(precio_lista1, 0.00) INTO v_val_usd_prod
        FROM public.productos
        WHERE id = v_producto_id;

        -- Buscar descuento especÃ­fico del cliente
        SELECT * INTO v_desc_rec
        FROM public.descuentos_cliente_producto
        WHERE cliente_id = p_cliente_id AND producto_id = v_producto_id AND activo = true;

        IF v_desc_rec.id IS NOT NULL THEN
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
            END IF;
        ELSE
            v_pct_desc := 0.00;
            v_monto_desc_unit := 0.00;
            v_val_usd := COALESCE((v_item->>'valor_unitario_usd')::NUMERIC, (v_item->>'precio_unitario')::NUMERIC, v_val_usd_prod);
        END IF;

        IF v_val_usd <= 0 OR (v_val_usd < 1.00 AND v_val_usd_prod >= 1.00) THEN
            v_val_usd := v_val_usd_prod;
        END IF;

        v_subtotal_usd := ROUND(v_cantidad * v_val_usd, 2);

        INSERT INTO public.detalle_distribucion (
            id,
            orden_id,
            producto_id,
            cantidad_solicitada,
            cantidad_despachada,
            valor_unitario_recaudar,
            subtotal_recaudar,
            secuencia_entrega,
            estado_entrega,
            motivo_rechazo,
            valor_unitario_usd,
            subtotal_recaudar_usd,
            precio_lista_usd,
            porcentaje_descuento,
            monto_descuento_usd
        ) VALUES (
            gen_random_uuid(),
            v_orden_id,
            v_producto_id,
            v_cantidad,
            0,
            NULL,
            NULL,
            v_secuencia,
            'pendiente',
            NULL,
            v_val_usd,
            v_subtotal_usd,
            v_val_usd_prod,
            v_pct_desc,
            v_monto_desc_unit * v_cantidad
        );
        
        v_secuencia := v_secuencia + 1;
    END LOOP;

    RETURN jsonb_build_object(
        'success', true, 
        'message', 'Orden de distribuciÃ³n creada exitosamente.', 
        'orden_id', v_orden_id,
        'data', jsonb_build_object(
            'orden_id', v_orden_id,
            'correlativo', v_correlativo,
            'tasa_cambio', v_tasa_cambio,
            'total_recaudar_bs', NULL,
            'total_recaudar_usd', v_total_recaudar_usd,
            'peso_total_calculado', v_peso_total
        )
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false, 
        'message', 'Error al crear la orden: ' || SQLERRM
    );
END;
$$;
-- MigraciÃ³n: Crear buckets de Supabase Storage para rendiciones-captures, productos y usuarios con sus respectivas polÃ­ticas RLS.

-- 1. Insertar bucket 'rendiciones-captures' (pÃºblico)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'rendiciones-captures',
    'rendiciones-captures',
    true,
    10485760, -- 10 MB lÃ­mite por archivo
    ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp', 'image/heic', 'application/pdf']
)
ON CONFLICT (id) DO UPDATE SET public = true;

-- 2. Insertar bucket 'productos' (pÃºblico)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'productos',
    'productos',
    true,
    5242880, -- 5 MB lÃ­mite por archivo
    ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE SET public = true;

-- 3. Insertar bucket 'usuarios' (pÃºblico)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'usuarios',
    'usuarios',
    true,
    5242880, -- 5 MB lÃ­mite por archivo
    ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE SET public = true;

-- ==========================================
-- 4. POLÃTICAS RLS PARA 'rendiciones-captures'
-- ==========================================
DROP POLICY IF EXISTS "Lectura publica de rendiciones-captures" ON storage.objects;
CREATE POLICY "Lectura publica de rendiciones-captures"
ON storage.objects FOR SELECT
USING (bucket_id = 'rendiciones-captures');

DROP POLICY IF EXISTS "Insercion autenticada de rendiciones-captures" ON storage.objects;
CREATE POLICY "Insercion autenticada de rendiciones-captures"
ON storage.objects FOR INSERT
WITH CHECK (
    bucket_id = 'rendiciones-captures' 
    AND (auth.role() = 'authenticated' OR auth.role() = 'service_role')
);

DROP POLICY IF EXISTS "Actualizacion autenticada de rendiciones-captures" ON storage.objects;
CREATE POLICY "Actualizacion autenticada de rendiciones-captures"
ON storage.objects FOR UPDATE
USING (
    bucket_id = 'rendiciones-captures' 
    AND (auth.role() = 'authenticated' OR auth.role() = 'service_role')
);

DROP POLICY IF EXISTS "Eliminacion autenticada de rendiciones-captures" ON storage.objects;
CREATE POLICY "Eliminacion autenticada de rendiciones-captures"
ON storage.objects FOR DELETE
USING (
    bucket_id = 'rendiciones-captures' 
    AND (auth.role() = 'authenticated' OR auth.role() = 'service_role')
);

-- ==========================================
-- 5. POLÃTICAS RLS PARA 'productos'
-- ==========================================
DROP POLICY IF EXISTS "Lectura publica de productos" ON storage.objects;
CREATE POLICY "Lectura publica de productos"
ON storage.objects FOR SELECT
USING (bucket_id = 'productos');

DROP POLICY IF EXISTS "Insercion autenticada de productos" ON storage.objects;
CREATE POLICY "Insercion autenticada de productos"
ON storage.objects FOR INSERT
WITH CHECK (
    bucket_id = 'productos' 
    AND (auth.role() = 'authenticated' OR auth.role() = 'service_role')
);

DROP POLICY IF EXISTS "Actualizacion autenticada de productos" ON storage.objects;
CREATE POLICY "Actualizacion autenticada de productos"
ON storage.objects FOR UPDATE
USING (
    bucket_id = 'productos' 
    AND (auth.role() = 'authenticated' OR auth.role() = 'service_role')
);

-- ==========================================
-- 6. POLÃTICAS RLS PARA 'usuarios'
-- ==========================================
DROP POLICY IF EXISTS "Lectura publica de usuarios" ON storage.objects;
CREATE POLICY "Lectura publica de usuarios"
ON storage.objects FOR SELECT
USING (bucket_id = 'usuarios');

DROP POLICY IF EXISTS "Insercion autenticada de usuarios" ON storage.objects;
CREATE POLICY "Insercion autenticada de usuarios"
ON storage.objects FOR INSERT
WITH CHECK (
    bucket_id = 'usuarios' 
    AND (auth.role() = 'authenticated' OR auth.role() = 'service_role')
);

DROP POLICY IF EXISTS "Actualizacion autenticada de usuarios" ON storage.objects;
CREATE POLICY "Actualizacion autenticada de usuarios"
ON storage.objects FOR UPDATE
USING (
    bucket_id = 'usuarios' 
    AND (auth.role() = 'authenticated' OR auth.role() = 'service_role')
);
-- MigraciÃ³n: DepuraciÃ³n de Ã³rdenes/tablas y carga masiva de productos desde INVENTARIO_260922_193808.xlsx

-- 1. Depurar tablas de Ã³rdenes e inventario dependientes de productos
TRUNCATE TABLE
    public.movimientos_contenedores,
    public.saldo_contenedores_clientes,
    public.radars,
    public.detalle_distribucion,
    public.ordenes_distribucion,
    public.inventario_movil,
    public.inventario_almacen,
    public.descuentos_cliente_producto,
    public.productos
RESTART IDENTITY CASCADE;

-- 2. Bloque PL/pgSQL para obtener el ID de contenedor y registrar productos Ãºnicos
DO $$
DECLARE
    v_contenedor_id UUID;
BEGIN
    -- Obtener el ID de contenedor por defecto disponible
    SELECT id INTO v_contenedor_id FROM public.tipos_contenedores ORDER BY created_at ASC LIMIT 1;

    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1045', 'REG. PILSEN 222ML BOT RT/ETQ-TF', 'UNID', 0.00, 1, v_contenedor_id);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1054', 'REG. PILSEN 355ML LT-TF', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1086', 'ZULIA 222ML BOT RT/PIR-TF', 'UNID', 0.00, 1, v_contenedor_id);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1116', 'ZULIA 250ML NI BOT NR/PIR-TF', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1139', 'CARDENAL ULTRA 250ML LT-TF', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1157', 'MALTA REG. 207ML NI BOT NR/ETQ-TF', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1158', 'MALTA REG. 250ML NI BOT NR/ETQ-TF', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1175', 'MALTA REG. 222ML NI BOT RT/ETQ-TF', 'UNID', 0.00, 1, v_contenedor_id);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1187', 'ZULIA 295ML LT-TF', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1226', 'MORENA 250ML LT-TF', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1300', 'MALTA MORENA 222ML BOT RT/ETQ-TF', 'UNID', 0.00, 1, v_contenedor_id);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1304', 'MORENA 355ML LT-TF', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1305', 'MALTA MORENA 250ML BOT NR/ETQ-TF', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1306', 'MALTA MORENA 250ML LT-TF', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1374', 'MALTA MORENA 207ML BOT NR/ETQ-TF', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1396', 'CERVEZA REGIONAL 250ML LT-TF', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1441', 'CERVEZA REGIONAL 222ML BOT RT/ETQ-TF', 'UNID', 0.00, 1, v_contenedor_id);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1472', 'CARDENAL 250ML LT-TF', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1625', 'LECHE EN POLVO COMP. SAN SIMON 12X400GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1626', 'LECHE EN POLVO COMP. SAN SIMON 12X900GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1627', 'BEBIDA LACTEA MONTANA FRESCA 24X125GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1628', 'BEBIDA LACTEA MONTANA FRESCA 12X400GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1629', 'BEBIDA LACTEA MONTANA FRESCA 12X900 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1631', 'LECHE LIQUIDA DESC. SAN SIMON 12X1L', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1702', 'ARROZ MARY DORADO 30x800 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1704', 'ARROZ MARY INTEGRAL 30x800 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1707', 'CREMA DE ARROZ MARY ENR. 24X450 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1714', 'CARAOTAS BLANCAS MARY 24x500 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1747', 'TOMATES PELADOS MARY 12x800 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1749', 'PASSATA DE TOMATE MARY 12x700 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1751', 'PALMITOS ENTEROS AL NATURAL 24x400 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1759', 'MARY LINGUINI PREMIUM 24x500 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1760', 'MARY VERMICELLI PREMIUM 24x500 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1761', 'MARY TORNILLOS PREMIUM 12x500 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1762', 'MARY PLUMITAS PREMIUM 12x500 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1763', 'MARY DEDAL PREMIUM 12x500 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1764', 'MARY MACARRON PREMIUM 12x500 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1766', 'MARY VERMICELLI SUPERIOR 12X1 KG', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1767', 'MARY TORNILLO SUPERIOR 12X1 KG', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1769', 'ACEITE OLIVA EXTRA VIRGEN MARY 12x500 ML', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1791', 'MARY PLUMA SUPERIOR 12X1 KG', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1797', 'MARY VERMICELLI TRADICIONAL 12x1 KG', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1799', 'HAR.TRIGO MARY TODO USO 20X900GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1800', 'ARROZ MARY PREMIUM 24X900 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7200', 'KESITOS 12x25 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7201', 'KESITOS 5x85 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7203', 'BOLIKRUNCH 5x85 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7204', 'CHISKESITOS 12x45 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7232', 'TOCINETIKAS ORIGINAL 6x40 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7234', 'TOCINETIKAS PICANTE 6x40 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7264', 'SNACHOS MUNCHY 12X42GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7271', 'MARY VERMICELLI SUPERIOR 24X500 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7353', 'ARVEJAS VERDES PARTIDAS MARY 30X400 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7354', 'CARAOTAS NEGRAS MARY 30X400 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7355', 'LENTEJAS MARY 30X400 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7357', 'GALLETAS CHARMY MOKA 24X192 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7361', 'GALLETAS CHARMY FRESA 24X192 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7363', 'GALLETAS CHARMY CHOCOLATE 24X192 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7365', 'GALLETAS MARIA CALEDONIA 24X252GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7367', 'ARROZ MARY ESMERALDA 24X900 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7369', 'MARY PLUMA SUPERIOR 12X500 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7370', 'MARY TORNILLO SUPERIOR 12X500 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7388', 'GALLETAS MARIA CALEDONIA LIMON 24X150GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7389', 'GALLETAS TIP TOP MANI 24X96GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7390', 'GALLETAS TIP TOP CHOCO 24X96GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7391', 'GALLETAS TIP TOP CHOCOMANI 24X96GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7392', 'GALLETAS TIP TOP VAINILLA 24X96GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7393', 'GALLETAS TIP TOP COCO 24X96GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7468', 'GALLETAS TIPTOP CHOCO 8X18X16 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7472', 'GALLETAS CHARMY VAINI. ESTUCHE 8X18X16GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7473', 'GALLETA CHARMY CHOCO ESTU 8X18X16GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7474', 'GALLETA CHARMY MOKA ESTU 8X18X16GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7475', 'GALLETAS MARIA CALEDONIA CANELA 24X150GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7476', 'ARROZ MARY SUPERIOR TIPO I 24x900 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7477', 'ARROZ MARY TRADICIONAL TIPO I 24x900 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7480', 'GALLETAS CHARMY BROWNIE 24X192 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7481', 'GALLETAS CHARMY CHOCO MANIA 24X192 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7482', 'HAR.MAIZ BLANCO MARY PREC.ENRIQ.20X900GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7483', 'HARINA DE TRIGO LEUDANTE MARY 20X900GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7485', 'HAR.MAIZ BLANCO PREC. ENRIQ. MARY 9X2KG', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7486', 'MAIZ PARA COTUFAS MARY 30X400G', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7851', 'RON PAMPERO ESPECIAL 12X700 ML 40GL NAC', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7852', 'VODKA GORDONS 12X700 ML 40GL NAC', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7853', 'VODKA GORDONS UVA 12X700 ML 30GL NAC', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7855', 'VODKA GORDONS PARCH. 12X700 ML 30GL NAC', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7856', 'GIN GORDONS 12X700 ML 40GL NAC', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7857', 'WHISKY BLACK AND WHITE 12X750ML 40GL IMP', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7858', 'RON PAMPERO ANIVERSARIO 6X700ML 40GL NAC', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7859', 'RON PAMPERO SELECCION 6X700ML 40GL NAC', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7863', 'WHISKY BUCHANANS 12A 12X750ML 40GL IMP', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7865', 'WHISKY OLD PARR 12A 12X750ML 40GL IMP', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7866', 'CREMA WHISKY BAILEYS 12X750ML 17GL IMP', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7867', 'GIN TANQUERAY LONDON 6X700ML 47,3GL IMP', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7868', 'VODKA SMIRNOFF XXI 6X700 ML 40GL IMP', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7871', 'WHISKY BUCHANANS 18A 6X750ML 40GL IMP', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7872', 'WHISKY OLD PARR SILVER 12X750ML 40GL IMP', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7882', 'WHISKY JW BLC. LB. 12A 12x700ML 40GL IMP', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7887', 'WHISKY BLACK AND WHITE 12X1L 40GL IMP', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7888', 'WHISKY BUCHANAN MASTER 12X750ML 40GL IMP', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7889', 'VODKA SMIRNOFF SPICY TMR 6X700ML 30G IMP', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7893', 'WHISKY OLD PARR TROPICAL12A 12X750ML IMP', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7896', 'WHISKY OLD PARR 12A 12X1L 40GL IMP', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7971', 'AGUA MINERAL BIENESTAR 16X600ML', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7972', 'AGUA MINERAL BIENESTAR 6X1.5L', 'UNID', 0.00, 1, NULL);
END;
$$;
-- MigraciÃ³n: Crear Esquema de Base de Datos Central y Enrutamiento Multi-Tenant

-- 1. Crear tabla catÃ¡logo de empresas (empresas tenant lt_*)
CREATE TABLE IF NOT EXISTS public.empresas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_empresa VARCHAR(50) NOT NULL UNIQUE,
    nombre_empresa VARCHAR(150) NOT NULL,
    supabase_url TEXT NOT NULL,
    supabase_anon_key TEXT NOT NULL,
    activo BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Crear tabla relaciÃ³n usuario-empresa
CREATE TABLE IF NOT EXISTS public.usuarios_empresas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    empresa_id UUID NOT NULL REFERENCES public.empresas(id) ON DELETE CASCADE,
    rol VARCHAR(50) DEFAULT 'operador',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_user_empresa UNIQUE (user_id, empresa_id)
);

-- 3. Habilitar Aislamiento RLS
ALTER TABLE public.empresas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.usuarios_empresas ENABLE ROW LEVEL SECURITY;

-- 4. Crear PolÃ­ticas RLS
DROP POLICY IF EXISTS "Allow users to read their own mapping" ON public.usuarios_empresas;
CREATE POLICY "Allow users to read their own mapping" 
ON public.usuarios_empresas FOR SELECT TO authenticated 
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Allow users to read assigned empresa details" ON public.empresas;
CREATE POLICY "Allow users to read assigned empresa details" 
ON public.empresas FOR SELECT TO authenticated 
USING (id IN (SELECT empresa_id FROM public.usuarios_empresas WHERE user_id = auth.uid()));
-- MigraciÃ³n: Crear Stored Procedures para GestiÃ³n de Empresas y Usuarios Multi-Tenant

-- 1. FunciÃ³n para crear nueva empresa
CREATE OR REPLACE FUNCTION public.crea_nueva_empresa(
    p_codigo_empresa VARCHAR,
    p_nombre_empresa VARCHAR,
    p_supabase_url TEXT,
    p_supabase_anon_key TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_empresa_id UUID;
    v_response JSONB;
BEGIN
    -- Validar que el cÃ³digo no exista
    IF EXISTS (SELECT 1 FROM public.empresas WHERE codigo_empresa = p_codigo_empresa) THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', null,
            'error', jsonb_build_object(
                'code', 'CODIGO_EMPRESA_DUPLICADO',
                'message', 'El cÃ³digo de empresa especificado ya existe en el sistema.',
                'details', null
            )
        );
    END IF;

    -- Insertar nueva empresa
    INSERT INTO public.empresas (
        codigo_empresa,
        nombre_empresa,
        supabase_url,
        supabase_anon_key
    ) VALUES (
        p_codigo_empresa,
        p_nombre_empresa,
        p_supabase_url,
        p_supabase_anon_key
    ) RETURNING id INTO v_empresa_id;

    -- Construir respuesta de Ã©xito
    RETURN jsonb_build_object(
        'success', true,
        'message', 'Empresa creada exitosamente.',
        'data', jsonb_build_object(
            'empresa_id', v_empresa_id,
            'codigo_empresa', p_codigo_empresa,
            'nombre_empresa', p_nombre_empresa
        ),
        'error', null
    );
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false,
        'data', null,
        'error', jsonb_build_object(
            'code', 'DB_ERROR',
            'message', 'Error interno al crear la empresa.',
            'details', SQLERRM
        )
    );
END;
$$;

-- 2. FunciÃ³n para asignar usuario a empresa
CREATE OR REPLACE FUNCTION public.asignar_usuario_empresa(
    p_user_id UUID,
    p_empresa_id UUID,
    p_rol VARCHAR DEFAULT 'operador'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_asignacion_id UUID;
    v_response JSONB;
BEGIN
    -- Validar que la empresa exista
    IF NOT EXISTS (SELECT 1 FROM public.empresas WHERE id = p_empresa_id) THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', null,
            'error', jsonb_build_object(
                'code', 'EMPRESA_INEXISTENTE',
                'message', 'No se encontrÃ³ la empresa especificada.',
                'details', null
            )
        );
    END IF;

    -- Usamos UPSERT (ON CONFLICT) dado que existe la restricciÃ³n unique_user_empresa
    INSERT INTO public.usuarios_empresas (
        user_id,
        empresa_id,
        rol
    ) VALUES (
        p_user_id,
        p_empresa_id,
        p_rol
    )
    ON CONFLICT (user_id, empresa_id) 
    DO UPDATE SET 
        rol = EXCLUDED.rol
    RETURNING id INTO v_asignacion_id;

    -- Construir respuesta de Ã©xito
    RETURN jsonb_build_object(
        'success', true,
        'message', 'Usuario asignado a la empresa exitosamente.',
        'data', jsonb_build_object(
            'asignacion_id', v_asignacion_id,
            'user_id', p_user_id,
            'empresa_id', p_empresa_id,
            'rol', p_rol
        ),
        'error', null
    );
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false,
        'data', null,
        'error', jsonb_build_object(
            'code', 'DB_ERROR',
            'message', 'Error interno al asignar el usuario a la empresa.',
            'details', SQLERRM
        )
    );
END;
$$;
-- MigraciÃ³n: DepuraciÃ³n masiva de tablas (Clientes, Choferes, Radars, etc) solicitada el 23-09-2026

TRUNCATE TABLE 
    public.clientes,
    public.choferes,
    public.cuentas_bancarias_empresa,
    public.movimientos_contenedores,
    public.movimientos_saldo_favor,
    public.radars
CASCADE;
-- MigraciÃ³n: DepuraciÃ³n masiva de todas las tablas (excepto catÃ¡logos maestros) solicitada el 23-09-2026

TRUNCATE TABLE 
    auth.users,
    public.empresas,
    public.usuarios_empresas,
    public.clientes,
    public.choferes,
    public.tasa_cambio,
    public.ordenes_distribucion,
    public.inventario_almacen,
    public.inventario_movil,
    public.radars,
    public.rendiciones_cuentas,
    public.descuentos_cliente_producto,
    public.cuentas_bancarias_empresa,
    public.movimientos_saldo_favor,
    public.saldo_contenedores_clientes
CASCADE;
-- MigraciÃ³n de datos: Crear empresa de pruebas (lt_tests) y asignar usuarios superadmin

DO $$
DECLARE
    v_empresa_id UUID;
    v_response JSONB;
    v_user RECORD;
BEGIN
    -- 1. Crear la empresa usando el SP
    v_response := public.crea_nueva_empresa(
        'LT-TESTS', 
        'tests', 
        'https://tests-project-url.supabase.co', 
        'dummy-anon-key-tests'
    );
    
    -- Extraer el ID de la empresa reciÃ©n creada
    v_empresa_id := (v_response->'data'->>'empresa_id')::UUID;
    
    -- 2. Asignar todos los usuarios actuales de auth.users a la nueva empresa
    -- Como la tabla de usuarios se vaciÃ³ recientemente, asumimos que los dos 
    -- que existen actualmente son los superadmins que mencionaste.
    FOR v_user IN SELECT id FROM auth.users LOOP
        PERFORM public.asignar_usuario_empresa(v_user.id, v_empresa_id, 'superadmin');
    END LOOP;
END;
$$;
