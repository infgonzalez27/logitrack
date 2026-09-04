-- Migration: Módulo de Políticas de Crédito y Excepciones de Despacho Gerenciales (DB-027)

-- 1. DDL: Agregar columnas de políticas de crédito a public.clientes
ALTER TABLE public.clientes
ADD COLUMN IF NOT EXISTS limite_credito NUMERIC(14,2) DEFAULT 0.00 CHECK (limite_credito >= 0.00),
ADD COLUMN IF NOT EXISTS max_facturas_vencidas INT DEFAULT 0 CHECK (max_facturas_vencidas >= 0),
ADD COLUMN IF NOT EXISTS permiso_despacho_manual BOOLEAN DEFAULT TRUE,
ADD COLUMN IF NOT EXISTS excepcion_despacho_gerencia BOOLEAN DEFAULT FALSE;

COMMENT ON COLUMN public.clientes.limite_credito IS 'Monto máximo de saldo deudor permitido para el cliente en Bs/USD';
COMMENT ON COLUMN public.clientes.max_facturas_vencidas IS 'Cantidad máxima de facturas o solicitudes vencidas pendientes sin pago';
COMMENT ON COLUMN public.clientes.permiso_despacho_manual IS 'Habilitación manual de despacho para el cliente (.T. / .F.)';
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
        'message', 'Excepción de despacho otorgada exitosamente por gerencia (Válida por 1 despacho).',
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

-- 3. RPC: actualiza_registro_cliente_segun_uuid con crédito
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
                'message', 'El parámetro p_id es obligatorio.'
            )
        );
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.clientes WHERE id = p_id) THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'CLIENTE_INEXISTENTE',
                'message', 'No se encontró ningún cliente con el ID especificado.'
            )
        );
    END IF;

    IF p_rif_nit IS NOT NULL AND TRIM(p_rif_nit) <> '' THEN
        IF EXISTS (SELECT 1 FROM public.clientes WHERE rif_nit = TRIM(p_rif_nit) AND id <> p_id) THEN
            RETURN jsonb_build_object(
                'success', FALSE,
                'error', jsonb_build_object(
                    'code', 'RIF_DUPLICADO',
                    'message', 'El RIF/NIT especificado ya está registrado en otro cliente.'
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
                'message', 'El usuario no está autenticado.'
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
                            WHEN COALESCE(c.permiso_despacho_manual, TRUE) = FALSE THEN 'Despacho bloqueado manualmente por política de crédito'
                            WHEN COALESCE(c.limite_credito, 0.00) > 0.00 AND COALESCE(o.total_recaudar_bs, 0.00) > COALESCE(c.limite_credito, 0.00) THEN 'Monto de la orden supera el límite de crédito del cliente'
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

-- 5. RPC: registrar_despacho_cliente_radar con validación y reseteo de excepción
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
                'message', 'El parámetro p_orden_id es obligatorio.'
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
                'message', 'No se encontró la orden especificada.'
            )
        );
    END IF;

    IF NOT v_despacho_permitido THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'DESPACHO_BLOQUEADO_CREDITO',
                'message', 'No se puede despachar la orden: El cliente se encuentra bloqueado por política de crédito y no posee una excepción gerencial activa.'
            )
        );
    END IF;

    IF v_estado_orden NOT IN ('en_transito', 'despachada') THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo se pueden registrar entregas de órdenes en estado en_transito o despachada.'
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
