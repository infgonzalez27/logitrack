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
    p_activo BOOLEAN DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
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

COMMENT ON FUNCTION public.actualiza_registro_cliente_segun_uuid(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC, NUMERIC, UUID, UUID, UUID, BOOLEAN) 
IS 'Actualiza la información de un cliente existente en la tabla clientes según su ID (UUID)';
