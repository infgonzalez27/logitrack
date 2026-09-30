-- AutoVentas: descargar el camión devolviendo al almacén solo el sobrante
-- (cantidad_cargada − cantidad_entregada). No toca órdenes, detalle ni radares
-- (el reverso del radar pone cantidad_despachada = 0 en todas las órdenes del
-- camión y devuelve también lo vendido).
--
-- p_productos NULL o []: descarga total; el inventario móvil del camión queda
-- vacío y el camión 'disponible'.
-- p_productos [{producto_id, cantidad}]: descarga parcial; cada cantidad debe
-- ser <= disponible.

CREATE OR REPLACE FUNCTION public.descargar_camion_autoventa(
  p_camion_id uuid,
  p_productos jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_rol text;
  v_total boolean;
  v_pedido jsonb;
  v_disponible int;
  v_nombre text;
  v_rec record;
  v_detalle jsonb := '[]'::jsonb;
  v_productos int := 0;
  v_unidades int := 0;
BEGIN
  IF auth.uid() IS NOT NULL THEN
    v_rol := public.lt_current_user_rol();
    IF v_rol IS NULL OR v_rol NOT IN ('admin', 'gerente', 'vendedor', 'despachador') THEN
      RETURN jsonb_build_object('success', false, 'data', NULL,
        'error', jsonb_build_object('code', 'ACCESO_DENEGADO',
          'message', 'No tienes permiso para descargar el camión.'));
    END IF;
  END IF;

  IF p_camion_id IS NULL OR NOT EXISTS (SELECT 1 FROM camiones WHERE id = p_camion_id) THEN
    RETURN jsonb_build_object('success', false, 'data', NULL,
      'error', jsonb_build_object('code', 'CAMION_INEXISTENTE',
        'message', 'El camión especificado no existe.'));
  END IF;

  IF EXISTS (
    SELECT 1 FROM ordenes_distribucion
    WHERE camion_id = p_camion_id AND radar_id IS NOT NULL AND estado = 'en_transito'
  ) THEN
    RETURN jsonb_build_object('success', false, 'data', NULL,
      'error', jsonb_build_object('code', 'RUTA_RADAR_ACTIVA',
        'message', 'El camión tiene una ruta de radar en tránsito. Descárgalo desde el radar.'));
  END IF;

  PERFORM 1 FROM inventario_movil WHERE camion_id = p_camion_id FOR UPDATE;

  v_total := p_productos IS NULL
    OR jsonb_typeof(p_productos) <> 'array'
    OR jsonb_array_length(p_productos) = 0;

  IF v_total THEN
    FOR v_rec IN
      SELECT im.producto_id, p.codigo_producto, p.nombre,
             GREATEST(0, im.cantidad_cargada - im.cantidad_entregada) AS disponible
      FROM inventario_movil im
      JOIN productos p ON p.id = im.producto_id
      WHERE im.camion_id = p_camion_id
      ORDER BY p.nombre
    LOOP
      IF v_rec.disponible > 0 THEN
        INSERT INTO inventario_almacen (producto_id, stock_disponible, stock_comprometido, updated_at)
        VALUES (v_rec.producto_id, v_rec.disponible, 0, now())
        ON CONFLICT (producto_id) DO UPDATE
          SET stock_disponible = inventario_almacen.stock_disponible + EXCLUDED.stock_disponible,
              updated_at = now();

        v_detalle := v_detalle || jsonb_build_object(
          'producto_id', v_rec.producto_id, 'codigo', v_rec.codigo_producto,
          'nombre', v_rec.nombre, 'cantidad', v_rec.disponible);
        v_productos := v_productos + 1;
        v_unidades := v_unidades + v_rec.disponible;
      END IF;
    END LOOP;

    DELETE FROM inventario_movil WHERE camion_id = p_camion_id;
    UPDATE camiones SET estado = 'disponible' WHERE id = p_camion_id AND estado = 'en_ruta';
  ELSE
    -- Una fila por producto (si viene repetido se suman las cantidades).
    SELECT COALESCE(jsonb_agg(jsonb_build_object('producto_id', pid, 'cantidad', cant)), '[]'::jsonb)
    INTO v_pedido
    FROM (
      SELECT (x->>'producto_id')::uuid AS pid,
             SUM(COALESCE(NULLIF(x->>'cantidad', ''), NULLIF(x->>'cantidad_solicitada', ''), '0')::int) AS cant
      FROM jsonb_array_elements(p_productos) x
      WHERE NULLIF(x->>'producto_id', '') IS NOT NULL
      GROUP BY 1
    ) s
    WHERE cant > 0;

    -- Validar todo antes de mover stock.
    FOR v_rec IN SELECT * FROM jsonb_to_recordset(v_pedido) AS t(producto_id uuid, cantidad int) LOOP
      v_disponible := NULL;
      v_nombre := NULL;
      SELECT GREATEST(0, im.cantidad_cargada - im.cantidad_entregada), p.nombre
      INTO v_disponible, v_nombre
      FROM inventario_movil im JOIN productos p ON p.id = im.producto_id
      WHERE im.camion_id = p_camion_id AND im.producto_id = v_rec.producto_id;

      IF COALESCE(v_disponible, 0) < v_rec.cantidad THEN
        RETURN jsonb_build_object('success', false, 'data', NULL,
          'error', jsonb_build_object('code', 'CANTIDAD_EXCEDE_DISPONIBLE',
            'message', format('%s: solo hay %s disponible(s) en el camión.',
              COALESCE(v_nombre, 'Producto'), COALESCE(v_disponible, 0))));
      END IF;
    END LOOP;

    FOR v_rec IN
      SELECT d.producto_id, d.cantidad, p.codigo_producto, p.nombre
      FROM jsonb_to_recordset(v_pedido) AS d(producto_id uuid, cantidad int)
      JOIN productos p ON p.id = d.producto_id
      ORDER BY p.nombre
    LOOP
      UPDATE inventario_movil
      SET cantidad_cargada = cantidad_cargada - v_rec.cantidad, updated_at = now()
      WHERE camion_id = p_camion_id AND producto_id = v_rec.producto_id;

      INSERT INTO inventario_almacen (producto_id, stock_disponible, stock_comprometido, updated_at)
      VALUES (v_rec.producto_id, v_rec.cantidad, 0, now())
      ON CONFLICT (producto_id) DO UPDATE
        SET stock_disponible = inventario_almacen.stock_disponible + EXCLUDED.stock_disponible,
            updated_at = now();

      v_detalle := v_detalle || jsonb_build_object(
        'producto_id', v_rec.producto_id, 'codigo', v_rec.codigo_producto,
        'nombre', v_rec.nombre, 'cantidad', v_rec.cantidad);
      v_productos := v_productos + 1;
      v_unidades := v_unidades + v_rec.cantidad;
    END LOOP;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'message', CASE
      WHEN v_unidades = 0 THEN 'El camión no tenía sobrante para devolver.'
      ELSE format('Se devolvieron %s unidad(es) de %s producto(s) al almacén.', v_unidades, v_productos)
    END,
    'data', jsonb_build_object(
      'camion_id', p_camion_id,
      'descarga_total', v_total,
      'productos_devueltos', v_productos,
      'unidades_devueltas', v_unidades,
      'detalle', v_detalle
    ),
    'error', NULL
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.descargar_camion_autoventa(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.descargar_camion_autoventa(uuid, jsonb) TO authenticated, service_role;
