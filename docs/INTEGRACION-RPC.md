# INTEGRACION-RPC

## Actualización de Reporte de Rendición y Carga de Camión

Se ha actualizado la función encargada de retornar el reporte de la carga de camión y la rendición, inyectando las métricas solicitadas de productos y contenedores (vacíos). 

- **Nombre de la función RPC:** `retorna_radar_detalle_reporte`
- **Parámetros de entrada:** 
  - `p_radar_id` (`uuid`): Identificador único del radar/ruta.

### Mockup de Respuesta JSON (Contrato)

A continuación se muestra un ejemplo de la nueva estructura que devuelve la función. Se destacan en la documentación los nuevos campos solicitados:

```json
{
  "success": true,
  "data": {
    "radar": {
      "id": "uuid-del-radar",
      "correlativo": 1001,
      "fecha_despacho": "2026-10-01T08:00:00.000Z",
      "status_radar": "en_ruta",
      "total_cantidad_solicitada": 1500,
      "total_cantidad_despachada": 1450,
      "total_contenedores_retirados": 200,
      "created_at": "2026-10-01T07:30:00.000Z"
    },
    "despachador": {
      "id": "uuid-despachador",
      "nombre_completo": "Juan Pérez",
      "telefono": "0414-1234567",
      "correo_e": "juan@logitrack.com"
    },
    "resumen_productos": [
      {
        "producto_id": "uuid-producto",
        "codigo_producto": "PRD-001",
        "nombre_producto": "Agua Mineral 20L",
        "imagen_path": "/productos/agua-20l.webp",
        "cargado": 100,
        "despachado": 90,
        "sobrante": 10
      }
    ],
    "resumen_vacios": [
      {
        "cliente_id": "uuid-cliente",
        "razon_social": "Inversiones ABC C.A.",
        "rif_nit": "J-12345678-9",
        "detalles": [
          {
            "contenedor_id": "uuid-contenedor",
            "codigo_producto": "BOTELLON",
            "nombre_producto": "Botellón Vacío 20L",
            "entregado": 5,
            "retirado": 5
          }
        ]
      }
    ],
    "ordenes": [
      {
         // Detalle interno de la orden de distribución
         "orden_id": "uuid-orden",
         "correlativo": "ORD-001",
         "cliente": { ... },
         "detalles": [ ... ]
      }
    ]
  }
}
```

### Notas sobre los nuevos campos:
1. Dentro de **`resumen_productos`**:
   - `cargado`: La cantidad inicial asignada al camión.
   - `despachado`: La cantidad total facturada/entregada en la ruta.
   - `sobrante`: Diferencia matemática entre `cargado` y `despachado`.
2. Dentro del nuevo arreglo **`resumen_vacios`**:
   - Este bloque agrupa la actividad de contenedores por cliente.
   - `entregado`: Total de contenedores dejados al cliente (calculado según el producto).
   - `retirado`: Total de contenedores devueltos por el cliente en esa orden.

### Auto-Venta (Actualizado)

La funci�n `registrar_venta_en_ruta_autoventa` ahora soporta y calcula autom�ticamente el descuento de la tabla `descuentos_cliente_producto`, detallando en el response y en BD los campos `precio_lista_usd`, `porcentaje_descuento`, y `monto_descuento_usd`. La app m�vil ya no necesita enviarlos como el �nico source of truth (aunque si env�a `valor_unitario_usd` y no hay descuento expl�cito en BD, lo utilizar�).

### Consulta de Descuentos en Vivo

Para darle retroalimentaci�n en tiempo real al usuario de la aplicaci�n cuando selecciona un producto (si tiene internet), pueden usar el nuevo RPC `consultar_descuento_producto_cliente`.

- **Firma SQL:** `consultar_descuento_producto_cliente(p_cliente_id UUID, p_producto_id UUID)`
- **Uso en Frontend (TypeScript):**
``typescript
const { data, error } = await supabase.rpc('consultar_descuento_producto_cliente', {
  p_cliente_id: 'UUID-DEL-CLIENTE',
  p_producto_id: 'UUID-DEL-PRODUCTO'
});
``
Este RPC retorna un objeto JSON con los campos `aplica_descuento`, `precio_lista_usd`, `precio_final_usd`, `porcentaje_descuento` y `monto_descuento_usd`.
