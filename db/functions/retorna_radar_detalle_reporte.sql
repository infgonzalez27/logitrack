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
                'message', 'No se encontró el radar especificado.'
            )
        );
    END IF;

    -- 2. Obtener datos del despachador
    SELECT pu.id, pu.nombre_completo, pu.telefono, u.email AS correo_e
    INTO v_despachador
    FROM public.perfiles_usuario pu
    LEFT JOIN auth.users u ON pu.id = u.id
    WHERE pu.id = v_radar.despachador_id;

    -- 3. Consolidado de productos solicitados/despachados en este radar (Reporte global / resumen de productos al final)
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

    -- 4. Detalle orden por orden (Clientes y sus productos)
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

GRANT EXECUTE ON FUNCTION public.retorna_radar_detalle_reporte TO authenticated, service_role;

COMMENT ON FUNCTION public.retorna_radar_detalle_reporte(UUID) IS 'Retorna el JSON estructurado del radar con la información del despachador, órdenes por cliente y el resumen consolidado de productos para reportes impresos y digitales.';
