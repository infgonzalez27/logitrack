-- Script SQL para recalcular masivamente movimientos_contenedores y saldo_contenedores_clientes

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
    RAISE NOTICE 'Iniciando recálculo masivo de movimientos y saldos de contenedores...';

    -- 1. Limpiar registros de movimientos y saldos de contenedores para evitar duplicados
    DELETE FROM public.movimientos_contenedores;
    DELETE FROM public.saldo_contenedores_clientes;

    -- 2. Procesar contenedores ENTREGADOS para todas las órdenes despachadas en radares aprobados
    -- Fórmula: CEIL(cantidad_despachada * unidades_por_contenedor)
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

    RAISE NOTICE 'Recálculo masivo completado:';
    RAISE NOTICE '- Movimientos de entregas: %', v_mov_entregados_count;
    RAISE NOTICE '- Movimientos de retiros: %', v_mov_retirados_count;
    RAISE NOTICE '- Saldos de clientes actualizados: %', v_saldos_actualizados_count;
END;
$$;
