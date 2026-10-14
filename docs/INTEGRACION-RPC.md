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

> [!IMPORTANT]
> **Envío explícito de `p_es_cortesia` y Limpieza de Sobrecargas (Parche `20261013192500`):**
> Al llamar a `crear_orden_distribucion`, el Frontend debe enviar SIEMPRE de forma explícita `p_es_cortesia: boolean` (ej. `p_es_cortesia: input.esCortesia ?? false`).
> Mediante el parche `20261013192500_drop_overload_crear_orden_distribucion.sql` se eliminó la sobrecarga obsoleta huérfana de 7 parámetros que provocaba el error en PostgreSQL:
> *"Could not choose the best candidate function between: public.crear_orden_distribucion(7 params) and public.crear_orden_distribucion(8 params)"*.

**Uso en Frontend (TypeScript):**
```typescript
const { data, error } = await supabase.rpc('crear_orden_distribucion', {
  p_vendedor_id: '...',
  p_cliente_id: '...',
  p_camion_id: '...',
  p_tasa_cambio: tasaCambio ?? null,
  p_productos_json: [...],
  p_despachador_id: cliente.despachador_id,
  p_id_ruta: cliente.id_ruta,
  p_es_cortesia: esCortesia ?? false // OBLIGATORIO: enviar true o false explícito
});
```

---

## Nuevas Funciones RPC: Inventario Móvil, Anulación y Edición de Órdenes (Parche `20261012114500`)

### 1. Consulta de Inventario Móvil Disponible (`obtener_inventario_disponible_movil`)

Permite a la aplicación móvil consultar en tiempo real los productos y existencias disponibles en el camión para prevenir ventas de productos agotados.

- **Nombre RPC:** `obtener_inventario_disponible_movil`
- **Parámetros:**
  - `p_camion_id` (`UUID`, requerido): Identificador único del camión.

**Ejemplo de llamada en Frontend (TypeScript):**
```typescript
const { data, error } = await supabase.rpc('obtener_inventario_disponible_movil', {
  p_camion_id: 'UUID-DEL-CAMION'
});
```

**Estructura de Respuesta JSON (Contrato):**
```json
{
  "success": true,
  "data": {
    "camion_id": "42618991-...",
    "placa": "A12BC34",
    "marca_modelo": "Iveco Daily",
    "estado_camion": "en_ruta",
    "inventario": [
      {
        "producto_id": "3333-444...",
        "codigo": "B20L",
        "nombre": "Botellón 20L",
        "imagen_path": "/productos/botellon.webp",
        "precio_lista1": 5.00,
        "cantidad_cargada": 100,
        "cantidad_entregada": 20,
        "cantidad_disponible": 80
      }
    ]
  },
  "error": null
}
```

---

### 2. Anulación de Órdenes de Distribución (`anular_orden_distribucion`)

Reversión atómica y transaccional de una orden. Restituye el inventario correspondiente (del camión en Auto-Venta / ruta, o del almacén central en Venta Directa), revierte los saldos de envases dejados/retirados al cliente y pasa el estado a `'anulada'`.

- **Nombre RPC:** `anular_orden_distribucion`
- **Parámetros:**
  - `p_orden_id` (`UUID`, requerido): Identificador de la orden a anular.
  - `p_motivo` (`TEXT`, opcional): Razón o justificativo de la anulación.

> [!CAUTION]
> **REGLA CRÍTICA DE BLOQUEO (Rendición/Cobranzas):**
> Si la orden ya cuenta con una rendición de cuentas activa (cobro registrado), la función **rechaza la anulación** con el código de error `ORDEN_CON_RENDICION`. Para poder anular la orden, el gerente debe reversar primero la rendición correspondiente.

**Ejemplo de llamada en Frontend (TypeScript):**
```typescript
const { data, error } = await supabase.rpc('anular_orden_distribucion', {
  p_orden_id: 'UUID-DE-LA-ORDEN',
  p_motivo: 'Cliente canceló el pedido por error en cantidades'
});

if (error || !data?.success) {
  // Manejo de error (ej: si tiene cobranzas/rendición activa)
  alert(data?.error?.message || error?.message);
}
```

**Estructura de Respuesta JSON (Contrato):**
```json
{
  "success": true,
  "message": "Orden de distribución anulada exitosamente y saldos revertidos.",
  "data": {
    "orden_id": "uuid-de-la-orden",
    "correlativo": 1054,
    "estado_anterior": "por_liquidar",
    "estado_nuevo": "anulada"
  },
  "error": null
}
```

---

### 3. Edición de Órdenes de Distribución (`editar_orden_distribucion`)

Permite corregir productos, cantidades o envases de una orden de distribución existente, recalculando de forma transparente y transaccional el inventario disponible y el saldo de envases del cliente.

- **Nombre RPC:** `editar_orden_distribucion`
- **Parámetros:**
  - `p_orden_id` (`UUID`, requerido): Identificador de la orden a editar.
  - `p_productos_json` (`JSONB`, requerido): Lista de productos actualizada `[{ producto_id, cantidad, valor_unitario_usd? }]`.
  - `p_contenedores_json` (`JSONB`, opcional): Lista de envases retirados `[{ contenedor_id, cantidad_retirada }]`.
  - `p_observaciones` (`TEXT`, opcional): Notas de la modificación.

> [!WARNING]
> Al igual que la anulación, **NO se permite editar una orden que ya tenga rendición de cuentas o cobranzas asociadas**, ya que alteraría los importes cobrados en caja.

**Ejemplo de llamada en Frontend (TypeScript):**
```typescript
const { data, error } = await supabase.rpc('editar_orden_distribucion', {
  p_orden_id: 'UUID-DE-LA-ORDEN',
  p_productos_json: [
    { producto_id: 'uuid-prod-1', cantidad: 10 }
  ],
  p_contenedores_json: [
    { contenedor_id: 'uuid-tipo-contenedor', cantidad_retirada: 5 }
  ],
  p_observaciones: 'Corrección de cantidades solicitadas'
});
```

---

### 📢 DIRECTIVA OBLIGATORIA PARA EL EQUIPO FRONTEND

1. **Incorporación del botón "Anular Orden":**
   - Debe habilitarse e incorporarse la acción interactiva de **"Anular Orden"** en las interfaces y pantallas de consulta/detalle de los tres módulos de emisión:
     - **Pre-venta** (Web y Móvil)
     - **Auto-venta** (App Móvil y Web)
     - **Ventas Directas de Almacén** (Web y Móvil)
3. **Soporte de Saldo de Contenedores a Favor del Cliente (`saldo < 0`):**
   - Anteriormente existía una restricción `CHECK (saldo_pendiente >= 0)` y un truncamiento `GREATEST(0, ...)` que impedía que un cliente pudiera entregar más envases de los que tenía pendientes.
   - **Comportamiento Actual:** Se eliminaron las restricciones CHECK y truncamientos. Si a un cliente se le retiran más envases de los que debía, su saldo ahora reflejará un valor **negativo (`< 0`)**, lo cual indica un saldo de envases **a favor del cliente**.
   - **Frontend Web & Mobile:** La función `retorna_saldo_contenedores_segun_clientes` y los listados de estado de cuenta filtran ahora por `saldo_pendiente <> 0` (no solo `> 0`), mostrando saldos tanto adeudados (> 0) como saldos a favor (< 0).
   - **Anulación de Órdenes:** Se eliminó la inserción errónea de movimientos con cantidades negativas. Ahora `anular_orden_distribucion` revierte el saldo del cliente matemáticamente y purga los registros de `movimientos_contenedores` correspondientes a la orden, evitando violaciones de restricciones CHECK.
