# Plan de Implementación: Reporte Detallado de Entregas por Cliente (AutoVentas)

## 1. Objetivo
Crear una nueva función (RPC) en Supabase que devuelva un desglose detallado de los productos entregados a cada cliente durante la jornada de AutoVenta. Esta información estará agrupada por cliente y filtrada por un `camion_id` y `fecha` específicos, para resolver la necesidad de auditar qué mercancía se quedó cada cliente.

## 2. Tablas Involucradas
1. **`ordenes_distribucion` (od):** Permite filtrar las ventas correspondientes (`es_autoventa = TRUE`, `camion_id = p_camion_id` y por fecha).
2. **`clientes` (c):** Para obtener la información del negocio receptor (Razón Social, ID).
3. **`detalle_distribucion` (odd):** Para extraer las cantidades reales despachadas/cargadas al cliente y sus subtotales monetarios.
4. **`productos` (p):** Para cruzar el código y nombre del ítem.

## 3. Firma de la Función RPC Propuesta

```sql
CREATE OR REPLACE FUNCTION public.retorna_reporte_autoventas_entregas_cliente(
    p_camion_id UUID,
    p_fecha DATE DEFAULT CURRENT_DATE
) RETURNS JSONB
```

## 4. Estructura de Salida JSON (El Contrato)
La función retornará un JSON estructurado con la información anidada para que el Frontend o cualquier herramienta de reportes pueda mapear fácilmente la relación **Orden -> Cliente -> Detalles (Productos)**.

```json
{
  "success": true,
  "data": {
    "camion_id": "42618991-5...",
    "fecha": "2026-10-06",
    "total_general_usd": 350.00,
    "entregas": [
      {
        "cliente_id": "1111-222...",
        "razon_social": "Inversiones ABC",
        "orden_id": "8888-999...",
        "correlativo": 1054,
        "total_orden_usd": 150.00,
        "productos": [
          {
            "producto_id": "3333-444...",
            "codigo": "B20L",
            "nombre": "Botellón 20L",
            "cantidad_entregada": 20,
            "precio_unitario_usd": 5.00,
            "subtotal_usd": 100.00
          },
          {
            "producto_id": "5555-666...",
            "codigo": "B10L",
            "nombre": "Botellón 10L",
            "cantidad_entregada": 10,
            "precio_unitario_usd": 5.00,
            "subtotal_usd": 50.00
          }
        ]
      }
    ]
  }
}
```

## 5. Pasos de Ejecución
1. Escribir el script **idempotente** de la migración utilizando `CREATE OR REPLACE FUNCTION`. 
2. Realizar la agrupación con Postgres JSON functions (`jsonb_agg` y `jsonb_build_object`). La lógica utilizará un Sub-SELECT correlacionado o CTE para traer el detalle de los productos por cada orden de manera limpia y eficiente.
3. El archivo SQL será creado en el directorio de `supabase/tenant_patches/` (siguiendo las Reglas de Oro) con el nombre `[FECHA]_rpc_reporte_entregas_autoventas.sql` para que el esquema se mantenga replicable para todas las empresas (Tenants).
4. El agente ejecutará el parche con los comandos CLI para aplicar la función a la base de datos de manera inmediata.
5. (Opcional, futuro) El desarrollador Frontend podrá consumir el RPC mediante el cliente TypeScript utilizando esta misma estructura.
