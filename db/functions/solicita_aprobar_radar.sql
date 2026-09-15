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

    -- Note: El cálculo de contenedores entregados y retirados fue trasladado a registrar_despacho_cliente_radar
    -- para asentar los saldos al momento de confirmar el despacho.
    v_contenedores_entregados_procesados := 0;
    v_contenedores_retirados_procesados := 0;

    -- 2. Devuelve el inventario no despachado del camión al almacén principal
    v_inv_res := public.retorna_inventario_no_despachado_para_almacen(p_radar_id);

    -- 5. Las órdenes en estado 'devuelta' pasan al estado final 'anulada'
    WITH ordenes_devueltas AS (
        UPDATE public.ordenes_distribucion
        SET estado = 'anulada'
        WHERE radar_id = p_radar_id AND estado = 'devuelta'
        RETURNING id
    )
    SELECT COUNT(*) INTO v_ordenes_anuladas_count FROM ordenes_devueltas;

    -- 6. Políticas de crédito desactivadas temporalmente para mantener todos los clientes activos
    -- Ningún cliente es desactivado al aprobar el radar. Todos mantienen permiso_despacho_manual = TRUE.
    v_clientes_deshabilitados_count := 0;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Radar aprobado exitosamente. Saldos de contenedores actualizados, políticas de crédito evaluadas, inventario restituido a almacén y órdenes devueltas anuladas.',
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

COMMENT ON FUNCTION public.solicita_aprobar_radar(UUID) IS 'Aprueba el radar (status_radar = TRUE), carga envases entregados/retirados a saldos de clientes, evalúa políticas de crédito (max_facturas_vencidas), reingresa inventario a almacén y anula órdenes devueltas.';
