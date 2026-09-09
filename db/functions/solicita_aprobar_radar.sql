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

    -- Verificar existencia del radar
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

    -- 1. Marcar el radar como aprobado y cerrado (.T.)
    UPDATE public.radars
    SET status_radar = TRUE,
        aprobado = TRUE
    WHERE id = p_radar_id;

    -- 2. Procesar movimiento de envases devueltos por clientes (contenedores_retirados)
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
            -- Registrar transacción de movimiento de contenedores
            INSERT INTO public.movimientos_contenedores (
                cliente_id, orden_id, contenedor_id, cantidad_entregada, cantidad_retirada, creado_por
            ) VALUES (
                v_rec.cliente_id, v_rec.orden_id, v_rec.contenedor_id, 0, v_rec.total_retirados, auth.uid()
            );

            -- Descontar saldo pendiente en saldo_contenedores_clientes
            UPDATE public.saldo_contenedores_clientes
            SET saldo_pendiente = GREATEST(0, saldo_pendiente - v_rec.total_retirados),
                updated_at = NOW()
            WHERE cliente_id = v_rec.cliente_id AND contenedor_id = v_rec.contenedor_id;

            v_contenedores_procesados := v_contenedores_procesados + v_rec.total_retirados;
        END IF;
    END LOOP;

    -- 3. Devuelve el inventario no despachado del camión al almacén principal
    v_inv_res := public.retorna_inventario_no_despachado_para_almacen(p_radar_id);

    -- 4. Las órdenes en estado 'devuelta' pasan al estado final 'anulada'
    WITH ordenes_devueltas AS (
        UPDATE public.ordenes_distribucion
        SET estado = 'anulada'
        WHERE radar_id = p_radar_id AND estado = 'devuelta'
        RETURNING id
    )
    SELECT COUNT(*) INTO v_ordenes_anuladas_count FROM ordenes_devueltas;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Radar aprobado exitosamente. Saldos de contenedores actualizados, inventario restituido a almacén y órdenes devueltas anuladas.',
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

COMMENT ON FUNCTION public.solicita_aprobar_radar(UUID) IS 'Aprueba el radar (.T.), actualiza saldos de contenedores de clientes, reingresa inventario no despachado a almacén y pasa órdenes devueltas a anulada.';
