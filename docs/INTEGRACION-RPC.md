# INTEGRACION-RPC

## ActualizaciÃ³n de Reporte de RendiciÃ³n y Carga de CamiÃ³n

Se ha actualizado la funciÃ³n encargada de retornar el reporte de la carga de camiÃ³n y la rendiciÃ³n, inyectando las mÃ©tricas solicitadas de productos y contenedores (vacÃ­os). 

- **Nombre de la funciÃ³n RPC:** `retorna_radar_detalle_reporte`
- **ParÃ¡metros de entrada:** 
  - `p_radar_id` (`uuid`): Identificador Ãºnico del radar/ruta.

### Mockup de Respuesta JSON (Contrato)

A continuaciÃ³n se muestra un ejemplo de la nueva estructura que devuelve la funciÃ³n. Se destacan en la documentaciÃ³n los nuevos campos solicitados:

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
      "nombre_completo": "Juan PÃ©rez",
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
            "nombre_producto": "BotellÃ³n VacÃ­o 20L",
            "entregado": 5,
            "retirado": 5
          }
        ]
      }
    ],
    "ordenes": [
      {
         // Detalle interno de la orden de distribuciÃ³n
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
   - `cargado`: La cantidad inicial asignada al camiÃ³n.
   - `despachado`: La cantidad total facturada/entregada en la ruta.
   - `sobrante`: Diferencia matemÃ¡tica entre `cargado` y `despachado`.
2. Dentro del nuevo arreglo **`resumen_vacios`**:
   - Este bloque agrupa la actividad de contenedores por cliente.
   - `entregado`: Total de contenedores dejados al cliente (calculado segÃºn el producto).
   - `retirado`: Total de contenedores devueltos por el cliente en esa orden.

### Auto-Venta (Actualizado)

La función `registrar_venta_en_ruta_autoventa` ahora soporta y calcula automáticamente el descuento de la tabla `descuentos_cliente_producto`, detallando en el response y en BD los campos `precio_lista_usd`, `porcentaje_descuento`, y `monto_descuento_usd`. La app móvil ya no necesita enviarlos como el único source of truth (aunque si envía `valor_unitario_usd` y no hay descuento explícito en BD, lo utilizará).

### Consulta de Descuentos en Vivo

Para darle retroalimentación en tiempo real al usuario de la aplicación cuando selecciona un producto (si tiene internet), pueden usar el nuevo RPC `consultar_descuento_producto_cliente`.

- **Firma SQL:** `consultar_descuento_producto_cliente(p_cliente_id UUID, p_producto_id UUID)`
- **Uso en Frontend (TypeScript):**
``typescript
const { data, error } = await supabase.rpc('consultar_descuento_producto_cliente', {
  p_cliente_id: 'UUID-DEL-CLIENTE',
  p_producto_id: 'UUID-DEL-PRODUCTO'
});
``
Este RPC retorna un objeto JSON con los campos `aplica_descuento`, `precio_lista_usd`, `precio_final_usd`, `porcentaje_descuento` y `monto_descuento_usd`.

### Reporte Detallado de Entregas por Cliente (AutoVentas)

Se ha creado un nuevo RPC para retornar el detalle pormenorizado de los productos entregados a cada cliente durante una jornada de AutoVenta, agrupado por cliente. Esto facilita la generación del reporte y auditoría de la mercancía de un camión.

- **Nombre de la función RPC:** `retorna_reporte_autoventas_entregas_cliente`
- **Parámetros de entrada:** 
  - `p_camion_id` (`uuid`): Identificador único del camión.
  - `p_fecha` (`date`): Opcional. Fecha de la jornada (por defecto usa la fecha actual).

**Uso en Frontend (TypeScript):**
```typescript
const { data, error } = await supabase.rpc('retorna_reporte_autoventas_entregas_cliente', {
  p_camion_id: 'UUID-DEL-CAMION',
  p_fecha: '2026-10-06' // Opcional
});
```

**Estructura de Respuesta JSON (Contrato):**
```json
{
  "success": true,
  "data": {
    "camion_id": "42618991-...",
    "fecha": "2026-10-06",
    "total_general_usd": 350.00,
    "inventario": [
      {
        "producto_id": "3333-444...",
        "codigo": "B20L",
        "nombre": "Botellón 20L",
        "cantidad_cargada": 100,
        "cantidad_entregada": 20,
        "devolucion": 80
      }
    ],
    "entregas": [
      {
        "cliente_id": "1111-222...",
        "razon_social": "Inversiones ABC",
        "rif_nit": "J-12345678-9",
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
          }
        ]
      }
    ]
  }
}
```

### Órdenes de Distribución por Cortesía (Ventas y AutoVentas)

A partir del parche `20261007161348`, se ha implementado la funcionalidad para registrar entregas de productos como cortesía, afectando el inventario normalmente, pero asumiendo los montos de cobro y registro como `$0.00` para no generar falsas cuentas por cobrar ni descuadrar los reportes financieros.

**Cambios aplicados:**
1. **`crear_orden_distribucion`**: Recibe ahora el parámetro opcional `p_es_cortesia BOOLEAN DEFAULT FALSE`.
2. **`registrar_venta_en_ruta_autoventa`**: Recibe ahora el parámetro opcional `p_es_cortesia BOOLEAN DEFAULT FALSE`.
3. **`crear_venta_directa_almacen`**: Recibe ahora el parámetro opcional `p_es_cortesia BOOLEAN DEFAULT FALSE`.

Si se envía `p_es_cortesia: true` desde la App Móvil o panel Web, el sistema automáticamente:
- Marca la orden con `es_cortesia = true`.
- Fija `valor_unitario_usd` y los `subtotales` en `0.00` (ignorando incluso los descuentos de clientes).
- Excluye estas órdenes de la lista que retorna `solicita_abonos_orden_distribucion`, lo que impide cobrar dinero sobre ellas.

*Nota del Frontend*: Ya se implementó el Checkbox / Switch visual en el formulario de Venta Directa (tanto en el Dashboard Web (`venta-directa-form.tsx`) como en la App Móvil (`venta-directa.tsx`)). Al marcarse la opción de cortesía, la interfaz visualiza automáticamente los montos y totales en `$0.00` de forma simultánea, enviando el booleano `p_es_cortesia` a este RPC.

**Uso en Frontend (TypeScript):**
```typescript
const { data, error } = await supabase.rpc('crear_orden_distribucion', {
  p_vendedor_id: '...',
  p_cliente_id: '...',
  p_camion_id: '...',
  p_productos_json: [...],
  p_es_cortesia: true // NUEVO: Enviar en true si es de cortesía
});
```
