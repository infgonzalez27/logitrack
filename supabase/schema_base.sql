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
