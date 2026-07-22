DROP FUNCTION IF EXISTS public.retorna_lista_camiones();

CREATE OR REPLACE FUNCTION public.retorna_lista_camiones()
RETURNS SETOF public.camiones
LANGUAGE plpgsql
SECURITY DEFINER
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
