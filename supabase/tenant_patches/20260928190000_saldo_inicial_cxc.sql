-- Cuentas por cobrar iniciales: deuda previa del cliente cargada como documento
-- sin productos (estado por_liquidar), cobrable con la rendición normal, y
-- vacíos (contenedores) que el cliente ya tenía en su poder.

ALTER TABLE public.ordenes_distribucion
  ADD COLUMN IF NOT EXISTS es_saldo_inicial boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.ordenes_distribucion.es_saldo_inicial IS
  'Deuda previa del cliente (cuenta inicial). Sin productos, sin radar ni inventario; el monto está en total_recaudar_usd.';

-- crear_o_obtener_radar / sincronizar radar vinculan por fecha y despachador.
CREATE OR REPLACE FUNCTION public.lt_ordenes_saldo_inicial_sin_radar()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  NEW.radar_id := NULL;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ordenes_saldo_inicial_sin_radar ON public.ordenes_distribucion;
CREATE TRIGGER trg_ordenes_saldo_inicial_sin_radar
  BEFORE INSERT OR UPDATE OF radar_id ON public.ordenes_distribucion
  FOR EACH ROW
  WHEN (NEW.es_saldo_inicial AND NEW.radar_id IS NOT NULL)
  EXECUTE FUNCTION public.lt_ordenes_saldo_inicial_sin_radar();

-- Firma anterior (solo deuda); se reemplaza por la que también carga vacíos.
DROP FUNCTION IF EXISTS public.registra_saldo_inicial_cliente(uuid, numeric, text, date);

CREATE OR REPLACE FUNCTION public.registra_saldo_inicial_cliente(
  p_cliente_id uuid,
  p_total_recaudar_usd numeric DEFAULT 0,
  p_factura_origen_numero text DEFAULT NULL,
  p_fecha_factura date DEFAULT CURRENT_DATE,
  p_cantidad_contenedores integer DEFAULT 0,
  p_contenedor_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_rol text;
  v_cliente record;
  v_factura text := NULLIF(btrim(p_factura_origen_numero), '');
  v_fecha date := COALESCE(p_fecha_factura, CURRENT_DATE);
  v_fecha_ts timestamptz;
  v_tasa numeric(14,4);
  v_monto numeric(14,2) := ROUND(COALESCE(p_total_recaudar_usd, 0), 2);
  v_cantidad integer := COALESCE(p_cantidad_contenedores, 0);
  v_contenedor_id uuid := p_contenedor_id;
  v_correlativo int;
  v_orden_id uuid;
  v_saldo_contenedores integer;
BEGIN
  v_rol := public.lt_current_user_rol();
  IF auth.uid() IS NULL OR v_rol IS NULL OR v_rol NOT IN ('admin', 'gerente') THEN
    RETURN jsonb_build_object('success', false, 'data', NULL, 'error', jsonb_build_object(
      'code', 'NO_AUTORIZADO', 'message', 'Solo admin o gerente pueden cargar cuentas iniciales.'));
  END IF;

  IF p_cliente_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'data', NULL, 'error', jsonb_build_object(
      'code', 'PARAMETRO_INVALIDO', 'message', 'Selecciona el cliente.'));
  END IF;

  IF v_monto < 0 OR v_cantidad < 0 THEN
    RETURN jsonb_build_object('success', false, 'data', NULL, 'error', jsonb_build_object(
      'code', 'PARAMETRO_INVALIDO', 'message', 'La deuda y los vacíos no pueden ser negativos.'));
  END IF;

  IF v_monto = 0 AND v_cantidad = 0 THEN
    RETURN jsonb_build_object('success', false, 'data', NULL, 'error', jsonb_build_object(
      'code', 'PARAMETRO_INVALIDO', 'message', 'Indica la deuda en USD, los vacíos o ambos.'));
  END IF;

  IF v_monto > 0 AND v_factura IS NULL THEN
    RETURN jsonb_build_object('success', false, 'data', NULL, 'error', jsonb_build_object(
      'code', 'PARAMETRO_INVALIDO', 'message', 'Indica el número de factura o documento de la deuda.'));
  END IF;
  IF length(v_factura) > 30 THEN
    RETURN jsonb_build_object('success', false, 'data', NULL, 'error', jsonb_build_object(
      'code', 'PARAMETRO_INVALIDO', 'message', 'El número de factura admite máximo 30 caracteres.'));
  END IF;

  IF v_fecha > CURRENT_DATE THEN
    RETURN jsonb_build_object('success', false, 'data', NULL, 'error', jsonb_build_object(
      'code', 'PARAMETRO_INVALIDO', 'message', 'La fecha no puede ser futura.'));
  END IF;

  SELECT id, vendedor_id, despachador_id, id_ruta
    INTO v_cliente
    FROM public.clientes
   WHERE id = p_cliente_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'data', NULL, 'error', jsonb_build_object(
      'code', 'CLIENTE_INEXISTENTE', 'message', 'El cliente no existe.'));
  END IF;

  IF v_cantidad > 0 THEN
    IF v_contenedor_id IS NULL THEN
      IF (SELECT count(*) FROM public.tipos_contenedores) <> 1 THEN
        RETURN jsonb_build_object('success', false, 'data', NULL, 'error', jsonb_build_object(
          'code', 'PARAMETRO_INVALIDO', 'message', 'Selecciona el tipo de contenedor de los vacíos.'));
      END IF;
      SELECT id INTO v_contenedor_id FROM public.tipos_contenedores;
    ELSIF NOT EXISTS (SELECT 1 FROM public.tipos_contenedores WHERE id = v_contenedor_id) THEN
      RETURN jsonb_build_object('success', false, 'data', NULL, 'error', jsonb_build_object(
        'code', 'CONTENEDOR_INEXISTENTE', 'message', 'El tipo de contenedor no existe.'));
    END IF;
  END IF;

  IF v_monto > 0 AND EXISTS (
    SELECT 1 FROM public.ordenes_distribucion
     WHERE cliente_id = p_cliente_id
       AND es_saldo_inicial
       AND estado <> 'anulada'
       AND upper(factura_origen_numero) = upper(v_factura)
  ) THEN
    RETURN jsonb_build_object('success', false, 'data', NULL, 'error', jsonb_build_object(
      'code', 'DUPLICADO', 'message', 'Ese cliente ya tiene cargada la factura ' || v_factura || '.'));
  END IF;

  -- Mediodía de Caracas: la fecha no cambia al convertir a UTC.
  v_fecha_ts := (v_fecha + time '12:00') AT TIME ZONE 'America/Caracas';

  IF v_monto > 0 THEN
    SELECT tasa_cambio INTO v_tasa
      FROM public.tasa_cambio
     ORDER BY fecha_tasa DESC, created_at DESC
     LIMIT 1;
    v_tasa := COALESCE(v_tasa, 1.0000);

    v_orden_id := gen_random_uuid();
    v_correlativo := nextval('public.ordenes_distribucion_correlativo_seq');

    INSERT INTO public.ordenes_distribucion (
      id, correlativo, cliente_id, camion_id, vendedor_id, despachador_id, id_ruta,
      estado, es_autoventa, es_saldo_inicial, radar_id, fecha_despacho,
      peso_total_calculado, factura_origen_numero, creado_por, created_at,
      tasa_cambio, total_recaudar_usd, total_recaudar_bs
    ) VALUES (
      v_orden_id, v_correlativo, p_cliente_id, NULL, v_cliente.vendedor_id,
      v_cliente.despachador_id, v_cliente.id_ruta,
      'por_liquidar', false, true, NULL, v_fecha_ts,
      0, v_factura, auth.uid(), v_fecha_ts,
      v_tasa, v_monto, ROUND(v_monto * v_tasa, 2)
    );
  END IF;

  -- Sin orden_id: el recálculo de envases por orden (despacho de radar) no lo toca.
  IF v_cantidad > 0 THEN
    INSERT INTO public.movimientos_contenedores (
      cliente_id, orden_id, contenedor_id, cantidad_entregada, cantidad_retirada, creado_por, created_at
    ) VALUES (
      p_cliente_id, NULL, v_contenedor_id, v_cantidad, 0, auth.uid(), v_fecha_ts
    );

    INSERT INTO public.saldo_contenedores_clientes (cliente_id, contenedor_id, saldo_pendiente, updated_at)
    VALUES (p_cliente_id, v_contenedor_id, v_cantidad, now())
    ON CONFLICT (cliente_id, contenedor_id) DO UPDATE
      SET saldo_pendiente = public.saldo_contenedores_clientes.saldo_pendiente + EXCLUDED.saldo_pendiente,
          updated_at = now()
    RETURNING saldo_pendiente INTO v_saldo_contenedores;
  END IF;

  RETURN jsonb_build_object('success', true, 'error', NULL, 'data', jsonb_build_object(
    'orden_id', v_orden_id,
    'correlativo', v_correlativo,
    'factura_origen_numero', v_factura,
    'total_recaudar_usd', v_monto,
    'fecha_factura', v_fecha,
    'contenedor_id', v_contenedor_id,
    'cantidad_contenedores', v_cantidad,
    'saldo_contenedores', v_saldo_contenedores));
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'data', NULL, 'error', jsonb_build_object(
    'code', SQLSTATE, 'message', SQLERRM));
END;
$$;

REVOKE ALL ON FUNCTION public.registra_saldo_inicial_cliente(uuid, numeric, text, date, integer, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.registra_saldo_inicial_cliente(uuid, numeric, text, date, integer, uuid) TO authenticated, service_role;
