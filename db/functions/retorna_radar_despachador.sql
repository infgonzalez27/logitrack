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

COMMENT ON FUNCTION public.retorna_radar_despachador() IS 'Retorna las órdenes en tránsito o despachadas del despachador autenticado con detalles de mercancía y saldo de envases del cliente';
