


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE OR REPLACE FUNCTION "public"."actualiza_orden_distribucion_segun_correlativo"("p_correlativo" integer, "p_header" "jsonb", "p_detalle" "jsonb") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
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
    -- 1. Validar parámetros principales
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
                'message', 'No se encontró la orden con correlativo ' || p_correlativo::text,
                'details', NULL
            )
        );
    END IF;

    -- Validar que la orden esté en estado borrador o aprobada para modificación
    IF v_estado_actual NOT IN ('borrador', 'aprobada') THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo se pueden actualizar órdenes en estado borrador o aprobada. Estado actual: ' || v_estado_actual,
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
                    'message', 'Un vendedor solo puede actualizar las órdenes que él mismo ha registrado.',
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


ALTER FUNCTION "public"."actualiza_orden_distribucion_segun_correlativo"("p_correlativo" integer, "p_header" "jsonb", "p_detalle" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."actualiza_registro_cliente_segun_uuid"("p_id" "uuid", "p_rif_nit" "text" DEFAULT NULL::"text", "p_razon_social" "text" DEFAULT NULL::"text", "p_direccion_fiscal" "text" DEFAULT NULL::"text", "p_telefono" "text" DEFAULT NULL::"text", "p_movil1" "text" DEFAULT NULL::"text", "p_movil2" "text" DEFAULT NULL::"text", "p_movil3" "text" DEFAULT NULL::"text", "p_correo_e" "text" DEFAULT NULL::"text", "p_cond_liq" numeric DEFAULT NULL::numeric, "p_max_liq" numeric DEFAULT NULL::numeric, "p_vendedor_id" "uuid" DEFAULT NULL::"uuid", "p_despachador_id" "uuid" DEFAULT NULL::"uuid", "p_id_ruta" "uuid" DEFAULT NULL::"uuid", "p_activo" boolean DEFAULT NULL::boolean) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_cliente_actualizado RECORD;
BEGIN
    -- Validar que el id del cliente no sea nulo
    IF p_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El parámetro p_id es obligatorio.'
            )
        );
    END IF;

    -- Verificar si el cliente existe
    IF NOT EXISTS (SELECT 1 FROM public.clientes WHERE id = p_id) THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'CLIENTE_INEXISTENTE',
                'message', 'No se encontró ningún cliente con el ID especificado.'
            )
        );
    END IF;

    -- Validar si el RIF/NIT ingresado ya pertenece a otro cliente
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

    -- Actualizar el registro en la tabla clientes
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
        activo = COALESCE(p_activo, activo)
    WHERE id = p_id
    RETURNING id, rif_nit, razon_social, direccion_fiscal, telefono, movil1, movil2, movil3, 
              correo_e, cond_liq, max_liq, vendedor_id, despachador_id, id_ruta, activo, created_at
    INTO v_cliente_actualizado;

    -- Retornar éxito
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


ALTER FUNCTION "public"."actualiza_registro_cliente_segun_uuid"("p_id" "uuid", "p_rif_nit" "text", "p_razon_social" "text", "p_direccion_fiscal" "text", "p_telefono" "text", "p_movil1" "text", "p_movil2" "text", "p_movil3" "text", "p_correo_e" "text", "p_cond_liq" numeric, "p_max_liq" numeric, "p_vendedor_id" "uuid", "p_despachador_id" "uuid", "p_id_ruta" "uuid", "p_activo" boolean) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."actualiza_registro_cliente_segun_uuid"("p_id" "uuid", "p_rif_nit" "text", "p_razon_social" "text", "p_direccion_fiscal" "text", "p_telefono" "text", "p_movil1" "text", "p_movil2" "text", "p_movil3" "text", "p_correo_e" "text", "p_cond_liq" numeric, "p_max_liq" numeric, "p_vendedor_id" "uuid", "p_despachador_id" "uuid", "p_id_ruta" "uuid", "p_activo" boolean) IS 'Actualiza la información de un cliente existente en la tabla clientes según su ID (UUID)';



CREATE OR REPLACE FUNCTION "public"."actualiza_registro_cliente_segun_uuid"("p_id" "uuid", "p_rif_nit" "text" DEFAULT NULL::"text", "p_razon_social" "text" DEFAULT NULL::"text", "p_direccion_fiscal" "text" DEFAULT NULL::"text", "p_telefono" "text" DEFAULT NULL::"text", "p_movil1" "text" DEFAULT NULL::"text", "p_movil2" "text" DEFAULT NULL::"text", "p_movil3" "text" DEFAULT NULL::"text", "p_correo_e" "text" DEFAULT NULL::"text", "p_cond_liq" numeric DEFAULT NULL::numeric, "p_max_liq" numeric DEFAULT NULL::numeric, "p_vendedor_id" "uuid" DEFAULT NULL::"uuid", "p_despachador_id" "uuid" DEFAULT NULL::"uuid", "p_id_ruta" "uuid" DEFAULT NULL::"uuid", "p_activo" boolean DEFAULT NULL::boolean, "p_limite_credito" numeric DEFAULT NULL::numeric, "p_max_facturas_vencidas" integer DEFAULT NULL::integer, "p_permiso_despacho_manual" boolean DEFAULT NULL::boolean, "p_excepcion_despacho_gerencia" boolean DEFAULT NULL::boolean) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
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


ALTER FUNCTION "public"."actualiza_registro_cliente_segun_uuid"("p_id" "uuid", "p_rif_nit" "text", "p_razon_social" "text", "p_direccion_fiscal" "text", "p_telefono" "text", "p_movil1" "text", "p_movil2" "text", "p_movil3" "text", "p_correo_e" "text", "p_cond_liq" numeric, "p_max_liq" numeric, "p_vendedor_id" "uuid", "p_despachador_id" "uuid", "p_id_ruta" "uuid", "p_activo" boolean, "p_limite_credito" numeric, "p_max_facturas_vencidas" integer, "p_permiso_despacho_manual" boolean, "p_excepcion_despacho_gerencia" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."actualiza_registro_rutas_segun_uuid"("p_id_ruta" "uuid", "p_nombre_ruta" "text", "p_descripcion_ruta" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_ruta_actualizada RECORD;
BEGIN
    -- Validar que el id_ruta no sea nulo
    IF p_id_ruta IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El parámetro p_id_ruta es obligatorio.'
            )
        );
    END IF;

    -- Validar que el nombre_ruta no esté vacío
    IF p_nombre_ruta IS NULL OR TRIM(p_nombre_ruta) = '' THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El parámetro p_nombre_ruta es obligatorio y no puede estar vacío.'
            )
        );
    END IF;

    -- Verificar si la ruta existe
    IF NOT EXISTS (SELECT 1 FROM public.rutas WHERE id_ruta = p_id_ruta) THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'RUTA_INEXISTENTE',
                'message', 'No se encontró ninguna ruta con el id_ruta especificado.'
            )
        );
    END IF;

    -- Actualizar el registro en la tabla rutas
    UPDATE public.rutas
    SET nombre_ruta = TRIM(p_nombre_ruta),
        descripcion_ruta = p_descripcion_ruta
    WHERE id_ruta = p_id_ruta
    RETURNING id_ruta, nombre_ruta, descripcion_ruta, created_at
    INTO v_ruta_actualizada;

    -- Retornar éxito
    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Ruta actualizada exitosamente.',
        'data', jsonb_build_object(
            'id_ruta', v_ruta_actualizada.id_ruta,
            'nombre_ruta', v_ruta_actualizada.nombre_ruta,
            'descripcion_ruta', v_ruta_actualizada.descripcion_ruta,
            'created_at', v_ruta_actualizada.created_at
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


ALTER FUNCTION "public"."actualiza_registro_rutas_segun_uuid"("p_id_ruta" "uuid", "p_nombre_ruta" "text", "p_descripcion_ruta" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."actualiza_registro_rutas_segun_uuid"("p_id_ruta" "uuid", "p_nombre_ruta" "text", "p_descripcion_ruta" "text") IS 'Actualiza el nombre y descripción de una ruta existente identificada por su id_ruta (UUID)';



CREATE OR REPLACE FUNCTION "public"."actualizar_cuenta_bancaria_empresa"("p_id" "uuid", "p_cuenta_bancaria" "text" DEFAULT NULL::"text", "p_entidad_bancaria" "text" DEFAULT NULL::"text", "p_status_cuenta" boolean DEFAULT NULL::boolean) RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_rec RECORD;
BEGIN
    IF p_id IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID de la cuenta bancaria es requerido.'
            )
        );
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.cuentas_bancarias_empresa WHERE id = p_id) THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'CUENTA_INEXISTENTE',
                'message', 'La cuenta bancaria especificada no existe.'
            )
        );
    END IF;

    IF p_cuenta_bancaria IS NOT NULL AND TRIM(p_cuenta_bancaria) <> '' THEN
        IF EXISTS (SELECT 1 FROM public.cuentas_bancarias_empresa WHERE cuenta_bancaria = TRIM(p_cuenta_bancaria) AND id <> p_id) THEN
            RETURN json_build_object(
                'success', false,
                'data', NULL,
                'error', json_build_object(
                    'code', 'CUENTA_DUPLICADA',
                    'message', 'El número de cuenta especificado pertenece a otra cuenta registrada.'
                )
            );
        END IF;
    END IF;

    UPDATE public.cuentas_bancarias_empresa
    SET 
        cuenta_bancaria = COALESCE(NULLIF(TRIM(p_cuenta_bancaria), ''), cuenta_bancaria),
        entidad_bancaria = COALESCE(NULLIF(TRIM(p_entidad_bancaria), ''), entidad_bancaria),
        status_cuenta = COALESCE(p_status_cuenta, status_cuenta)
    WHERE id = p_id
    RETURNING id, cuenta_bancaria, entidad_bancaria, status_cuenta, created_at
    INTO v_rec;

    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'id', v_rec.id,
            'cuenta_bancaria', v_rec.cuenta_bancaria,
            'entidad_bancaria', v_rec.entidad_bancaria,
            'status_cuenta', v_rec.status_cuenta
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


ALTER FUNCTION "public"."actualizar_cuenta_bancaria_empresa"("p_id" "uuid", "p_cuenta_bancaria" "text", "p_entidad_bancaria" "text", "p_status_cuenta" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."actualizar_estado_orden_distribucion"("p_orden_id" "uuid", "p_estado" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_estado_actual TEXT;
    v_camion_id UUID;
    v_creado_por UUID;
    v_user_id UUID := auth.uid();
    v_item RECORD;
    v_producto_nombre TEXT;
    v_stock_disponible INT;
    v_stock_comprometido INT;
BEGIN
    IF p_orden_id IS NULL THEN
        RAISE EXCEPTION 'El ID de la orden es requerido.';
    END IF;

    IF p_estado IS NULL THEN
        RAISE EXCEPTION 'El estado de destino es requerido.';
    END IF;

    IF p_estado NOT IN ('borrador', 'lista_para_carga', 'en_transito', 'liquidada', 'anulada') THEN
        RAISE EXCEPTION 'El estado % no es un estado válido para la orden.', p_estado;
    END IF;

    SELECT estado, camion_id, creado_por 
    INTO v_estado_actual, v_camion_id, v_creado_por
    FROM public.ordenes_distribucion
    WHERE id = p_orden_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La orden de distribución con ID % no existe.', p_orden_id;
    END IF;

    IF public.user_has_role(ARRAY['vendedor']) AND NOT public.user_has_role(ARRAY['admin', 'gerente', 'despachador']) THEN
        IF v_user_id IS NOT NULL AND v_creado_por IS DISTINCT FROM v_user_id THEN
            RAISE EXCEPTION 'ACCESO_DENEGADO: Un vendedor solo puede modificar las órdenes que ha registrado.';
        END IF;
    END IF;

    IF v_estado_actual = p_estado THEN
        RETURN;
    END IF;

    IF v_estado_actual = 'borrador' AND p_estado NOT IN ('lista_para_carga', 'anulada') THEN
        RAISE EXCEPTION 'Transición no permitida: de % a %.', v_estado_actual, p_estado;
    ELSIF v_estado_actual = 'lista_para_carga' AND p_estado NOT IN ('en_transito', 'borrador', 'anulada') THEN
        RAISE EXCEPTION 'Transición no permitida: de % a %.', v_estado_actual, p_estado;
    ELSIF v_estado_actual = 'en_transito' AND p_estado NOT IN ('liquidada', 'anulada') THEN
        RAISE EXCEPTION 'Transición no permitida: de % a %.', v_estado_actual, p_estado;
    ELSIF v_estado_actual IN ('liquidada', 'anulada') THEN
        RAISE EXCEPTION 'No se pueden realizar cambios de estado en una orden %.', v_estado_actual;
    END IF;

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
                RAISE EXCEPTION 'El producto % no tiene un registro de inventario en almacén.', COALESCE(v_producto_nombre, v_item.producto_id::text);
            END IF;

            IF v_stock_disponible < v_item.cantidad_solicitada THEN
                SELECT nombre INTO v_producto_nombre FROM public.productos WHERE id = v_item.producto_id;
                RAISE EXCEPTION 'Stock insuficiente en almacén para el producto % (Disponible: %, Requerido: %).', 
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

    ELSIF v_estado_actual = 'lista_para_carga' AND p_estado = 'borrador' THEN
        FOR v_item IN 
            SELECT producto_id, cantidad_solicitada 
            FROM public.detalle_distribucion 
            WHERE orden_id = p_orden_id
        LOOP
            UPDATE public.inventario_almacen
            SET stock_disponible = stock_disponible + v_item.cantidad_solicitada,
                stock_comprometido = stock_comprometido - v_item.cantidad_solicitada,
                updated_at = NOW()
            WHERE producto_id = v_item.producto_id;
        END LOOP;

        UPDATE public.ordenes_distribucion
        SET estado = 'borrador'
        WHERE id = p_orden_id;

    ELSIF v_estado_actual = 'lista_para_carga' AND p_estado = 'en_transito' THEN
        IF v_camion_id IS NULL THEN
            RAISE EXCEPTION 'No se puede despachar la orden porque no tiene un camión asignado.';
        END IF;

        UPDATE public.camiones
        SET estado = 'en_ruta'
        WHERE id = v_camion_id;

        FOR v_item IN 
            SELECT producto_id, cantidad_solicitada 
            FROM public.detalle_distribucion 
            WHERE orden_id = p_orden_id
        LOOP
            UPDATE public.inventario_almacen
            SET stock_comprometido = stock_comprometido - v_item.cantidad_solicitada,
                updated_at = NOW()
            WHERE producto_id = v_item.producto_id;

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

        UPDATE public.ordenes_distribucion
        SET estado = 'en_transito',
            fecha_despacho = NOW()
        WHERE id = p_orden_id;

    ELSIF v_estado_actual = 'en_transito' AND p_estado = 'liquidada' THEN
        UPDATE public.camiones
        SET estado = 'disponible'
        WHERE id = v_camion_id;

        FOR v_item IN 
            SELECT producto_id, cantidad_despachada, COALESCE(estado_entrega, 'pendiente') as estado_entrega
            FROM public.detalle_distribucion 
            WHERE orden_id = p_orden_id
        LOOP
            IF v_item.estado_entrega IN ('entregado', 'pendiente', 'entregado_parcial') THEN
                UPDATE public.inventario_movil
                SET cantidad_cargada = cantidad_cargada - v_item.cantidad_despachada,
                    cantidad_entregada = cantidad_entregada + v_item.cantidad_despachada,
                    updated_at = NOW()
                WHERE camion_id = v_camion_id AND producto_id = v_item.producto_id;

            ELSIF v_item.estado_entrega = 'rechazado' THEN
                UPDATE public.inventario_movil
                SET cantidad_cargada = cantidad_cargada - v_item.cantidad_despachada,
                    cantidad_devolucion = cantidad_devolucion + v_item.cantidad_despachada,
                    updated_at = NOW()
                WHERE camion_id = v_camion_id AND producto_id = v_item.producto_id;

                UPDATE public.inventario_almacen
                SET stock_disponible = stock_disponible + v_item.cantidad_despachada,
                    updated_at = NOW()
                WHERE producto_id = v_item.producto_id;
            END IF;
        END LOOP;

        UPDATE public.ordenes_distribucion
        SET estado = 'liquidada'
        WHERE id = p_orden_id;

    ELSIF p_estado = 'anulada' THEN
        IF v_estado_actual = 'borrador' THEN
            NULL;

        ELSIF v_estado_actual = 'lista_para_carga' THEN
            FOR v_item IN 
                SELECT producto_id, cantidad_solicitada 
                FROM public.detalle_distribucion 
                WHERE orden_id = p_orden_id
            LOOP
                UPDATE public.inventario_almacen
                SET stock_disponible = stock_disponible + v_item.cantidad_solicitada,
                    stock_comprometido = stock_comprometido - v_item.cantidad_solicitada,
                    updated_at = NOW()
                WHERE producto_id = v_item.producto_id;
            END LOOP;

        ELSIF v_estado_actual = 'en_transito' THEN
            UPDATE public.camiones
            SET estado = 'disponible'
            WHERE id = v_camion_id;

            FOR v_item IN 
                SELECT producto_id, cantidad_despachada 
                FROM public.detalle_distribucion 
                WHERE orden_id = p_orden_id
            LOOP
                UPDATE public.inventario_movil
                SET cantidad_cargada = cantidad_cargada - v_item.cantidad_despachada,
                    updated_at = NOW()
                WHERE camion_id = v_camion_id AND producto_id = v_item.producto_id;

                UPDATE public.inventario_almacen
                SET stock_disponible = stock_disponible + v_item.cantidad_despachada,
                    updated_at = NOW()
                WHERE producto_id = v_item.producto_id;
            END LOOP;
        END IF;

        UPDATE public.ordenes_distribucion
        SET estado = 'anulada'
        WHERE id = p_orden_id;
    END IF;

END;
$$;


ALTER FUNCTION "public"."actualizar_estado_orden_distribucion"("p_orden_id" "uuid", "p_estado" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."actualizar_registro_perfil_usuarios_segun_id"("p_id" "uuid", "p_rol_id" "uuid", "p_nombre_completo" "text", "p_telefono" "text", "p_activo" boolean) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    UPDATE public.perfiles_usuario
    SET 
        rol_id = p_rol_id,
        nombre_completo = p_nombre_completo,
        telefono = p_telefono,
        activo = p_activo,
        updated_at = NOW()
    WHERE id = p_id;

    RETURN FOUND;
END;
$$;


ALTER FUNCTION "public"."actualizar_registro_perfil_usuarios_segun_id"("p_id" "uuid", "p_rol_id" "uuid", "p_nombre_completo" "text", "p_telefono" "text", "p_activo" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."actualizar_registro_productos_segun_id"("p_id" "uuid", "p_codigo_producto" "text", "p_nombre" "text", "p_codigo_barras" "text", "p_precio_lista1" numeric, "p_precio_lista2" numeric, "p_precio_lista3" numeric) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    UPDATE public.productos
    SET 
        codigo_producto = p_codigo_producto,
        nombre = p_nombre,
        codigo_barras = p_codigo_barras,
        precio_lista1 = p_precio_lista1,
        precio_lista2 = p_precio_lista2,
        precio_lista3 = p_precio_lista3
    WHERE id = p_id;

    RETURN FOUND;
END;
$$;


ALTER FUNCTION "public"."actualizar_registro_productos_segun_id"("p_id" "uuid", "p_codigo_producto" "text", "p_nombre" "text", "p_codigo_barras" "text", "p_precio_lista1" numeric, "p_precio_lista2" numeric, "p_precio_lista3" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."actualizar_registro_productos_segun_id"("p_id" "uuid", "p_codigo_producto" "text", "p_nombre" "text", "p_codigo_barras" "text" DEFAULT NULL::"text", "p_precio_lista1" numeric DEFAULT 0, "p_precio_lista2" numeric DEFAULT 0, "p_precio_lista3" numeric DEFAULT 0, "p_descripcion" "text" DEFAULT NULL::"text", "p_cant_unidad_medida" numeric DEFAULT NULL::numeric, "p_contenedor_id" "uuid" DEFAULT NULL::"uuid", "p_unidades_por_contenedor" numeric DEFAULT 1, "p_imagen_path" "text" DEFAULT NULL::"text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_codigo_barras TEXT;
BEGIN
    -- Tratar cadena vacía como NULL en codigo_barras para evitar violaciones de UNIQUE
    v_codigo_barras := NULLIF(TRIM(p_codigo_barras), '');

    UPDATE public.productos
    SET 
        codigo_producto = TRIM(p_codigo_producto),
        nombre = TRIM(p_nombre),
        codigo_barras = v_codigo_barras,
        precio_lista1 = COALESCE(p_precio_lista1, 0),
        precio_lista2 = COALESCE(p_precio_lista2, 0),
        precio_lista3 = COALESCE(p_precio_lista3, 0),
        descripcion = p_descripcion,
        cant_unidad_medida = p_cant_unidad_medida,
        contenedor_id = p_contenedor_id,
        unidades_por_contenedor = COALESCE(p_unidades_por_contenedor, 1),
        imagen_path = p_imagen_path
    WHERE id = p_id;

    RETURN FOUND;
END;
$$;


ALTER FUNCTION "public"."actualizar_registro_productos_segun_id"("p_id" "uuid", "p_codigo_producto" "text", "p_nombre" "text", "p_codigo_barras" "text", "p_precio_lista1" numeric, "p_precio_lista2" numeric, "p_precio_lista3" numeric, "p_descripcion" "text", "p_cant_unidad_medida" numeric, "p_contenedor_id" "uuid", "p_unidades_por_contenedor" numeric, "p_imagen_path" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."anular_orden_distribucion"("p_orden_id" "uuid") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_estado_actual TEXT;
    v_creado_por UUID;
    v_user_id UUID := auth.uid();
    v_item RECORD;
BEGIN
    -- Validar parámetros
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
                'message', 'La orden de distribución especificada no existe.',
                'details', NULL
            )
        );
    END IF;

    -- VALIDACIÓN DE PERMISOS POR ROL Y AUTORÍA (DB-012)
    IF public.user_has_role(ARRAY['vendedor']) AND NOT public.user_has_role(ARRAY['admin', 'gerente', 'despachador']) THEN
        IF v_user_id IS NOT NULL AND v_creado_por IS DISTINCT FROM v_user_id THEN
            RETURN json_build_object(
                'success', false,
                'data', NULL,
                'error', json_build_object(
                    'code', 'ACCESO_DENEGADO',
                    'message', 'Un vendedor solo puede anular las órdenes que ha registrado.',
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

    -- Si está aprobada / lista_para_carga, liberar reservas de inventario
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


ALTER FUNCTION "public"."anular_orden_distribucion"("p_orden_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."aprobar_despacho_orden_distribucion"("p_orden_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_estado_orden TEXT;
    v_cliente_id UUID;
    v_camion_id UUID;
    v_det RECORD;
    v_pendientes_count INT;
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

    SELECT estado, cliente_id, camion_id
    INTO v_estado_orden, v_cliente_id, v_camion_id
    FROM public.ordenes_distribucion
    WHERE id = p_orden_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'ORDEN_INEXISTENTE',
                'message', 'No se encontró la orden de distribución especificada.'
            )
        );
    END IF;

    IF v_estado_orden NOT IN ('en_transito', 'despachada') THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo se puede aprobar el despacho de órdenes en estado en_transito o despachada.',
                'details', 'Estado actual: ' || v_estado_orden
            )
        );
    END IF;

    SELECT COUNT(*) INTO v_pendientes_count
    FROM public.detalle_distribucion
    WHERE orden_id = p_orden_id AND (estado_entrega IS NULL OR estado_entrega = 'pendiente');

    IF v_pendientes_count > 0 THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'ENTREGA_INCOMPLETA',
                'message', 'La orden aún tiene productos pendientes por despachar en el radar.',
                'details', 'Líneas pendientes: ' || v_pendientes_count
            )
        );
    END IF;

    -- A. Reingresar mercancía devuelta del inventario móvil al almacén principal
    FOR v_det IN 
        SELECT producto_id, (cantidad_solicitada - COALESCE(cantidad_despachada, 0)) AS cantidad_devuelta
        FROM public.detalle_distribucion
        WHERE orden_id = p_orden_id AND (cantidad_solicitada - COALESCE(cantidad_despachada, 0)) > 0
    LOOP
        UPDATE public.inventario_almacen
        SET stock_disponible = stock_disponible + v_det.cantidad_devuelta,
            updated_at = NOW()
        WHERE producto_id = v_det.producto_id;

        UPDATE public.inventario_movil
        SET cantidad_devolucion = GREATEST(0, cantidad_devolucion - v_det.cantidad_devuelta),
            updated_at = NOW()
        WHERE camion_id = v_camion_id AND producto_id = v_det.producto_id;
    END LOOP;

    -- B. Trasladar envases retirados provisionales de detalle_distribucion a movimientos_contenedores y actualizar saldo del cliente
    FOR v_det IN
        SELECT contenedor_id, SUM(contenedores_retirados) AS total_retirados
        FROM public.detalle_distribucion
        WHERE orden_id = p_orden_id AND contenedor_id IS NOT NULL AND contenedores_retirados > 0
        GROUP BY contenedor_id
    LOOP
        INSERT INTO public.movimientos_contenedores (
            cliente_id,
            orden_id,
            contenedor_id,
            cantidad_entregada,
            cantidad_retirada,
            creado_por,
            created_at
        ) VALUES (
            v_cliente_id,
            p_orden_id,
            v_det.contenedor_id,
            0,
            v_det.total_retirados,
            auth.uid(),
            NOW()
        );

        INSERT INTO public.saldo_contenedores_clientes (
            cliente_id,
            contenedor_id,
            saldo_pendiente,
            updated_at
        ) VALUES (
            v_cliente_id,
            v_det.contenedor_id,
            0,
            NOW()
        )
        ON CONFLICT (cliente_id, contenedor_id)
        DO UPDATE SET
            saldo_pendiente = GREATEST(0, saldo_contenedores_clientes.saldo_pendiente - v_det.total_retirados),
            updated_at = NOW();
    END LOOP;

    -- C. Transicionar el estado de la orden a 'por_liquidar'
    UPDATE public.ordenes_distribucion
    SET estado = 'por_liquidar'
    WHERE id = p_orden_id;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Despacho de orden aprobado exitosamente. Orden pasa a estado por_liquidar.',
        'data', jsonb_build_object(
            'orden_id', p_orden_id,
            'nuevo_estado', 'por_liquidar'
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


ALTER FUNCTION "public"."aprobar_despacho_orden_distribucion"("p_orden_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."aprobar_despacho_orden_distribucion"("p_orden_id" "uuid") IS 'Aprueba el despacho físico de la orden al cierre de día, ajusta inventarios de almacén, registra movimientos de envases retirados y transiciona a por_liquidar';



CREATE OR REPLACE FUNCTION "public"."aprobar_orden_distribucion"("p_orden_id" "uuid") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_estado_actual TEXT;
    v_item RECORD;
    v_producto_nombre TEXT;
    v_stock_disponible INT;
BEGIN
    -- 1. Validaciones básicas
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
                'message', 'La orden de distribución especificada no existe.',
                'details', 'ID: ' || p_orden_id
            )
        );
    END IF;

    -- Validar que esté en estado 'borrador'
    IF v_estado_actual != 'borrador' THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo las órdenes en estado borrador pueden ser aprobadas.',
                'details', 'Estado actual: ' || v_estado_actual
            )
        );
    END IF;

    -- 2. Validar stock disponible para todos los detalles en almacén
    FOR v_item IN 
        SELECT d.producto_id, d.cantidad_solicitada, p.nombre
        FROM public.detalle_distribucion d
        JOIN public.productos p ON p.id = d.producto_id
        WHERE d.orden_id = p_orden_id
    LOOP
        -- Buscar stock disponible en el almacén principal
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
                    'message', 'El producto ' || v_item.nombre || ' no tiene registro de inventario en almacén.',
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
                    'message', 'Stock insuficiente en almacén para el producto: ' || v_item.nombre,
                    'details', 'Disponible: ' || v_stock_disponible || ', Solicitado: ' || v_item.cantidad_solicitada
                )
            );
        END IF;
    END LOOP;

    -- 3. Comprometer stock y cambiar estado (Transacción Atómica)
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


ALTER FUNCTION "public"."aprobar_orden_distribucion"("p_orden_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."asignar_usuario_empresa"("p_user_id" "uuid", "p_empresa_id" "uuid", "p_rol" character varying DEFAULT 'operador'::character varying) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_asignacion_id UUID;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.empresas WHERE id = p_empresa_id) THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', null,
            'error', jsonb_build_object(
                'code', 'EMPRESA_INEXISTENTE',
                'message', 'No se encontró la empresa especificada.',
                'details', null
            )
        );
    END IF;

    INSERT INTO public.usuarios_empresas (
        user_id,
        empresa_id,
        rol
    ) VALUES (
        p_user_id,
        p_empresa_id,
        p_rol
    )
    ON CONFLICT (user_id, empresa_id)
    DO UPDATE SET
        rol = EXCLUDED.rol
    RETURNING id INTO v_asignacion_id;

    RETURN jsonb_build_object(
        'success', true,
        'message', 'Usuario asignado a la empresa exitosamente.',
        'data', jsonb_build_object(
            'asignacion_id', v_asignacion_id,
            'user_id', p_user_id,
            'empresa_id', p_empresa_id,
            'rol', p_rol
        ),
        'error', null
    );
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false,
        'data', null,
        'error', jsonb_build_object(
            'code', 'DB_ERROR',
            'message', 'Error interno al asignar el usuario a la empresa.',
            'details', SQLERRM
        )
    );
END;
$$;


ALTER FUNCTION "public"."asignar_usuario_empresa"("p_user_id" "uuid", "p_empresa_id" "uuid", "p_rol" character varying) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."audit_changes_trigger"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
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

    -- Insertar en la tabla de logs de auditoría
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


ALTER FUNCTION "public"."audit_changes_trigger"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cambiar_status_cuenta_bancaria_empresa"("p_id" "uuid", "p_status_cuenta" boolean) RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    IF p_id IS NULL OR p_status_cuenta IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID de la cuenta y el estatus son requeridos.'
            )
        );
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.cuentas_bancarias_empresa WHERE id = p_id) THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'CUENTA_INEXISTENTE',
                'message', 'La cuenta bancaria especificada no existe.'
            )
        );
    END IF;

    UPDATE public.cuentas_bancarias_empresa
    SET status_cuenta = p_status_cuenta
    WHERE id = p_id;

    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'id', p_id,
            'status_cuenta', p_status_cuenta
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


ALTER FUNCTION "public"."cambiar_status_cuenta_bancaria_empresa"("p_id" "uuid", "p_status_cuenta" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cargar_inventario_movil"("p_orden_id" "uuid") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
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
                'message', 'La orden de distribución especificada no existe.',
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
                'message', 'No se puede despachar la orden porque no tiene un camión asignado.',
                'details', NULL
            )
        );
    END IF;

    FOR v_item IN 
        SELECT producto_id, cantidad_solicitada
        FROM public.detalle_distribucion
        WHERE orden_id = p_orden_id
    LOOP
        -- Descontar del almacén principal (sale físicamente del centro de distribución)
        UPDATE public.inventario_almacen
        SET stock_comprometido = GREATEST(0, stock_comprometido - v_item.cantidad_solicitada),
            stock_disponible = CASE 
                WHEN stock_comprometido < v_item.cantidad_solicitada 
                THEN GREATEST(0, stock_disponible - (v_item.cantidad_solicitada - stock_comprometido))
                ELSE stock_disponible 
            END,
            updated_at = NOW()
        WHERE producto_id = v_item.producto_id;

        -- Upsert en el inventario móvil del camión (suma a la cantidad cargada)
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


ALTER FUNCTION "public"."cargar_inventario_movil"("p_orden_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."consulta_registros_formas_pago"() RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
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


ALTER FUNCTION "public"."consulta_registros_formas_pago"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."crea_nueva_empresa"("p_codigo_empresa" character varying, "p_nombre_empresa" character varying, "p_supabase_url" "text", "p_supabase_anon_key" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_empresa_id UUID;
BEGIN
    IF EXISTS (SELECT 1 FROM public.empresas WHERE codigo_empresa = p_codigo_empresa) THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', null,
            'error', jsonb_build_object(
                'code', 'CODIGO_EMPRESA_DUPLICADO',
                'message', 'El código de empresa especificado ya existe en el sistema.',
                'details', null
            )
        );
    END IF;

    INSERT INTO public.empresas (
        codigo_empresa,
        nombre_empresa,
        supabase_url,
        supabase_anon_key
    ) VALUES (
        p_codigo_empresa,
        p_nombre_empresa,
        p_supabase_url,
        p_supabase_anon_key
    ) RETURNING id INTO v_empresa_id;

    RETURN jsonb_build_object(
        'success', true,
        'message', 'Empresa creada exitosamente.',
        'data', jsonb_build_object(
            'empresa_id', v_empresa_id,
            'codigo_empresa', p_codigo_empresa,
            'nombre_empresa', p_nombre_empresa
        ),
        'error', null
    );
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false,
        'data', null,
        'error', jsonb_build_object(
            'code', 'DB_ERROR',
            'message', 'Error interno al crear la empresa.',
            'details', SQLERRM
        )
    );
END;
$$;


ALTER FUNCTION "public"."crea_nueva_empresa"("p_codigo_empresa" character varying, "p_nombre_empresa" character varying, "p_supabase_url" "text", "p_supabase_anon_key" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."crear_cuenta_bancaria_empresa"("p_cuenta_bancaria" "text", "p_entidad_bancaria" "text") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_id UUID;
BEGIN
    IF p_cuenta_bancaria IS NULL OR TRIM(p_cuenta_bancaria) = '' THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El número de cuenta bancaria es requerido.'
            )
        );
    END IF;

    IF p_entidad_bancaria IS NULL OR TRIM(p_entidad_bancaria) = '' THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'La entidad bancaria es requerida.'
            )
        );
    END IF;

    IF EXISTS (SELECT 1 FROM public.cuentas_bancarias_empresa WHERE cuenta_bancaria = TRIM(p_cuenta_bancaria)) THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'CUENTA_DUPLICADA',
                'message', 'La cuenta bancaria especificada ya está registrada.'
            )
        );
    END IF;

    INSERT INTO public.cuentas_bancarias_empresa (
        cuenta_bancaria,
        entidad_bancaria,
        status_cuenta
    ) VALUES (
        TRIM(p_cuenta_bancaria),
        TRIM(p_entidad_bancaria),
        TRUE
    ) RETURNING id INTO v_id;

    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'id', v_id,
            'cuenta_bancaria', TRIM(p_cuenta_bancaria),
            'entidad_bancaria', TRIM(p_entidad_bancaria),
            'status_cuenta', true
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


ALTER FUNCTION "public"."crear_cuenta_bancaria_empresa"("p_cuenta_bancaria" "text", "p_entidad_bancaria" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."crear_o_obtener_radar"("p_despachador_id" "uuid" DEFAULT NULL::"uuid", "p_fecha_despacho" "date" DEFAULT CURRENT_DATE) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_despachador_id UUID;
    v_radar_id UUID;
    v_correlativo INT;
    v_status_radar BOOLEAN;
    v_tot_solicitada NUMERIC(10,0);
    v_tot_despachada NUMERIC(10,0);
    v_tot_retirados NUMERIC(10,0);
    v_total_ordenes INT;
    v_resultado JSONB;
BEGIN
    v_despachador_id := COALESCE(p_despachador_id, auth.uid());

    IF v_despachador_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_REQUERIDO',
                'message', 'Se requiere especificar un despachador_id o estar autenticado.'
            )
        );
    END IF;

    -- Verificar si existe un radar para este despachador y fecha
    SELECT id, correlativo, status_radar
    INTO v_radar_id, v_correlativo, v_status_radar
    FROM public.radars
    WHERE despachador_id = v_despachador_id
      AND fecha_despacho = p_fecha_despacho
    ORDER BY created_at DESC
    LIMIT 1;

    -- Si no existe, crearlo
    IF v_radar_id IS NULL THEN
        INSERT INTO public.radars (despachador_id, fecha_despacho, status_radar)
        VALUES (v_despachador_id, p_fecha_despacho, FALSE)
        RETURNING id, correlativo, status_radar INTO v_radar_id, v_correlativo, v_status_radar;
    END IF;

    -- EXCLUIR VENTA EN RUTA (es_autoventa = TRUE): No asociar órdenes de AutoVentas al Radar
    UPDATE public.ordenes_distribucion o
    SET radar_id = v_radar_id
    FROM public.clientes c
    WHERE o.cliente_id = c.id
      AND c.despachador_id = v_despachador_id
      AND o.fecha_despacho::date = p_fecha_despacho
      AND o.estado IN ('aprobada', 'en_transito', 'por_liquidar', 'liquidada', 'devuelta')
      AND (o.radar_id IS NULL OR o.radar_id = v_radar_id)
      AND COALESCE(o.es_autoventa, FALSE) = FALSE;

    -- Recalcular totales del radar
    SELECT 
        COALESCE(SUM(d.cantidad_solicitada), 0),
        COALESCE(SUM(d.cantidad_despachada), 0),
        COALESCE(SUM(d.contenedores_retirados), 0),
        COUNT(DISTINCT o.id)
    INTO v_tot_solicitada, v_tot_despachada, v_tot_retirados, v_total_ordenes
    FROM public.ordenes_distribucion o
    JOIN public.detalle_distribucion d ON d.orden_id = o.id
    WHERE o.radar_id = v_radar_id;

    UPDATE public.radars
    SET total_cantidad_solicitada = v_tot_solicitada,
        total_cantidad_despachada = v_tot_despachada,
        total_contenedores_retirados = v_tot_retirados
    WHERE id = v_radar_id;

    SELECT jsonb_build_object(
        'success', TRUE,
        'message', 'Radar obtenido/creado exitosamente.',
        'data', jsonb_build_object(
            'id', v_radar_id,
            'correlativo', v_correlativo,
            'despachador_id', v_despachador_id,
            'fecha_despacho', p_fecha_despacho,
            'status_radar', v_status_radar,
            'total_cantidad_solicitada', v_tot_solicitada,
            'total_cantidad_despachada', v_tot_despachada,
            'total_contenedores_retirados', v_tot_retirados,
            'total_ordenes', v_total_ordenes
        )
    ) INTO v_resultado;

    RETURN v_resultado;
END;
$$;


ALTER FUNCTION "public"."crear_o_obtener_radar"("p_despachador_id" "uuid", "p_fecha_despacho" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."crear_orden_distribucion"("p_vendedor_id" "uuid", "p_chofer_id" "uuid", "p_cliente_id" "uuid", "p_camion_id" "uuid", "p_productos_json" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_orden_id UUID;
    v_correlativo INT;
    v_factura_origen VARCHAR(30);
    v_peso_total NUMERIC(10,2) := 0.00;
    v_item JSONB;
    v_secuencia INT := 1;
    v_producto_id UUID;
    v_cantidad INT;
    v_precio_unitario NUMERIC(14,2);
    v_peso_unitario NUMERIC(10,2);
    v_subtotal NUMERIC(12,2);
BEGIN
    -- Validaciones básicas
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
        RETURN jsonb_build_object('success', false, 'message', 'El ID del camión es requerido.');
    END IF;

    IF p_productos_json IS NULL OR jsonb_array_length(p_productos_json) = 0 THEN
        RETURN jsonb_build_object('success', false, 'message', 'Debe incluir al menos un producto en la orden.');
    END IF;

    -- Validar existencia de entidades
    IF NOT EXISTS (SELECT 1 FROM public.perfiles_usuario WHERE id = p_vendedor_id) THEN
        RETURN jsonb_build_object('success', false, 'message', 'El vendedor especificado no existe.');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.choferes WHERE perfil_id = p_chofer_id) THEN
        RETURN jsonb_build_object('success', false, 'message', 'El chofer especificado no existe o no está registrado.');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.clientes WHERE id = p_cliente_id) THEN
        RETURN jsonb_build_object('success', false, 'message', 'El cliente especificado no existe.');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.camiones WHERE id = p_camion_id) THEN
        RETURN jsonb_build_object('success', false, 'message', 'El camión especificado no existe.');
    END IF;

    -- Generar correlativo y número de factura de origen automáticamente
    v_correlativo := nextval('public.ordenes_distribucion_correlativo_seq');
    v_factura_origen := 'FAC-' || LPAD(v_correlativo::text, 6, '0');
    v_orden_id := gen_random_uuid();

    -- Calcular peso total de la orden
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;
        
        IF v_cantidad <= 0 THEN
            RETURN jsonb_build_object('success', false, 'message', 'La cantidad del producto debe ser mayor a cero.');
        END IF;

        -- Obtener peso unitario del producto
        SELECT peso_unitario_kg INTO v_peso_unitario
        FROM public.productos
        WHERE id = v_producto_id;

        IF NOT FOUND THEN
            RETURN jsonb_build_object('success', false, 'message', 'El producto con ID ' || v_producto_id::text || ' no existe.');
        END IF;

        v_peso_total := v_peso_total + (COALESCE(v_peso_unitario, 0.00) * v_cantidad);
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
        created_at
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
        NOW()
    );

    -- Insertar Detalles de la Orden
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;
        v_precio_unitario := (v_item->>'precio_unitario')::NUMERIC;
        v_subtotal := v_cantidad * v_precio_unitario;

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
            motivo_rechazo
        ) VALUES (
            gen_random_uuid(),
            v_orden_id,
            v_producto_id,
            v_cantidad,
            0, -- Despachado inicialmente en 0, se actualiza al cambiar estado a en_transito
            v_precio_unitario,
            v_subtotal,
            v_secuencia,
            'pendiente',
            NULL
        );
        
        v_secuencia := v_secuencia + 1;
    END LOOP;

    RETURN jsonb_build_object(
        'success', true, 
        'message', 'Orden de distribución creada exitosamente.', 
        'orden_id', v_orden_id
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false, 
        'message', 'Error al crear la orden: ' || SQLERRM
    );
END;
$$;


ALTER FUNCTION "public"."crear_orden_distribucion"("p_vendedor_id" "uuid", "p_chofer_id" "uuid", "p_cliente_id" "uuid", "p_camion_id" "uuid", "p_productos_json" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."crear_orden_distribucion"("p_vendedor_id" "uuid", "p_cliente_id" "uuid", "p_camion_id" "uuid", "p_tasa_cambio" numeric DEFAULT NULL::numeric, "p_productos_json" "jsonb" DEFAULT '[]'::"jsonb", "p_despachador_id" "uuid" DEFAULT NULL::"uuid", "p_id_ruta" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_orden_id UUID;
    v_correlativo INT;
    v_factura_origen VARCHAR(30);
    v_tasa_cambio NUMERIC(14,4);
    
    v_vendedor_id UUID;
    v_despachador_id UUID;
    v_id_ruta UUID;
    
    v_peso_total NUMERIC(10,2) := 0.00;
    v_total_recaudar_usd NUMERIC(14,2) := 0.00;
    
    v_item JSONB;
    v_secuencia INT := 1;
    v_producto_id UUID;
    v_cantidad INT;
    
    v_val_usd_prod NUMERIC(14,2);
    v_val_usd NUMERIC(14,2);
    v_pct_desc NUMERIC(5,2) := 0.00;
    v_monto_desc_unit NUMERIC(14,2) := 0.00;
    v_subtotal_usd NUMERIC(14,2);
    v_peso_unitario NUMERIC(10,2);

    v_desc_rec RECORD;
BEGIN
    -- Validaciones básicas
    IF p_vendedor_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del vendedor es requerido.');
    END IF;

    IF p_cliente_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del cliente es requerido.');
    END IF;

    IF p_camion_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del camión es requerido.');
    END IF;

    IF p_productos_json IS NULL OR jsonb_array_length(p_productos_json) = 0 THEN
        RETURN jsonb_build_object('success', false, 'message', 'Debe incluir al menos un producto en la orden.');
    END IF;

    -- Obtener información del cliente (vendedor_id, despachador_id, id_ruta)
    SELECT c.vendedor_id, c.despachador_id, c.id_ruta
    INTO v_vendedor_id, v_despachador_id, v_id_ruta
    FROM public.clientes c
    WHERE c.id = p_cliente_id;

    -- Priorizar parámetros explícitos si fueron proporcionados
    v_vendedor_id := COALESCE(p_vendedor_id, v_vendedor_id);
    v_despachador_id := COALESCE(p_despachador_id, v_despachador_id);
    v_id_ruta := COALESCE(p_id_ruta, v_id_ruta);

    -- Validar existencia de entidades
    IF NOT EXISTS (SELECT 1 FROM public.perfiles_usuario WHERE id = p_vendedor_id) THEN
        RETURN jsonb_build_object('success', false, 'message', 'El vendedor especificado no existe.');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.clientes WHERE id = p_cliente_id) THEN
        RETURN jsonb_build_object('success', false, 'message', 'El cliente especificado no existe.');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.camiones WHERE id = p_camion_id) THEN
        RETURN jsonb_build_object('success', false, 'message', 'El camión especificado no existe.');
    END IF;

    -- Determinar / validar la tasa de cambio
    IF p_tasa_cambio IS NOT NULL AND p_tasa_cambio > 0 THEN
        v_tasa_cambio := p_tasa_cambio;
    ELSE
        SELECT tasa_cambio INTO v_tasa_cambio
        FROM public.tasa_cambio
        WHERE fecha_tasa = CURRENT_DATE;

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

    -- Generar correlativo y número de factura de origen automáticamente
    v_correlativo := nextval('public.ordenes_distribucion_correlativo_seq');
    v_factura_origen := 'FAC-' || LPAD(v_correlativo::text, 6, '0');
    v_orden_id := gen_random_uuid();

    -- Validar productos y calcular totales exclusivamente en USD y peso total
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;
        
        IF v_cantidad IS NULL OR v_cantidad <= 0 THEN
            RETURN jsonb_build_object('success', false, 'message', 'La cantidad del producto debe ser mayor a cero.');
        END IF;

        SELECT COALESCE(precio_lista1, 0.00), COALESCE(peso_unitario_kg, 0.00) 
        INTO v_val_usd_prod, v_peso_unitario
        FROM public.productos
        WHERE id = v_producto_id;

        IF NOT FOUND THEN
            RETURN jsonb_build_object('success', false, 'message', 'El producto con ID ' || v_producto_id::text || ' no existe.');
        END IF;

        -- Buscar descuento específico del cliente para este producto
        SELECT * INTO v_desc_rec
        FROM public.descuentos_cliente_producto
        WHERE cliente_id = p_cliente_id AND producto_id = v_producto_id AND activo = true;

        -- Resolver precio unitario en USD
        IF (v_item->>'valor_unitario_usd') IS NOT NULL THEN
            v_val_usd := (v_item->>'valor_unitario_usd')::NUMERIC;
        ELSIF (v_item->>'precio_unitario') IS NOT NULL THEN
            v_val_usd := (v_item->>'precio_unitario')::NUMERIC;
        ELSIF v_desc_rec.id IS NOT NULL THEN
            IF v_desc_rec.precio_pactado_usd IS NOT NULL THEN
                v_val_usd := v_desc_rec.precio_pactado_usd;
            ELSIF v_desc_rec.porcentaje_descuento > 0 THEN
                v_val_usd := ROUND(v_val_usd_prod * (1.00 - (v_desc_rec.porcentaje_descuento / 100.00)), 2);
            ELSE
                v_val_usd := v_val_usd_prod;
            END IF;
        ELSE
            v_val_usd := v_val_usd_prod;
        END IF;

        IF v_val_usd <= 0 OR (v_val_usd < 1.00 AND v_val_usd_prod >= 1.00) THEN
            v_val_usd := v_val_usd_prod;
        END IF;

        v_subtotal_usd := ROUND(v_cantidad * v_val_usd, 2);

        v_peso_total := v_peso_total + (COALESCE(v_peso_unitario, 0.00) * v_cantidad);
        v_total_recaudar_usd := v_total_recaudar_usd + v_subtotal_usd;
    END LOOP;

    -- Insertar Cabecera de la Orden con estado 'aprobada'
    INSERT INTO public.ordenes_distribucion (
        id,
        correlativo,
        cliente_id,
        camion_id,
        vendedor_id,
        despachador_id,
        id_ruta,
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
        v_vendedor_id,
        v_despachador_id,
        v_id_ruta,
        'aprobada',
        NULL,
        v_peso_total,
        v_factura_origen,
        p_vendedor_id,
        NOW(),
        v_tasa_cambio,
        NULL,
        v_total_recaudar_usd
    );

    -- Insertar Detalles de la Orden
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;
        
        SELECT COALESCE(precio_lista1, 0.00) INTO v_val_usd_prod
        FROM public.productos
        WHERE id = v_producto_id;

        -- Buscar descuento específico del cliente
        SELECT * INTO v_desc_rec
        FROM public.descuentos_cliente_producto
        WHERE cliente_id = p_cliente_id AND producto_id = v_producto_id AND activo = true;

        IF v_desc_rec.id IS NOT NULL THEN
            v_pct_desc := COALESCE(v_desc_rec.porcentaje_descuento, 0.00);
            IF v_desc_rec.precio_pactado_usd IS NOT NULL THEN
                v_val_usd := v_desc_rec.precio_pactado_usd;
                v_monto_desc_unit := GREATEST(0.00, v_val_usd_prod - v_val_usd);
            ELSIF v_desc_rec.porcentaje_descuento > 0 THEN
                v_val_usd := ROUND(v_val_usd_prod * (1.00 - (v_pct_desc / 100.00)), 2);
                v_monto_desc_unit := v_val_usd_prod - v_val_usd;
            ELSE
                v_val_usd := v_val_usd_prod;
                v_monto_desc_unit := 0.00;
            END IF;
        ELSE
            v_pct_desc := 0.00;
            v_monto_desc_unit := 0.00;
            v_val_usd := COALESCE((v_item->>'valor_unitario_usd')::NUMERIC, (v_item->>'precio_unitario')::NUMERIC, v_val_usd_prod);
        END IF;

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
            secuencia_entrega,
            estado_entrega,
            motivo_rechazo,
            valor_unitario_usd,
            subtotal_recaudar_usd,
            precio_lista_usd,
            porcentaje_descuento,
            monto_descuento_usd
        ) VALUES (
            gen_random_uuid(),
            v_orden_id,
            v_producto_id,
            v_cantidad,
            0,
            NULL,
            NULL,
            v_secuencia,
            'pendiente',
            NULL,
            v_val_usd,
            v_subtotal_usd,
            v_val_usd_prod,
            v_pct_desc,
            v_monto_desc_unit * v_cantidad
        );
        
        v_secuencia := v_secuencia + 1;
    END LOOP;

    RETURN jsonb_build_object(
        'success', true, 
        'message', 'Orden de distribución creada exitosamente.', 
        'orden_id', v_orden_id,
        'data', jsonb_build_object(
            'orden_id', v_orden_id,
            'correlativo', v_correlativo,
            'tasa_cambio', v_tasa_cambio,
            'total_recaudar_bs', NULL,
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


ALTER FUNCTION "public"."crear_orden_distribucion"("p_vendedor_id" "uuid", "p_cliente_id" "uuid", "p_camion_id" "uuid", "p_tasa_cambio" numeric, "p_productos_json" "jsonb", "p_despachador_id" "uuid", "p_id_ruta" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."crear_perfil_usuario_nuevo"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$DECLARE
    v_rol_id UUID;
BEGIN
    -- Buscamos el ID del rol 'chofer' por defecto para nuevos registros
    -- (Puedes cambiarlo según tu conveniencia o pasarlo en los metadata de auth)
    SELECT id INTO v_rol_id FROM public.roles WHERE nombre = 'chofer';

    INSERT INTO public.perfiles_usuario (id, rol_id, nombre_completo, telefono, activo)
    VALUES (
        NEW.id,
        v_rol_id,
        COALESCE(NEW.raw_user_meta_data->>'nombre_completo', 'Usuario Nuevo'),
        NEW.raw_user_meta_data->>'telefono',
        TRUE
    );
    RETURN NEW;
END;$$;


ALTER FUNCTION "public"."crear_perfil_usuario_nuevo"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."elimina_tasa_cambio"("p_fecha_tasa" "date") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
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
                'message', 'No se encontró ninguna tasa registrada para la fecha ' || p_fecha_tasa::text,
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


ALTER FUNCTION "public"."elimina_tasa_cambio"("p_fecha_tasa" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."guardar_resultado_despacho_radar"("p_radar_id" "uuid", "p_despacho_json" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_orden RECORD;
    v_detalle RECORD;
    v_cliente_id UUID;
    v_contenedor_id UUID;
    v_cant_entregada INT;
    v_cant_retirada INT;
    v_tot_solicitada NUMERIC(10,0);
    v_tot_despachada NUMERIC(10,0);
    v_tot_retirados NUMERIC(10,0);
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.radars WHERE id = p_radar_id) THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'RADAR_INEXISTENTE',
                'message', 'El radar especificado no existe.'
            )
        );
    END IF;

    -- Procesar cada orden entregada en el JSON
    FOR v_orden IN SELECT * FROM jsonb_to_recordset(p_despacho_json->'ordenes') AS x(orden_id UUID, detalles JSONB)
    LOOP
        -- Obtener el cliente de la orden
        SELECT cliente_id INTO v_cliente_id
        FROM public.ordenes_distribucion
        WHERE id = v_orden.orden_id;

        IF v_cliente_id IS NOT NULL THEN
            -- Recorrer detalles de la orden
            FOR v_detalle IN SELECT * FROM jsonb_to_recordset(v_orden.detalles) AS d(
                detalle_id UUID,
                cantidad_despachada NUMERIC,
                estado_entrega TEXT,
                motivo_rechazo TEXT,
                contenedores_retirados INT,
                contenedor_id UUID
            )
            LOOP
                -- Actualizar el renglón en detalle_distribucion
                UPDATE public.detalle_distribucion
                SET cantidad_despachada = COALESCE(v_detalle.cantidad_despachada, 0),
                    estado_entrega = COALESCE(v_detalle.estado_entrega, 'entregado'),
                    motivo_rechazo = v_detalle.motivo_rechazo,
                    contenedores_retirados = COALESCE(v_detalle.contenedores_retirados, 0),
                    contenedor_id = v_detalle.contenedor_id
                WHERE id = v_detalle.detalle_id;

                -- Identificar contenedor asociado al producto si no vino explícito
                v_contenedor_id := v_detalle.contenedor_id;
                IF v_contenedor_id IS NULL THEN
                    SELECT p.contenedor_id INTO v_contenedor_id
                    FROM public.detalle_distribucion dd
                    JOIN public.productos p ON dd.producto_id = p.id
                    WHERE dd.id = v_detalle.detalle_id;
                END IF;

                -- Calcular movimiento de contenedores
                IF v_contenedor_id IS NOT NULL THEN
                    v_cant_entregada := COALESCE(v_detalle.cantidad_despachada, 0)::INT;
                    v_cant_retirada := COALESCE(v_detalle.contenedores_retirados, 0);

                    IF v_cant_entregada > 0 OR v_cant_retirada > 0 THEN
                        INSERT INTO public.movimientos_contenedores (
                            cliente_id, orden_id, contenedor_id, cantidad_entregada, cantidad_retirada, creado_por
                        ) VALUES (
                            v_cliente_id, v_orden.orden_id, v_contenedor_id, v_cant_entregada, v_cant_retirada, auth.uid()
                        );
                    END IF;
                END IF;
            END LOOP;

            -- Actualizar estado de la orden a 'por_liquidar'
            UPDATE public.ordenes_distribucion
            SET estado = 'por_liquidar'
            WHERE id = v_orden.orden_id
              AND estado IN ('en_transito', 'aprobada');
        END IF;
    END LOOP;

    -- Actualizar totales globales del Radar y marcar status_radar = TRUE (.T.)
    SELECT 
        COALESCE(SUM(d.cantidad_solicitada), 0),
        COALESCE(SUM(d.cantidad_despachada), 0),
        COALESCE(SUM(d.contenedores_retirados), 0)
    INTO v_tot_solicitada, v_tot_despachada, v_tot_retirados
    FROM public.ordenes_distribucion o
    JOIN public.detalle_distribucion d ON d.orden_id = o.id
    WHERE o.radar_id = p_radar_id;

    UPDATE public.radars
    SET total_cantidad_solicitada = v_tot_solicitada,
        total_cantidad_despachada = v_tot_despachada,
        total_contenedores_retirados = v_tot_retirados,
        status_radar = TRUE
    WHERE id = p_radar_id;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Resultado del despacho registrado en el radar exitosamente.',
        'data', jsonb_build_object(
            'radar_id', p_radar_id,
            'status_radar', TRUE,
            'total_cantidad_solicitada', v_tot_solicitada,
            'total_cantidad_despachada', v_tot_despachada,
            'total_contenedores_retirados', v_tot_retirados
        )
    );
END;
$$;


ALTER FUNCTION "public"."guardar_resultado_despacho_radar"("p_radar_id" "uuid", "p_despacho_json" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."inserta_tasa_cambio"("p_fecha_tasa" "date", "p_tasa" numeric) RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    IF p_fecha_tasa IS NULL OR p_tasa IS NULL OR p_tasa <= 0 THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'La fecha y el monto de la tasa deben ser válidos y mayores a cero.',
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
                'message', 'Ya existe una tasa registrada para la fecha ' || p_fecha_tasa::text || '. Para modificarla, elimínela primero.',
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


ALTER FUNCTION "public"."inserta_tasa_cambio"("p_fecha_tasa" "date", "p_tasa" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."liquidar_orden_distribucion"("p_orden_id" "uuid") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_estado_orden TEXT;
    v_cliente_id UUID;
    v_camion_id UUID;
    v_subtotal_recaudar NUMERIC(12, 2) := 0.00;
    v_total_abonos_aprobados NUMERIC(12, 2) := 0.00;
BEGIN
    IF p_orden_id IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID de la orden es requerido.'
            )
        );
    END IF;

    SELECT estado, cliente_id, camion_id, COALESCE(total_recaudar_usd, 0.00)
    INTO v_estado_orden, v_cliente_id, v_camion_id, v_subtotal_recaudar
    FROM public.ordenes_distribucion
    WHERE id = p_orden_id;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'ORDEN_INEXISTENTE',
                'message', 'La orden de distribución especificada no existe.'
            )
        );
    END IF;

    IF v_estado_orden != 'por_liquidar' THEN
        RETURN json_build_object(
            'success', false,
            'error', json_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo se pueden evaluar o liquidar financieramente órdenes en estado por_liquidar.'
            )
        );
    END IF;

    SELECT COALESCE(SUM(dro.recaudado), 0.00)
    INTO v_total_abonos_aprobados
    FROM public.detalle_rendicion_ordenes dro
    JOIN public.rendiciones_cuentas rc ON dro.rendicion_id = rc.id
    WHERE dro.orden_distribucion_id = p_orden_id
      AND rc.estado = 'aprobada';

    IF v_total_abonos_aprobados >= v_subtotal_recaudar THEN
        IF v_camion_id IS NOT NULL THEN
            UPDATE public.camiones SET estado = 'disponible' WHERE id = v_camion_id;
        END IF;

        UPDATE public.ordenes_distribucion 
        SET estado = 'liquidada' 
        WHERE id = p_orden_id;

        RETURN json_build_object(
            'success', true,
            'data', json_build_object(
                'orden_id', p_orden_id,
                'nuevo_estado', 'liquidada',
                'total_recaudado', v_total_abonos_aprobados,
                'subtotal_recaudar', v_subtotal_recaudar
            ),
            'error', NULL
        );
    ELSE
        RETURN json_build_object(
            'success', true,
            'data', json_build_object(
                'orden_id', p_orden_id,
                'nuevo_estado', 'por_liquidar',
                'total_recaudado', v_total_abonos_aprobados,
                'subtotal_recaudar', v_subtotal_recaudar,
                'saldo_pendiente', (v_subtotal_recaudar - v_total_abonos_aprobados)
            ),
            'error', NULL
        );
    END IF;

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


ALTER FUNCTION "public"."liquidar_orden_distribucion"("p_orden_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."lt_can_finanzas"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT lt_current_user_rol() IN ('admin', 'gerente');
$$;


ALTER FUNCTION "public"."lt_can_finanzas"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."lt_current_user_rol"() RETURNS "text"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT r.nombre
  FROM perfiles_usuario p
  JOIN roles r ON r.id = p.rol_id
  WHERE p.id = auth.uid()
    AND COALESCE(p.activo, true) = true;
$$;


ALTER FUNCTION "public"."lt_current_user_rol"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."lt_is_admin"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT lt_current_user_rol() = 'admin';
$$;


ALTER FUNCTION "public"."lt_is_admin"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."lt_is_staff"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT lt_current_user_rol() IN ('admin', 'gerente', 'despachador');
$$;


ALTER FUNCTION "public"."lt_is_staff"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."on_rendicion_aprobada_trigger"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_item RECORD;
    v_res JSON;
BEGIN
    -- Solo actuar cuando el estado cambia a 'aprobada'
    IF NEW.estado = 'aprobada' AND (OLD.estado IS DISTINCT FROM 'aprobada') THEN
        -- Buscar todas las órdenes asociadas a esta rendición de cuentas
        FOR v_item IN 
            SELECT orden_distribucion_id 
            FROM public.detalle_rendicion_ordenes 
            WHERE rendicion_id = NEW.id
        LOOP
            -- Ejecutar liquidación de forma automática
            v_res := public.liquidar_orden_distribucion(v_item.orden_distribucion_id);
            
            -- Si falla, revertimos toda la transacción
            IF (v_res->>'success')::BOOLEAN = FALSE THEN
                RAISE EXCEPTION 'Fallo al liquidar automáticamente la orden %: %', 
                    v_item.orden_distribucion_id, v_res->'error'->>'message';
            END IF;
        END LOOP;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."on_rendicion_aprobada_trigger"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."otorgar_excepcion_despacho_gerencia"("p_cliente_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
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


ALTER FUNCTION "public"."otorgar_excepcion_despacho_gerencia"("p_cliente_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."procesar_log_auditoria"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_usuario_id UUID;
    v_valores_anteriores JSONB := NULL;
    v_valores_nuevos JSONB := NULL;
BEGIN
    -- 1. Intentar capturar el ID del usuario autenticado en Supabase
    -- auth.uid() es una función nativa de Supabase que extrae el ID del JWT de la sesión
    v_usuario_id := auth.uid();

    -- 2. Estructurar los datos según la operación realizada
    IF (TG_OP = 'UPDATE') THEN
        v_valores_anteriores := to_jsonb(OLD);
        v_valores_nuevos := to_jsonb(NEW);
    ELSIF (TG_OP = 'INSERT') THEN
        v_valores_nuevos := to_jsonb(NEW);
    ELSIF (TG_OP = 'DELETE') THEN
        v_valores_anteriores := to_jsonb(OLD);
    END IF;

    -- 3. Insertar el registro en la tabla de logs 
    INSERT INTO public.logs_auditoria (
        usuario_id,
        tabla_afectada,
        accion,
        registro_id,
        valores_anteriores,
        valores_nuevos
    ) VALUES (
        v_usuario_id,
        TG_TABLE_NAME::TEXT,
        TG_OP,
        COALESCE(NEW.id, OLD.id), -- Captura el ID del registro afectado independientemente de la acción
        v_valores_anteriores,
        v_valores_nuevos
    );

    -- En triggers del tipo AFTER, se retorna el registro tal cual
    IF (TG_OP = 'DELETE') THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$;


ALTER FUNCTION "public"."procesar_log_auditoria"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."reasignar_orden_a_radar"("p_orden_id" "uuid", "p_nuevo_radar_id" "uuid" DEFAULT NULL::"uuid", "p_nueva_fecha" "date" DEFAULT NULL::"date") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_radar_anterior_id UUID;
    v_estado_orden TEXT;
BEGIN
    SELECT radar_id, estado INTO v_radar_anterior_id, v_estado_orden
    FROM public.ordenes_distribucion
    WHERE id = p_orden_id;

    IF v_radar_anterior_id IS NULL AND v_estado_orden IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'ORDEN_INEXISTENTE',
                'message', 'La orden especificada no existe.'
            )
        );
    END IF;

    IF v_estado_orden = 'liquidada' THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'ORDEN_LIQUIDADA',
                'message', 'No se puede reasignar una orden que ya ha sido liquidada.'
            )
        );
    END IF;

    -- Actualizar la orden
    UPDATE public.ordenes_distribucion
    SET radar_id = p_nuevo_radar_id,
        fecha_despacho = COALESCE(p_nueva_fecha::timestamptz, fecha_despacho)
    WHERE id = p_orden_id;

    -- Recalcular totales en el radar anterior si existía
    IF v_radar_anterior_id IS NOT NULL THEN
        UPDATE public.radars
        SET total_cantidad_solicitada = (
                SELECT COALESCE(SUM(d.cantidad_solicitada), 0)
                FROM public.ordenes_distribucion o
                JOIN public.detalle_distribucion d ON d.orden_id = o.id
                WHERE o.radar_id = v_radar_anterior_id
            ),
            total_cantidad_despachada = (
                SELECT COALESCE(SUM(d.cantidad_despachada), 0)
                FROM public.ordenes_distribucion o
                JOIN public.detalle_distribucion d ON d.orden_id = o.id
                WHERE o.radar_id = v_radar_anterior_id
            ),
            total_contenedores_retirados = (
                SELECT COALESCE(SUM(d.contenedores_retirados), 0)
                FROM public.ordenes_distribucion o
                JOIN public.detalle_distribucion d ON d.orden_id = o.id
                WHERE o.radar_id = v_radar_anterior_id
            )
        WHERE id = v_radar_anterior_id;
    END IF;

    -- Recalcular totales en el nuevo radar si existe
    IF p_nuevo_radar_id IS NOT NULL THEN
        UPDATE public.radars
        SET total_cantidad_solicitada = (
                SELECT COALESCE(SUM(d.cantidad_solicitada), 0)
                FROM public.ordenes_distribucion o
                JOIN public.detalle_distribucion d ON d.orden_id = o.id
                WHERE o.radar_id = p_nuevo_radar_id
            ),
            total_cantidad_despachada = (
                SELECT COALESCE(SUM(d.cantidad_despachada), 0)
                FROM public.ordenes_distribucion o
                JOIN public.detalle_distribucion d ON d.orden_id = o.id
                WHERE o.radar_id = p_nuevo_radar_id
            ),
            total_contenedores_retirados = (
                SELECT COALESCE(SUM(d.contenedores_retirados), 0)
                FROM public.ordenes_distribucion o
                JOIN public.detalle_distribucion d ON d.orden_id = o.id
                WHERE o.radar_id = p_nuevo_radar_id
            )
        WHERE id = p_nuevo_radar_id;
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Orden reasignada exitosamente.',
        'data', jsonb_build_object(
            'orden_id', p_orden_id,
            'radar_id', p_nuevo_radar_id,
            'fecha_despacho', p_nueva_fecha
        )
    );
END;
$$;


ALTER FUNCTION "public"."reasignar_orden_a_radar"("p_orden_id" "uuid", "p_nuevo_radar_id" "uuid", "p_nueva_fecha" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."registra_nuevo_producto_retorna_id"("p_codigo_producto" "text", "p_nombre" "text", "p_codigo_barras" "text" DEFAULT NULL::"text", "p_descripcion" "text" DEFAULT NULL::"text", "p_cant_unidad_medida" numeric DEFAULT NULL::numeric, "p_precio_lista1" numeric DEFAULT 0, "p_precio_lista2" numeric DEFAULT 0, "p_precio_lista3" numeric DEFAULT 0, "p_contenedor_id" "uuid" DEFAULT NULL::"uuid", "p_unidades_por_contenedor" numeric DEFAULT 1, "p_imagen_path" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_new_id UUID;
    v_codigo_barras TEXT;
BEGIN
    -- Tratar cadena vacía como NULL en codigo_barras para evitar violaciones de UNIQUE
    v_codigo_barras := NULLIF(TRIM(p_codigo_barras), '');

    INSERT INTO public.productos (
        codigo_producto,
        nombre,
        codigo_barras,
        descripcion,
        cant_unidad_medida,
        precio_lista1,
        precio_lista2,
        precio_lista3,
        contenedor_id,
        unidades_por_contenedor,
        imagen_path
    )
    VALUES (
        TRIM(p_codigo_producto),
        TRIM(p_nombre),
        v_codigo_barras,
        p_descripcion,
        p_cant_unidad_medida,
        COALESCE(p_precio_lista1, 0),
        COALESCE(p_precio_lista2, 0),
        COALESCE(p_precio_lista3, 0),
        p_contenedor_id,
        COALESCE(p_unidades_por_contenedor, 1),
        p_imagen_path
    )
    RETURNING id INTO v_new_id;

    RETURN v_new_id;
END;
$$;


ALTER FUNCTION "public"."registra_nuevo_producto_retorna_id"("p_codigo_producto" "text", "p_nombre" "text", "p_codigo_barras" "text", "p_descripcion" "text", "p_cant_unidad_medida" numeric, "p_precio_lista1" numeric, "p_precio_lista2" numeric, "p_precio_lista3" numeric, "p_contenedor_id" "uuid", "p_unidades_por_contenedor" numeric, "p_imagen_path" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."registra_nuevo_usuario"("p_email" "text", "p_password" "text", "p_nombre_completo" "text", "p_telefono" "text", "p_rol_nombre" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth', 'extensions'
    AS $$
DECLARE
    v_user_id UUID;
    v_rol_id UUID;
    v_rol_normalizado TEXT;
    v_identity_id UUID;
BEGIN
    IF p_email IS NULL OR btrim(p_email) = '' THEN
        RETURN jsonb_build_object('success', false, 'message', 'El correo electrónico es requerido.');
    END IF;

    IF p_password IS NULL OR p_password = '' THEN
        RETURN jsonb_build_object('success', false, 'message', 'La contraseña es requerida.');
    END IF;

    IF p_nombre_completo IS NULL OR btrim(p_nombre_completo) = '' THEN
        RETURN jsonb_build_object('success', false, 'message', 'El nombre completo es requerido.');
    END IF;

    IF EXISTS (SELECT 1 FROM auth.users WHERE lower(email) = lower(btrim(p_email))) THEN
        RETURN jsonb_build_object('success', false, 'message', 'El correo electrónico ya está registrado.');
    END IF;

    v_rol_normalizado := lower(btrim(p_rol_nombre));

    SELECT id INTO v_rol_id FROM public.roles WHERE nombre = v_rol_normalizado;
    IF v_rol_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El rol ' || p_rol_nombre || ' no existe en el sistema.');
    END IF;

    v_user_id := gen_random_uuid();
    v_identity_id := gen_random_uuid();

    INSERT INTO auth.users (
        id, instance_id, email, encrypted_password, email_confirmed_at,
        created_at, updated_at, raw_app_meta_data, raw_user_meta_data,
        aud, role, is_super_admin, is_sso_user, is_anonymous,
        confirmation_token, recovery_token, email_change_token_new, email_change,
        email_change_token_current, phone_change, phone_change_token,
        reauthentication_token, email_change_confirm_status
    ) VALUES (
        v_user_id, '00000000-0000-0000-0000-000000000000', lower(btrim(p_email)),
        crypt(p_password, gen_salt('bf')), now(), now(), now(),
        jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email')),
        jsonb_build_object('full_name', btrim(p_nombre_completo)),
        'authenticated', 'authenticated', false, false, false,
        '', '', '', '', '', '', '', '', 0
    );

    INSERT INTO auth.identities (
        id, user_id, identity_data, provider, provider_id,
        last_sign_in_at, created_at, updated_at
    ) VALUES (
        v_identity_id, v_user_id,
        jsonb_build_object(
            'sub', v_user_id::text,
            'email', lower(btrim(p_email)),
            'email_verified', true,
            'phone_verified', false
        ),
        'email', v_user_id::text, now(), now(), now()
    );

    INSERT INTO public.perfiles_usuario (
        id, rol_id, nombre_completo, telefono, activo, updated_at
    ) VALUES (
        v_user_id, v_rol_id, btrim(p_nombre_completo), COALESCE(p_telefono, ''), true, now()
    )
    ON CONFLICT (id) DO UPDATE
    SET rol_id = EXCLUDED.rol_id,
        nombre_completo = EXCLUDED.nombre_completo,
        telefono = EXCLUDED.telefono,
        updated_at = now();

    RETURN jsonb_build_object(
        'success', true,
        'message', 'Usuario y perfil creados exitosamente.',
        'user_id', v_user_id
    );
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false,
        'message', 'Error en el registro del usuario: ' || SQLERRM
    );
END;
$$;


ALTER FUNCTION "public"."registra_nuevo_usuario"("p_email" "text", "p_password" "text", "p_nombre_completo" "text", "p_telefono" "text", "p_rol_nombre" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."registrar_despacho_cliente_radar"("p_orden_id" "uuid", "p_detalles_json" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
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

    -- Variables para procesamiento y resumen de saldos de contenedores
    v_rec_prev RECORD;
    v_rec_cont RECORD;
    v_saldo_previo INT;
    v_saldo_nuevo INT;
    v_cant_entregada INT;
    v_cant_retirada INT;
    v_contenedores_resumen JSONB := '[]'::JSONB;
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

    -- Obtener información de la orden, cliente y radar asociado
    SELECT o.estado, o.camion_id, o.cliente_id, o.radar_id,
           COALESCE(c.excepcion_despacho_gerencia, FALSE),
           TRUE
    INTO v_estado_orden, v_camion_id, v_cliente_id, v_radar_id, v_excepcion_gerencia, v_despacho_permitido
    FROM public.ordenes_distribucion o
    JOIN public.clientes c ON o.cliente_id = c.id
    WHERE o.id = p_orden_id;

    -- Desactivar temporalmente bloqueos por crédito: permitir despacho siempre
    v_despacho_permitido := TRUE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'ORDEN_INEXISTENTE',
                'message', 'No se encontró la orden especificada.'
            )
        );
    END IF;

    -- Validar si el radar asociado ya fue aprobado/cerrado por Gerencia (status_radar = TRUE)
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

    IF NOT v_despacho_permitido THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'DESPACHO_BLOQUEADO_CREDITO',
                'message', 'No se puede despachar la orden: El cliente se encuentra bloqueado por política de crédito y no posee una excepción gerencial activa.'
            )
        );
    END IF;

    IF v_estado_orden NOT IN ('en_transito', 'despachada', 'por_liquidar', 'devuelta') THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', jsonb_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo se pueden registrar entregas de órdenes activas en ruta.'
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

    -- =========================================================================
    -- PROCESAMIENTO Y ASIENTO DE SALDOS DE CONTENEDORES (AL MOMENTO DEL DESPACHO)
    -- =========================================================================
    -- 1. Reversar movimientos previos registrados para esta orden (para permitir re-edición idempotente)
    FOR v_rec_prev IN
        SELECT contenedor_id, cantidad_entregada, cantidad_retirada
        FROM public.movimientos_contenedores
        WHERE orden_id = p_orden_id
    LOOP
        UPDATE public.saldo_contenedores_clientes
        SET saldo_pendiente = GREATEST(0, saldo_pendiente - v_rec_prev.cantidad_entregada + v_rec_prev.cantidad_retirada),
            updated_at = NOW()
        WHERE cliente_id = v_cliente_id AND contenedor_id = v_rec_prev.contenedor_id;
    END LOOP;

    DELETE FROM public.movimientos_contenedores WHERE orden_id = p_orden_id;

    -- 2. Calcular entregas y retiros por tipo de contenedor asignado
    FOR v_rec_cont IN
        SELECT 
            COALESCE(d.contenedor_id, p.contenedor_id) AS contenedor_id,
            SUM(
                CASE 
                    WHEN COALESCE(d.contenedor_id, p.contenedor_id) IS NOT NULL AND COALESCE(d.cantidad_despachada, 0) > 0 THEN
                        CEIL(COALESCE(d.cantidad_despachada, 0)::numeric / GREATEST(COALESCE(p.unidades_por_contenedor, 1)::numeric, 1))
                    ELSE 0
                END
            )::INT AS total_entregados,
            SUM(COALESCE(d.contenedores_retirados, 0))::INT AS total_retirados
        FROM public.detalle_distribucion d
        LEFT JOIN public.productos p ON p.id = d.producto_id
        WHERE d.orden_id = p_orden_id
          AND COALESCE(d.contenedor_id, p.contenedor_id) IS NOT NULL
        GROUP BY COALESCE(d.contenedor_id, p.contenedor_id)
    LOOP
        v_cant_entregada := v_rec_cont.total_entregados;
        v_cant_retirada := v_rec_cont.total_retirados;

        IF v_cant_entregada > 0 OR v_cant_retirada > 0 THEN
            -- Obtener saldo anterior del cliente para este contenedor
            SELECT COALESCE(saldo_pendiente, 0)
            INTO v_saldo_previo
            FROM public.saldo_contenedores_clientes
            WHERE cliente_id = v_cliente_id AND contenedor_id = v_rec_cont.contenedor_id;

            IF NOT FOUND THEN
                v_saldo_previo := 0;
            END IF;

            v_saldo_nuevo := GREATEST(0, v_saldo_previo + v_cant_entregada - v_cant_retirada);

            -- Registrar movimiento individual
            INSERT INTO public.movimientos_contenedores (
                cliente_id, orden_id, contenedor_id, cantidad_entregada, cantidad_retirada, creado_por
            ) VALUES (
                v_cliente_id, p_orden_id, v_rec_cont.contenedor_id, v_cant_entregada, v_cant_retirada, auth.uid()
            );

            -- Upsert del saldo del cliente
            INSERT INTO public.saldo_contenedores_clientes (
                cliente_id, contenedor_id, saldo_pendiente, updated_at
            ) VALUES (
                v_cliente_id, v_rec_cont.contenedor_id, v_saldo_nuevo, NOW()
            )
            ON CONFLICT (cliente_id, contenedor_id)
            DO UPDATE SET
                saldo_pendiente = EXCLUDED.saldo_pendiente,
                updated_at = NOW();

            -- Construir resumen para el Frontend
            v_contenedores_resumen := v_contenedores_resumen || jsonb_build_object(
                'contenedor_id', v_rec_cont.contenedor_id,
                'saldo_anterior', v_saldo_previo,
                'cantidad_entregada', v_cant_entregada,
                'cantidad_retirada', v_cant_retirada,
                'saldo_actualizado', v_saldo_nuevo
            );
        END IF;
    END LOOP;

    -- Validar si quedan ítems pendientes en la orden
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
            'total_despachado', v_total_despachado,
            'contenedores_resumen', v_contenedores_resumen
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


ALTER FUNCTION "public"."registrar_despacho_cliente_radar"("p_orden_id" "uuid", "p_detalles_json" "jsonb") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."registrar_despacho_cliente_radar"("p_orden_id" "uuid", "p_detalles_json" "jsonb") IS 'Registra las entregas y el retiro provisional de envases del cliente desde la interfaz del despachador, cambiando la orden a por_liquidar';



CREATE OR REPLACE FUNCTION "public"."registrar_entrega_detalle"("p_detalle_id" "uuid", "p_cantidad_despachada" integer, "p_estado_entrega" "text", "p_motivo_rechazo" "text") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
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
    -- 1. Validaciones básicas
    IF p_detalle_id IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID del detalle de distribución es requerido.',
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

    -- Obtener información del detalle
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
                'message', 'El registro de detalle de distribución no existe.',
                'details', 'ID: ' || p_detalle_id
            )
        );
    END IF;

    -- Obtener información de la orden
    SELECT estado, camion_id
    INTO v_estado_orden, v_camion_id
    FROM public.ordenes_distribucion
    WHERE id = v_orden_id;

    -- Validar que la orden esté en tránsito
    IF v_estado_orden != 'en_transito' THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo se pueden registrar entregas para órdenes en estado en_transito.',
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

    -- 2. Procesamiento de Inventario Móvil
    -- Calcular la devolución
    v_devolucion := v_cantidad_solicitada - p_cantidad_despachada;

    -- Actualizar inventario móvil (resta de cantidad_cargada, suma a cantidad_entregada y cantidad_devolucion)
    UPDATE public.inventario_movil
    SET cantidad_cargada = cantidad_cargada - v_cantidad_solicitada,
        cantidad_entregada = cantidad_entregada + p_cantidad_despachada,
        cantidad_devolucion = cantidad_devolucion + v_devolucion,
        updated_at = NOW()
    WHERE camion_id = v_camion_id AND producto_id = v_producto_id;

    -- 3. Actualizar la línea de detalle
    UPDATE public.detalle_distribucion
    SET cantidad_despachada = p_cantidad_despachada,
        estado_entrega = p_estado_entrega,
        motivo_rechazo = p_motivo_rechazo
    WHERE id = p_detalle_id;

    -- 4. Verificar si todas las líneas están entregadas para transicionar la orden a 'por_liquidar'
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


ALTER FUNCTION "public"."registrar_entrega_detalle"("p_detalle_id" "uuid", "p_cantidad_despachada" integer, "p_estado_entrega" "text", "p_motivo_rechazo" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."registrar_movimiento_contenedores"("p_cliente_id" "uuid", "p_orden_id" "uuid", "p_contenedor_id" "uuid", "p_cantidad_entregada" integer, "p_cantidad_retirada" integer, "p_creado_por" "uuid") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_estado_orden TEXT;
    v_movimiento_id UUID;
BEGIN
    -- 1. Validaciones básicas
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
                'message', 'La orden de distribución especificada no existe.',
                'details', 'ID: ' || p_orden_id
            )
        );
    END IF;

    -- Validar que la orden esté en ruta o entregada en espera de conciliación
    IF v_estado_orden NOT IN ('en_transito', 'por_liquidar') THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'ESTADO_INVALIDO',
                'message', 'Solo se pueden registrar movimientos de envases para órdenes en tránsito o por liquidar.',
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


ALTER FUNCTION "public"."registrar_movimiento_contenedores"("p_cliente_id" "uuid", "p_orden_id" "uuid", "p_contenedor_id" "uuid", "p_cantidad_entregada" integer, "p_cantidad_retirada" integer, "p_creado_por" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."registrar_rendicion_cuentas"("p_cliente_id" "uuid", "p_observaciones" "text", "p_creado_por" "uuid", "p_ordenes" "jsonb", "p_pagos" "jsonb") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_rendicion_id UUID;
    v_total_ordenes NUMERIC(12, 2) := 0.00;
    v_total_pagos NUMERIC(12, 2) := 0.00;
    v_total_efectivo NUMERIC(12, 2) := 0.00;
    v_total_transferencias NUMERIC(12, 2) := 0.00;
    v_saldo_favor_usado NUMERIC(12, 2) := 0.00;
    v_cliente_saldo_favor NUMERIC(12, 2) := 0.00;
    v_item RECORD;
    v_pago RECORD;
    v_exceso NUMERIC(12, 2) := 0.00;
    v_fpago_concepto TEXT;
    v_fpago_info BOOLEAN;
BEGIN
    -- 1. Validaciones básicas
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

    -- Validar que el cliente exista y obtener saldo a favor actual
    SELECT COALESCE(saldo_favor, 0.00) 
    INTO v_cliente_saldo_favor 
    FROM public.clientes 
    WHERE id = p_cliente_id;

    IF NOT FOUND THEN
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
                'message', 'Debe registrar al menos una orden en el detalle de la rendición.',
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
                'message', 'Debe registrar al menos una forma de pago en la rendición.',
                'details', NULL
            )
        );
    END IF;

    -- 2. Calcular totales de órdenes
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_ordenes) AS x(orden_id UUID, monto_recaudado NUMERIC(12,2)) LOOP
        v_total_ordenes := v_total_ordenes + COALESCE(v_item.monto_recaudado, 0.00);
    END LOOP;

    -- 3. Validar y clasificar formas de pago
    FOR v_pago IN SELECT * FROM jsonb_to_recordset(p_pagos) AS y(fpago_id UUID, monto NUMERIC(12,2), referencia_bancaria TEXT, cuenta_bancaria TEXT, capture_url TEXT) LOOP
        v_total_pagos := v_total_pagos + COALESCE(v_pago.monto, 0.00);
        
        -- Obtener información de la forma de pago
        SELECT fpago_concepto, fpago_info 
        INTO v_fpago_concepto, v_fpago_info 
        FROM public.fpagos 
        WHERE fpago_id = v_pago.fpago_id;
        
        IF v_fpago_concepto IS NULL THEN
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

        -- Verificar si es uso de Saldo a Favor
        IF v_fpago_concepto ILIKE '%saldo%favor%' THEN
            v_saldo_favor_usado := v_saldo_favor_usado + COALESCE(v_pago.monto, 0.00);
        ELSIF v_fpago_info = FALSE THEN
            v_total_efectivo := v_total_efectivo + COALESCE(v_pago.monto, 0.00);
        ELSE
            v_total_transferencias := v_total_transferencias + COALESCE(v_pago.monto, 0.00);
        END IF;
    END LOOP;

    -- Validar si el saldo a favor usado excede el disponible del cliente
    IF v_saldo_favor_usado > v_cliente_saldo_favor THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'SALDO_FAVOR_INSUFICIENTE',
                'message', 'El saldo a favor utilizado (' || v_saldo_favor_usado || ') supera el saldo a favor disponible del cliente (' || v_cliente_saldo_favor || ').',
                'details', NULL
            )
        );
    END IF;

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

    -- 5. Registrar detalle de órdenes asociadas
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

    -- 7. Procesar uso de Saldo a Favor si aplica
    IF v_saldo_favor_usado > 0 THEN
        UPDATE public.clientes
        SET saldo_favor = saldo_favor - v_saldo_favor_usado
        WHERE id = p_cliente_id;

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
            -v_saldo_favor_usado,
            'cargo_pago_orden',
            'Uso de saldo a favor en rendición de cuentas ID: ' || v_rendicion_id,
            NOW()
        );
    END IF;

    -- 8. Manejo de Excedente de Pago (Crédito a Favor Generado)
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
            'Excedente en formas de pago de rendición de cuentas ID: ' || v_rendicion_id,
            NOW()
        );

        UPDATE public.clientes
        SET saldo_favor = COALESCE(saldo_favor, 0.00) + v_exceso
        WHERE id = p_cliente_id;
    END IF;

    -- 9. Retorno Exitoso
    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'rendicion_id', v_rendicion_id,
            'total_ordenes', v_total_ordenes,
            'total_pagos', v_total_pagos,
            'saldo_favor_usado', v_saldo_favor_usado,
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


ALTER FUNCTION "public"."registrar_rendicion_cuentas"("p_cliente_id" "uuid", "p_observaciones" "text", "p_creado_por" "uuid", "p_ordenes" "jsonb", "p_pagos" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."registrar_rendicion_cuentas"("p_cliente_id" "uuid", "p_observaciones" "text", "p_creado_por" "uuid", "p_ordenes" "jsonb", "p_pagos" "jsonb", "p_tasa_cambio" numeric DEFAULT NULL::numeric) RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_rendicion_id UUID;
    v_tasa_cambio NUMERIC(10, 4);
    v_total_ordenes NUMERIC(12, 2) := 0.00;
    v_total_ordenes_bs NUMERIC(12, 2) := 0.00;
    v_total_pagos NUMERIC(12, 2) := 0.00;
    v_total_pagos_bs NUMERIC(12, 2) := 0.00;
    v_total_efectivo NUMERIC(12, 2) := 0.00;
    v_total_transferencias NUMERIC(12, 2) := 0.00;
    v_saldo_favor_usado NUMERIC(12, 2) := 0.00;
    v_cliente_saldo_favor NUMERIC(12, 2) := 0.00;
    v_item RECORD;
    v_pago RECORD;
    v_exceso NUMERIC(12, 2) := 0.00;
    v_exceso_bs NUMERIC(12, 2) := 0.00;
    v_fpago_concepto TEXT;
    v_fpago_info BOOLEAN;
    v_item_usd NUMERIC(12, 2);
    v_item_bs NUMERIC(12, 2);
    v_rec_usd NUMERIC(12, 2);
    v_rec_bs NUMERIC(12, 2);
BEGIN
    -- 1. Validaciones básicas
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

    -- Determinar tasa de cambio
    IF p_tasa_cambio IS NOT NULL AND p_tasa_cambio > 0 THEN
        v_tasa_cambio := p_tasa_cambio;
    ELSE
        SELECT COALESCE(tasa_cambio, 1.0000) INTO v_tasa_cambio
        FROM public.tasa_cambio
        ORDER BY fecha_tasa DESC, created_at DESC
        LIMIT 1;

        IF v_tasa_cambio IS NULL THEN
            v_tasa_cambio := 1.0000;
        END IF;
    END IF;

    -- Validar que el cliente exista y obtener saldo a favor actual
    SELECT COALESCE(saldo_favor, 0.00) 
    INTO v_cliente_saldo_favor 
    FROM public.clientes 
    WHERE id = p_cliente_id;

    IF NOT FOUND THEN
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
                'message', 'Debe registrar al menos una orden en el detalle de la rendición.',
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
                'message', 'Debe registrar al menos una forma de pago en la rendición.',
                'details', NULL
            )
        );
    END IF;

    -- 2. Calcular totales de órdenes
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_ordenes) AS x(orden_id UUID, monto_recaudado NUMERIC(12,2), monto_recaudado_bs NUMERIC(12,2)) LOOP
        v_rec_usd := COALESCE(v_item.monto_recaudado, 0.00);
        v_rec_bs := COALESCE(v_item.monto_recaudado_bs, v_rec_usd * v_tasa_cambio);

        v_total_ordenes := v_total_ordenes + v_rec_usd;
        v_total_ordenes_bs := v_total_ordenes_bs + v_rec_bs;
    END LOOP;

    -- 3. Validar y clasificar formas de pago (USD y Bs)
    FOR v_pago IN SELECT * FROM jsonb_to_recordset(p_pagos) AS y(fpago_id UUID, monto NUMERIC(12,2), monto_bs NUMERIC(12,2), monto_usd NUMERIC(12,2), cuenta_bancaria_id UUID, referencia_bancaria TEXT, cuenta_bancaria TEXT, capture_url TEXT) LOOP
        -- Calcular valores en ambas monedas
        IF v_pago.monto_bs IS NOT NULL AND v_pago.monto_bs > 0 THEN
            v_item_bs := v_pago.monto_bs;
            v_item_usd := COALESCE(v_pago.monto_usd, v_item_bs / v_tasa_cambio);
        ELSE
            v_item_usd := COALESCE(v_pago.monto_usd, v_pago.monto, 0.00);
            v_item_bs := COALESCE(v_pago.monto_bs, v_item_usd * v_tasa_cambio);
        END IF;

        v_total_pagos := v_total_pagos + v_item_usd;
        v_total_pagos_bs := v_total_pagos_bs + v_item_bs;
        
        -- Obtener información de la forma de pago
        SELECT fpago_concepto, fpago_info 
        INTO v_fpago_concepto, v_fpago_info 
        FROM public.fpagos 
        WHERE fpago_id = v_pago.fpago_id;
        
        IF v_fpago_concepto IS NULL THEN
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

        -- Verificar si es uso de Saldo a Favor
        IF v_fpago_concepto ILIKE '%saldo%favor%' THEN
            v_saldo_favor_usado := v_saldo_favor_usado + v_item_usd;
        ELSIF v_fpago_info = FALSE THEN
            v_total_efectivo := v_total_efectivo + v_item_usd;
        ELSE
            v_total_transferencias := v_total_transferencias + v_item_usd;
        END IF;
    END LOOP;

    -- Validar si el saldo a favor usado excede el disponible del cliente
    IF v_saldo_favor_usado > v_cliente_saldo_favor THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'SALDO_FAVOR_INSUFICIENTE',
                'message', 'El saldo a favor utilizado (' || v_saldo_favor_usado || ') supera el saldo a favor disponible del cliente (' || v_cliente_saldo_favor || ').',
                'details', NULL
            )
        );
    END IF;

    -- 4. Crear el registro principal (Cabecera) en rendiciones_cuentas con estado = 'aprobada'
    INSERT INTO public.rendiciones_cuentas (
        cliente_id,
        fecha_rendicion,
        tasa_cambio,
        total_efectivo_recaudado,
        total_transferencias_recaudado,
        total_recaudado_bs,
        total_recaudado_usd,
        total_devoluciones_valoradas,
        estado,
        observaciones,
        auditado_por
    ) VALUES (
        p_cliente_id,
        NOW(),
        v_tasa_cambio,
        v_total_efectivo,
        v_total_transferencias,
        v_total_pagos_bs,
        v_total_pagos,
        0.00,
        'aprobada',
        p_observaciones,
        NULL
    ) RETURNING id INTO v_rendicion_id;

    -- 5. Registrar detalle de órdenes asociadas y actualizar estado de las órdenes
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_ordenes) AS x(orden_id UUID, monto_recaudado NUMERIC(12,2), monto_recaudado_bs NUMERIC(12,2)) LOOP
        v_rec_usd := COALESCE(v_item.monto_recaudado, 0.00);
        v_rec_bs := COALESCE(v_item.monto_recaudado_bs, v_rec_usd * v_tasa_cambio);

        INSERT INTO public.detalle_rendicion_ordenes (
            rendicion_id,
            orden_distribucion_id,
            recaudado,
            recaudado_bs
        ) VALUES (
            v_rendicion_id,
            v_item.orden_id,
            v_rec_usd,
            v_rec_bs
        );

        -- Evaluar y liquidar financieramente la orden de distribución
        PERFORM public.liquidar_orden_distribucion(v_item.orden_id);
    END LOOP;

    -- 6. Registrar formas de pago (detalle_rendicion_fpagos)
    FOR v_pago IN SELECT * FROM jsonb_to_recordset(p_pagos) AS y(fpago_id UUID, monto NUMERIC(12,2), monto_bs NUMERIC(12,2), monto_usd NUMERIC(12,2), cuenta_bancaria_id UUID, referencia_bancaria TEXT, cuenta_bancaria TEXT, capture_url TEXT) LOOP
        IF v_pago.monto_bs IS NOT NULL AND v_pago.monto_bs > 0 THEN
            v_item_bs := v_pago.monto_bs;
            v_item_usd := COALESCE(v_pago.monto_usd, v_item_bs / v_tasa_cambio);
        ELSE
            v_item_usd := COALESCE(v_pago.monto_usd, v_pago.monto, 0.00);
            v_item_bs := COALESCE(v_pago.monto_bs, v_item_usd * v_tasa_cambio);
        END IF;

        INSERT INTO public.detalle_rendicion_fpagos (
            rendicion_id,
            fpago_id,
            cuenta_bancaria_id,
            monto,
            monto_bs,
            monto_usd,
            referencia_bancaria,
            cuenta_bancaria,
            capture_url
        ) VALUES (
            v_rendicion_id,
            v_pago.fpago_id,
            v_pago.cuenta_bancaria_id,
            v_item_usd,
            v_item_bs,
            v_item_usd,
            v_pago.referencia_bancaria,
            v_pago.cuenta_bancaria,
            v_pago.capture_url
        );
    END LOOP;

    -- 7. Procesar uso de Saldo a Favor si aplica
    IF v_saldo_favor_usado > 0 THEN
        UPDATE public.clientes
        SET saldo_favor = saldo_favor - v_saldo_favor_usado
        WHERE id = p_cliente_id;

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
            -v_saldo_favor_usado,
            'cargo_pago_orden',
            'Uso de saldo a favor en rendición de cuentas ID: ' || v_rendicion_id,
            NOW()
        );
    END IF;

    -- 8. Manejo de Excedente de Pago (Crédito a Favor Generado)
    IF v_total_pagos > v_total_ordenes THEN
        v_exceso := v_total_pagos - v_total_ordenes;
        v_exceso_bs := v_total_pagos_bs - v_total_ordenes_bs;

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
            'Excedente en formas de pago de rendición de cuentas ID: ' || v_rendicion_id,
            NOW()
        );

        UPDATE public.clientes
        SET saldo_favor = COALESCE(saldo_favor, 0.00) + v_exceso
        WHERE id = p_cliente_id;
    END IF;

    -- 9. Retorno Exitoso
    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'rendicion_id', v_rendicion_id,
            'tasa_cambio', v_tasa_cambio,
            'total_ordenes', v_total_ordenes,
            'total_ordenes_bs', v_total_ordenes_bs,
            'total_pagos', v_total_pagos,
            'total_pagos_bs', v_total_pagos_bs,
            'saldo_favor_usado', v_saldo_favor_usado,
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


ALTER FUNCTION "public"."registrar_rendicion_cuentas"("p_cliente_id" "uuid", "p_observaciones" "text", "p_creado_por" "uuid", "p_ordenes" "jsonb", "p_pagos" "jsonb", "p_tasa_cambio" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."registrar_venta_en_ruta_autoventa"("p_vendedor_id" "uuid", "p_cliente_id" "uuid", "p_camion_id" "uuid", "p_productos_json" "jsonb" DEFAULT '[]'::"jsonb", "p_contenedores_json" "jsonb" DEFAULT '[]'::"jsonb", "p_observaciones" "text" DEFAULT NULL::"text", "p_tasa_cambio" numeric DEFAULT NULL::numeric) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_orden_id UUID;
    v_correlativo INT;
    v_factura_origen VARCHAR(30);
    v_tasa_cambio NUMERIC(14,4);
    
    v_vendedor_id UUID;
    v_despachador_id UUID;
    v_id_ruta UUID;
    v_camion_estado TEXT;
    
    v_peso_total NUMERIC(10,2) := 0.00;
    v_total_recaudar_usd NUMERIC(14,2) := 0.00;
    v_total_recaudar_bs NUMERIC(14,2) := 0.00;
    
    v_item JSONB;
    v_secuencia INT := 1;
    v_producto_id UUID;
    v_cantidad INT;
    v_stock_disponible_movil INT := 0;
    v_val_usd NUMERIC(14,2);
    v_val_usd_prod NUMERIC(14,2);
    v_subtotal_usd NUMERIC(14,2);
    v_peso_unitario NUMERIC(10,2);
    
    v_cont_item JSONB;
    v_cont_id UUID;
    v_cant_entregada INT;
    v_cant_retirada INT;
BEGIN
    -- Validaciones de parámetros
    IF p_vendedor_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del vendedor es requerido.');
    END IF;

    IF p_cliente_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del cliente es requerido.');
    END IF;

    IF p_camion_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del camión es requerido.');
    END IF;

    IF p_productos_json IS NULL OR jsonb_array_length(p_productos_json) = 0 THEN
        RETURN jsonb_build_object('success', false, 'message', 'Debe incluir al menos un producto en la orden de AutoVenta.');
    END IF;

    -- Validar existencia del camión y estado ('en_ruta' o 'asignado')
    SELECT estado INTO v_camion_estado
    FROM public.camiones
    WHERE id = p_camion_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'message', 'El camión especificado no existe.');
    END IF;

    IF v_camion_estado NOT IN ('en_ruta', 'asignado') THEN
        RETURN jsonb_build_object('success', false, 'message', 'El camión debe estar en ruta para registrar AutoVentas. Estado actual: ' || v_camion_estado);
    END IF;

    -- Obtener datos del cliente (vendedor, despachador, ruta)
    SELECT c.vendedor_id, c.despachador_id, c.id_ruta
    INTO v_vendedor_id, v_despachador_id, v_id_ruta
    FROM public.clientes c
    WHERE c.id = p_cliente_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'message', 'El cliente especificado no existe.');
    END IF;

    v_vendedor_id := COALESCE(p_vendedor_id, v_vendedor_id);

    -- Determinar tasa de cambio
    IF p_tasa_cambio IS NOT NULL AND p_tasa_cambio > 0 THEN
        v_tasa_cambio := p_tasa_cambio;
    ELSE
        SELECT tasa_cambio INTO v_tasa_cambio
        FROM public.tasa_cambio
        WHERE fecha_tasa = CURRENT_DATE;

        IF v_tasa_cambio IS NULL THEN
            SELECT tasa_cambio INTO v_tasa_cambio
            FROM public.tasa_cambio
            ORDER BY fecha_tasa DESC, created_at DESC
            LIMIT 1;
        END IF;

        IF v_tasa_cambio IS NULL THEN
            v_tasa_cambio := 1.0000;
        END IF;
    END IF;

    -- 1. Validar disponibilidad de stock en inventario_movil para cada producto
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;

        IF v_cantidad IS NULL OR v_cantidad <= 0 THEN
            RETURN jsonb_build_object('success', false, 'message', 'La cantidad solicitada para cada producto debe ser mayor a cero.');
        END IF;

        -- Consultar disponibilidad real en inventario_movil (cargado - entregado)
        SELECT (COALESCE(cantidad_cargada, 0) - COALESCE(cantidad_entregada, 0))
        INTO v_stock_disponible_movil
        FROM public.inventario_movil
        WHERE camion_id = p_camion_id AND producto_id = v_producto_id;

        IF v_stock_disponible_movil IS NULL THEN
            v_stock_disponible_movil := 0;
        END IF;

        IF v_stock_disponible_movil < v_cantidad THEN
            RETURN jsonb_build_object(
                'success', false,
                'message', 'Stock insuficiente en el camión para el producto seleccionado. Disponible: ' || v_stock_disponible_movil || ', Solicitado: ' || v_cantidad
            );
        END IF;
    END LOOP;

    -- 2. Generar correlativo e ID de orden
    v_correlativo := nextval('public.ordenes_distribucion_correlativo_seq');
    v_factura_origen := 'AV-' || LPAD(v_correlativo::text, 6, '0');
    v_orden_id := gen_random_uuid();

    -- 3. Calcular montos y pesos
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;

        SELECT COALESCE(precio_lista1, 0.00), COALESCE(peso_unitario_kg, 0.00) 
        INTO v_val_usd_prod, v_peso_unitario
        FROM public.productos
        WHERE id = v_producto_id;

        v_val_usd := COALESCE((v_item->>'valor_unitario_usd')::NUMERIC, (v_item->>'precio_unitario')::NUMERIC, v_val_usd_prod);
        IF v_val_usd <= 0 THEN
            v_val_usd := v_val_usd_prod;
        END IF;

        v_subtotal_usd := ROUND(v_cantidad * v_val_usd, 2);
        v_peso_total := v_peso_total + (COALESCE(v_peso_unitario, 0.00) * v_cantidad);
        v_total_recaudar_usd := v_total_recaudar_usd + v_subtotal_usd;
    END LOOP;

    v_total_recaudar_bs := ROUND(v_total_recaudar_usd * v_tasa_cambio, 2);

    -- 4. Insertar la orden en ordenes_distribucion (estado = 'por_liquidar', es_autoventa = TRUE, radar_id = NULL)
    INSERT INTO public.ordenes_distribucion (
        id,
        correlativo,
        cliente_id,
        camion_id,
        vendedor_id,
        despachador_id,
        id_ruta,
        estado,
        es_autoventa,
        radar_id,
        fecha_despacho,
        peso_total_calculado,
        factura_origen_numero,
        creado_por,
        created_at,
        tasa_cambio,
        total_recaudar_usd,
        total_recaudar_bs
    ) VALUES (
        v_orden_id,
        v_correlativo,
        p_cliente_id,
        p_camion_id,
        v_vendedor_id,
        v_despachador_id,
        v_id_ruta,
        'por_liquidar',
        TRUE,
        NULL,
        NOW(),
        v_peso_total,
        v_factura_origen,
        p_vendedor_id,
        NOW(),
        v_tasa_cambio,
        v_total_recaudar_usd,
        v_total_recaudar_bs
    );

    -- 5. Insertar detalles y actualizar inventario_movil (cantidad_entregada += v_cantidad)
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json) LOOP
        v_producto_id := (v_item->>'producto_id')::UUID;
        v_cantidad := (v_item->>'cantidad')::INT;

        SELECT COALESCE(precio_lista1, 0.00) INTO v_val_usd_prod FROM public.productos WHERE id = v_producto_id;
        v_val_usd := COALESCE((v_item->>'valor_unitario_usd')::NUMERIC, (v_item->>'precio_unitario')::NUMERIC, v_val_usd_prod);
        IF v_val_usd <= 0 THEN v_val_usd := v_val_usd_prod; END IF;
        v_subtotal_usd := ROUND(v_cantidad * v_val_usd, 2);

        INSERT INTO public.detalle_distribucion (
            id,
            orden_id,
            producto_id,
            cantidad_solicitada,
            cantidad_despachada,
            valor_unitario_usd,
            subtotal_recaudar_usd,
            secuencia_entrega,
            estado_entrega
        ) VALUES (
            gen_random_uuid(),
            v_orden_id,
            v_producto_id,
            v_cantidad,
            v_cantidad,
            v_val_usd,
            v_subtotal_usd,
            v_secuencia,
            'entregado'
        );

        v_secuencia := v_secuencia + 1;

        -- Incrementar cantidad_entregada en el inventario móvil del camión
        UPDATE public.inventario_movil
        SET cantidad_entregada = cantidad_entregada + v_cantidad,
            updated_at = NOW()
        WHERE camion_id = p_camion_id AND producto_id = v_producto_id;
    END LOOP;

    -- 6. Procesar movimiento de envases / contenedores si fueron suministrados
    IF p_contenedores_json IS NOT NULL AND jsonb_array_length(p_contenedores_json) > 0 THEN
        FOR v_cont_item IN SELECT * FROM jsonb_array_elements(p_contenedores_json) LOOP
            v_cont_id := (v_cont_item->>'contenedor_id')::UUID;
            v_cant_entregada := COALESCE((v_cont_item->>'cantidad_entregada')::INT, 0);
            v_cant_retirada := COALESCE((v_cont_item->>'cantidad_retirada')::INT, 0);

            IF v_cont_id IS NOT NULL AND (v_cant_entregada > 0 OR v_cant_retirada > 0) THEN
                -- Registro histórico del movimiento
                INSERT INTO public.movimientos_contenedores (
                    cliente_id,
                    orden_id,
                    contenedor_id,
                    cantidad_entregada,
                    cantidad_retirada,
                    created_at
                ) VALUES (
                    p_cliente_id,
                    v_orden_id,
                    v_cont_id,
                    v_cant_entregada,
                    v_cant_retirada,
                    NOW()
                );

                -- Actualización del saldo acumulado del cliente
                INSERT INTO public.saldo_contenedores_clientes (
                    cliente_id,
                    contenedor_id,
                    saldo_pendiente,
                    updated_at
                ) VALUES (
                    p_cliente_id,
                    v_cont_id,
                    GREATEST(0, v_cant_entregada - v_cant_retirada),
                    NOW()
                )
                ON CONFLICT (cliente_id, contenedor_id)
                DO UPDATE SET
                    saldo_pendiente = GREATEST(0, public.saldo_contenedores_clientes.saldo_pendiente + v_cant_entregada - v_cant_retirada),
                    updated_at = NOW();
            END IF;
        END LOOP;
    END IF;

    -- 7. Respuesta exitosa
    RETURN jsonb_build_object(
        'success', true,
        'message', 'Venta en ruta (AutoVenta) registrada exitosamente.',
        'data', jsonb_build_object(
            'orden_id', v_orden_id,
            'correlativo', v_correlativo,
            'factura_origen_numero', v_factura_origen,
            'cliente_id', p_cliente_id,
            'camion_id', p_camion_id,
            'estado', 'por_liquidar',
            'es_autoventa', true,
            'total_recaudar_usd', v_total_recaudar_usd,
            'total_recaudar_bs', v_total_recaudar_bs,
            'tasa_cambio', v_tasa_cambio
        ),
        'error', NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'SQL_ERROR',
                'message', SQLERRM,
                'details', 'SQLSTATE: ' || SQLSTATE
            )
        );
END;
$$;


ALTER FUNCTION "public"."registrar_venta_en_ruta_autoventa"("p_vendedor_id" "uuid", "p_cliente_id" "uuid", "p_camion_id" "uuid", "p_productos_json" "jsonb", "p_contenedores_json" "jsonb", "p_observaciones" "text", "p_tasa_cambio" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."reporte_formas_pago_rendicion"("p_fecha_desde" "date" DEFAULT NULL::"date", "p_fecha_hasta" "date" DEFAULT NULL::"date", "p_solo_bancarios" boolean DEFAULT false) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_fecha_desde DATE;
    v_fecha_hasta DATE;
    v_movimientos JSONB;
    v_total_registros INT := 0;
    v_monto_total_bs NUMERIC(14,2) := 0.00;
    v_monto_total_usd NUMERIC(14,2) := 0.00;
BEGIN
    v_fecha_desde := COALESCE(p_fecha_desde, date_trunc('month', CURRENT_DATE)::date);
    v_fecha_hasta := COALESCE(p_fecha_hasta, CURRENT_DATE);

    SELECT
        COUNT(*)::INT,
        COALESCE(SUM(dfp.monto_bs), 0.00),
        COALESCE(SUM(dfp.monto_usd), 0.00)
    INTO v_total_registros, v_monto_total_bs, v_monto_total_usd
    FROM public.detalle_rendicion_fpagos dfp
    JOIN public.rendiciones_cuentas rc ON dfp.rendicion_id = rc.id
    JOIN public.fpagos fp ON dfp.fpago_id = fp.fpago_id
    WHERE rc.fecha_rendicion::date >= v_fecha_desde
      AND rc.fecha_rendicion::date <= v_fecha_hasta
      AND rc.estado = 'aprobada'
      AND (p_solo_bancarios = FALSE OR fp.es_bancario = TRUE);

    SELECT jsonb_agg(
        jsonb_build_object(
            'rendicion_id', rc.id,
            'fecha_rendicion', rc.fecha_rendicion,
            'tasa_cambio', rc.tasa_cambio,
            'cliente_id', c.id,
            'cliente_nombre', c.razon_social,
            'cliente_rif', c.rif_nit,
            'fpago_id', fp.fpago_id,
            'fpago_concepto', fp.fpago_concepto,
            'es_bancario', fp.es_bancario,
            'referencia_bancaria', dfp.referencia_bancaria,
            'cuenta_bancaria', dfp.cuenta_bancaria,
            'capture_url', dfp.capture_url,
            'monto_bs', COALESCE(dfp.monto_bs, (dfp.monto_usd * COALESCE(rc.tasa_cambio, 0))),
            'monto_usd', dfp.monto_usd
        ) ORDER BY rc.fecha_rendicion DESC, dfp.id DESC
    ) INTO v_movimientos
    FROM public.detalle_rendicion_fpagos dfp
    JOIN public.rendiciones_cuentas rc ON dfp.rendicion_id = rc.id
    JOIN public.fpagos fp ON dfp.fpago_id = fp.fpago_id
    JOIN public.clientes c ON rc.cliente_id = c.id
    WHERE rc.fecha_rendicion::date >= v_fecha_desde
      AND rc.fecha_rendicion::date <= v_fecha_hasta
      AND rc.estado = 'aprobada'
      AND (p_solo_bancarios = FALSE OR fp.es_bancario = TRUE);

    RETURN jsonb_build_object(
        'success', true,
        'data', jsonb_build_object(
            'fecha_desde', v_fecha_desde,
            'fecha_hasta', v_fecha_hasta,
            'solo_bancarios', p_solo_bancarios,
            'total_registros', v_total_registros,
            'monto_total_bs', v_monto_total_bs,
            'monto_total_usd', v_monto_total_usd,
            'movimientos', COALESCE(v_movimientos, '[]'::jsonb)
        ),
        'error', NULL
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', false,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'SQL_ERROR',
                'message', SQLERRM,
                'details', 'SQLSTATE: ' || SQLSTATE
            )
        );
END;
$$;


ALTER FUNCTION "public"."reporte_formas_pago_rendicion"("p_fecha_desde" "date", "p_fecha_hasta" "date", "p_solo_bancarios" boolean) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."reporte_formas_pago_rendicion"("p_fecha_desde" "date", "p_fecha_hasta" "date", "p_solo_bancarios" boolean) IS 'Reporte gerencial de formas de pago en rendiciones aprobadas. Usa clientes.razon_social / rif_nit.';



CREATE OR REPLACE FUNCTION "public"."reporte_recaudaciones_gerenciales"("p_fecha_desde" "date" DEFAULT NULL::"date", "p_fecha_hasta" "date" DEFAULT NULL::"date") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_data JSON;
    v_desde TIMESTAMP WITH TIME ZONE;
    v_hasta TIMESTAMP WITH TIME ZONE;
BEGIN
    -- Configurar fechas por defecto si no son pasadas (mes actual)
    v_desde := COALESCE(p_fecha_desde::TIMESTAMP WITH TIME ZONE, date_trunc('month', CURRENT_DATE));
    v_hasta := COALESCE((p_fecha_hasta + INTERVAL '1 day - 1 microsecond')::TIMESTAMP WITH TIME ZONE, CURRENT_TIMESTAMP);

    SELECT json_agg(
        json_build_object(
            'rendicion_id', rc.id,
            'fecha_rendicion', rc.fecha_rendicion,
            'tasa_cambio', COALESCE(rc.tasa_cambio, 1.0000),
            'cliente_id', rc.cliente_id,
            'cliente_nombre', c.razon_social,
            'cliente_rif', c.rif_nit,
            'estado', rc.estado,
            'total_efectivo_recaudado', rc.total_efectivo_recaudado,
            'total_transferencias_recaudado', rc.total_transferencias_recaudado,
            'total_recaudado_usd', COALESCE(rc.total_recaudado_usd, 0.00),
            'total_recaudado_bs', COALESCE(rc.total_recaudado_bs, 0.00),
            'observaciones', rc.observaciones,
            'detalle_fpagos', COALESCE(fpagos_agg.fpagos, '[]'::json),
            'detalle_ordenes', COALESCE(ordenes_agg.ordenes, '[]'::json)
        ) ORDER BY rc.fecha_rendicion DESC
    ) INTO v_data
    FROM public.rendiciones_cuentas rc
    JOIN public.clientes c ON rc.cliente_id = c.id
    LEFT JOIN LATERAL (
        SELECT json_agg(
            json_build_object(
                'fpago_id', dfp.fpago_id,
                'concepto', fp.fpago_concepto,
                'monto', dfp.monto,
                'monto_bs', COALESCE(dfp.monto_bs, 0.00),
                'monto_usd', COALESCE(dfp.monto_usd, dfp.monto, 0.00),
                'cuenta_bancaria_id', dfp.cuenta_bancaria_id,
                'entidad_bancaria', cbe.entidad_bancaria,
                'cuenta_bancaria', COALESCE(cbe.cuenta_bancaria, dfp.cuenta_bancaria),
                'referencia_bancaria', dfp.referencia_bancaria,
                'capture_url', dfp.capture_url
            )
        ) AS fpagos
        FROM public.detalle_rendicion_fpagos dfp
        LEFT JOIN public.fpagos fp ON dfp.fpago_id = fp.fpago_id
        LEFT JOIN public.cuentas_bancarias_empresa cbe ON dfp.cuenta_bancaria_id = cbe.id
        WHERE dfp.rendicion_id = rc.id
    ) fpagos_agg ON TRUE
    LEFT JOIN LATERAL (
        SELECT json_agg(
            json_build_object(
                'orden_id', dro.orden_distribucion_id,
                'correlativo', od.correlativo,
                'recaudado', dro.recaudado,
                'recaudado_bs', COALESCE(dro.recaudado_bs, 0.00)
            )
        ) AS ordenes
        FROM public.detalle_rendicion_ordenes dro
        LEFT JOIN public.ordenes_distribucion od ON dro.orden_distribucion_id = od.id
        WHERE dro.rendicion_id = rc.id
    ) ordenes_agg ON TRUE
    WHERE rc.fecha_rendicion >= v_desde
      AND rc.fecha_rendicion <= v_hasta;

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


ALTER FUNCTION "public"."reporte_recaudaciones_gerenciales"("p_fecha_desde" "date", "p_fecha_hasta" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."retorna_choferes_disponibles"() RETURNS TABLE("perfil_id" "uuid", "nombre_completo" "text", "cedula_licencia" "text", "telefono" "text", "estado" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- Retorna únicamente los choferes que están con estado 'disponible'
    -- y cuyo perfil de usuario esté activo.
    RETURN QUERY 
    SELECT 
        c.perfil_id,
        p.nombre_completo,
        c.cedula_licencia,
        -- Prioriza el movil1 del chofer, si no existe toma el teléfono del perfil
        COALESCE(c.movil1, p.telefono) AS telefono,
        c.estado::TEXT
    FROM public.choferes c
    JOIN public.perfiles_usuario p ON c.perfil_id = p.id
    WHERE c.estado = 'disponible' 
      AND p.activo = TRUE
    ORDER BY p.nombre_completo ASC;
END;
$$;


ALTER FUNCTION "public"."retorna_choferes_disponibles"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."retorna_cuentas_bancarias_empresa"("p_solo_activas" boolean DEFAULT true) RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_data JSON;
BEGIN
    SELECT json_agg(
        json_build_object(
            'id', id,
            'cuenta_bancaria', cuenta_bancaria,
            'entidad_bancaria', entidad_bancaria,
            'status_cuenta', status_cuenta,
            'created_at', created_at
        ) ORDER BY entidad_bancaria ASC, cuenta_bancaria ASC
    ) INTO v_data
    FROM public.cuentas_bancarias_empresa
    WHERE (NOT p_solo_activas OR status_cuenta = TRUE);

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


ALTER FUNCTION "public"."retorna_cuentas_bancarias_empresa"("p_solo_activas" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."retorna_inventario_no_despachado_para_almacen"("p_radar_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
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
        -- 1. Reingresar el stock no despachado al almacén principal (inventario_almacen.stock_disponible)
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

        -- 2. Descontar / rebajar del inventario móvil del camión la mercancía no entregada (devuelta)
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
        'message', 'Inventario no despachado retornado exitosamente al almacén principal.',
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


ALTER FUNCTION "public"."retorna_inventario_no_despachado_para_almacen"("p_radar_id" "uuid") OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."camiones" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "placa" "text" NOT NULL,
    "modelo" "text" NOT NULL,
    "capacidad_kg" numeric(10,2) NOT NULL,
    "volumen_m3" numeric(10,2),
    "estado" "text" DEFAULT 'disponible'::"text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "camiones_estado_check" CHECK (("estado" = ANY (ARRAY['disponible'::"text", 'en_ruta'::"text", 'mantenimiento'::"text", 'inactivo'::"text"])))
);


ALTER TABLE "public"."camiones" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."retorna_lista_camiones"() RETURNS SETOF "public"."camiones"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- Retorna todos los camiones para que el usuario pueda seleccionarlos
    -- Ordenamos primero los que están 'disponibles' para darles prioridad en el formulario,
    -- y luego por placa alfabéticamente.
    RETURN QUERY 
    SELECT *
    FROM public.camiones
    ORDER BY 
        CASE WHEN estado = 'disponible' THEN 1 ELSE 2 END,
        placa ASC;
END;
$$;


ALTER FUNCTION "public"."retorna_lista_camiones"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."retorna_lista_contenedores"() RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
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


ALTER FUNCTION "public"."retorna_lista_contenedores"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."retorna_lista_productos_segun_parametros"("p_busqueda" "text" DEFAULT NULL::"text", "p_activo" boolean DEFAULT NULL::boolean) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_resultado JSONB;
BEGIN
    SELECT jsonb_build_object(
        'success', TRUE,
        'total_registros', COUNT(p.id),
        'data', COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'id', p.id,
                    'codigo_producto', p.codigo_producto,
                    'nombre', p.nombre,
                    'codigo_barras', p.codigo_barras,
                    'precio_lista1', p.precio_lista1,
                    'precio_lista2', p.precio_lista2,
                    'precio_lista3', p.precio_lista3,
                    'imagen_path', p.imagen_path,
                    'created_at', p.created_at
                )
            ),
            '[]'::jsonb
        )
    ) INTO v_resultado
    FROM public.productos p
    WHERE (p_busqueda IS NULL OR p.nombre ILIKE '%' || p_busqueda || '%' OR p.codigo_producto ILIKE '%' || p_busqueda || '%')
      AND (p_activo IS NULL OR p.activo = p_activo);

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


ALTER FUNCTION "public"."retorna_lista_productos_segun_parametros"("p_busqueda" "text", "p_activo" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."retorna_lista_productos_segun_parametros"("p_parametro" "text", "p_cliente_id" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("id" "uuid", "nombre" "text", "codigo_barras" "text", "precio" numeric, "stock_disponible" integer, "imagen_path" "text", "precio_lista" numeric, "porcentaje_descuento" numeric, "precio_final_usd" numeric)
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    RETURN QUERY 
    SELECT 
        p.id, 
        p.nombre, 
        p.codigo_barras, 
        ROUND(
            CASE 
                WHEN d.id IS NOT NULL AND d.activo = true AND d.precio_pactado_usd IS NOT NULL THEN d.precio_pactado_usd
                WHEN d.id IS NOT NULL AND d.activo = true AND d.porcentaje_descuento > 0 THEN COALESCE(p.precio_lista1, 0.00) * (1.00 - (d.porcentaje_descuento / 100.00))
                ELSE COALESCE(p.precio_lista1, 0.00)
            END,
            2
        ) AS precio,
        COALESCE(i.stock_disponible, 0)::INT AS stock_disponible,
        p.imagen_path,
        COALESCE(p.precio_lista1, 0.00) AS precio_lista,
        CASE 
            WHEN d.id IS NOT NULL AND d.activo = true THEN COALESCE(d.porcentaje_descuento, 0.00)
            ELSE 0.00
        END AS porcentaje_descuento,
        ROUND(
            CASE 
                WHEN d.id IS NOT NULL AND d.activo = true AND d.precio_pactado_usd IS NOT NULL THEN d.precio_pactado_usd
                WHEN d.id IS NOT NULL AND d.activo = true AND d.porcentaje_descuento > 0 THEN COALESCE(p.precio_lista1, 0.00) * (1.00 - (d.porcentaje_descuento / 100.00))
                ELSE COALESCE(p.precio_lista1, 0.00)
            END,
            2
        ) AS precio_final_usd
    FROM public.productos p
    LEFT JOIN public.inventario_almacen i ON p.id = i.producto_id
    LEFT JOIN public.descuentos_cliente_producto d ON p.id = d.producto_id AND d.cliente_id = p_cliente_id AND d.activo = true
    WHERE 
        (p_parametro = '.F.' OR p.nombre ILIKE '%' || p_parametro || '%' OR p.codigo_barras ILIKE '%' || p_parametro || '%');
END;
$$;


ALTER FUNCTION "public"."retorna_lista_productos_segun_parametros"("p_parametro" "text", "p_cliente_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."retorna_lista_radars_aprobado_segun_rango_fechas"("p_despachador_id" "uuid" DEFAULT NULL::"uuid", "p_fecha_inicial" "date" DEFAULT NULL::"date", "p_fecha_limite" "date" DEFAULT NULL::"date") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
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


ALTER FUNCTION "public"."retorna_lista_radars_aprobado_segun_rango_fechas"("p_despachador_id" "uuid", "p_fecha_inicial" "date", "p_fecha_limite" "date") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."retorna_lista_radars_aprobado_segun_rango_fechas"("p_despachador_id" "uuid", "p_fecha_inicial" "date", "p_fecha_limite" "date") IS 'Retorna la lista de radares en estado APROBADO (status_radar = TRUE) asignados a un despachador en un rango de fechas.';



CREATE OR REPLACE FUNCTION "public"."retorna_lista_radars_pendiente_segun_rango_fechas"("p_despachador_id" "uuid" DEFAULT NULL::"uuid", "p_fecha_inicial" "date" DEFAULT NULL::"date", "p_fecha_limite" "date" DEFAULT NULL::"date") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
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


ALTER FUNCTION "public"."retorna_lista_radars_pendiente_segun_rango_fechas"("p_despachador_id" "uuid", "p_fecha_inicial" "date", "p_fecha_limite" "date") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."retorna_lista_radars_pendiente_segun_rango_fechas"("p_despachador_id" "uuid", "p_fecha_inicial" "date", "p_fecha_limite" "date") IS 'Retorna la lista de radares en estado PENDIENTE (status_radar = FALSE) asignados a un despachador en un rango de fechas.';



CREATE OR REPLACE FUNCTION "public"."retorna_lista_radars_segun_rango_fechas"("p_despachador_id" "uuid" DEFAULT NULL::"uuid", "p_fecha_inicial" "date" DEFAULT NULL::"date", "p_fecha_limite" "date" DEFAULT NULL::"date") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
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
                    'status_radar', COALESCE(r.status_radar, FALSE)
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


ALTER FUNCTION "public"."retorna_lista_radars_segun_rango_fechas"("p_despachador_id" "uuid", "p_fecha_inicial" "date", "p_fecha_limite" "date") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."retorna_lista_radars_segun_rango_fechas"("p_despachador_id" "uuid", "p_fecha_inicial" "date", "p_fecha_limite" "date") IS 'Retorna la lista de radares asignados a un despachador ordenados por fecha descendente en un rango de fechas con métricas consolidadas (paradas, items, sku).';



CREATE OR REPLACE FUNCTION "public"."retorna_lista_rutas"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_total_registros INT;
    v_data JSONB;
BEGIN
    -- Obtenemos el total de registros en la tabla rutas
    SELECT COUNT(*) INTO v_total_registros FROM public.rutas;

    -- Obtenemos el arreglo de rutas ordenadas por nombre_ruta
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'id_ruta', id_ruta,
                'nombre_ruta', nombre_ruta,
                'descripcion_ruta', descripcion_ruta,
                'created_at', created_at
            )
            ORDER BY nombre_ruta ASC
        ),
        '[]'::jsonb
    ) INTO v_data
    FROM public.rutas;

    -- Retornamos respuesta exitosa
    RETURN jsonb_build_object(
        'success', TRUE,
        'total_registros', v_total_registros,
        'data', v_data
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


ALTER FUNCTION "public"."retorna_lista_rutas"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."retorna_lista_rutas"() IS 'Retorna el listado completo de rutas y la cantidad total de registros almacenados';



CREATE OR REPLACE FUNCTION "public"."retorna_lista_usuarios_segun_parametro"("p_parametro" "text" DEFAULT ''::"text") RETURNS TABLE("id" "uuid", "nombre_completo" "text", "rol_nombre" "text")
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
    SELECT
        pu.id,
        pu.nombre_completo,
        r.nombre AS rol_nombre
    FROM perfiles_usuario pu
    LEFT JOIN roles r ON r.id = pu.rol_id
    WHERE
        p_parametro IS NULL
        OR TRIM(p_parametro) = ''
        OR pu.nombre_completo ILIKE '%' || p_parametro || '%'
    ORDER BY pu.nombre_completo;
$$;


ALTER FUNCTION "public"."retorna_lista_usuarios_segun_parametro"("p_parametro" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."retorna_lista_usuarios_segun_parametros"("p_nombre" "text", "p_rol" "text") RETURNS TABLE("id" "uuid", "nombre_completo" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    RETURN QUERY 
    SELECT 
        pu.id, 
        pu.nombre_completo
    FROM public.perfiles_usuario pu
    LEFT JOIN public.roles r ON pu.rol_id = r.id
    WHERE 
        (p_nombre IS NULL OR p_nombre = '' OR pu.nombre_completo ILIKE '%' || p_nombre || '%')
        AND 
        (p_rol IS NULL OR p_rol = '' OR r.nombre ILIKE '%' || p_rol || '%');
END;
$$;


ALTER FUNCTION "public"."retorna_lista_usuarios_segun_parametros"("p_nombre" "text", "p_rol" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."retorna_movimientos_contenedores_segun_cliente_id_rango_fechas"("p_cliente_id" "uuid", "p_fecha_inicial" "date" DEFAULT NULL::"date", "p_fecha_limite" "date" DEFAULT NULL::"date") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_cliente RECORD;
    v_saldo_anterior INT := 0;
    v_total_entregados INT := 0;
    v_total_retirados INT := 0;
    v_saldo_final INT := 0;
    v_movimientos JSONB := '[]'::jsonb;
    v_result JSONB;
BEGIN
    -- Validar parámetro obligatorio p_cliente_id
    IF p_cliente_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El parámetro p_cliente_id es obligatorio.'
            )
        );
    END IF;

    -- Validar que el cliente exista
    SELECT id, rif_nit, razon_social INTO v_cliente
    FROM public.clientes
    WHERE id = p_cliente_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'data', NULL,
            'error', jsonb_build_object(
                'code', 'CLIENTE_INEXISTENTE',
                'message', 'El cliente especificado no existe.'
            )
        );
    END IF;

    -- Si las fechas no vienen especificadas, asignar valores por defecto (últimos 30 días)
    IF p_fecha_inicial IS NULL THEN
        p_fecha_inicial := CURRENT_DATE - INTERVAL '30 days';
    END IF;

    IF p_fecha_limite IS NULL THEN
        p_fecha_limite := CURRENT_DATE;
    END IF;

    -- 1. Calcular Saldo Anterior acumulado antes de p_fecha_inicial
    SELECT COALESCE(SUM(cantidad_entregada - cantidad_retirada), 0)
    INTO v_saldo_anterior
    FROM public.movimientos_contenedores
    WHERE cliente_id = p_cliente_id
      AND created_at::DATE < p_fecha_inicial;

    -- 2. Calcular Totales entregados y retirados dentro del rango
    SELECT 
        COALESCE(SUM(cantidad_entregada), 0),
        COALESCE(SUM(cantidad_retirada), 0)
    INTO v_total_entregados, v_total_retirados
    FROM public.movimientos_contenedores
    WHERE cliente_id = p_cliente_id
      AND created_at::DATE BETWEEN p_fecha_inicial AND p_fecha_limite;

    v_saldo_final := v_saldo_anterior + v_total_entregados - v_total_retirados;

    -- 3. Extraer Detalle de Movimientos en el Rango
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', m.id,
            'fecha_movimiento', m.created_at,
            'orden_id', m.orden_id,
            'correlativo_orden', o.correlativo,
            'factura_origen_numero', o.factura_origen_numero,
            'contenedor_id', m.contenedor_id,
            'codigo_contenedor', t.codigo,
            'nombre_contenedor', t.nombre,
            'cantidad_entregada', m.cantidad_entregada,
            'cantidad_retirada', m.cantidad_retirada
        ) ORDER BY m.created_at ASC
    ), '[]'::jsonb)
    INTO v_movimientos
    FROM public.movimientos_contenedores m
    LEFT JOIN public.ordenes_distribucion o ON m.orden_id = o.id
    LEFT JOIN public.tipos_contenedores t ON m.contenedor_id = t.id
    WHERE m.cliente_id = p_cliente_id
      AND m.created_at::DATE BETWEEN p_fecha_inicial AND p_fecha_limite;

    -- Construir respuesta JSON exitosa
    SELECT jsonb_build_object(
        'success', TRUE,
        'data', jsonb_build_object(
            'cliente_id', v_cliente.id,
            'rif_nit', v_cliente.rif_nit,
            'razon_social', v_cliente.razon_social,
            'fecha_inicial', p_fecha_inicial,
            'fecha_limite', p_fecha_limite,
            'saldo_anterior', v_saldo_anterior,
            'total_entregados', v_total_entregados,
            'total_retirados', v_total_retirados,
            'saldo_final', v_saldo_final,
            'movimientos', v_movimientos
        ),
        'error', NULL
    ) INTO v_result;

    RETURN v_result;
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', FALSE,
        'data', NULL,
        'error', jsonb_build_object(
            'code', 'SQL_ERROR',
            'message', SQLERRM
        )
    );
END;
$$;


ALTER FUNCTION "public"."retorna_movimientos_contenedores_segun_cliente_id_rango_fechas"("p_cliente_id" "uuid", "p_fecha_inicial" "date", "p_fecha_limite" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."retorna_ordenes_distribucion_segun_estado"("p_estado" "text") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
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


ALTER FUNCTION "public"."retorna_ordenes_distribucion_segun_estado"("p_estado" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."retorna_ordenes_distribucion_segun_idradar"("p_radar_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_resultado JSONB;
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

    SELECT jsonb_build_object(
        'success', TRUE,
        'data', COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'id_orden_distribucion', o.id,
                    'correlativo', o.correlativo,
                    'ruta', COALESCE(rut.nombre_ruta, 'Sin Ruta'),
                    'razon_social', c.razon_social,
                    'direccion_fiscal', c.direccion_fiscal,
                    'items', COALESCE(det_stats.total_items, 0),
                    'sku', COALESCE(det_stats.total_sku, 0),
                    'contenedores_retirados', COALESCE(det_stats.total_contenedores_retirados, 0)
                ) ORDER BY o.correlativo ASC
            ),
            '[]'::jsonb
        ),
        'error', NULL
    ) INTO v_resultado
    FROM public.ordenes_distribucion o
    LEFT JOIN public.clientes c ON c.id = o.cliente_id
    LEFT JOIN public.rutas rut ON c.id_ruta = rut.id_ruta
    LEFT JOIN LATERAL (
        SELECT 
            SUM(COALESCE(d.cantidad_despachada, d.cantidad_solicitada, 0)) AS total_items,
            COUNT(DISTINCT d.producto_id) AS total_sku,
            SUM(COALESCE(d.contenedores_retirados, 0)) AS total_contenedores_retirados
        FROM public.detalle_distribucion d
        WHERE d.orden_id = o.id
    ) det_stats ON TRUE
    WHERE o.radar_id = p_radar_id;

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


ALTER FUNCTION "public"."retorna_ordenes_distribucion_segun_idradar"("p_radar_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."retorna_ordenes_distribucion_segun_idradar"("p_radar_id" "uuid") IS 'Retorna el detalle resumido de las órdenes de distribución vinculadas a un id_radar específico.';



CREATE OR REPLACE FUNCTION "public"."retorna_ordenes_por_liquidar"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_data JSONB;
BEGIN
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'cliente_id', sub.cliente_id,
                'razon_social', sub.razon_social,
                'rif_nit', sub.rif_nit,
                'dias_vencidos', sub.dias_vencidos,
                'cant_ordenes', sub.cant_ordenes,
                'monto_por_liquidar', sub.monto_por_liquidar
            )
            ORDER BY sub.dias_vencidos DESC
        ),
        '[]'::jsonb
    )
    INTO v_data
    FROM (
        SELECT
            c.id AS cliente_id,
            c.razon_social,
            c.rif_nit,
            (CURRENT_DATE - MIN(od.fecha_despacho::date))::INT AS dias_vencidos,
            COUNT(od.id)::INT AS cant_ordenes,
            SUM(
                COALESCE(od.total_recaudar_usd, 0.00)
                - COALESCE(abonos.total_recaudado_usd, 0.00)
            ) AS monto_por_liquidar
        FROM public.ordenes_distribucion od
        JOIN public.clientes c ON c.id = od.cliente_id
        LEFT JOIN LATERAL (
            SELECT SUM(COALESCE(dro.recaudado, 0.00)) AS total_recaudado_usd
            FROM public.detalle_rendicion_ordenes dro
            JOIN public.rendiciones_cuentas rc ON dro.rendicion_id = rc.id
            WHERE dro.orden_distribucion_id = od.id
              AND rc.estado = 'aprobada'
        ) abonos ON TRUE
        WHERE od.estado = 'por_liquidar'
        GROUP BY c.id, c.razon_social, c.rif_nit
    ) sub;

    RETURN jsonb_build_object(
        'success', TRUE,
        'data', v_data,
        'error', NULL
    );

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


ALTER FUNCTION "public"."retorna_ordenes_por_liquidar"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."retorna_ordenes_por_liquidar"() IS 'Retorna el listado de órdenes en estado por_liquidar agrupadas por cliente y ordenadas por días vencidos descendente.';



CREATE OR REPLACE FUNCTION "public"."retorna_radar_despachador"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
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
                'message', 'El usuario no esta autenticado.'
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
                                AND (COALESCE(c.limite_credito, 0.00) = 0.00 OR COALESCE(o.total_recaudar_bs, (COALESCE(o.total_recaudar_usd, 0.00) * COALESCE(o.tasa_cambio, 1.00)), 0.00) <= COALESCE(c.limite_credito, 0.00))
                            )
                        ),
                        'motivo_bloqueo', CASE
                            WHEN COALESCE(c.excepcion_despacho_gerencia, FALSE) = TRUE THEN NULL
                            WHEN COALESCE(c.permiso_despacho_manual, TRUE) = FALSE THEN 'Despacho bloqueado manualmente por politica de credito'
                            WHEN COALESCE(c.limite_credito, 0.00) > 0.00 AND COALESCE(o.total_recaudar_bs, (COALESCE(o.total_recaudar_usd, 0.00) * COALESCE(o.tasa_cambio, 1.00)), 0.00) > COALESCE(c.limite_credito, 0.00) THEN 'Monto de la orden supera el limite de credito del cliente'
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
                                'precio_lista_usd', COALESCE(d.precio_lista_usd, d.valor_unitario_usd, 0.00),
                                'porcentaje_descuento', COALESCE(d.porcentaje_descuento, 0.00),
                                'monto_descuento_usd', COALESCE(d.monto_descuento_usd, 0.00),
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


ALTER FUNCTION "public"."retorna_radar_despachador"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."retorna_radar_despachador"() IS 'Retorna ordenes en transito/despachadas del despachador autenticado con detalles y saldo de envases';



CREATE OR REPLACE FUNCTION "public"."retorna_radar_detalle_reporte"("p_radar_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
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

    -- 3. Consolidado de productos solicitados/despachados en este radar (Reporte global de carga)
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

    -- 4. Detalle orden por orden
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
END;
$$;


ALTER FUNCTION "public"."retorna_radar_detalle_reporte"("p_radar_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."retorna_resumen_autoventas_jornada"("p_camion_id" "uuid", "p_fecha" "date" DEFAULT CURRENT_DATE) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_inventario_movil JSONB;
    v_ventas_jornada JSONB;
    v_total_ordenes INT := 0;
    v_total_facturado_usd NUMERIC(14,2) := 0.00;
    v_total_facturado_bs NUMERIC(14,2) := 0.00;
BEGIN
    IF p_camion_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'El ID del camión es requerido.');
    END IF;

    SELECT jsonb_agg(
        jsonb_build_object(
            'producto_id', p.id,
            'codigo', p.codigo_producto,
            'nombre', p.nombre,
            'cantidad_cargada', COALESCE(im.cantidad_cargada, 0),
            'cantidad_entregada', COALESCE(im.cantidad_entregada, 0),
            'cantidad_disponible', GREATEST(0, COALESCE(im.cantidad_cargada, 0) - COALESCE(im.cantidad_entregada, 0))
        ) ORDER BY p.nombre ASC
    ) INTO v_inventario_movil
    FROM public.inventario_movil im
    JOIN public.productos p ON im.producto_id = p.id
    WHERE im.camion_id = p_camion_id;

    SELECT
        COUNT(*)::INT,
        COALESCE(SUM(total_recaudar_usd), 0.00),
        COALESCE(SUM(total_recaudar_bs), 0.00)
    INTO v_total_ordenes, v_total_facturado_usd, v_total_facturado_bs
    FROM public.ordenes_distribucion
    WHERE camion_id = p_camion_id
      AND es_autoventa = TRUE
      AND DATE(created_at) = COALESCE(p_fecha, CURRENT_DATE);

    SELECT jsonb_agg(
        jsonb_build_object(
            'orden_id', od.id,
            'correlativo', od.correlativo,
            'factura_origen_numero', od.factura_origen_numero,
            'cliente_nombre', c.razon_social,
            'estado', od.estado,
            'total_recaudar_usd', od.total_recaudar_usd,
            'total_recaudar_bs', od.total_recaudar_bs,
            'created_at', od.created_at
        ) ORDER BY od.created_at DESC
    ) INTO v_ventas_jornada
    FROM public.ordenes_distribucion od
    JOIN public.clientes c ON od.cliente_id = c.id
    WHERE od.camion_id = p_camion_id
      AND od.es_autoventa = TRUE
      AND DATE(od.created_at) = COALESCE(p_fecha, CURRENT_DATE);

    RETURN jsonb_build_object(
        'success', true,
        'data', jsonb_build_object(
            'camion_id', p_camion_id,
            'fecha', COALESCE(p_fecha, CURRENT_DATE),
            'total_ordenes_autoventa', v_total_ordenes,
            'total_facturado_usd', v_total_facturado_usd,
            'total_facturado_bs', v_total_facturado_bs,
            'inventario_movil', COALESCE(v_inventario_movil, '[]'::jsonb),
            'ventas', COALESCE(v_ventas_jornada, '[]'::jsonb)
        ),
        'error', NULL
    );
END;
$$;


ALTER FUNCTION "public"."retorna_resumen_autoventas_jornada"("p_camion_id" "uuid", "p_fecha" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."retorna_saldo_contenedores_segun_clientes"("p_cliente_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_result JSONB;
BEGIN
    IF p_cliente_id IS NULL THEN
        -- Retornar todos los clientes que poseen saldo_pendiente > 0
        SELECT jsonb_build_object(
            'success', TRUE,
            'data', COALESCE(jsonb_agg(
                jsonb_build_object(
                    'cliente_id', s.cliente_id,
                    'rif_nit', c.rif_nit,
                    'razon_social', c.razon_social,
                    'contenedor_id', s.contenedor_id,
                    'codigo_contenedor', t.codigo,
                    'nombre_contenedor', t.nombre,
                    'saldo_pendiente', s.saldo_pendiente,
                    'updated_at', s.updated_at
                ) ORDER BY c.razon_social, t.nombre
            ), '[]'::jsonb),
            'error', NULL
        ) INTO v_result
        FROM public.saldo_contenedores_clientes s
        JOIN public.clientes c ON s.cliente_id = c.id
        JOIN public.tipos_contenedores t ON s.contenedor_id = t.id
        WHERE s.saldo_pendiente > 0;

    ELSE
        -- Retornar el saldo del cliente especificado.
        -- Si posee registros en saldo_contenedores_clientes, retornarlos todos.
        IF EXISTS (
            SELECT 1 FROM public.saldo_contenedores_clientes WHERE cliente_id = p_cliente_id
        ) THEN
            SELECT jsonb_build_object(
                'success', TRUE,
                'data', COALESCE(jsonb_agg(
                    jsonb_build_object(
                        'cliente_id', s.cliente_id,
                        'rif_nit', c.rif_nit,
                        'razon_social', c.razon_social,
                        'contenedor_id', s.contenedor_id,
                        'codigo_contenedor', t.codigo,
                        'nombre_contenedor', t.nombre,
                        'saldo_pendiente', s.saldo_pendiente,
                        'updated_at', s.updated_at
                    ) ORDER BY t.nombre
                ), '[]'::jsonb),
                'error', NULL
            ) INTO v_result
            FROM public.saldo_contenedores_clientes s
            JOIN public.clientes c ON s.cliente_id = c.id
            JOIN public.tipos_contenedores t ON s.contenedor_id = t.id
            WHERE s.cliente_id = p_cliente_id;
        ELSE
            -- Verificar si el cliente existe
            IF NOT EXISTS (SELECT 1 FROM public.clientes WHERE id = p_cliente_id) THEN
                RETURN jsonb_build_object(
                    'success', FALSE,
                    'data', NULL,
                    'error', jsonb_build_object(
                        'code', 'CLIENTE_INEXISTENTE',
                        'message', 'El cliente especificado no existe.'
                    )
                );
            END IF;

            -- Retornar fila sintética con saldo_pendiente = 0 si el cliente no posee registros de saldo aún
            SELECT jsonb_build_object(
                'success', TRUE,
                'data', jsonb_build_array(
                    jsonb_build_object(
                        'cliente_id', c.id,
                        'rif_nit', c.rif_nit,
                        'razon_social', c.razon_social,
                        'contenedor_id', NULL,
                        'codigo_contenedor', NULL,
                        'nombre_contenedor', NULL,
                        'saldo_pendiente', 0,
                        'updated_at', c.created_at
                    )
                ),
                'error', NULL
            ) INTO v_result
            FROM public.clientes c
            WHERE c.id = p_cliente_id;
        END IF;
    END IF;

    RETURN v_result;
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', FALSE,
        'data', NULL,
        'error', jsonb_build_object(
            'code', 'SQL_ERROR',
            'message', SQLERRM
        )
    );
END;
$$;


ALTER FUNCTION "public"."retorna_saldo_contenedores_segun_clientes"("p_cliente_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."retorna_tasas_cambio_por_rango"("p_fecha_desde" "date", "p_fecha_hasta" "date") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
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


ALTER FUNCTION "public"."retorna_tasas_cambio_por_rango"("p_fecha_desde" "date", "p_fecha_hasta" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."retorna_ultima_tasa_cambio"() RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
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


ALTER FUNCTION "public"."retorna_ultima_tasa_cambio"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."retorna_usuarios_despachadores"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_data JSONB;
BEGIN
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'id', p.id,
                'nombre_completo', p.nombre_completo,
                'telefono', p.telefono
            )
            ORDER BY p.nombre_completo ASC
        ),
        '[]'::jsonb
    ) INTO v_data
    FROM public.perfiles_usuario p
    JOIN public.roles r ON p.rol_id = r.id
    WHERE r.nombre = 'despachador'
      AND p.activo = TRUE;

    RETURN jsonb_build_object(
        'success', TRUE,
        'data', v_data
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


ALTER FUNCTION "public"."retorna_usuarios_despachadores"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."retorna_usuarios_despachadores"() IS 'Retorna la lista de usuarios activos que poseen el rol de despachador';



CREATE OR REPLACE FUNCTION "public"."solicita_abonos_orden_distribucion"("p_cliente_id" "uuid") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_saldo_favor NUMERIC(12, 2) := 0.00;
    v_tasa_oficial NUMERIC(10, 4) := 1.0000;
    v_ordenes JSON;
BEGIN
    IF p_cliente_id IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'PARAMETRO_INVALIDO',
                'message', 'El ID de cliente es requerido.'
            )
        );
    END IF;

    SELECT COALESCE(saldo_favor, 0.00) INTO v_saldo_favor
    FROM public.clientes
    WHERE id = p_cliente_id;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'data', NULL,
            'error', json_build_object(
                'code', 'CLIENTE_INEXISTENTE',
                'message', 'El cliente especificado no existe.'
            )
        );
    END IF;

    SELECT COALESCE(tasa_cambio, 1.0000) INTO v_tasa_oficial
    FROM public.tasa_cambio
    ORDER BY fecha_tasa DESC, created_at DESC
    LIMIT 1;

    IF v_tasa_oficial IS NULL THEN
        v_tasa_oficial := 1.0000;
    END IF;

    SELECT json_agg(
        json_build_object(
            'orden_id', od.id,
            'correlativo', od.correlativo,
            'fecha_despacho', od.fecha_despacho,
            'dias_vencidos', CASE
                WHEN od.fecha_despacho IS NULL THEN 0
                ELSE GREATEST(0, (CURRENT_DATE - od.fecha_despacho::date)::INT)
            END,
            'tasa_orden', COALESCE(od.tasa_cambio, v_tasa_oficial),
            'monto_total_orden', COALESCE(od.total_recaudar_usd, 0.00),
            'monto_total_orden_bs', COALESCE(
                od.total_recaudar_bs,
                COALESCE(od.total_recaudar_usd, 0.00) * COALESCE(od.tasa_cambio, v_tasa_oficial),
                0.00
            ),
            'abonos_acumulados', COALESCE(abonos.total_recaudado_usd, 0.00),
            'abonos_acumulados_bs', COALESCE(abonos.total_recaudado_bs, 0.00),
            'saldo_pendiente',
                COALESCE(od.total_recaudar_usd, 0.00) - COALESCE(abonos.total_recaudado_usd, 0.00),
            'saldo_pendiente_bs',
                COALESCE(
                    od.total_recaudar_bs,
                    COALESCE(od.total_recaudar_usd, 0.00) * COALESCE(od.tasa_cambio, v_tasa_oficial),
                    0.00
                ) - COALESCE(abonos.total_recaudado_bs, 0.00)
        ) ORDER BY od.created_at ASC
    ) INTO v_ordenes
    FROM public.ordenes_distribucion od
    LEFT JOIN LATERAL (
        SELECT
            SUM(COALESCE(dro.recaudado, 0.00)) AS total_recaudado_usd,
            SUM(
                COALESCE(
                    dro.recaudado_bs,
                    COALESCE(dro.recaudado, 0.00) * COALESCE(rc.tasa_cambio, v_tasa_oficial),
                    0.00
                )
            ) AS total_recaudado_bs
        FROM public.detalle_rendicion_ordenes dro
        JOIN public.rendiciones_cuentas rc ON dro.rendicion_id = rc.id
        WHERE dro.orden_distribucion_id = od.id
          AND rc.estado = 'aprobada'
    ) abonos ON TRUE
    WHERE od.cliente_id = p_cliente_id
      AND od.estado IN ('despachada', 'por_liquidar');

    RETURN json_build_object(
        'success', true,
        'data', json_build_object(
            'cliente_id', p_cliente_id,
            'saldo_favor', v_saldo_favor,
            'saldo_favor_bs', (v_saldo_favor * v_tasa_oficial),
            'tasa_oficial_actual', v_tasa_oficial,
            'ordenes', COALESCE(v_ordenes, '[]'::json)
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


ALTER FUNCTION "public"."solicita_abonos_orden_distribucion"("p_cliente_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."solicita_aprobar_radar"("p_radar_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
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

    -- 3. Las órdenes en estado 'devuelta' pasan al estado final 'anulada'
    WITH ordenes_devueltas AS (
        UPDATE public.ordenes_distribucion
        SET estado = 'anulada'
        WHERE radar_id = p_radar_id AND estado = 'devuelta'
        RETURNING id
    )
    SELECT COUNT(*) INTO v_ordenes_anuladas_count FROM ordenes_devueltas;

    -- 4. Políticas de crédito desactivadas temporalmente para mantener todos los clientes activos
    v_clientes_deshabilitados_count := 0;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Radar aprobado exitosamente. Saldos de contenedores actualizados al despachar, inventario restituido a almacén y órdenes devueltas anuladas.',
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


ALTER FUNCTION "public"."solicita_aprobar_radar"("p_radar_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."solicita_aprobar_radar"("p_radar_id" "uuid") IS 'Aprueba el radar (status_radar = TRUE), carga envases entregados/retirados a saldos de clientes, evalúa políticas de crédito (max_facturas_vencidas), reingresa inventario a almacén y anula órdenes devueltas.';



CREATE OR REPLACE FUNCTION "public"."solicita_cargar_inventario_movil_desde_almacen"("p_camion_id" "uuid", "p_resumen_productos" "jsonb", "p_radar_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
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
                'message', 'El ID del camión es requerido.'
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
                'message', 'El camión especificado no existe.'
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
                'message', 'El resumen de productos a cargar no contiene elementos válidos.'
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
        'message', 'Carga a inventario móvil procesada exitosamente desde el almacén.',
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


ALTER FUNCTION "public"."solicita_cargar_inventario_movil_desde_almacen"("p_camion_id" "uuid", "p_resumen_productos" "jsonb", "p_radar_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."solicita_crear_orden_distribucion"("p_vendedor_id" "uuid", "p_chofer_id" "uuid", "p_productos_json" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_orden_id UUID;
    v_monto_total NUMERIC(10,2) := 0.00;
    v_codigo_orden TEXT;
    v_item JSONB;
    v_resultado JSONB;
BEGIN
    -- 1. Calcular de forma automática el monto total sumando los productos del parámetro JSONB
    SELECT COALESCE(SUM((item->>'cantidad')::INT * (item->>'precio_unitario')::NUMERIC), 0.00)
    INTO v_monto_total
    FROM jsonb_array_elements(p_productos_json) AS item;

    -- 2. Generar el código correlativo de la orden (Prefijo ORD + Fecha Hoy + Hash Único de 4 caracteres)
    v_codigo_orden := 'ORD-' || TO_CHAR(NOW(), 'YYYYMMDD') || '-' || UPPER(SUBSTRING(MD5(RANDOM()::TEXT) FROM 1 FOR 4));

    -- 3. Insertar la cabecera en la tabla RESUMEN (ordenes_distribucion)
    INSERT INTO public.ordenes_distribucion (
        vendedor_id,
        chofer_id,
        codigo_orden,
        estado,
        monto_total
    ) 
    VALUES (
        p_vendedor_id,
        p_chofer_id,
        v_codigo_orden,
        'pendiente',
        v_monto_total
    )
    RETURNING id INTO v_orden_id;

    -- 4. Recorrer el arreglo de productos e insertar cada fila en la tabla DETALLE (detalle_distribucion)
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos_json)
    LOOP
        INSERT INTO public.detalle_distribucion (
            orden_id,
            producto_id,
            cantidad_solicitada,
            precio_unitario
        ) 
        VALUES (
            v_orden_id,
            (v_item->>'producto_id')::UUID,
            (v_item->>'cantidad')::INT,
            (v_item->>'precio_unitario')::NUMERIC
        );
    END LOOP;

    -- 5. Construir respuesta exitosa en formato JSONB
    v_resultado := jsonb_build_object(
        'success', TRUE,
        'message', 'Orden de distribución y detalles creados con éxito',
        'orden_id', v_orden_id,
        'codigo_orden', v_codigo_orden,
        'monto_total', v_monto_total
    );

    RETURN v_resultado;

EXCEPTION WHEN OTHERS THEN
    -- En caso de cualquier error (IDs inválidos, tipos de datos incompatibles, etc.), revierte todo
    v_resultado := jsonb_build_object(
        'success', FALSE,
        'message', SQLERRM
    );
    RETURN v_resultado;
END;
$$;


ALTER FUNCTION "public"."solicita_crear_orden_distribucion"("p_vendedor_id" "uuid", "p_chofer_id" "uuid", "p_productos_json" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."solicita_datos_usuario"("p_user_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_resultado JSONB;
BEGIN
    -- Buscar el usuario unificando la tabla de autenticación, perfil público y roles
    SELECT jsonb_build_object(
        'success', TRUE,
        'user_id', p.id,
        'email', u.email,
        'nombre_completo', p.nombre_completo,
        'telefono', p.telefono,
        'activo', p.activo,
        'rol', r.nombre,
        'rol_descripcion', r.descripcion,
        'creado_el', p.created_at
    )
    INTO v_resultado
    FROM public.perfiles_usuario p
    JOIN auth.users u ON p.id = u.id
    JOIN public.roles r ON p.rol_id = r.id
    WHERE p.id = p_user_id;

    -- Si no se encontró ningún registro para ese UUID, armar respuesta controlada
    IF v_resultado IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'message', 'No se encontró ningún usuario con el ID proporcionado en LogiTrack.'
        );
    END IF;

    RETURN v_resultado;

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', FALSE,
        'message', SQLERRM
    );
END;
$$;


ALTER FUNCTION "public"."solicita_datos_usuario"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."solicita_editar_o_sincronizar_radar"("p_radar_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
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
                'message', 'Para modificar el Radar debe reversar el inventario movil al almacén'
            )
        );
    END IF;

    -- Desvincular únicamente órdenes estándar en estado 'aprobada'
    UPDATE public.ordenes_distribucion
    SET radar_id = NULL
    WHERE radar_id = p_radar_id AND estado = 'aprobada';

    GET DIAGNOSTICS v_desvinculadas = ROW_COUNT;

    -- EXCLUIR VENTA EN RUTA (es_autoventa = TRUE): Volver a vincular únicamente órdenes estándar
    UPDATE public.ordenes_distribucion o
    SET radar_id = p_radar_id
    FROM public.clientes c
    WHERE o.cliente_id = c.id
      AND c.despachador_id = v_despachador_id
      AND o.fecha_despacho::date = v_fecha_despacho
      AND o.estado IN ('aprobada', 'en_transito', 'por_liquidar', 'liquidada', 'devuelta')
      AND (o.radar_id IS NULL OR o.radar_id = p_radar_id)
      AND COALESCE(o.es_autoventa, FALSE) = FALSE;

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
END;
$$;


ALTER FUNCTION "public"."solicita_editar_o_sincronizar_radar"("p_radar_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."solicita_lista_usuarios"("p_usuarios_json" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_item JSONB;
    v_resultado_individual JSONB;
    v_creados INT := 0;
    v_errores INT := 0;
    v_detalles_exitosos JSONB := jsonb_build_array();
    v_detalles_errores JSONB := jsonb_build_array();
BEGIN
    -- 1. Validar que la entrada sea un arreglo JSON válido
    IF jsonb_typeof(p_usuarios_json) != 'array' THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'message', 'El parámetro provisto debe ser un arreglo JSON válido.'
        );
    END IF;

    -- 2. Iterar sobre cada usuario de la lista
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_usuarios_json)
    LOOP
        -- Invocamos la función base de registro individual
        v_resultado_individual := public.registra_nuevo_usuario(
            (v_item->>'email')::TEXT,
            (v_item->>'password')::TEXT,
            (v_item->>'nombre')::TEXT,
            (v_item->>'telefono')::TEXT,
            (v_item->>'rol')::TEXT
        );

        -- 3. Evaluar el estatus de la creación de este usuario
        IF (v_resultado_individual->>'success')::BOOLEAN = TRUE THEN
            v_creados := v_creados + 1;
            
            -- AGREGADO: Guardamos el email junto con su UUID autogenerado
            v_detalles_exitosos := v_detalles_exitosos || jsonb_build_object(
                'email', v_item->>'email',
                'user_id', (v_resultado_individual->>'user_id')::UUID
            );
        ELSE
            v_errores := v_errores + 1;
            -- Si falla, guardamos el detalle del error
            v_detalles_errores := v_detalles_errores || jsonb_build_object(
                'email', v_item->>'email',
                'error', v_resultado_individual->>'message'
            );
        END IF;
    END LOOP;

    -- 4. Retornar el balance general con la lista de usuarios y sus respectivos UUIDs
    RETURN jsonb_build_object(
        'success', TRUE,
        'usuarios_creados', v_creados,
        'usuarios_fallidos', v_errores,
        'detalles_exitosos', v_detalles_exitosos, -- <--- Aquí viajan los UUIDs nuevos
        'detalles_errores', v_detalles_errores
    );
END;
$$;


ALTER FUNCTION "public"."solicita_lista_usuarios"("p_usuarios_json" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."solicita_reversar_carga_inventario_movil_a_almacen"("p_camion_id" "uuid", "p_resumen_productos" "jsonb" DEFAULT NULL::"jsonb", "p_radar_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
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
                'message', 'El ID del camión es requerido.'
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
                'message', 'El camión especificado no existe.'
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
                    'message', 'El inventario móvil de este radar no ha sido cargado previamente o ya fue reversado.'
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
                    'message', 'No se puede reversar la carga al almacén porque ya existen entregas o despachos registrados en esta ruta.'
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
        'message', 'Reverso de inventario móvil al almacén procesado exitosamente.',
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


ALTER FUNCTION "public"."solicita_reversar_carga_inventario_movil_a_almacen"("p_camion_id" "uuid", "p_resumen_productos" "jsonb", "p_radar_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."user_has_role"("p_role_names" "text"[]) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
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


ALTER FUNCTION "public"."user_has_role"("p_role_names" "text"[]) OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."choferes" (
    "perfil_id" "uuid" NOT NULL,
    "cedula_licencia" "text" NOT NULL,
    "movil1" "text",
    "movil2" "text",
    "movil3" "text",
    "estado" "text" DEFAULT 'disponible'::"text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "choferes_estado_check" CHECK (("estado" = ANY (ARRAY['disponible'::"text", 'en_ruta'::"text", 'libre'::"text", 'suspendido'::"text"])))
);


ALTER TABLE "public"."choferes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."clientes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "rif_nit" "text" NOT NULL,
    "razon_social" "text" NOT NULL,
    "direccion_fiscal" "text" NOT NULL,
    "telefono" "text",
    "movil1" "text",
    "movil2" "text",
    "movil3" "text",
    "correo_e" "text",
    "cond_liq" numeric(1,0),
    "max_liq" numeric(14,2),
    "activo" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "saldo_favor" numeric(12,2) DEFAULT 0.00,
    "vendedor_id" "uuid",
    "despachador_id" "uuid",
    "id_ruta" "uuid",
    "limite_credito" numeric(14,2) DEFAULT 0.00,
    "max_facturas_vencidas" integer DEFAULT 0,
    "permiso_despacho_manual" boolean DEFAULT true,
    "excepcion_despacho_gerencia" boolean DEFAULT false,
    CONSTRAINT "clientes_limite_credito_check" CHECK (("limite_credito" >= 0.00)),
    CONSTRAINT "clientes_max_facturas_vencidas_check" CHECK (("max_facturas_vencidas" >= 0)),
    CONSTRAINT "clientes_saldo_favor_check" CHECK (("saldo_favor" >= 0.00))
);


ALTER TABLE "public"."clientes" OWNER TO "postgres";


COMMENT ON COLUMN "public"."clientes"."despachador_id" IS 'ID del perfil de usuario con rol despachador asignado preferencialmente al cliente';



COMMENT ON COLUMN "public"."clientes"."id_ruta" IS 'FK hacia la ruta asignada al cliente';



COMMENT ON COLUMN "public"."clientes"."limite_credito" IS 'Monto máximo de saldo deudor permitido para el cliente en Bs/USD';



COMMENT ON COLUMN "public"."clientes"."max_facturas_vencidas" IS 'Cantidad máxima de facturas o solicitudes vencidas pendientes sin pago';



COMMENT ON COLUMN "public"."clientes"."permiso_despacho_manual" IS 'Habilitación manual de despacho para el cliente (.T. / .F.)';



COMMENT ON COLUMN "public"."clientes"."excepcion_despacho_gerencia" IS 'Permiso especial de un solo uso otorgado por Gerencia para permitir el despacho en morosidad';



CREATE TABLE IF NOT EXISTS "public"."cuentas_bancarias_empresa" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "cuenta_bancaria" character varying(20) NOT NULL,
    "entidad_bancaria" character varying(100) NOT NULL,
    "status_cuenta" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."cuentas_bancarias_empresa" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."descuentos_cliente_producto" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "cliente_id" "uuid" NOT NULL,
    "producto_id" "uuid" NOT NULL,
    "porcentaje_descuento" numeric(5,2) DEFAULT 0.00 NOT NULL,
    "precio_pactado_usd" numeric(14,2) DEFAULT NULL::numeric,
    "activo" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."descuentos_cliente_producto" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."detalle_distribucion" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "orden_id" "uuid",
    "producto_id" "uuid",
    "cantidad_solicitada" integer NOT NULL,
    "cantidad_despachada" integer DEFAULT 0,
    "valor_unitario_recaudar" numeric(14,2) DEFAULT 0.00,
    "subtotal_recaudar" numeric(12,2) DEFAULT 0.00,
    "secuencia_entrega" integer,
    "estado_entrega" "text" DEFAULT 'pendiente'::"text",
    "motivo_rechazo" "text",
    "valor_unitario_usd" numeric(14,2),
    "subtotal_recaudar_usd" numeric(14,2),
    "contenedores_retirados" integer DEFAULT 0,
    "contenedor_id" "uuid",
    "precio_lista_usd" numeric(14,2) DEFAULT NULL::numeric,
    "porcentaje_descuento" numeric(5,2) DEFAULT 0.00,
    "monto_descuento_usd" numeric(14,2) DEFAULT 0.00,
    CONSTRAINT "detalle_distribucion_cantidad_solicitada_check" CHECK (("cantidad_solicitada" > 0)),
    CONSTRAINT "detalle_distribucion_contenedores_retirados_check" CHECK (("contenedores_retirados" >= 0)),
    CONSTRAINT "detalle_distribucion_estado_entrega_check" CHECK (("estado_entrega" = ANY (ARRAY['pendiente'::"text", 'entregado'::"text", 'entregado_parcial'::"text", 'rechazado'::"text"])))
);


ALTER TABLE "public"."detalle_distribucion" OWNER TO "postgres";


COMMENT ON COLUMN "public"."detalle_distribucion"."contenedores_retirados" IS 'Cantidad de envases vacíos retirados al cliente en ruta (provisional hasta liquidación)';



COMMENT ON COLUMN "public"."detalle_distribucion"."contenedor_id" IS 'Tipo de contenedor asociado al retiro/entrega de esta línea';



CREATE TABLE IF NOT EXISTS "public"."detalle_facturas_compras" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "factura_id" "uuid",
    "producto_id" "uuid",
    "cantidad_comprada" integer NOT NULL,
    "precio_unitario_compra" numeric(10,2) NOT NULL,
    "sub_total_compra" numeric(10,2) NOT NULL,
    "monto_linea" numeric(12,2) NOT NULL,
    CONSTRAINT "detalle_facturas_compras_cantidad_comprada_check" CHECK (("cantidad_comprada" > 0))
);


ALTER TABLE "public"."detalle_facturas_compras" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."detalle_pago_facturas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "pago_id" "uuid",
    "factura_id" "uuid",
    "monto_abonado" numeric(12,2) NOT NULL,
    CONSTRAINT "detalle_pago_facturas_monto_abonado_check" CHECK (("monto_abonado" > (0)::numeric))
);


ALTER TABLE "public"."detalle_pago_facturas" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."detalle_pago_metodos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "pago_id" "uuid",
    "banco_origen" "text" NOT NULL,
    "forma_pago" "text" NOT NULL,
    "monto_egreso" numeric(12,2) NOT NULL,
    "numero_referencia" "text",
    CONSTRAINT "detalle_pago_metodos_forma_pago_check" CHECK (("forma_pago" = ANY (ARRAY['transferencia'::"text", 'efectivo'::"text", 'cheque'::"text"]))),
    CONSTRAINT "detalle_pago_metodos_monto_egreso_check" CHECK (("monto_egreso" > (0)::numeric))
);


ALTER TABLE "public"."detalle_pago_metodos" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."detalle_rendicion_fpagos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "rendicion_id" "uuid",
    "monto" numeric(12,2) NOT NULL,
    "referencia_bancaria" "text",
    "cuenta_bancaria" "text",
    "capture_url" "text",
    "fpago_id" "uuid",
    "cuenta_bancaria_id" "uuid",
    "monto_bs" numeric(12,2) DEFAULT 0.00,
    "monto_usd" numeric(12,2) DEFAULT 0.00,
    CONSTRAINT "detalle_rendicion_pagos_monto_check" CHECK (("monto" >= (0)::numeric))
);


ALTER TABLE "public"."detalle_rendicion_fpagos" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."detalle_rendicion_ordenes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "rendicion_id" "uuid",
    "orden_distribucion_id" "uuid",
    "recaudado" numeric(14,2) DEFAULT 0.00,
    "recaudado_bs" numeric(12,2) DEFAULT 0.00
);


ALTER TABLE "public"."detalle_rendicion_ordenes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."empresas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "codigo_empresa" character varying(50) NOT NULL,
    "nombre_empresa" character varying(150) NOT NULL,
    "supabase_url" "text" NOT NULL,
    "supabase_anon_key" "text" NOT NULL,
    "activo" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."empresas" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."facturas_compras" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "proveedor_id" "uuid",
    "numero_factura" "text" NOT NULL,
    "fecha_emision" "date" NOT NULL,
    "fecha_vencimiento" "date",
    "monto_subtotal" numeric(12,2) NOT NULL,
    "monto_impuesto" numeric(12,2) DEFAULT 0.00,
    "monto_total" numeric(12,2) NOT NULL,
    "estado_pago" "text" DEFAULT 'pendiente'::"text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "facturas_compras_estado_pago_check" CHECK (("estado_pago" = ANY (ARRAY['pendiente'::"text", 'pago_parcial'::"text", 'pagada'::"text", 'vencida'::"text"])))
);


ALTER TABLE "public"."facturas_compras" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."fpagos" (
    "fpago_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "fpago_concepto" "text" NOT NULL,
    "fpago_info" boolean DEFAULT false NOT NULL,
    "es_bancario" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."fpagos" OWNER TO "postgres";


COMMENT ON COLUMN "public"."fpagos"."es_bancario" IS 'Indica si la forma de pago corresponde a una transacción bancaria/electrónica (Pago Móvil, Transferencia, Zelle, Binance, etc.)';



CREATE TABLE IF NOT EXISTS "public"."inventario_almacen" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "producto_id" "uuid",
    "stock_disponible" integer DEFAULT 0 NOT NULL,
    "stock_comprometido" integer DEFAULT 0 NOT NULL,
    "ubicacion_pasillo" "text",
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "inventario_almacen_stock_disponible_check" CHECK (("stock_disponible" >= 0))
);


ALTER TABLE "public"."inventario_almacen" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."inventario_movil" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "camion_id" "uuid",
    "producto_id" "uuid",
    "cantidad_cargada" integer DEFAULT 0 NOT NULL,
    "cantidad_entregada" integer DEFAULT 0 NOT NULL,
    "cantidad_devolucion" integer DEFAULT 0 NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "inventario_movil_cantidad_cargada_check" CHECK (("cantidad_cargada" >= 0)),
    CONSTRAINT "inventario_movil_cantidad_devolucion_check" CHECK (("cantidad_devolucion" >= 0)),
    CONSTRAINT "inventario_movil_cantidad_entregada_check" CHECK (("cantidad_entregada" >= 0))
);


ALTER TABLE "public"."inventario_movil" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."logs_auditoria" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "usuario_id" "uuid",
    "tabla_afectada" "text" NOT NULL,
    "accion" "text" NOT NULL,
    "registro_id" "uuid" NOT NULL,
    "valores_anteriores" "jsonb",
    "valores_nuevos" "jsonb",
    "fecha_registro" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."logs_auditoria" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."movimientos_contenedores" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "cliente_id" "uuid",
    "orden_id" "uuid",
    "contenedor_id" "uuid",
    "cantidad_entregada" integer DEFAULT 0 NOT NULL,
    "cantidad_retirada" integer DEFAULT 0 NOT NULL,
    "creado_por" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "movimientos_contenedores_cantidad_entregada_check" CHECK (("cantidad_entregada" >= 0)),
    CONSTRAINT "movimientos_contenedores_cantidad_retirada_check" CHECK (("cantidad_retirada" >= 0))
);


ALTER TABLE "public"."movimientos_contenedores" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."movimientos_saldo_favor" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "cliente_id" "uuid",
    "rendicion_id" "uuid",
    "orden_id" "uuid",
    "monto" numeric(12,2) NOT NULL,
    "tipo" "text" NOT NULL,
    "observaciones" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "movimientos_saldo_favor_tipo_check" CHECK (("tipo" = ANY (ARRAY['abono_recaudacion'::"text", 'cargo_pago_orden'::"text", 'devolucion_efectivo'::"text"])))
);


ALTER TABLE "public"."movimientos_saldo_favor" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."ordenes_distribucion" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "correlativo" integer NOT NULL,
    "cliente_id" "uuid",
    "camion_id" "uuid",
    "chofer_id" "uuid",
    "estado" "text" DEFAULT 'borrador'::"text",
    "fecha_despacho" timestamp with time zone,
    "peso_total_calculado" numeric(10,2) DEFAULT 0.00,
    "factura_origen_numero" character varying(30) NOT NULL,
    "creado_por" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "tasa_cambio" numeric(14,4),
    "total_recaudar_bs" numeric(14,2),
    "total_recaudar_usd" numeric(14,2),
    "vendedor_id" "uuid",
    "despachador_id" "uuid",
    "id_ruta" "uuid",
    "radar_id" "uuid",
    "es_autoventa" boolean DEFAULT false,
    CONSTRAINT "ordenes_distribucion_estado_check" CHECK (("estado" = ANY (ARRAY['borrador'::"text", 'aprobada'::"text", 'en_transito'::"text", 'despachada'::"text", 'por_liquidar'::"text", 'liquidada'::"text", 'anulada'::"text", 'devuelta'::"text"])))
);


ALTER TABLE "public"."ordenes_distribucion" OWNER TO "postgres";


COMMENT ON COLUMN "public"."ordenes_distribucion"."es_autoventa" IS 'Indica si la orden fue generada como venta en caliente en ruta de AutoVentas (sin radar).';



CREATE SEQUENCE IF NOT EXISTS "public"."ordenes_distribucion_correlativo_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."ordenes_distribucion_correlativo_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."ordenes_distribucion_correlativo_seq" OWNED BY "public"."ordenes_distribucion"."correlativo";



CREATE TABLE IF NOT EXISTS "public"."pagos_proveedores" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "proveedor_id" "uuid",
    "fecha_pago" timestamp with time zone DEFAULT "now"(),
    "monto_total_pagado" numeric(12,2) NOT NULL,
    "glosa_concepto" "text",
    "ejecutado_por" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "pagos_proveedores_monto_total_pagado_check" CHECK (("monto_total_pagado" > (0)::numeric))
);


ALTER TABLE "public"."pagos_proveedores" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."perfiles_usuario" (
    "id" "uuid" NOT NULL,
    "rol_id" "uuid",
    "nombre_completo" "text" NOT NULL,
    "telefono" "text",
    "activo" boolean DEFAULT true,
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "imagen_path" "text"
);


ALTER TABLE "public"."perfiles_usuario" OWNER TO "postgres";


COMMENT ON COLUMN "public"."perfiles_usuario"."imagen_path" IS 'Ruta relativa del avatar o fotografía del usuario en el almacenamiento de archivos (ej: /usuarios/avatar-001.webp)';



CREATE TABLE IF NOT EXISTS "public"."permisos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "codigo" "text" NOT NULL,
    "descripcion" "text",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."permisos" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."productos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "codigo_barras" "text",
    "nombre" "text" NOT NULL,
    "descripcion" "text",
    "unidad_medida" "text" DEFAULT 'unidades'::"text",
    "peso_unitario_kg" numeric(10,2) DEFAULT 0.00,
    "cant_unidad_medida" numeric(2,0) DEFAULT 0.00,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "codigo_producto" "text",
    "precio_lista1" numeric(12,2),
    "precio_lista2" numeric(12,2),
    "precio_lista3" numeric(12,2),
    "contenedor_id" "uuid",
    "unidades_por_contenedor" numeric(5,0) DEFAULT 1,
    "imagen_path" "text"
);


ALTER TABLE "public"."productos" OWNER TO "postgres";


COMMENT ON COLUMN "public"."productos"."imagen_path" IS 'Ruta relativa de la imagen del producto en el almacenamiento de archivos (ej: /productos/harina-pan.webp)';



CREATE TABLE IF NOT EXISTS "public"."proveedores" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "rif_nit" "text" NOT NULL,
    "razon_social" "text" NOT NULL,
    "direccion_fiscal" "text",
    "telefono" "text",
    "movil1" "text",
    "movil2" "text",
    "movil3" "text",
    "correo_e" "text",
    "activo" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."proveedores" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."radars" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "correlativo" integer NOT NULL,
    "despachador_id" "uuid" NOT NULL,
    "fecha_despacho" "date" DEFAULT CURRENT_DATE NOT NULL,
    "total_cantidad_solicitada" numeric(10,0) DEFAULT 0,
    "total_cantidad_despachada" numeric(10,0) DEFAULT 0,
    "total_contenedores_retirados" numeric(10,0) DEFAULT 0,
    "status_radar" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "carga_inventario_movil" boolean DEFAULT false
);


ALTER TABLE "public"."radars" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."radars_correlativo_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."radars_correlativo_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."radars_correlativo_seq" OWNED BY "public"."radars"."correlativo";



CREATE TABLE IF NOT EXISTS "public"."rendiciones_cuentas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "cliente_id" "uuid",
    "fecha_rendicion" timestamp with time zone DEFAULT "now"(),
    "total_efectivo_recaudado" numeric(12,2) DEFAULT 0.00,
    "total_transferencias_recaudado" numeric(12,2) DEFAULT 0.00,
    "total_devoluciones_valoradas" numeric(12,2) DEFAULT 0.00,
    "estado" "text" DEFAULT 'revision'::"text",
    "observaciones" "text",
    "auditado_por" "uuid",
    "tasa_cambio" numeric(10,4) DEFAULT 1.0000 NOT NULL,
    "total_recaudado_bs" numeric(12,2) DEFAULT 0.00,
    "total_recaudado_usd" numeric(12,2) DEFAULT 0.00,
    CONSTRAINT "rendiciones_cuentas_estado_check" CHECK (("estado" = ANY (ARRAY['revision'::"text", 'aprobada'::"text", 'con_discrepancia'::"text"])))
);


ALTER TABLE "public"."rendiciones_cuentas" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."roles" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "nombre" "text" NOT NULL,
    "descripcion" "text",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."roles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."roles_permisos" (
    "rol_id" "uuid" NOT NULL,
    "permiso_id" "uuid" NOT NULL
);


ALTER TABLE "public"."roles_permisos" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."rutas" (
    "id_ruta" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "nombre_ruta" "text" NOT NULL,
    "descripcion_ruta" "text",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."rutas" OWNER TO "postgres";


COMMENT ON TABLE "public"."rutas" IS 'Tabla maestra de rutas de despacho y distribución';



COMMENT ON COLUMN "public"."rutas"."id_ruta" IS 'Identificador único de la ruta (UUID)';



COMMENT ON COLUMN "public"."rutas"."nombre_ruta" IS 'Nombre identificador de la ruta (no nulo)';



COMMENT ON COLUMN "public"."rutas"."descripcion_ruta" IS 'Descripción o detalles adicionales de la ruta (acepta nulo)';



CREATE TABLE IF NOT EXISTS "public"."saldo_contenedores_clientes" (
    "cliente_id" "uuid" NOT NULL,
    "contenedor_id" "uuid" NOT NULL,
    "saldo_pendiente" integer DEFAULT 0 NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "saldo_contenedores_clientes_saldo_pendiente_check" CHECK (("saldo_pendiente" >= 0))
);


ALTER TABLE "public"."saldo_contenedores_clientes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."tasa_cambio" (
    "fecha_tasa" "date" NOT NULL,
    "tasa_cambio" numeric(14,4) NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."tasa_cambio" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."tipos_contenedores" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "codigo" "text" NOT NULL,
    "nombre" "text" NOT NULL,
    "descripcion" "text",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."tipos_contenedores" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."usuarios_empresas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "empresa_id" "uuid" NOT NULL,
    "rol" character varying(50) DEFAULT 'operador'::character varying,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."usuarios_empresas" OWNER TO "postgres";


ALTER TABLE ONLY "public"."ordenes_distribucion" ALTER COLUMN "correlativo" SET DEFAULT "nextval"('"public"."ordenes_distribucion_correlativo_seq"'::"regclass");



ALTER TABLE ONLY "public"."radars" ALTER COLUMN "correlativo" SET DEFAULT "nextval"('"public"."radars_correlativo_seq"'::"regclass");



ALTER TABLE ONLY "public"."camiones"
    ADD CONSTRAINT "camiones_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."camiones"
    ADD CONSTRAINT "camiones_placa_key" UNIQUE ("placa");



ALTER TABLE ONLY "public"."choferes"
    ADD CONSTRAINT "choferes_cedula_licencia_key" UNIQUE ("cedula_licencia");



ALTER TABLE ONLY "public"."choferes"
    ADD CONSTRAINT "choferes_pkey" PRIMARY KEY ("perfil_id");



ALTER TABLE ONLY "public"."clientes"
    ADD CONSTRAINT "clientes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."clientes"
    ADD CONSTRAINT "clientes_rif_nit_key" UNIQUE ("rif_nit");



ALTER TABLE ONLY "public"."cuentas_bancarias_empresa"
    ADD CONSTRAINT "cuentas_bancarias_empresa_cuenta_bancaria_key" UNIQUE ("cuenta_bancaria");



ALTER TABLE ONLY "public"."cuentas_bancarias_empresa"
    ADD CONSTRAINT "cuentas_bancarias_empresa_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."descuentos_cliente_producto"
    ADD CONSTRAINT "descuentos_cliente_producto_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."detalle_distribucion"
    ADD CONSTRAINT "detalle_distribucion_orden_id_producto_id_key" UNIQUE ("orden_id", "producto_id");



ALTER TABLE ONLY "public"."detalle_distribucion"
    ADD CONSTRAINT "detalle_distribucion_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."detalle_facturas_compras"
    ADD CONSTRAINT "detalle_facturas_compras_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."detalle_pago_facturas"
    ADD CONSTRAINT "detalle_pago_facturas_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."detalle_pago_metodos"
    ADD CONSTRAINT "detalle_pago_metodos_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."detalle_rendicion_ordenes"
    ADD CONSTRAINT "detalle_rendicion_ordenes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."detalle_rendicion_fpagos"
    ADD CONSTRAINT "detalle_rendicion_pagos_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."empresas"
    ADD CONSTRAINT "empresas_codigo_empresa_key" UNIQUE ("codigo_empresa");



ALTER TABLE ONLY "public"."empresas"
    ADD CONSTRAINT "empresas_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."facturas_compras"
    ADD CONSTRAINT "facturas_compras_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."facturas_compras"
    ADD CONSTRAINT "facturas_compras_proveedor_id_numero_factura_key" UNIQUE ("proveedor_id", "numero_factura");



ALTER TABLE ONLY "public"."fpagos"
    ADD CONSTRAINT "fpagos_fpago_concepto_key" UNIQUE ("fpago_concepto");



ALTER TABLE ONLY "public"."fpagos"
    ADD CONSTRAINT "fpagos_pkey" PRIMARY KEY ("fpago_id");



ALTER TABLE ONLY "public"."inventario_almacen"
    ADD CONSTRAINT "inventario_almacen_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."inventario_almacen"
    ADD CONSTRAINT "inventario_almacen_producto_id_key" UNIQUE ("producto_id");



ALTER TABLE ONLY "public"."inventario_movil"
    ADD CONSTRAINT "inventario_movil_camion_id_producto_id_key" UNIQUE ("camion_id", "producto_id");



ALTER TABLE ONLY "public"."inventario_movil"
    ADD CONSTRAINT "inventario_movil_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."logs_auditoria"
    ADD CONSTRAINT "logs_auditoria_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."movimientos_contenedores"
    ADD CONSTRAINT "movimientos_contenedores_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."movimientos_saldo_favor"
    ADD CONSTRAINT "movimientos_saldo_favor_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ordenes_distribucion"
    ADD CONSTRAINT "ordenes_distribucion_correlativo_key" UNIQUE ("correlativo");



ALTER TABLE ONLY "public"."ordenes_distribucion"
    ADD CONSTRAINT "ordenes_distribucion_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."pagos_proveedores"
    ADD CONSTRAINT "pagos_proveedores_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."perfiles_usuario"
    ADD CONSTRAINT "perfiles_usuario_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."permisos"
    ADD CONSTRAINT "permisos_codigo_key" UNIQUE ("codigo");



ALTER TABLE ONLY "public"."permisos"
    ADD CONSTRAINT "permisos_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."productos"
    ADD CONSTRAINT "productos_codigo_barras_key" UNIQUE ("codigo_barras");



ALTER TABLE ONLY "public"."productos"
    ADD CONSTRAINT "productos_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."proveedores"
    ADD CONSTRAINT "proveedores_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."proveedores"
    ADD CONSTRAINT "proveedores_rif_nit_key" UNIQUE ("rif_nit");



ALTER TABLE ONLY "public"."radars"
    ADD CONSTRAINT "radars_correlativo_key" UNIQUE ("correlativo");



ALTER TABLE ONLY "public"."radars"
    ADD CONSTRAINT "radars_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."rendiciones_cuentas"
    ADD CONSTRAINT "rendiciones_cuentas_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."roles"
    ADD CONSTRAINT "roles_nombre_key" UNIQUE ("nombre");



ALTER TABLE ONLY "public"."roles_permisos"
    ADD CONSTRAINT "roles_permisos_pkey" PRIMARY KEY ("rol_id", "permiso_id");



ALTER TABLE ONLY "public"."roles"
    ADD CONSTRAINT "roles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."rutas"
    ADD CONSTRAINT "rutas_pkey" PRIMARY KEY ("id_ruta");



ALTER TABLE ONLY "public"."saldo_contenedores_clientes"
    ADD CONSTRAINT "saldo_contenedores_clientes_pkey" PRIMARY KEY ("cliente_id", "contenedor_id");



ALTER TABLE ONLY "public"."tasa_cambio"
    ADD CONSTRAINT "tasa_cambio_pkey" PRIMARY KEY ("fecha_tasa");



ALTER TABLE ONLY "public"."tipos_contenedores"
    ADD CONSTRAINT "tipos_contenedores_codigo_key" UNIQUE ("codigo");



ALTER TABLE ONLY "public"."tipos_contenedores"
    ADD CONSTRAINT "tipos_contenedores_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."descuentos_cliente_producto"
    ADD CONSTRAINT "unique_cliente_producto_descuento" UNIQUE ("cliente_id", "producto_id");



ALTER TABLE ONLY "public"."usuarios_empresas"
    ADD CONSTRAINT "unique_user_empresa" UNIQUE ("user_id", "empresa_id");



ALTER TABLE ONLY "public"."productos"
    ADD CONSTRAINT "uq_productos_codigo_producto" UNIQUE ("codigo_producto");



ALTER TABLE ONLY "public"."usuarios_empresas"
    ADD CONSTRAINT "usuarios_empresas_pkey" PRIMARY KEY ("id");



CREATE INDEX "detalle_rendicion_ordenes_orden_distribucion_id_idx" ON "public"."detalle_rendicion_ordenes" USING "btree" ("orden_distribucion_id");



CREATE INDEX "idx_descuentos_cliente_id" ON "public"."descuentos_cliente_producto" USING "btree" ("cliente_id");



CREATE INDEX "idx_descuentos_producto_id" ON "public"."descuentos_cliente_producto" USING "btree" ("producto_id");



CREATE INDEX "idx_ordenes_distribucion_radar_id" ON "public"."ordenes_distribucion" USING "btree" ("radar_id");



CREATE INDEX "idx_radars_despachador_fecha" ON "public"."radars" USING "btree" ("despachador_id", "fecha_despacho");



CREATE INDEX "idx_radars_status" ON "public"."radars" USING "btree" ("status_radar");



CREATE OR REPLACE TRIGGER "audit_detalle_distribucion" AFTER INSERT OR DELETE OR UPDATE ON "public"."detalle_distribucion" FOR EACH ROW EXECUTE FUNCTION "public"."audit_changes_trigger"();



CREATE OR REPLACE TRIGGER "audit_inventario_almacen" AFTER INSERT OR DELETE OR UPDATE ON "public"."inventario_almacen" FOR EACH ROW EXECUTE FUNCTION "public"."audit_changes_trigger"();



CREATE OR REPLACE TRIGGER "audit_inventario_movil" AFTER INSERT OR DELETE OR UPDATE ON "public"."inventario_movil" FOR EACH ROW EXECUTE FUNCTION "public"."audit_changes_trigger"();



CREATE OR REPLACE TRIGGER "audit_movimientos_contenedores" AFTER INSERT OR DELETE OR UPDATE ON "public"."movimientos_contenedores" FOR EACH ROW EXECUTE FUNCTION "public"."audit_changes_trigger"();



CREATE OR REPLACE TRIGGER "audit_ordenes_distribucion" AFTER INSERT OR DELETE OR UPDATE ON "public"."ordenes_distribucion" FOR EACH ROW EXECUTE FUNCTION "public"."audit_changes_trigger"();



CREATE OR REPLACE TRIGGER "audit_pagos_proveedores" AFTER INSERT OR DELETE OR UPDATE ON "public"."pagos_proveedores" FOR EACH ROW EXECUTE FUNCTION "public"."procesar_log_auditoria"();



CREATE OR REPLACE TRIGGER "audit_rendiciones_cuentas" AFTER INSERT OR DELETE OR UPDATE ON "public"."rendiciones_cuentas" FOR EACH ROW EXECUTE FUNCTION "public"."procesar_log_auditoria"();



CREATE OR REPLACE TRIGGER "trigger_liquidar_ordenes_on_aprobacion" AFTER UPDATE ON "public"."rendiciones_cuentas" FOR EACH ROW EXECUTE FUNCTION "public"."on_rendicion_aprobada_trigger"();



ALTER TABLE ONLY "public"."choferes"
    ADD CONSTRAINT "choferes_perfil_id_fkey" FOREIGN KEY ("perfil_id") REFERENCES "public"."perfiles_usuario"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."clientes"
    ADD CONSTRAINT "clientes_despachador_id_fkey" FOREIGN KEY ("despachador_id") REFERENCES "public"."perfiles_usuario"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."clientes"
    ADD CONSTRAINT "clientes_id_ruta_fkey" FOREIGN KEY ("id_ruta") REFERENCES "public"."rutas"("id_ruta") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."clientes"
    ADD CONSTRAINT "clientes_vendedor_id_fkey" FOREIGN KEY ("vendedor_id") REFERENCES "public"."perfiles_usuario"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."descuentos_cliente_producto"
    ADD CONSTRAINT "descuentos_cliente_producto_cliente_id_fkey" FOREIGN KEY ("cliente_id") REFERENCES "public"."clientes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."descuentos_cliente_producto"
    ADD CONSTRAINT "descuentos_cliente_producto_producto_id_fkey" FOREIGN KEY ("producto_id") REFERENCES "public"."productos"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."detalle_distribucion"
    ADD CONSTRAINT "detalle_distribucion_contenedor_id_fkey" FOREIGN KEY ("contenedor_id") REFERENCES "public"."tipos_contenedores"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."detalle_distribucion"
    ADD CONSTRAINT "detalle_distribucion_orden_id_fkey" FOREIGN KEY ("orden_id") REFERENCES "public"."ordenes_distribucion"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."detalle_distribucion"
    ADD CONSTRAINT "detalle_distribucion_producto_id_fkey" FOREIGN KEY ("producto_id") REFERENCES "public"."productos"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."detalle_facturas_compras"
    ADD CONSTRAINT "detalle_facturas_compras_factura_id_fkey" FOREIGN KEY ("factura_id") REFERENCES "public"."facturas_compras"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."detalle_facturas_compras"
    ADD CONSTRAINT "detalle_facturas_compras_producto_id_fkey" FOREIGN KEY ("producto_id") REFERENCES "public"."productos"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."detalle_pago_facturas"
    ADD CONSTRAINT "detalle_pago_facturas_factura_id_fkey" FOREIGN KEY ("factura_id") REFERENCES "public"."facturas_compras"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."detalle_pago_facturas"
    ADD CONSTRAINT "detalle_pago_facturas_pago_id_fkey" FOREIGN KEY ("pago_id") REFERENCES "public"."pagos_proveedores"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."detalle_pago_metodos"
    ADD CONSTRAINT "detalle_pago_metodos_pago_id_fkey" FOREIGN KEY ("pago_id") REFERENCES "public"."pagos_proveedores"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."detalle_rendicion_fpagos"
    ADD CONSTRAINT "detalle_rendicion_fpagos_cuenta_bancaria_id_fkey" FOREIGN KEY ("cuenta_bancaria_id") REFERENCES "public"."cuentas_bancarias_empresa"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."detalle_rendicion_fpagos"
    ADD CONSTRAINT "detalle_rendicion_fpagos_fpago_id_fkey" FOREIGN KEY ("fpago_id") REFERENCES "public"."fpagos"("fpago_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."detalle_rendicion_ordenes"
    ADD CONSTRAINT "detalle_rendicion_ordenes_orden_distribucion_id_fkey" FOREIGN KEY ("orden_distribucion_id") REFERENCES "public"."ordenes_distribucion"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."detalle_rendicion_ordenes"
    ADD CONSTRAINT "detalle_rendicion_ordenes_rendicion_id_fkey" FOREIGN KEY ("rendicion_id") REFERENCES "public"."rendiciones_cuentas"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."detalle_rendicion_fpagos"
    ADD CONSTRAINT "detalle_rendicion_pagos_rendicion_id_fkey" FOREIGN KEY ("rendicion_id") REFERENCES "public"."rendiciones_cuentas"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."facturas_compras"
    ADD CONSTRAINT "facturas_compras_proveedor_id_fkey" FOREIGN KEY ("proveedor_id") REFERENCES "public"."proveedores"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."inventario_almacen"
    ADD CONSTRAINT "inventario_almacen_producto_id_fkey" FOREIGN KEY ("producto_id") REFERENCES "public"."productos"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."inventario_movil"
    ADD CONSTRAINT "inventario_movil_camion_id_fkey" FOREIGN KEY ("camion_id") REFERENCES "public"."camiones"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."inventario_movil"
    ADD CONSTRAINT "inventario_movil_producto_id_fkey" FOREIGN KEY ("producto_id") REFERENCES "public"."productos"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."logs_auditoria"
    ADD CONSTRAINT "logs_auditoria_usuario_id_fkey" FOREIGN KEY ("usuario_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."movimientos_contenedores"
    ADD CONSTRAINT "movimientos_contenedores_cliente_id_fkey" FOREIGN KEY ("cliente_id") REFERENCES "public"."clientes"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."movimientos_contenedores"
    ADD CONSTRAINT "movimientos_contenedores_contenedor_id_fkey" FOREIGN KEY ("contenedor_id") REFERENCES "public"."tipos_contenedores"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."movimientos_contenedores"
    ADD CONSTRAINT "movimientos_contenedores_creado_por_fkey" FOREIGN KEY ("creado_por") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."movimientos_contenedores"
    ADD CONSTRAINT "movimientos_contenedores_orden_id_fkey" FOREIGN KEY ("orden_id") REFERENCES "public"."ordenes_distribucion"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."movimientos_saldo_favor"
    ADD CONSTRAINT "movimientos_saldo_favor_cliente_id_fkey" FOREIGN KEY ("cliente_id") REFERENCES "public"."clientes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."movimientos_saldo_favor"
    ADD CONSTRAINT "movimientos_saldo_favor_orden_id_fkey" FOREIGN KEY ("orden_id") REFERENCES "public"."ordenes_distribucion"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."movimientos_saldo_favor"
    ADD CONSTRAINT "movimientos_saldo_favor_rendicion_id_fkey" FOREIGN KEY ("rendicion_id") REFERENCES "public"."rendiciones_cuentas"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."ordenes_distribucion"
    ADD CONSTRAINT "ordenes_distribucion_camion_id_fkey" FOREIGN KEY ("camion_id") REFERENCES "public"."camiones"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."ordenes_distribucion"
    ADD CONSTRAINT "ordenes_distribucion_cliente_id_fkey" FOREIGN KEY ("cliente_id") REFERENCES "public"."clientes"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."ordenes_distribucion"
    ADD CONSTRAINT "ordenes_distribucion_creado_por_fkey" FOREIGN KEY ("creado_por") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."ordenes_distribucion"
    ADD CONSTRAINT "ordenes_distribucion_despachador_id_fkey" FOREIGN KEY ("despachador_id") REFERENCES "public"."perfiles_usuario"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."ordenes_distribucion"
    ADD CONSTRAINT "ordenes_distribucion_id_ruta_fkey" FOREIGN KEY ("id_ruta") REFERENCES "public"."rutas"("id_ruta") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."ordenes_distribucion"
    ADD CONSTRAINT "ordenes_distribucion_radar_id_fkey" FOREIGN KEY ("radar_id") REFERENCES "public"."radars"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."ordenes_distribucion"
    ADD CONSTRAINT "ordenes_distribucion_vendedor_id_fkey" FOREIGN KEY ("vendedor_id") REFERENCES "public"."perfiles_usuario"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."pagos_proveedores"
    ADD CONSTRAINT "pagos_proveedores_ejecutado_por_fkey" FOREIGN KEY ("ejecutado_por") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."pagos_proveedores"
    ADD CONSTRAINT "pagos_proveedores_proveedor_id_fkey" FOREIGN KEY ("proveedor_id") REFERENCES "public"."proveedores"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."perfiles_usuario"
    ADD CONSTRAINT "perfiles_usuario_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."perfiles_usuario"
    ADD CONSTRAINT "perfiles_usuario_rol_id_fkey" FOREIGN KEY ("rol_id") REFERENCES "public"."roles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."productos"
    ADD CONSTRAINT "productos_contenedor_id_fkey" FOREIGN KEY ("contenedor_id") REFERENCES "public"."tipos_contenedores"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."radars"
    ADD CONSTRAINT "radars_despachador_id_fkey" FOREIGN KEY ("despachador_id") REFERENCES "public"."perfiles_usuario"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."rendiciones_cuentas"
    ADD CONSTRAINT "rendiciones_cuentas_auditado_por_fkey" FOREIGN KEY ("auditado_por") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."rendiciones_cuentas"
    ADD CONSTRAINT "rendiciones_cuentas_cliente_id_fkey" FOREIGN KEY ("cliente_id") REFERENCES "public"."clientes"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."roles_permisos"
    ADD CONSTRAINT "roles_permisos_permiso_id_fkey" FOREIGN KEY ("permiso_id") REFERENCES "public"."permisos"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."roles_permisos"
    ADD CONSTRAINT "roles_permisos_rol_id_fkey" FOREIGN KEY ("rol_id") REFERENCES "public"."roles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."saldo_contenedores_clientes"
    ADD CONSTRAINT "saldo_contenedores_clientes_cliente_id_fkey" FOREIGN KEY ("cliente_id") REFERENCES "public"."clientes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."saldo_contenedores_clientes"
    ADD CONSTRAINT "saldo_contenedores_clientes_contenedor_id_fkey" FOREIGN KEY ("contenedor_id") REFERENCES "public"."tipos_contenedores"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."usuarios_empresas"
    ADD CONSTRAINT "usuarios_empresas_empresa_id_fkey" FOREIGN KEY ("empresa_id") REFERENCES "public"."empresas"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."usuarios_empresas"
    ADD CONSTRAINT "usuarios_empresas_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



CREATE POLICY "Admin y Gerente pueden gestionar rutas" ON "public"."rutas" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM ("public"."perfiles_usuario" "p"
     JOIN "public"."roles" "r" ON (("p"."rol_id" = "r"."id")))
  WHERE (("p"."id" = "auth"."uid"()) AND ("r"."nombre" = ANY (ARRAY['admin'::"text", 'gerente'::"text"]))))));



CREATE POLICY "Allow users to read assigned empresa details" ON "public"."empresas" FOR SELECT TO "authenticated" USING (("id" IN ( SELECT "usuarios_empresas"."empresa_id"
   FROM "public"."usuarios_empresas"
  WHERE ("usuarios_empresas"."user_id" = "auth"."uid"()))));



CREATE POLICY "Allow users to read their own mapping" ON "public"."usuarios_empresas" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Permitir administracion de tasa_cambio a usuarios autorizados" ON "public"."tasa_cambio" TO "authenticated" USING ("public"."user_has_role"(ARRAY['admin'::"text", 'gerente'::"text"]));



CREATE POLICY "Permitir edicion autenticada de cuentas bancarias" ON "public"."cuentas_bancarias_empresa" TO "authenticated" USING (true);



CREATE POLICY "Permitir insercion y actualizacion de radares a usuarios autent" ON "public"."radars" TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "Permitir lectura autenticada de cuentas bancarias" ON "public"."cuentas_bancarias_empresa" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Permitir lectura autenticada de fpagos" ON "public"."fpagos" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Permitir lectura de radares a usuarios autenticados" ON "public"."radars" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Permitir lectura de tasa_cambio a usuarios autenticados" ON "public"."tasa_cambio" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Permitir lectura publica a autenticados en descuentos_cliente_p" ON "public"."descuentos_cliente_producto" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Permitir todo a autenticados en descuentos_cliente_producto" ON "public"."descuentos_cliente_producto" TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "Usuarios autenticados pueden ver rutas" ON "public"."rutas" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."camiones" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "camiones_select" ON "public"."camiones" FOR SELECT TO "authenticated" USING ("public"."lt_is_staff"());



CREATE POLICY "camiones_write_staff" ON "public"."camiones" TO "authenticated" USING ("public"."lt_is_staff"()) WITH CHECK ("public"."lt_is_staff"());



ALTER TABLE "public"."choferes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "choferes_select" ON "public"."choferes" FOR SELECT TO "authenticated" USING (("public"."lt_is_staff"() OR ("perfil_id" = "auth"."uid"())));



CREATE POLICY "choferes_write_staff" ON "public"."choferes" TO "authenticated" USING ("public"."lt_is_admin"()) WITH CHECK ("public"."lt_is_admin"());



ALTER TABLE "public"."clientes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "clientes_select" ON "public"."clientes" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "clientes_write_staff" ON "public"."clientes" TO "authenticated" USING ("public"."lt_is_staff"()) WITH CHECK ("public"."lt_is_staff"());



ALTER TABLE "public"."cuentas_bancarias_empresa" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."descuentos_cliente_producto" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."detalle_distribucion" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."detalle_facturas_compras" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."detalle_pago_facturas" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."detalle_pago_metodos" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."detalle_rendicion_fpagos" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."detalle_rendicion_ordenes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "detalle_select" ON "public"."detalle_distribucion" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."ordenes_distribucion" "o"
  WHERE (("o"."id" = "detalle_distribucion"."orden_id") AND ("public"."lt_is_staff"() OR ("o"."chofer_id" = "auth"."uid"()))))));



CREATE POLICY "detalle_write_staff" ON "public"."detalle_distribucion" TO "authenticated" USING ("public"."lt_is_staff"()) WITH CHECK ("public"."lt_is_staff"());



ALTER TABLE "public"."empresas" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."facturas_compras" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "facturas_select" ON "public"."facturas_compras" FOR SELECT TO "authenticated" USING ("public"."lt_can_finanzas"());



CREATE POLICY "facturas_write" ON "public"."facturas_compras" TO "authenticated" USING ("public"."lt_can_finanzas"()) WITH CHECK ("public"."lt_can_finanzas"());



ALTER TABLE "public"."fpagos" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "inv_almacen_select" ON "public"."inventario_almacen" FOR SELECT TO "authenticated" USING ("public"."lt_is_staff"());



CREATE POLICY "inv_almacen_write" ON "public"."inventario_almacen" TO "authenticated" USING ("public"."lt_is_staff"()) WITH CHECK ("public"."lt_is_staff"());



CREATE POLICY "inv_movil_select" ON "public"."inventario_movil" FOR SELECT TO "authenticated" USING (("public"."lt_is_staff"() OR ("public"."lt_current_user_rol"() = 'chofer_cobrador'::"text")));



CREATE POLICY "inv_movil_write" ON "public"."inventario_movil" TO "authenticated" USING ("public"."lt_is_staff"()) WITH CHECK ("public"."lt_is_staff"());



ALTER TABLE "public"."inventario_almacen" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."inventario_movil" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."logs_auditoria" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "modify_movimientos_contenedores" ON "public"."movimientos_contenedores" TO "authenticated" USING ("public"."user_has_role"(ARRAY['admin'::"text", 'gerente'::"text", 'despachador'::"text", 'vendedor'::"text"]));



CREATE POLICY "modify_movimientos_saldo_favor" ON "public"."movimientos_saldo_favor" TO "authenticated" USING ("public"."user_has_role"(ARRAY['admin'::"text", 'gerente'::"text", 'despachador'::"text", 'vendedor'::"text"]));



CREATE POLICY "modify_ordenes_distribucion" ON "public"."ordenes_distribucion" USING (("public"."user_has_role"(ARRAY['admin'::"text", 'gerente'::"text", 'despachador'::"text"]) OR ("public"."user_has_role"(ARRAY['vendedor'::"text"]) AND ("creado_por" = "auth"."uid"()))));



CREATE POLICY "modify_saldo_contenedores_clientes" ON "public"."saldo_contenedores_clientes" TO "authenticated" USING ("public"."user_has_role"(ARRAY['admin'::"text", 'gerente'::"text", 'despachador'::"text", 'vendedor'::"text"]));



CREATE POLICY "modify_tipos_contenedores" ON "public"."tipos_contenedores" TO "authenticated" USING ("public"."user_has_role"(ARRAY['admin'::"text", 'gerente'::"text", 'despachador'::"text"]));



ALTER TABLE "public"."movimientos_contenedores" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."movimientos_saldo_favor" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."ordenes_distribucion" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "ordenes_insert_staff" ON "public"."ordenes_distribucion" FOR INSERT TO "authenticated" WITH CHECK ("public"."lt_is_staff"());



CREATE POLICY "ordenes_select" ON "public"."ordenes_distribucion" FOR SELECT TO "authenticated" USING (("public"."lt_is_staff"() OR ("chofer_id" = "auth"."uid"())));



CREATE POLICY "ordenes_update_chofer" ON "public"."ordenes_distribucion" FOR UPDATE TO "authenticated" USING ((("public"."lt_current_user_rol"() = 'chofer_cobrador'::"text") AND ("chofer_id" = "auth"."uid"()))) WITH CHECK (("chofer_id" = "auth"."uid"()));



CREATE POLICY "ordenes_update_staff" ON "public"."ordenes_distribucion" FOR UPDATE TO "authenticated" USING ("public"."lt_is_staff"()) WITH CHECK ("public"."lt_is_staff"());



ALTER TABLE "public"."pagos_proveedores" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "pagos_select" ON "public"."pagos_proveedores" FOR SELECT TO "authenticated" USING ("public"."lt_can_finanzas"());



CREATE POLICY "pagos_write" ON "public"."pagos_proveedores" TO "authenticated" USING ("public"."lt_can_finanzas"()) WITH CHECK ("public"."lt_can_finanzas"());



CREATE POLICY "perfiles_select_own_or_admin" ON "public"."perfiles_usuario" FOR SELECT TO "authenticated" USING ((("id" = "auth"."uid"()) OR "public"."lt_is_admin"()));



CREATE POLICY "perfiles_update_own" ON "public"."perfiles_usuario" FOR UPDATE TO "authenticated" USING (("id" = "auth"."uid"())) WITH CHECK (("id" = "auth"."uid"()));



ALTER TABLE "public"."perfiles_usuario" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."permisos" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."productos" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "productos_select" ON "public"."productos" FOR SELECT TO "authenticated" USING ("public"."lt_is_staff"());



CREATE POLICY "productos_write_staff" ON "public"."productos" TO "authenticated" USING ("public"."lt_is_staff"()) WITH CHECK ("public"."lt_is_staff"());



ALTER TABLE "public"."proveedores" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "proveedores_select" ON "public"."proveedores" FOR SELECT TO "authenticated" USING ("public"."lt_can_finanzas"());



CREATE POLICY "proveedores_write_finanzas" ON "public"."proveedores" TO "authenticated" USING ("public"."lt_can_finanzas"()) WITH CHECK ("public"."lt_can_finanzas"());



ALTER TABLE "public"."radars" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."rendiciones_cuentas" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "rendiciones_select" ON "public"."rendiciones_cuentas" FOR SELECT TO "authenticated" USING (("public"."lt_can_finanzas"() OR ("public"."lt_current_user_rol"() = 'despachador'::"text") OR ("public"."lt_current_user_rol"() = 'chofer_cobrador'::"text")));



CREATE POLICY "rendiciones_write_finanzas" ON "public"."rendiciones_cuentas" TO "authenticated" USING (("public"."lt_can_finanzas"() OR ("public"."lt_current_user_rol"() = 'despachador'::"text"))) WITH CHECK (("public"."lt_can_finanzas"() OR ("public"."lt_current_user_rol"() = 'despachador'::"text")));



ALTER TABLE "public"."roles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."roles_permisos" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "roles_select_own" ON "public"."roles" FOR SELECT TO "authenticated" USING (("public"."lt_is_admin"() OR ("id" IN ( SELECT "perfiles_usuario"."rol_id"
   FROM "public"."perfiles_usuario"
  WHERE ("perfiles_usuario"."id" = "auth"."uid"())))));



ALTER TABLE "public"."rutas" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."saldo_contenedores_clientes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "select_movimientos_contenedores" ON "public"."movimientos_contenedores" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "select_movimientos_saldo_favor" ON "public"."movimientos_saldo_favor" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "select_ordenes_distribucion" ON "public"."ordenes_distribucion" FOR SELECT USING ("public"."user_has_role"(ARRAY['admin'::"text", 'gerente'::"text", 'despachador'::"text"]));



CREATE POLICY "select_saldo_contenedores_clientes" ON "public"."saldo_contenedores_clientes" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "select_tipos_contenedores" ON "public"."tipos_contenedores" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."tasa_cambio" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."tipos_contenedores" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."usuarios_empresas" ENABLE ROW LEVEL SECURITY;


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON FUNCTION "public"."actualiza_orden_distribucion_segun_correlativo"("p_correlativo" integer, "p_header" "jsonb", "p_detalle" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."actualiza_orden_distribucion_segun_correlativo"("p_correlativo" integer, "p_header" "jsonb", "p_detalle" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."actualiza_orden_distribucion_segun_correlativo"("p_correlativo" integer, "p_header" "jsonb", "p_detalle" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."actualiza_registro_cliente_segun_uuid"("p_id" "uuid", "p_rif_nit" "text", "p_razon_social" "text", "p_direccion_fiscal" "text", "p_telefono" "text", "p_movil1" "text", "p_movil2" "text", "p_movil3" "text", "p_correo_e" "text", "p_cond_liq" numeric, "p_max_liq" numeric, "p_vendedor_id" "uuid", "p_despachador_id" "uuid", "p_id_ruta" "uuid", "p_activo" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."actualiza_registro_cliente_segun_uuid"("p_id" "uuid", "p_rif_nit" "text", "p_razon_social" "text", "p_direccion_fiscal" "text", "p_telefono" "text", "p_movil1" "text", "p_movil2" "text", "p_movil3" "text", "p_correo_e" "text", "p_cond_liq" numeric, "p_max_liq" numeric, "p_vendedor_id" "uuid", "p_despachador_id" "uuid", "p_id_ruta" "uuid", "p_activo" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."actualiza_registro_cliente_segun_uuid"("p_id" "uuid", "p_rif_nit" "text", "p_razon_social" "text", "p_direccion_fiscal" "text", "p_telefono" "text", "p_movil1" "text", "p_movil2" "text", "p_movil3" "text", "p_correo_e" "text", "p_cond_liq" numeric, "p_max_liq" numeric, "p_vendedor_id" "uuid", "p_despachador_id" "uuid", "p_id_ruta" "uuid", "p_activo" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."actualiza_registro_cliente_segun_uuid"("p_id" "uuid", "p_rif_nit" "text", "p_razon_social" "text", "p_direccion_fiscal" "text", "p_telefono" "text", "p_movil1" "text", "p_movil2" "text", "p_movil3" "text", "p_correo_e" "text", "p_cond_liq" numeric, "p_max_liq" numeric, "p_vendedor_id" "uuid", "p_despachador_id" "uuid", "p_id_ruta" "uuid", "p_activo" boolean, "p_limite_credito" numeric, "p_max_facturas_vencidas" integer, "p_permiso_despacho_manual" boolean, "p_excepcion_despacho_gerencia" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."actualiza_registro_cliente_segun_uuid"("p_id" "uuid", "p_rif_nit" "text", "p_razon_social" "text", "p_direccion_fiscal" "text", "p_telefono" "text", "p_movil1" "text", "p_movil2" "text", "p_movil3" "text", "p_correo_e" "text", "p_cond_liq" numeric, "p_max_liq" numeric, "p_vendedor_id" "uuid", "p_despachador_id" "uuid", "p_id_ruta" "uuid", "p_activo" boolean, "p_limite_credito" numeric, "p_max_facturas_vencidas" integer, "p_permiso_despacho_manual" boolean, "p_excepcion_despacho_gerencia" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."actualiza_registro_cliente_segun_uuid"("p_id" "uuid", "p_rif_nit" "text", "p_razon_social" "text", "p_direccion_fiscal" "text", "p_telefono" "text", "p_movil1" "text", "p_movil2" "text", "p_movil3" "text", "p_correo_e" "text", "p_cond_liq" numeric, "p_max_liq" numeric, "p_vendedor_id" "uuid", "p_despachador_id" "uuid", "p_id_ruta" "uuid", "p_activo" boolean, "p_limite_credito" numeric, "p_max_facturas_vencidas" integer, "p_permiso_despacho_manual" boolean, "p_excepcion_despacho_gerencia" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."actualiza_registro_rutas_segun_uuid"("p_id_ruta" "uuid", "p_nombre_ruta" "text", "p_descripcion_ruta" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."actualiza_registro_rutas_segun_uuid"("p_id_ruta" "uuid", "p_nombre_ruta" "text", "p_descripcion_ruta" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."actualiza_registro_rutas_segun_uuid"("p_id_ruta" "uuid", "p_nombre_ruta" "text", "p_descripcion_ruta" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."actualizar_cuenta_bancaria_empresa"("p_id" "uuid", "p_cuenta_bancaria" "text", "p_entidad_bancaria" "text", "p_status_cuenta" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."actualizar_cuenta_bancaria_empresa"("p_id" "uuid", "p_cuenta_bancaria" "text", "p_entidad_bancaria" "text", "p_status_cuenta" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."actualizar_cuenta_bancaria_empresa"("p_id" "uuid", "p_cuenta_bancaria" "text", "p_entidad_bancaria" "text", "p_status_cuenta" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."actualizar_estado_orden_distribucion"("p_orden_id" "uuid", "p_estado" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."actualizar_estado_orden_distribucion"("p_orden_id" "uuid", "p_estado" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."actualizar_estado_orden_distribucion"("p_orden_id" "uuid", "p_estado" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."actualizar_registro_perfil_usuarios_segun_id"("p_id" "uuid", "p_rol_id" "uuid", "p_nombre_completo" "text", "p_telefono" "text", "p_activo" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."actualizar_registro_perfil_usuarios_segun_id"("p_id" "uuid", "p_rol_id" "uuid", "p_nombre_completo" "text", "p_telefono" "text", "p_activo" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."actualizar_registro_perfil_usuarios_segun_id"("p_id" "uuid", "p_rol_id" "uuid", "p_nombre_completo" "text", "p_telefono" "text", "p_activo" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."actualizar_registro_productos_segun_id"("p_id" "uuid", "p_codigo_producto" "text", "p_nombre" "text", "p_codigo_barras" "text", "p_precio_lista1" numeric, "p_precio_lista2" numeric, "p_precio_lista3" numeric) TO "anon";
GRANT ALL ON FUNCTION "public"."actualizar_registro_productos_segun_id"("p_id" "uuid", "p_codigo_producto" "text", "p_nombre" "text", "p_codigo_barras" "text", "p_precio_lista1" numeric, "p_precio_lista2" numeric, "p_precio_lista3" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."actualizar_registro_productos_segun_id"("p_id" "uuid", "p_codigo_producto" "text", "p_nombre" "text", "p_codigo_barras" "text", "p_precio_lista1" numeric, "p_precio_lista2" numeric, "p_precio_lista3" numeric) TO "service_role";



GRANT ALL ON FUNCTION "public"."actualizar_registro_productos_segun_id"("p_id" "uuid", "p_codigo_producto" "text", "p_nombre" "text", "p_codigo_barras" "text", "p_precio_lista1" numeric, "p_precio_lista2" numeric, "p_precio_lista3" numeric, "p_descripcion" "text", "p_cant_unidad_medida" numeric, "p_contenedor_id" "uuid", "p_unidades_por_contenedor" numeric, "p_imagen_path" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."actualizar_registro_productos_segun_id"("p_id" "uuid", "p_codigo_producto" "text", "p_nombre" "text", "p_codigo_barras" "text", "p_precio_lista1" numeric, "p_precio_lista2" numeric, "p_precio_lista3" numeric, "p_descripcion" "text", "p_cant_unidad_medida" numeric, "p_contenedor_id" "uuid", "p_unidades_por_contenedor" numeric, "p_imagen_path" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."actualizar_registro_productos_segun_id"("p_id" "uuid", "p_codigo_producto" "text", "p_nombre" "text", "p_codigo_barras" "text", "p_precio_lista1" numeric, "p_precio_lista2" numeric, "p_precio_lista3" numeric, "p_descripcion" "text", "p_cant_unidad_medida" numeric, "p_contenedor_id" "uuid", "p_unidades_por_contenedor" numeric, "p_imagen_path" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."anular_orden_distribucion"("p_orden_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."anular_orden_distribucion"("p_orden_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."anular_orden_distribucion"("p_orden_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."aprobar_despacho_orden_distribucion"("p_orden_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."aprobar_despacho_orden_distribucion"("p_orden_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."aprobar_despacho_orden_distribucion"("p_orden_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."aprobar_orden_distribucion"("p_orden_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."aprobar_orden_distribucion"("p_orden_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."aprobar_orden_distribucion"("p_orden_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."asignar_usuario_empresa"("p_user_id" "uuid", "p_empresa_id" "uuid", "p_rol" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."asignar_usuario_empresa"("p_user_id" "uuid", "p_empresa_id" "uuid", "p_rol" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."asignar_usuario_empresa"("p_user_id" "uuid", "p_empresa_id" "uuid", "p_rol" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."audit_changes_trigger"() TO "anon";
GRANT ALL ON FUNCTION "public"."audit_changes_trigger"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."audit_changes_trigger"() TO "service_role";



GRANT ALL ON FUNCTION "public"."cambiar_status_cuenta_bancaria_empresa"("p_id" "uuid", "p_status_cuenta" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."cambiar_status_cuenta_bancaria_empresa"("p_id" "uuid", "p_status_cuenta" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."cambiar_status_cuenta_bancaria_empresa"("p_id" "uuid", "p_status_cuenta" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."cargar_inventario_movil"("p_orden_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."cargar_inventario_movil"("p_orden_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cargar_inventario_movil"("p_orden_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."consulta_registros_formas_pago"() TO "anon";
GRANT ALL ON FUNCTION "public"."consulta_registros_formas_pago"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."consulta_registros_formas_pago"() TO "service_role";



GRANT ALL ON FUNCTION "public"."crea_nueva_empresa"("p_codigo_empresa" character varying, "p_nombre_empresa" character varying, "p_supabase_url" "text", "p_supabase_anon_key" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."crea_nueva_empresa"("p_codigo_empresa" character varying, "p_nombre_empresa" character varying, "p_supabase_url" "text", "p_supabase_anon_key" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."crea_nueva_empresa"("p_codigo_empresa" character varying, "p_nombre_empresa" character varying, "p_supabase_url" "text", "p_supabase_anon_key" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."crear_cuenta_bancaria_empresa"("p_cuenta_bancaria" "text", "p_entidad_bancaria" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."crear_cuenta_bancaria_empresa"("p_cuenta_bancaria" "text", "p_entidad_bancaria" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."crear_cuenta_bancaria_empresa"("p_cuenta_bancaria" "text", "p_entidad_bancaria" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."crear_o_obtener_radar"("p_despachador_id" "uuid", "p_fecha_despacho" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."crear_o_obtener_radar"("p_despachador_id" "uuid", "p_fecha_despacho" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."crear_o_obtener_radar"("p_despachador_id" "uuid", "p_fecha_despacho" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."crear_orden_distribucion"("p_vendedor_id" "uuid", "p_chofer_id" "uuid", "p_cliente_id" "uuid", "p_camion_id" "uuid", "p_productos_json" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."crear_orden_distribucion"("p_vendedor_id" "uuid", "p_chofer_id" "uuid", "p_cliente_id" "uuid", "p_camion_id" "uuid", "p_productos_json" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."crear_orden_distribucion"("p_vendedor_id" "uuid", "p_chofer_id" "uuid", "p_cliente_id" "uuid", "p_camion_id" "uuid", "p_productos_json" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."crear_orden_distribucion"("p_vendedor_id" "uuid", "p_cliente_id" "uuid", "p_camion_id" "uuid", "p_tasa_cambio" numeric, "p_productos_json" "jsonb", "p_despachador_id" "uuid", "p_id_ruta" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."crear_orden_distribucion"("p_vendedor_id" "uuid", "p_cliente_id" "uuid", "p_camion_id" "uuid", "p_tasa_cambio" numeric, "p_productos_json" "jsonb", "p_despachador_id" "uuid", "p_id_ruta" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."crear_orden_distribucion"("p_vendedor_id" "uuid", "p_cliente_id" "uuid", "p_camion_id" "uuid", "p_tasa_cambio" numeric, "p_productos_json" "jsonb", "p_despachador_id" "uuid", "p_id_ruta" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."crear_perfil_usuario_nuevo"() TO "anon";
GRANT ALL ON FUNCTION "public"."crear_perfil_usuario_nuevo"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."crear_perfil_usuario_nuevo"() TO "service_role";



GRANT ALL ON FUNCTION "public"."elimina_tasa_cambio"("p_fecha_tasa" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."elimina_tasa_cambio"("p_fecha_tasa" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."elimina_tasa_cambio"("p_fecha_tasa" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."guardar_resultado_despacho_radar"("p_radar_id" "uuid", "p_despacho_json" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."guardar_resultado_despacho_radar"("p_radar_id" "uuid", "p_despacho_json" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."guardar_resultado_despacho_radar"("p_radar_id" "uuid", "p_despacho_json" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."inserta_tasa_cambio"("p_fecha_tasa" "date", "p_tasa" numeric) TO "anon";
GRANT ALL ON FUNCTION "public"."inserta_tasa_cambio"("p_fecha_tasa" "date", "p_tasa" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."inserta_tasa_cambio"("p_fecha_tasa" "date", "p_tasa" numeric) TO "service_role";



GRANT ALL ON FUNCTION "public"."liquidar_orden_distribucion"("p_orden_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."liquidar_orden_distribucion"("p_orden_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."liquidar_orden_distribucion"("p_orden_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."lt_can_finanzas"() TO "anon";
GRANT ALL ON FUNCTION "public"."lt_can_finanzas"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."lt_can_finanzas"() TO "service_role";



GRANT ALL ON FUNCTION "public"."lt_current_user_rol"() TO "anon";
GRANT ALL ON FUNCTION "public"."lt_current_user_rol"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."lt_current_user_rol"() TO "service_role";



GRANT ALL ON FUNCTION "public"."lt_is_admin"() TO "anon";
GRANT ALL ON FUNCTION "public"."lt_is_admin"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."lt_is_admin"() TO "service_role";



GRANT ALL ON FUNCTION "public"."lt_is_staff"() TO "anon";
GRANT ALL ON FUNCTION "public"."lt_is_staff"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."lt_is_staff"() TO "service_role";



GRANT ALL ON FUNCTION "public"."on_rendicion_aprobada_trigger"() TO "anon";
GRANT ALL ON FUNCTION "public"."on_rendicion_aprobada_trigger"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."on_rendicion_aprobada_trigger"() TO "service_role";



GRANT ALL ON FUNCTION "public"."otorgar_excepcion_despacho_gerencia"("p_cliente_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."otorgar_excepcion_despacho_gerencia"("p_cliente_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."otorgar_excepcion_despacho_gerencia"("p_cliente_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."procesar_log_auditoria"() TO "anon";
GRANT ALL ON FUNCTION "public"."procesar_log_auditoria"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."procesar_log_auditoria"() TO "service_role";



GRANT ALL ON FUNCTION "public"."reasignar_orden_a_radar"("p_orden_id" "uuid", "p_nuevo_radar_id" "uuid", "p_nueva_fecha" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."reasignar_orden_a_radar"("p_orden_id" "uuid", "p_nuevo_radar_id" "uuid", "p_nueva_fecha" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."reasignar_orden_a_radar"("p_orden_id" "uuid", "p_nuevo_radar_id" "uuid", "p_nueva_fecha" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."registra_nuevo_producto_retorna_id"("p_codigo_producto" "text", "p_nombre" "text", "p_codigo_barras" "text", "p_descripcion" "text", "p_cant_unidad_medida" numeric, "p_precio_lista1" numeric, "p_precio_lista2" numeric, "p_precio_lista3" numeric, "p_contenedor_id" "uuid", "p_unidades_por_contenedor" numeric, "p_imagen_path" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."registra_nuevo_producto_retorna_id"("p_codigo_producto" "text", "p_nombre" "text", "p_codigo_barras" "text", "p_descripcion" "text", "p_cant_unidad_medida" numeric, "p_precio_lista1" numeric, "p_precio_lista2" numeric, "p_precio_lista3" numeric, "p_contenedor_id" "uuid", "p_unidades_por_contenedor" numeric, "p_imagen_path" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."registra_nuevo_producto_retorna_id"("p_codigo_producto" "text", "p_nombre" "text", "p_codigo_barras" "text", "p_descripcion" "text", "p_cant_unidad_medida" numeric, "p_precio_lista1" numeric, "p_precio_lista2" numeric, "p_precio_lista3" numeric, "p_contenedor_id" "uuid", "p_unidades_por_contenedor" numeric, "p_imagen_path" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."registra_nuevo_usuario"("p_email" "text", "p_password" "text", "p_nombre_completo" "text", "p_telefono" "text", "p_rol_nombre" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."registra_nuevo_usuario"("p_email" "text", "p_password" "text", "p_nombre_completo" "text", "p_telefono" "text", "p_rol_nombre" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."registra_nuevo_usuario"("p_email" "text", "p_password" "text", "p_nombre_completo" "text", "p_telefono" "text", "p_rol_nombre" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."registrar_despacho_cliente_radar"("p_orden_id" "uuid", "p_detalles_json" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."registrar_despacho_cliente_radar"("p_orden_id" "uuid", "p_detalles_json" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."registrar_despacho_cliente_radar"("p_orden_id" "uuid", "p_detalles_json" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."registrar_entrega_detalle"("p_detalle_id" "uuid", "p_cantidad_despachada" integer, "p_estado_entrega" "text", "p_motivo_rechazo" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."registrar_entrega_detalle"("p_detalle_id" "uuid", "p_cantidad_despachada" integer, "p_estado_entrega" "text", "p_motivo_rechazo" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."registrar_entrega_detalle"("p_detalle_id" "uuid", "p_cantidad_despachada" integer, "p_estado_entrega" "text", "p_motivo_rechazo" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."registrar_movimiento_contenedores"("p_cliente_id" "uuid", "p_orden_id" "uuid", "p_contenedor_id" "uuid", "p_cantidad_entregada" integer, "p_cantidad_retirada" integer, "p_creado_por" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."registrar_movimiento_contenedores"("p_cliente_id" "uuid", "p_orden_id" "uuid", "p_contenedor_id" "uuid", "p_cantidad_entregada" integer, "p_cantidad_retirada" integer, "p_creado_por" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."registrar_movimiento_contenedores"("p_cliente_id" "uuid", "p_orden_id" "uuid", "p_contenedor_id" "uuid", "p_cantidad_entregada" integer, "p_cantidad_retirada" integer, "p_creado_por" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."registrar_rendicion_cuentas"("p_cliente_id" "uuid", "p_observaciones" "text", "p_creado_por" "uuid", "p_ordenes" "jsonb", "p_pagos" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."registrar_rendicion_cuentas"("p_cliente_id" "uuid", "p_observaciones" "text", "p_creado_por" "uuid", "p_ordenes" "jsonb", "p_pagos" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."registrar_rendicion_cuentas"("p_cliente_id" "uuid", "p_observaciones" "text", "p_creado_por" "uuid", "p_ordenes" "jsonb", "p_pagos" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."registrar_rendicion_cuentas"("p_cliente_id" "uuid", "p_observaciones" "text", "p_creado_por" "uuid", "p_ordenes" "jsonb", "p_pagos" "jsonb", "p_tasa_cambio" numeric) TO "anon";
GRANT ALL ON FUNCTION "public"."registrar_rendicion_cuentas"("p_cliente_id" "uuid", "p_observaciones" "text", "p_creado_por" "uuid", "p_ordenes" "jsonb", "p_pagos" "jsonb", "p_tasa_cambio" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."registrar_rendicion_cuentas"("p_cliente_id" "uuid", "p_observaciones" "text", "p_creado_por" "uuid", "p_ordenes" "jsonb", "p_pagos" "jsonb", "p_tasa_cambio" numeric) TO "service_role";



GRANT ALL ON FUNCTION "public"."registrar_venta_en_ruta_autoventa"("p_vendedor_id" "uuid", "p_cliente_id" "uuid", "p_camion_id" "uuid", "p_productos_json" "jsonb", "p_contenedores_json" "jsonb", "p_observaciones" "text", "p_tasa_cambio" numeric) TO "anon";
GRANT ALL ON FUNCTION "public"."registrar_venta_en_ruta_autoventa"("p_vendedor_id" "uuid", "p_cliente_id" "uuid", "p_camion_id" "uuid", "p_productos_json" "jsonb", "p_contenedores_json" "jsonb", "p_observaciones" "text", "p_tasa_cambio" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."registrar_venta_en_ruta_autoventa"("p_vendedor_id" "uuid", "p_cliente_id" "uuid", "p_camion_id" "uuid", "p_productos_json" "jsonb", "p_contenedores_json" "jsonb", "p_observaciones" "text", "p_tasa_cambio" numeric) TO "service_role";



GRANT ALL ON FUNCTION "public"."reporte_formas_pago_rendicion"("p_fecha_desde" "date", "p_fecha_hasta" "date", "p_solo_bancarios" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."reporte_formas_pago_rendicion"("p_fecha_desde" "date", "p_fecha_hasta" "date", "p_solo_bancarios" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."reporte_formas_pago_rendicion"("p_fecha_desde" "date", "p_fecha_hasta" "date", "p_solo_bancarios" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."reporte_recaudaciones_gerenciales"("p_fecha_desde" "date", "p_fecha_hasta" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."reporte_recaudaciones_gerenciales"("p_fecha_desde" "date", "p_fecha_hasta" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."reporte_recaudaciones_gerenciales"("p_fecha_desde" "date", "p_fecha_hasta" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."retorna_choferes_disponibles"() TO "anon";
GRANT ALL ON FUNCTION "public"."retorna_choferes_disponibles"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."retorna_choferes_disponibles"() TO "service_role";



GRANT ALL ON FUNCTION "public"."retorna_cuentas_bancarias_empresa"("p_solo_activas" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."retorna_cuentas_bancarias_empresa"("p_solo_activas" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."retorna_cuentas_bancarias_empresa"("p_solo_activas" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."retorna_inventario_no_despachado_para_almacen"("p_radar_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."retorna_inventario_no_despachado_para_almacen"("p_radar_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."retorna_inventario_no_despachado_para_almacen"("p_radar_id" "uuid") TO "service_role";



GRANT ALL ON TABLE "public"."camiones" TO "anon";
GRANT ALL ON TABLE "public"."camiones" TO "authenticated";
GRANT ALL ON TABLE "public"."camiones" TO "service_role";



GRANT ALL ON FUNCTION "public"."retorna_lista_camiones"() TO "anon";
GRANT ALL ON FUNCTION "public"."retorna_lista_camiones"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."retorna_lista_camiones"() TO "service_role";



GRANT ALL ON FUNCTION "public"."retorna_lista_contenedores"() TO "anon";
GRANT ALL ON FUNCTION "public"."retorna_lista_contenedores"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."retorna_lista_contenedores"() TO "service_role";



GRANT ALL ON FUNCTION "public"."retorna_lista_productos_segun_parametros"("p_busqueda" "text", "p_activo" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."retorna_lista_productos_segun_parametros"("p_busqueda" "text", "p_activo" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."retorna_lista_productos_segun_parametros"("p_busqueda" "text", "p_activo" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."retorna_lista_productos_segun_parametros"("p_parametro" "text", "p_cliente_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."retorna_lista_productos_segun_parametros"("p_parametro" "text", "p_cliente_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."retorna_lista_productos_segun_parametros"("p_parametro" "text", "p_cliente_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."retorna_lista_radars_aprobado_segun_rango_fechas"("p_despachador_id" "uuid", "p_fecha_inicial" "date", "p_fecha_limite" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."retorna_lista_radars_aprobado_segun_rango_fechas"("p_despachador_id" "uuid", "p_fecha_inicial" "date", "p_fecha_limite" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."retorna_lista_radars_aprobado_segun_rango_fechas"("p_despachador_id" "uuid", "p_fecha_inicial" "date", "p_fecha_limite" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."retorna_lista_radars_pendiente_segun_rango_fechas"("p_despachador_id" "uuid", "p_fecha_inicial" "date", "p_fecha_limite" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."retorna_lista_radars_pendiente_segun_rango_fechas"("p_despachador_id" "uuid", "p_fecha_inicial" "date", "p_fecha_limite" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."retorna_lista_radars_pendiente_segun_rango_fechas"("p_despachador_id" "uuid", "p_fecha_inicial" "date", "p_fecha_limite" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."retorna_lista_radars_segun_rango_fechas"("p_despachador_id" "uuid", "p_fecha_inicial" "date", "p_fecha_limite" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."retorna_lista_radars_segun_rango_fechas"("p_despachador_id" "uuid", "p_fecha_inicial" "date", "p_fecha_limite" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."retorna_lista_radars_segun_rango_fechas"("p_despachador_id" "uuid", "p_fecha_inicial" "date", "p_fecha_limite" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."retorna_lista_rutas"() TO "anon";
GRANT ALL ON FUNCTION "public"."retorna_lista_rutas"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."retorna_lista_rutas"() TO "service_role";



GRANT ALL ON FUNCTION "public"."retorna_lista_usuarios_segun_parametro"("p_parametro" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."retorna_lista_usuarios_segun_parametro"("p_parametro" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."retorna_lista_usuarios_segun_parametro"("p_parametro" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."retorna_lista_usuarios_segun_parametros"("p_nombre" "text", "p_rol" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."retorna_lista_usuarios_segun_parametros"("p_nombre" "text", "p_rol" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."retorna_lista_usuarios_segun_parametros"("p_nombre" "text", "p_rol" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."retorna_movimientos_contenedores_segun_cliente_id_rango_fechas"("p_cliente_id" "uuid", "p_fecha_inicial" "date", "p_fecha_limite" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."retorna_movimientos_contenedores_segun_cliente_id_rango_fechas"("p_cliente_id" "uuid", "p_fecha_inicial" "date", "p_fecha_limite" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."retorna_movimientos_contenedores_segun_cliente_id_rango_fechas"("p_cliente_id" "uuid", "p_fecha_inicial" "date", "p_fecha_limite" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."retorna_ordenes_distribucion_segun_estado"("p_estado" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."retorna_ordenes_distribucion_segun_estado"("p_estado" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."retorna_ordenes_distribucion_segun_estado"("p_estado" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."retorna_ordenes_distribucion_segun_idradar"("p_radar_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."retorna_ordenes_distribucion_segun_idradar"("p_radar_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."retorna_ordenes_distribucion_segun_idradar"("p_radar_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."retorna_ordenes_por_liquidar"() TO "anon";
GRANT ALL ON FUNCTION "public"."retorna_ordenes_por_liquidar"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."retorna_ordenes_por_liquidar"() TO "service_role";



GRANT ALL ON FUNCTION "public"."retorna_radar_despachador"() TO "anon";
GRANT ALL ON FUNCTION "public"."retorna_radar_despachador"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."retorna_radar_despachador"() TO "service_role";



GRANT ALL ON FUNCTION "public"."retorna_radar_detalle_reporte"("p_radar_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."retorna_radar_detalle_reporte"("p_radar_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."retorna_radar_detalle_reporte"("p_radar_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."retorna_resumen_autoventas_jornada"("p_camion_id" "uuid", "p_fecha" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."retorna_resumen_autoventas_jornada"("p_camion_id" "uuid", "p_fecha" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."retorna_resumen_autoventas_jornada"("p_camion_id" "uuid", "p_fecha" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."retorna_saldo_contenedores_segun_clientes"("p_cliente_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."retorna_saldo_contenedores_segun_clientes"("p_cliente_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."retorna_saldo_contenedores_segun_clientes"("p_cliente_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."retorna_tasas_cambio_por_rango"("p_fecha_desde" "date", "p_fecha_hasta" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."retorna_tasas_cambio_por_rango"("p_fecha_desde" "date", "p_fecha_hasta" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."retorna_tasas_cambio_por_rango"("p_fecha_desde" "date", "p_fecha_hasta" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."retorna_ultima_tasa_cambio"() TO "anon";
GRANT ALL ON FUNCTION "public"."retorna_ultima_tasa_cambio"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."retorna_ultima_tasa_cambio"() TO "service_role";



GRANT ALL ON FUNCTION "public"."retorna_usuarios_despachadores"() TO "anon";
GRANT ALL ON FUNCTION "public"."retorna_usuarios_despachadores"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."retorna_usuarios_despachadores"() TO "service_role";



GRANT ALL ON FUNCTION "public"."solicita_abonos_orden_distribucion"("p_cliente_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."solicita_abonos_orden_distribucion"("p_cliente_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."solicita_abonos_orden_distribucion"("p_cliente_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."solicita_aprobar_radar"("p_radar_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."solicita_aprobar_radar"("p_radar_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."solicita_aprobar_radar"("p_radar_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."solicita_cargar_inventario_movil_desde_almacen"("p_camion_id" "uuid", "p_resumen_productos" "jsonb", "p_radar_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."solicita_cargar_inventario_movil_desde_almacen"("p_camion_id" "uuid", "p_resumen_productos" "jsonb", "p_radar_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."solicita_cargar_inventario_movil_desde_almacen"("p_camion_id" "uuid", "p_resumen_productos" "jsonb", "p_radar_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."solicita_crear_orden_distribucion"("p_vendedor_id" "uuid", "p_chofer_id" "uuid", "p_productos_json" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."solicita_crear_orden_distribucion"("p_vendedor_id" "uuid", "p_chofer_id" "uuid", "p_productos_json" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."solicita_crear_orden_distribucion"("p_vendedor_id" "uuid", "p_chofer_id" "uuid", "p_productos_json" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."solicita_datos_usuario"("p_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."solicita_datos_usuario"("p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."solicita_datos_usuario"("p_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."solicita_editar_o_sincronizar_radar"("p_radar_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."solicita_editar_o_sincronizar_radar"("p_radar_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."solicita_editar_o_sincronizar_radar"("p_radar_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."solicita_lista_usuarios"("p_usuarios_json" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."solicita_lista_usuarios"("p_usuarios_json" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."solicita_lista_usuarios"("p_usuarios_json" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."solicita_reversar_carga_inventario_movil_a_almacen"("p_camion_id" "uuid", "p_resumen_productos" "jsonb", "p_radar_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."solicita_reversar_carga_inventario_movil_a_almacen"("p_camion_id" "uuid", "p_resumen_productos" "jsonb", "p_radar_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."solicita_reversar_carga_inventario_movil_a_almacen"("p_camion_id" "uuid", "p_resumen_productos" "jsonb", "p_radar_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."user_has_role"("p_role_names" "text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."user_has_role"("p_role_names" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."user_has_role"("p_role_names" "text"[]) TO "service_role";



GRANT ALL ON TABLE "public"."choferes" TO "anon";
GRANT ALL ON TABLE "public"."choferes" TO "authenticated";
GRANT ALL ON TABLE "public"."choferes" TO "service_role";



GRANT ALL ON TABLE "public"."clientes" TO "anon";
GRANT ALL ON TABLE "public"."clientes" TO "authenticated";
GRANT ALL ON TABLE "public"."clientes" TO "service_role";



GRANT ALL ON TABLE "public"."cuentas_bancarias_empresa" TO "anon";
GRANT ALL ON TABLE "public"."cuentas_bancarias_empresa" TO "authenticated";
GRANT ALL ON TABLE "public"."cuentas_bancarias_empresa" TO "service_role";



GRANT ALL ON TABLE "public"."descuentos_cliente_producto" TO "anon";
GRANT ALL ON TABLE "public"."descuentos_cliente_producto" TO "authenticated";
GRANT ALL ON TABLE "public"."descuentos_cliente_producto" TO "service_role";



GRANT ALL ON TABLE "public"."detalle_distribucion" TO "anon";
GRANT ALL ON TABLE "public"."detalle_distribucion" TO "authenticated";
GRANT ALL ON TABLE "public"."detalle_distribucion" TO "service_role";



GRANT ALL ON TABLE "public"."detalle_facturas_compras" TO "anon";
GRANT ALL ON TABLE "public"."detalle_facturas_compras" TO "authenticated";
GRANT ALL ON TABLE "public"."detalle_facturas_compras" TO "service_role";



GRANT ALL ON TABLE "public"."detalle_pago_facturas" TO "anon";
GRANT ALL ON TABLE "public"."detalle_pago_facturas" TO "authenticated";
GRANT ALL ON TABLE "public"."detalle_pago_facturas" TO "service_role";



GRANT ALL ON TABLE "public"."detalle_pago_metodos" TO "anon";
GRANT ALL ON TABLE "public"."detalle_pago_metodos" TO "authenticated";
GRANT ALL ON TABLE "public"."detalle_pago_metodos" TO "service_role";



GRANT ALL ON TABLE "public"."detalle_rendicion_fpagos" TO "anon";
GRANT ALL ON TABLE "public"."detalle_rendicion_fpagos" TO "authenticated";
GRANT ALL ON TABLE "public"."detalle_rendicion_fpagos" TO "service_role";



GRANT ALL ON TABLE "public"."detalle_rendicion_ordenes" TO "anon";
GRANT ALL ON TABLE "public"."detalle_rendicion_ordenes" TO "authenticated";
GRANT ALL ON TABLE "public"."detalle_rendicion_ordenes" TO "service_role";



GRANT ALL ON TABLE "public"."empresas" TO "anon";
GRANT ALL ON TABLE "public"."empresas" TO "authenticated";
GRANT ALL ON TABLE "public"."empresas" TO "service_role";



GRANT ALL ON TABLE "public"."facturas_compras" TO "anon";
GRANT ALL ON TABLE "public"."facturas_compras" TO "authenticated";
GRANT ALL ON TABLE "public"."facturas_compras" TO "service_role";



GRANT ALL ON TABLE "public"."fpagos" TO "anon";
GRANT ALL ON TABLE "public"."fpagos" TO "authenticated";
GRANT ALL ON TABLE "public"."fpagos" TO "service_role";



GRANT ALL ON TABLE "public"."inventario_almacen" TO "anon";
GRANT ALL ON TABLE "public"."inventario_almacen" TO "authenticated";
GRANT ALL ON TABLE "public"."inventario_almacen" TO "service_role";



GRANT ALL ON TABLE "public"."inventario_movil" TO "anon";
GRANT ALL ON TABLE "public"."inventario_movil" TO "authenticated";
GRANT ALL ON TABLE "public"."inventario_movil" TO "service_role";



GRANT ALL ON TABLE "public"."logs_auditoria" TO "anon";
GRANT ALL ON TABLE "public"."logs_auditoria" TO "authenticated";
GRANT ALL ON TABLE "public"."logs_auditoria" TO "service_role";



GRANT ALL ON TABLE "public"."movimientos_contenedores" TO "anon";
GRANT ALL ON TABLE "public"."movimientos_contenedores" TO "authenticated";
GRANT ALL ON TABLE "public"."movimientos_contenedores" TO "service_role";



GRANT ALL ON TABLE "public"."movimientos_saldo_favor" TO "anon";
GRANT ALL ON TABLE "public"."movimientos_saldo_favor" TO "authenticated";
GRANT ALL ON TABLE "public"."movimientos_saldo_favor" TO "service_role";



GRANT ALL ON TABLE "public"."ordenes_distribucion" TO "anon";
GRANT ALL ON TABLE "public"."ordenes_distribucion" TO "authenticated";
GRANT ALL ON TABLE "public"."ordenes_distribucion" TO "service_role";



GRANT ALL ON SEQUENCE "public"."ordenes_distribucion_correlativo_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."ordenes_distribucion_correlativo_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."ordenes_distribucion_correlativo_seq" TO "service_role";



GRANT ALL ON TABLE "public"."pagos_proveedores" TO "anon";
GRANT ALL ON TABLE "public"."pagos_proveedores" TO "authenticated";
GRANT ALL ON TABLE "public"."pagos_proveedores" TO "service_role";



GRANT ALL ON TABLE "public"."perfiles_usuario" TO "anon";
GRANT ALL ON TABLE "public"."perfiles_usuario" TO "authenticated";
GRANT ALL ON TABLE "public"."perfiles_usuario" TO "service_role";



GRANT ALL ON TABLE "public"."permisos" TO "anon";
GRANT ALL ON TABLE "public"."permisos" TO "authenticated";
GRANT ALL ON TABLE "public"."permisos" TO "service_role";



GRANT ALL ON TABLE "public"."productos" TO "anon";
GRANT ALL ON TABLE "public"."productos" TO "authenticated";
GRANT ALL ON TABLE "public"."productos" TO "service_role";



GRANT ALL ON TABLE "public"."proveedores" TO "anon";
GRANT ALL ON TABLE "public"."proveedores" TO "authenticated";
GRANT ALL ON TABLE "public"."proveedores" TO "service_role";



GRANT ALL ON TABLE "public"."radars" TO "anon";
GRANT ALL ON TABLE "public"."radars" TO "authenticated";
GRANT ALL ON TABLE "public"."radars" TO "service_role";



GRANT ALL ON SEQUENCE "public"."radars_correlativo_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."radars_correlativo_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."radars_correlativo_seq" TO "service_role";



GRANT ALL ON TABLE "public"."rendiciones_cuentas" TO "anon";
GRANT ALL ON TABLE "public"."rendiciones_cuentas" TO "authenticated";
GRANT ALL ON TABLE "public"."rendiciones_cuentas" TO "service_role";



GRANT ALL ON TABLE "public"."roles" TO "anon";
GRANT ALL ON TABLE "public"."roles" TO "authenticated";
GRANT ALL ON TABLE "public"."roles" TO "service_role";



GRANT ALL ON TABLE "public"."roles_permisos" TO "anon";
GRANT ALL ON TABLE "public"."roles_permisos" TO "authenticated";
GRANT ALL ON TABLE "public"."roles_permisos" TO "service_role";



GRANT ALL ON TABLE "public"."rutas" TO "anon";
GRANT ALL ON TABLE "public"."rutas" TO "authenticated";
GRANT ALL ON TABLE "public"."rutas" TO "service_role";



GRANT ALL ON TABLE "public"."saldo_contenedores_clientes" TO "anon";
GRANT ALL ON TABLE "public"."saldo_contenedores_clientes" TO "authenticated";
GRANT ALL ON TABLE "public"."saldo_contenedores_clientes" TO "service_role";



GRANT ALL ON TABLE "public"."tasa_cambio" TO "anon";
GRANT ALL ON TABLE "public"."tasa_cambio" TO "authenticated";
GRANT ALL ON TABLE "public"."tasa_cambio" TO "service_role";



GRANT ALL ON TABLE "public"."tipos_contenedores" TO "anon";
GRANT ALL ON TABLE "public"."tipos_contenedores" TO "authenticated";
GRANT ALL ON TABLE "public"."tipos_contenedores" TO "service_role";



GRANT ALL ON TABLE "public"."usuarios_empresas" TO "anon";
GRANT ALL ON TABLE "public"."usuarios_empresas" TO "authenticated";
GRANT ALL ON TABLE "public"."usuarios_empresas" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";







