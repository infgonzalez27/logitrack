# Plan de Implementación: Movimientos Especiales de Inventario

## 1. Estructura DDL Propuesta

```sql
-- Tabla: movimientos_inventario
CREATE TABLE IF NOT EXISTS public.movimientos_inventario (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    fecha_movimiento TIMESTAMPTZ DEFAULT now(),
    tipo_movimiento VARCHAR(20) NOT NULL CHECK (tipo_movimiento IN ('ENTRADA', 'SALIDA')),
    concepto VARCHAR(100) NOT NULL,
    tipo_inventario_afectado VARCHAR(20) NOT NULL CHECK (tipo_inventario_afectado IN ('ALMACEN', 'MOVIL')),
    id_referencia_movil UUID,
    id_cliente UUID,
    autorizado_por UUID REFERENCES auth.users(id),
    observaciones TEXT,
    CONSTRAINT chk_movil_referencia CHECK (
        (tipo_inventario_afectado = 'MOVIL' AND id_referencia_movil IS NOT NULL) OR 
        (tipo_inventario_afectado = 'ALMACEN')
    )
);

-- Habilitar RLS
ALTER TABLE public.movimientos_inventario ENABLE ROW LEVEL SECURITY;

-- Políticas Base
CREATE POLICY "Lectura general autenticados" ON public.movimientos_inventario
    FOR SELECT TO authenticated USING (true);
CREATE POLICY "Inserción autenticados" ON public.movimientos_inventario
    FOR INSERT TO authenticated WITH CHECK (true);

-- Tabla: movimientos_inventario_detalle
CREATE TABLE IF NOT EXISTS public.movimientos_inventario_detalle (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    id_movimiento UUID NOT NULL REFERENCES public.movimientos_inventario(id) ON DELETE CASCADE,
    id_producto UUID NOT NULL, 
    cantidad NUMERIC NOT NULL CHECK (cantidad > 0),
    costo_unitario NUMERIC NOT NULL
);

-- Habilitar RLS
ALTER TABLE public.movimientos_inventario_detalle ENABLE ROW LEVEL SECURITY;

-- Políticas Base
CREATE POLICY "Lectura general autenticados" ON public.movimientos_inventario_detalle
    FOR SELECT TO authenticated USING (true);
CREATE POLICY "Inserción autenticados" ON public.movimientos_inventario_detalle
    FOR INSERT TO authenticated WITH CHECK (true);
```

## 2. Firma de la Función (RPC PL/pgSQL)

```sql
CREATE OR REPLACE FUNCTION public.registrar_movimiento_inventario_especial(
    p_tipo_movimiento VARCHAR,
    p_concepto VARCHAR,
    p_tipo_inventario_afectado VARCHAR,
    p_id_referencia_movil UUID,
    p_id_cliente UUID,
    p_autorizado_por UUID,
    p_observaciones TEXT,
    p_detalles JSONB
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_id_movimiento UUID;
    v_detalle RECORD;
    v_stock_actual NUMERIC;
BEGIN
    -- 1. Insertar Cabecera
    INSERT INTO public.movimientos_inventario (
        tipo_movimiento, concepto, tipo_inventario_afectado, id_referencia_movil,
        id_cliente, autorizado_por, observaciones
    ) VALUES (
        p_tipo_movimiento, p_concepto, p_tipo_inventario_afectado, p_id_referencia_movil,
        p_id_cliente, p_autorizado_por, p_observaciones
    ) RETURNING id INTO v_id_movimiento;

    -- 2. Procesar Detalles y Actualizar Stock
    FOR v_detalle IN SELECT * FROM jsonb_to_recordset(p_detalles) AS x(id_producto UUID, cantidad NUMERIC, costo_unitario NUMERIC)
    LOOP
        -- Insertar Detalle
        INSERT INTO public.movimientos_inventario_detalle (
            id_movimiento, id_producto, cantidad, costo_unitario
        ) VALUES (
            v_id_movimiento, v_detalle.id_producto, v_detalle.cantidad, v_detalle.costo_unitario
        );

        -- Lógica de validación y actualización de stock (Almacén o Móvil)
        IF p_tipo_movimiento = 'SALIDA' THEN
            -- [Validar stock suficiente e interrupción con RAISE EXCEPTION]
            -- [Restar stock]
        ELSE
            -- [Sumar stock]
        END IF;
    END LOOP;

    RETURN v_id_movimiento;
END;
$$;
```

## 3. Comandos de Supabase CLI a Ejecutar

1. Crear la migración:
   ```bash
   supabase migration new tablas_y_rpc_movimientos_especiales
   ```
2. Insertar el código SQL anterior (DDL + RPC) en el archivo de migración generado.
3. Aplicar los cambios:
   ```bash
   supabase db push
   ```
