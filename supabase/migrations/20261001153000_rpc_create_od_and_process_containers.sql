-- Migration: 20261001153000_rpc_create_od_and_process_containers.sql

CREATE OR REPLACE FUNCTION public.rpc_create_od_and_process_containers(
    p_vendedor_id UUID,
    p_cliente_id UUID,
    p_camion_id UUID,
    p_tasa_cambio NUMERIC,
    p_productos_json JSONB,
    p_despachador_id UUID DEFAULT NULL,
    p_id_ruta UUID DEFAULT NULL,
    p_contenedores_retirados INT DEFAULT 0
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_orden_id UUID;
    v_item JSONB;
    v_producto_id UUID;
    v_cantidad INT;
    
    v_contenedor_id UUID;
    v_unidades_por_contenedor NUMERIC;
    
    v_saldo_anterior INT := 0;
    v_saldo_actual INT := 0;
    v_entregados INT := 0;
    v_resultado JSONB;
    v_primary_contenedor_id UUID;
BEGIN
    -- 1. Delegar la transaccion principal al RPC existente de creacion de orden
    v_resultado := public.crear_orden_distribucion(
        p_vendedor_id,
        p_cliente_id,
        p_camion_id,
        p_tasa_cambio,
        p_productos_json,
        p_despachador_id,
        p_id_ruta
    );
    
    -- Si falla la creacion de la orden, abortar y retornar el error
    IF NOT (v_resultado->>'success')::BOOLEAN THEN
        RETURN v_resultado; 
    END IF;
    
    v_orden_id := (v_resultado->>'orden_id')::UUID;
    
    -- 2. Calcular los contenedores entregados segun los productos de la orden
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json)
    LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;
        
        -- Obtener detalle del contenedor para este producto
        SELECT contenedor_id, COALESCE(unidades_por_contenedor, 1) 
        INTO v_contenedor_id, v_unidades_por_contenedor
        FROM public.productos
        WHERE id = v_producto_id;
        
        IF v_contenedor_id IS NOT NULL THEN
            -- Sumar los entregados (ej. si la caja trae 24 botellas, entregamos 1 caja)
            v_entregados := v_entregados + FLOOR(v_cantidad / v_unidades_por_contenedor)::INT;
            
            -- Guardamos el contenedor primario para registrar el retiro
            IF v_primary_contenedor_id IS NULL THEN
                v_primary_contenedor_id := v_contenedor_id;
            END IF;
        END IF;
    END LOOP;
    
    -- 3. Procesar los movimientos de saldo de contenedores
    IF v_primary_contenedor_id IS NOT NULL THEN
        -- Obtener saldo anterior
        SELECT saldo_pendiente INTO v_saldo_anterior
        FROM public.saldo_contenedores_clientes
        WHERE cliente_id = p_cliente_id AND contenedor_id = v_primary_contenedor_id;
        
        v_saldo_anterior := COALESCE(v_saldo_anterior, 0);
        v_saldo_actual := v_saldo_anterior + v_entregados - p_contenedores_retirados;
        
        -- Insertar el registro de movimiento
        IF v_entregados > 0 OR p_contenedores_retirados > 0 THEN
            INSERT INTO public.movimientos_contenedores (
                cliente_id, orden_id, contenedor_id, cantidad_entregada, cantidad_retirada, creado_por
            ) VALUES (
                p_cliente_id, v_orden_id, v_primary_contenedor_id, v_entregados, p_contenedores_retirados, auth.uid()
            );
        END IF;
        
        -- Actualizar o Insertar el saldo final del cliente
        INSERT INTO public.saldo_contenedores_clientes (cliente_id, contenedor_id, saldo_pendiente, updated_at)
        VALUES (p_cliente_id, v_primary_contenedor_id, v_saldo_actual, NOW())
        ON CONFLICT (cliente_id, contenedor_id)
        DO UPDATE SET 
            saldo_pendiente = EXCLUDED.saldo_pendiente,
            updated_at = NOW();
            
    ELSE
        -- Si no hubo productos con contenedor
        v_saldo_anterior := 0;
        v_saldo_actual := 0 - p_contenedores_retirados;
    END IF;
    
    -- 4. Retornar el JSON estructurado para el Frontend (impresion del Ticket)
    RETURN jsonb_build_object(
        'success', true,
        'order_id', v_orden_id,
        'resumen_contenedores', jsonb_build_object(
            'saldo_anterior', v_saldo_anterior,
            'entregados', v_entregados,
            'retirados', p_contenedores_retirados,
            'saldo_actual', v_saldo_actual
        )
    );
END;
$$;
