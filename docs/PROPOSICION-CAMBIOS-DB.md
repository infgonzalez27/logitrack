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

## 2. Modificaciones a las Tablas Existentes

### 2.1. Tabla `detalle_distribucion`
Necesitamos registrar cuántos contenedores se entregaron y cuántos se retiraron por cada línea de despacho de la orden.
```sql
ALTER TABLE detalle_distribucion
ADD COLUMN contenedores_entregados INT DEFAULT 0 CHECK (contenedores_entregados >= 0),
ADD COLUMN contenedores_devueltos INT DEFAULT 0 CHECK (contenedores_devueltos >= 0);
```

### 2.2. Tabla `ordenes_distribucion` (Alineación de Estados)
Ajustar la restricción del campo `estado` para reflejar el ciclo exacto:
*   `borrador` (creado por el vendedor)
*   `aprobada` (aprobada por el gerente, stock comprometido)
*   `en_transito` (cargado al camión)
*   `liquidada` (recaudación aprobada por el gerente)
*   `anulada`

```sql
-- Eliminar restricción CHECK existente e insertar la nueva
ALTER TABLE ordenes_distribucion DROP CONSTRAINT IF EXISTS ordenes_distribucion_estado_check;
ALTER TABLE ordenes_distribucion 
ADD CONSTRAINT ordenes_distribucion_estado_check 
CHECK (estado IN ('borrador', 'aprobada', 'en_transito', 'liquidada', 'anulada'));
```

---

## 3. Flujo de Recaudación y Liquidación (Módulo 4)

El SP de liquidación (`liquidar_orden_distribucion`) debe verificar las tablas del Módulo 4:
1.  Cuando el vendedor registra la cobranza, inserta en `rendiciones_cuentas` (estado: `revision`) y asocia las órdenes correspondientes en `detalle_rendicion_ordenes` (ej. recaudando la totalidad de `subtotal_recaudar`).
2.  Al aprobar la rendición (`rendiciones_cuentas.estado = 'aprobada'`), un Trigger o un SP de aprobación debe disparar la transición del estado de la orden a `liquidada` y actualizar el saldo acumulado en `saldo_contenedores_clientes` restando los contenedores devueltos y sumando los entregados en esa orden.
