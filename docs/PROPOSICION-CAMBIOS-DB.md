# Propuesta de Cambios en la Estructura de la Base de Datos (LogiTrack)

Este documento detalla los cambios sugeridos para el esquema de la base de datos (PostgreSQL en Supabase) con el fin de soportar el **doble inventario de contenedores retornables** y el **flujo de recaudación acoplado a la liquidación**, de acuerdo a lo definido en el ciclo de despacho.

---

## 1. Módulo de Contenedores y Empaques Retornables (Nuevo)

Para gestionar los contenedores que el cliente debe devolver, proponemos añadir las siguientes tablas y columnas:

### 1.1. Tabla Maestra de Contenedores (`tipos_contenedores`)
Permite registrar diferentes tipos de envases retornables (ej. cajas plásticas, cestas, bombonas).
```sql
CREATE TABLE tipos_contenedores (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    codigo TEXT NOT NULL UNIQUE, -- ej: 'caja_refresco', 'bombona_18l', 'cesta_pan'
    nombre TEXT NOT NULL,
    descripcion TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

### 1.2. Tabla de Saldo Acumulado por Cliente (`saldo_contenedores_clientes`)
Almacena el balance neto de cuántos contenedores tiene en su poder cada cliente.
```sql
CREATE TABLE saldo_contenedores_clientes (
    cliente_id UUID REFERENCES clientes(id) ON DELETE CASCADE,
    contenedor_id UUID REFERENCES tipos_contenedores(id) ON DELETE RESTRICT,
    saldo_pendiente INT NOT NULL DEFAULT 0 CHECK (saldo_pendiente >= 0),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    PRIMARY KEY (cliente_id, contenedor_id)
);
```

### 1.3. Relación de Productos con Contenedores (Opcional pero Recomendado)
Permite asociar qué tipo de contenedor requiere un producto y en qué proporción.
```sql
ALTER TABLE productos 
ADD COLUMN contenedor_id UUID REFERENCES tipos_contenedores(id) ON DELETE SET NULL,
ADD COLUMN unidades_por_contenedor NUMERIC(5,0) DEFAULT 1;
```

---

## 2. Modificaciones a las Tablas Existentes y Registro de Movimientos

### 2.1. Registro Independiente de Envases (`movimientos_contenedores`)
Dado que el retiro y entrega de contenedores es responsabilidad del despachador en ruta (reportado a través del Radar) y no del vendedor que crea la orden, los movimientos de envases no deben mezclarse en la tabla `detalle_distribucion`. 

Proponemos una tabla de transacciones dedicada para auditar las entregas y retiros de envases por cada viaje/orden:
```sql
CREATE TABLE movimientos_contenedores (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    cliente_id UUID REFERENCES clientes(id) ON DELETE RESTRICT,
    orden_id UUID REFERENCES ordenes_distribucion(id) ON DELETE CASCADE,
    contenedor_id UUID REFERENCES tipos_contenedores(id) ON DELETE RESTRICT,
    cantidad_entregada INT NOT NULL DEFAULT 0 CHECK (cantidad_entregada >= 0),
    cantidad_retirada INT NOT NULL DEFAULT 0 CHECK (cantidad_retirada >= 0),
    creado_por UUID REFERENCES auth.users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

### 2.2. Tabla `ordenes_distribucion` (Alineación de Estados)
Ajustar la restricción del campo `estado` para reflejar el ciclo exacto:
*   `borrador` (creado por el vendedor)
*   `aprobada` (aprobada por el gerente, stock comprometido)
*   `en_transito` (cargado al camión y en ruta)
*   `por_liquidar` (mercancía entregada y pendiente de conciliar recaudación)
*   `liquidada` (recaudación aprobada por el gerente)
*   `anulada`

```sql
-- Eliminar restricción CHECK existente e insertar la nueva
ALTER TABLE ordenes_distribucion DROP CONSTRAINT IF EXISTS ordenes_distribucion_estado_check;
ALTER TABLE ordenes_distribucion 
ADD CONSTRAINT ordenes_distribucion_estado_check 
CHECK (estado IN ('borrador', 'aprobada', 'en_transito', 'por_liquidar', 'liquidada', 'anulada'));
```

---

## 3. Flujo de Recaudación y Liquidación (Módulo 4)

El SP de liquidación (`liquidar_orden_distribucion`) debe verificar las tablas del Módulo 4:
1.  Cuando el vendedor registra la cobranza, inserta en `rendiciones_cuentas` (estado: `revision`) y asocia las órdenes correspondientes en `detalle_rendicion_ordenes` (ej. recaudando la totalidad de `subtotal_recaudar`).
2.  Al aprobar la rendición (`rendiciones_cuentas.estado = 'aprobada'`), un Trigger o un SP de aprobación debe disparar la transición del estado de la orden a `liquidada` y actualizar el saldo acumulado en `saldo_contenedores_clientes` restando los contenedores devueltos y sumando los entregados en esa orden.

---

## 4. Módulo de Control de Radares por Despachador (`radars`)

Para soportar el control centralizado de los radares por fecha y despachador, la emisión de reportes impresos y la reasignación de órdenes no despachadas:

### 4.1. Tabla Maestra de Radares (`radars`)
```sql
CREATE TABLE public.radars (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    correlativo SERIAL UNIQUE, -- ej: RAD-000001
    despachador_id UUID NOT NULL REFERENCES public.perfiles_usuario(id) ON DELETE RESTRICT,
    fecha_despacho DATE NOT NULL DEFAULT CURRENT_DATE,
    total_cantidad_solicitada NUMERIC(10,0) DEFAULT 0,
    total_cantidad_despachada NUMERIC(10,0) DEFAULT 0,
    total_contenedores_retirados NUMERIC(10,0) DEFAULT 0,
    status_radar BOOLEAN DEFAULT FALSE, -- .T. (true) si el despacho salió, .F. (false) si no salió
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

### 4.2. Relación en Cabecera de Orden (`ordenes_distribucion`)
Se añade la relación en `ordenes_distribucion.radar_id` para vincular de manera limpia ($1:N$) las órdenes correspondientes a cada radar planificado.
```sql
ALTER TABLE public.ordenes_distribucion
ADD COLUMN IF NOT EXISTS radar_id UUID REFERENCES public.radars(id) ON DELETE SET NULL;
```

> **Asesoría Técnica sobre la FK:**
> Colocar `radar_id` en `ordenes_distribucion` en lugar de `detalle_distribucion` mantiene la estructura de datos perfectamente normalizada. Puesto que la orden es la entidad operativa entregada al cliente por el despachador, al reasignar una orden no despachada a una nueva fecha o radar, sólo se actualiza 1 registro en `ordenes_distribucion` sin duplicar la llave en todos los renglones de producto.

### 4.3. Procedimientos Almacenados Asociados
1. **`crear_o_obtener_radar`**: Registra la cabecera del radar asociando las órdenes del despachador según su `ordenes_distribucion.fecha_despacho`.
2. **`retorna_radar_detalle_reporte`**: Retorna el formato JSON estructurado con la información del despachador, fecha de despacho, órdenes y productos para la impresión del reporte físico y visualización electrónica.
3. **`reasignar_orden_a_radar`**: Desvincula una orden no despachada y la asigna a un nuevo radar, actualizando `ordenes_distribucion.fecha_despacho`.
4. **`guardar_resultado_despacho_radar`**: Procesa de manera **atómica** las tablas involucradas al confirmar el despacho:
   - **`detalle_distribucion`**: Actualiza `cantidad_despachada`, `motivo_rechazo` y `estado_entrega`.
   - **`movimientos_contenedores`**:
     - **`cantidad_entregada` (Cálculo Automático):** Si el producto entregado en `detalle_distribucion` tiene un `contenedor_id` asignado en `productos`, se registra automáticamente `cantidad_entregada = cantidad_despachada` (1 contenedor por producto entregado).
     - **`cantidad_retirada`**: Registra los envases retirados ingresados por el despachador en el reporte.
   - **`radars`**: Actualiza `total_cantidad_solicitada`, `total_cantidad_despachada`, `total_contenedores_retirados` y marca `status_radar = true` (.T.).


