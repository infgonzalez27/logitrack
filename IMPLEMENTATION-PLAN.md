# Plan de Implementación: Venta Directa en Almacén (Caso #3)

## 1. Análisis de Impacto y Tablas Afectadas
El nuevo requerimiento de venta directa impacta las siguientes áreas del modelo de datos:
*   **`ordenes_distribucion`:** Actualmente está orientada a despachos en ruta (requiere `camion_id`, `vendedor_id`, y fluye de `aprobada` -> `en_transito` -> `por_liquidar` / `liquidada`).
*   **`inventario_almacen`:** Debe recibir la deducción directa del stock en el momento en que se procesa la venta, sin pasar por una carga de camión (`inventario_movil`).

## 2. Decisión Arquitectónica: Crear Nueva Función (RPC)
Se decide **crear un nuevo RPC exclusivo (`crear_venta_directa_almacen`)** en lugar de reutilizar `crear_orden_distribucion`.

**Justificación:**
1.  **Diferencia Transaccional:** El flujo actual separa la creación de la orden (`aprobada`), la reserva/carga (`en_transito` en `inventario_movil`), y la entrega (`por_liquidar`). La venta directa ocurre de forma atómica: se crea la orden, se deduce directamente de `inventario_almacen` y se entrega en el mismo momento, pasando directamente al estado `por_liquidar` o `liquidada`.
2.  **Parámetros y Dependencias:** La venta directa no requiere `camion_id`, `radar_id`, ni un `despachador_id` en ruta. Reutilizar la función existente obligaría a ensuciar el código con múltiples condicionales y a saltar validaciones estrictas.
3.  **Claridad del Código:** Separar la lógica mantiene el código limpio y evita efectos secundarios accidentales en el flujo de "Preventa" o "Auto-Venta".

## 3. Modificaciones a la Estructura de la Orden
Para identificar correctamente estas órdenes y evitar que sean arrastradas por consultas de "Radares" o liquidación de camiones, se propone agregar una nueva columna (bandera) en la tabla `ordenes_distribucion`:

```sql
ALTER TABLE public.ordenes_distribucion 
ADD COLUMN origen_venta VARCHAR(20) DEFAULT 'RUTA'; -- Valores: 'RUTA' o 'ALMACEN'
-- O alternativamente:
-- ADD COLUMN es_venta_directa BOOLEAN DEFAULT false;
```
Adicionalmente, se revisará la nulabilidad de `camion_id` para asegurar que permita `NULL` en estos casos (si actualmente es obligatorio).

## 4. Propuesta de Parámetros JSON para el Frontend (Cursor)

El Frontend invocará la nueva función `crear_venta_directa_almacen` enviando los siguientes parámetros:

```json
{
  "p_cliente_id": "uuid-del-cliente",
  "p_vendedor_id": "uuid-del-vendedor-en-mostrador",
  "p_tasa_cambio": 45.50, // Opcional, si es null toma la del día
  "p_tipo_venta": "credito", // 'credito' (pasa a por_liquidar) o 'contado' (pasa a liquidada)
  "p_productos_json": [
    {
      "producto_id": "uuid-del-producto-1",
      "cantidad": 5,
      "valor_unitario_usd": 10.00
    },
    {
      "producto_id": "uuid-del-producto-2",
      "cantidad": 2,
      "valor_unitario_usd": 25.00
    }
  ]
}
```

**Comportamiento de la función:**
1. Valida el stock directamente contra `inventario_almacen`.
2. Crea la orden con `origen_venta = 'ALMACEN'`.
3. Deduce las cantidades de `inventario_almacen`.
4. Establece el estado de la orden en `por_liquidar` (si es a crédito) o `liquidada` (si es de contado).

## 5. Próximos Pasos
*   [ ] Esperar aprobación de este plan.
*   [ ] Generar y ejecutar el parche SQL (DDL para la nueva columna y DML para el nuevo RPC).
*   [ ] Actualizar `INTEGRACION-RPC.md` con la firma y ejemplos de uso de la nueva función.
