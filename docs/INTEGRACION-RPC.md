# INTEGRACION-RPC

## Especificaciones Técnicas: Ajustes en Reportes de Radar

> **Fecha:** 2026-11-06  
> **Destinatario:** Encargado de Front-end  
> **Documento Fuente:** `docs/especificaciones_de_reportes_de_radar.md`  
> **Objetivo:** Cumplir las directrices y medidas técnicas exactas para corregir el diseño, tamaño de tipografía y ancho de las celdas en los reportes de Radar, evitando errores de renderizado o desbordamiento en el Front-end.

---

### 1. Tipografía Global
* **Tamaño de fuente:** `8pt` (ocho puntos) de manera estricta.
* **Aplicación:** Aplica para todas las tablas, encabezados (headers) y celdas de datos en los reportes de Radar.

---

### 2. Reporte Resumen
Configuración de anchos de columna (basada en unidades estándar de caracteres de celda o su equivalente exacto en el motor de renderizado del Front-end):

* **Columna A (Producto):** Ancho `= 35`
* **Columna B (Código):** Ancho `= 12`
* **Columna C (Cargado):** Ancho `= 8`
* **Columna D (Despachado):** Ancho `= 10`
* **Columna E (Sobrante):** Ancho `= 8`

*Definición HTML/Excel recomendada (<colgroup>):*
```html
<colgroup>
  <col width="35" style="width: 35ch;" />
  <col width="12" style="width: 12ch;" />
  <col width="8"  style="width: 8ch;" />
  <col width="10" style="width: 10ch;" />
  <col width="8"  style="width: 8ch;" />
</colgroup>
```

---

### 3. Reporte de Despachos
Configuración de anchos de columna:

* **Columna A (Producto):** Ancho `= 46`
* **Columna B (Código):** Ancho `= 16`
* **Columna C (Cantidad Solicitada):** Ancho `= 16`

*Definición HTML/Excel recomendada (<colgroup>):*
```html
<colgroup>
  <col width="46" style="width: 46ch;" />
  <col width="16" style="width: 16ch;" />
  <col width="16" style="width: 16ch;" />
</colgroup>
```

---

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
   - **Comportamiento Actual:** Se eliminaron las restricciones CHECK y truncamientos en Supabase (`db push` completado). Si a un cliente se le retiran más envases de los que debía, su saldo ahora refleja un valor **negativo (`< 0`)**, lo cual indica un saldo de envases **a favor del cliente**.
   - **Frontend Web & Mobile:** Se eliminaron todas las alertas y mensajes restrictivos (ej. *"Los retirados superan el saldo del cliente más lo entregado; el saldo quedará en 0"*) y los `Math.max(0, ...)` en estado de cuenta y tickets de impresión. Ahora los saldos a favor se muestran en verde o con su valor negativo real (`-X`).
   - **Listados de Envases:** La función `retorna_saldo_contenedores_segun_clientes` y los listados de estado de cuenta filtran ahora por `saldo_pendiente <> 0` (no solo `> 0`), mostrando saldos tanto adeudados (> 0) como saldos a favor (< 0).
   - **Anulación de Órdenes:** Se eliminó la inserción errónea de movimientos con cantidades negativas. Ahora `anular_orden_distribucion` revierte el saldo del cliente matemáticamente y purga los registros de `movimientos_contenedores` correspondientes a la orden, evitando violaciones de restricciones CHECK.

---

### 4. Movimientos Especiales de Inventario (`registrar_movimiento_inventario_especial`)

Permite registrar entradas o salidas excepcionales (obsequios, consumo interno, eventos, mermas/daños o ajustes) afectando tanto el **Almacén** central como el **Inventario Móvil** (camiones).

- **Nombre RPC:** `registrar_movimiento_inventario_especial`
- **Parámetros:**
  - `p_tipo_movimiento` (`VARCHAR`): `'ENTRADA'` o `'SALIDA'`.
  - `p_concepto` (`VARCHAR`): Concepto (`'OBSEQUIO'`, `'CONSUMO_INTERNO'`, `'EVENTOS'`, `'MERMA'`, `'AJUSTE'`, u otro texto).
  - `p_tipo_inventario_afectado` (`VARCHAR`): `'ALMACEN'` o `'MOVIL'`.
  - `p_id_referencia_movil` (`UUID`, requerido si es `'MOVIL'`): Identificador del camión (`camion_id`).
  - `p_id_cliente` (`UUID`, opcional): Identificador del cliente asociado al movimiento especial (si aplica).
  - `p_observaciones` (`TEXT`, opcional): Notas adicionales.
  - `p_detalles` (`JSONB`): Array de productos `[{ producto_id: UUID, cantidad: number, costo_unitario: number }]`.

**Corrección en BD para `MOVIL`:**
- En la tabla `public.inventario_movil`, el stock disponible se calcula como `(cantidad_cargada - cantidad_entregada)`. Se corrigió la consulta que erróneamente buscaba columnas inexistentes (`radar_id` y `cantidad_disponible`), vinculando ahora directamente por `camion_id` y actualizando `cantidad_cargada`.

**Respuesta estándar:**
```json
{
  "success": true,
  "message": "Movimiento registrado exitosamente",
  "data": {
    "movimiento_id": "uuid-del-movimiento"
  },
  "error": null
}
```

---

### 5. Resumen de Jornada de AutoVentas (`retorna_resumen_autoventas_jornada`)

#### Directiva para el Frontend (Web y Móvil):
Al consultar el **Resumen de Jornada** en el módulo de AutoVentas, es **indispensable enviar el parámetro `p_fecha`** si se desea consultar cualquier día específico o una jornada histórica.

#### Contexto del Comportamiento:
La función en Supabase tiene como firma `public.retorna_resumen_autoventas_jornada(p_camion_id uuid, p_fecha date DEFAULT CURRENT_DATE)`.
- Si **no** se envía `p_fecha` (o se envía `null`/`undefined`), PostgreSQL aplica automáticamente `CURRENT_DATE` (la fecha de hoy).
- Si el usuario en el frontend selecciona una fecha anterior en el calendario (por ejemplo, `2026-10-07`) pero el frontend no envía el parámetro a Supabase, la base de datos consulta la fecha actual y la pantalla muestra 0 ventas.

#### Parámetros de la RPC:
- `p_camion_id` (`UUID`, Requerido): Identificador del camión asignado a la autoventa.
- `p_fecha` (`DATE`, Recomendado / Obligatorio para fechas pasadas): Fecha de la jornada en formato `'YYYY-MM-DD'`. Si se omite, toma la fecha del día actual.

#### Ejemplo de Invocación en Frontend (TypeScript / Supabase Client):
```typescript
const { data, error } = await supabase.rpc('retorna_resumen_autoventas_jornada', {
  p_camion_id: camionId,
  p_fecha: fechaSeleccionada // ej: '2026-10-07'
});
```

#### En Server Actions de Next.js (`@/lib/actions/autoventas`):
```typescript
// En autoventas-client.tsx o hook de consulta:
useEffect(() => {
  if (!camionId) return;
  setCargandoResumen(true);
  void obtenerResumenAutoVentasJornada(camionId, fechaSeleccionada).then((res) => {
    setCargandoResumen(false);
    if (res.success && res.data) {
      setResumenRpc(res.data);
    }
  });
}, [camionId, fechaSeleccionada]); // Recordar incluir fechaSeleccionada en las dependencias
```

#### Estructura de Respuesta del RPC:
```json
{
  "success": true,
  "data": {
    "camion_id": "1a921046-7e7a-429b-bbb0-f242b32071a6",
    "fecha": "2026-10-07",
    "total_ordenes_autoventa": 4,
    "total_facturado_usd": 3959.5,
    "total_facturado_bs": 3460076.38,
    "inventario_movil": [
      {
        "producto_id": "uuid-producto",
        "codigo": "PRD-01",
        "nombre": "Agua 20L",
        "cantidad_cargada": 100,
        "cantidad_entregada": 100,
        "cantidad_disponible": 0
      }
    ],
    "ventas": [
      {
        "orden_id": "6f605f38-3243-4ef0-8a1b-6c1f3d020156",
        "correlativo": 15,
        "factura_origen_numero": "AV-000015",
        "cliente_nombre": "INVERSIONES PUERTO LA CRUZ",
        "estado": "por_liquidar",
        "total_recaudar_usd": 692.7,
        "total_recaudar_bs": 605327.67,
        "created_at": "2026-10-07T19:09:50.051346+00:00"
      }
    ]
  },
  "error": null
}
```


---

### 6. Regla de Estado de Camiones: Solo en Carga y Descarga (`en_ruta` / `disponible`)

#### Regla de Negocio Implementada en Base de Datos (`20261022125500_fix_estado_camion_solo_carga_descarga.sql`):
El estado de un camión (`public.camiones.estado`) **únicamente cambia cuando se carga o se descarga el camión**, nunca al cobrar o liquidar órdenes individuales:

1. **Carga del Camión (`disponible` → `en_ruta`):**
   - `solicita_cargar_inventario_movil_desde_almacen` (tanto en **Radar** como en **AutoVentas**).
   - `cargar_inventario_movil` / transición a `en_transito`.

2. **Liquidación Financiera / Cobranzas (NO altera el estado del camión):**
   - Se eliminó el `UPDATE public.camiones SET estado = 'disponible'` dentro de `liquidar_orden_distribucion` (disparado al aprobar Rendiciones de Cuentas) y de `actualizar_estado_orden_distribucion` (en las transiciones a `liquidada` o `anulada`).
   - Ahora, cuando se cobra o liquida una orden individual, el camión **mantiene su estado actual** (`en_ruta`) hasta que se ejecute formalmente su descarga de inventario en almacén.

3. **Descarga del Camión (`en_ruta` → `disponible`):**
   - **AutoVentas (`descargar_camion_autoventa`):** Al ejecutar la descarga total del sobrante al almacén principal, vacía `inventario_movil` del camión y pasa el camión a `'disponible'`.
   - **Radar — Cierre y Retorno de Inventario (`solicita_aprobar_radar` → `retorna_inventario_no_despachado_para_almacen`):** Devuelve la mercancía no despachada al almacén principal, limpia el `inventario_movil` del camión y actualiza `camiones.estado = 'disponible'` (verificando que no tenga otro radar activo en tránsito).
   - **Radar — Reverso de Carga (`solicita_reversar_carga_inventario_movil_a_almacen`):** Al descargar/reversar toda la carga del camión de vuelta al almacén antes de iniciar entregas, actualiza `camiones.estado = 'disponible'`.


---

## 7. Tareas Exclusivas del Frontend (22/10/2026) — Sin cambios en Base de Datos

Las siguientes tareas corresponden 100% al equipo de desarrollo Frontend (Web y Móvil), ya que toda la infraestructura de datos, tablas y funciones RPC en Supabase se encuentran implementadas y listas para su consumo.

---

### A. APK Móvil: Opción de Impresión de Orden en Despacho de Productos

- **Módulo:** `apps/mobile` (Radar / Entregas / Órdenes)
- **Estado de Supabase / Backend:** ✅ **Listo y disponible**. No requiere nuevas funciones en base de datos.
- **Detalle de la Tarea para Frontend:**
  1. En el flujo donde el despachador o chofer realiza la entrega/despacho físico de productos (módulo de Radar `app/(app)/radar/index.tsx` y `app/(app)/radar/entrega/[ordenId].tsx`), asegurar que la acción interactiva de **"Imprimir Orden / Ticket"** esté visible y accesible de forma directa.
  2. Verificar que tanto antes de iniciar la parada como inmediatamente tras confirmar la entrega de productos y el retiro de vacíos, el usuario pueda lanzar la impresión térmica Bluetooth mediante el motor existente `imprimirTicketOrden(ordenId)` de `apps/mobile/lib/print-orden.ts`.
  3. En la tarjeta de orden (`OrdenCard.tsx`) o listado general de órdenes (`ordenes/index.tsx`), habilitar el acceso directo a la impresión del ticket sin obligar al usuario a navegar por múltiples pantallas intermedias.

---

### B. Dashboard Web: Reporte de Formas de Pago — Exportar a Excel y Quitar Botón de Imprimir

- **Módulo:** Dashboard Web (`src/app/(dashboard)/rendiciones/formas-pago/`)
- **Estado:** ✅ **Completado**.
- **Función RPC Existente:** `public.reporte_formas_pago_rendicion(p_fecha_desde date, p_fecha_hasta date, p_solo_bancarios boolean)`
- **Detalle Implementado:**
  1. Se removió el botón Imprimir y se agregó el botón `Exportar a Excel` con estilos a 10pt, `line-height: 1.15`, padding compacto y resumen final con montos totales.
  2. Archivos: `src/lib/export/formas-pago-excel.ts`, `src/app/(dashboard)/rendiciones/formas-pago/export-formas-pago-excel-button.tsx`, `page.tsx`.

---

### C. Dashboard Web: Cuentas por Cobrar (Órdenes por Liquidar) — Exportar a Excel

- **Módulo:** Dashboard Web (`src/app/(dashboard)/rendiciones/por-liquidar/`)
- **Estado:** ✅ **Completado**.
- **Detalle Implementado:**
  1. Se incorporó botón `Exportar a Excel` en la cabecera de la vista de órdenes por liquidar.
  2. Generación de Excel con estándar visual de 10pt, `line-height: 1.15`, padding compacto y resumen al final con Total Clientes, Total Órdenes y Monto Total por Liquidar (USD).
  3. Archivos: `src/lib/export/por-liquidar-excel.ts`, `src/app/(dashboard)/rendiciones/por-liquidar/export-por-liquidar-excel-button.tsx`, `page.tsx`.

---

### D. Dashboard Web: Cobranzas — Consulta por Rango de Fechas y Exportar a Excel

- **Módulo:** Dashboard Web (`src/app/(dashboard)/rendiciones/`)
- **Estado:** ✅ **Completado**.
- **Detalle Implementado:**
  1. Formulario interactivo de filtros de fecha (`desde` y `hasta`) con botón "Consultar" y "Limpiar".
  2. Filtrado dinámico en la consulta a `rendiciones_cuentas`.
  3. Botón `Exportar a Excel` que genera la planilla de cobranzas del período con formato 10pt, padding compacto y resumen final de totales (Efectivo, Transferencias, Total USD y Total Bs).
  4. Archivos: `src/lib/export/cobranzas-excel.ts`, `src/app/(dashboard)/rendiciones/cobranzas-filtros.tsx`, `src/app/(dashboard)/rendiciones/export-cobranzas-excel-button.tsx`, `page.tsx`.

---

## 8. Entidades Bancarias (BCV) y Control de Duplicidad de Referencias en Cobranzas (23/10/2026)

### Parche de Base de Datos:
- `supabase/tenant_patches/20261023140000_entidades_bancarias_y_unicidad_pagos.sql`
- `supabase/migrations/20261023140000_entidades_bancarias_y_unicidad_pagos.sql`
- `supabase/seed_base.sql` (Semilla inicial para futuros tenants)

### 8.1. Tabla `public.entidades_bancarias`
Catálogo oficial de instituciones bancarias activas en Venezuela según el BCV / SUDEBAN, utilizando el código oficial de 4 dígitos como llave primaria natural:

```sql
CREATE TABLE IF NOT EXISTS public.entidades_bancarias (
    codigo_eb VARCHAR(4) PRIMARY KEY,      -- '0102', '0134', '0105', etc.
    nombre_eb VARCHAR(120) NOT NULL,
    nombre_corto VARCHAR(50),
    rif_eb VARCHAR(15),
    activo BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);
```

### 8.2. Nueva Función RPC: `public.retorna_entidades_bancarias`
- **Firma:** `public.retorna_entidades_bancarias(p_solo_activas boolean DEFAULT true)`
- **Respuesta JSON:**
  ```json
  {
    "success": true,
    "data": [
      {
        "codigo_eb": "0102",
        "nombre_eb": "Banco de Venezuela, S.A. Banco Universal",
        "nombre_corto": "Banco de Venezuela",
        "rif_eb": "G-20009997-6",
        "activo": true
      }
    ],
    "error": null
  }
  ```

### 8.3. Modificación en `public.detalle_rendicion_fpagos` (Control de Duplicidad)
- Se agregó la columna `codigo_banco VARCHAR(4) REFERENCES public.entidades_bancarias(codigo_eb) ON DELETE RESTRICT`.
- Se agregó la restricción de unicidad compuesta:
  ```sql
  CONSTRAINT uq_pago_banco_referencia UNIQUE (codigo_banco, referencia_bancaria)
  ```
- **Comportamiento:**
  - Permite una misma referencia en bancos distintos (`0102-000225633` y `0134-000225633`).
  - Bloquea que la misma tupla `(codigo_banco, referencia_bancaria)` se registre más de una vez.
  - **Registros históricos (Opción A):** Permanecen con `codigo_banco = NULL` (histórico cerrado y conciliado; en PostgreSQL los valores `NULL` no colisionan en la restricción `UNIQUE`).
  - **Reverso de cobranzas (`reversa_rendicion_cuenta_segun_id_rendicion`):** Cuando el gerente reversa una cobranza aprobada, la función libera `codigo_banco = NULL` en `detalle_rendicion_fpagos` para que la referencia bancaria pueda volver a cargarse si fue reversada por error de captura.

### 8.4. Contratos Actualizados en RPCs e Integración Frontend / Móvil
1. **`public.registrar_rendicion_cuentas`:**
   - Cada elemento del arreglo `p_pagos` ahora acepta `"codigo_banco": "0102"`.
   - Si el par `(codigo_banco, referencia_bancaria)` ya existe en `detalle_rendicion_fpagos`, retorna `success: false` con `error.code = 'REFERENCIA_DUPLICADA'` y un mensaje descriptivo indicando el banco y la referencia.
2. **`public.reporte_formas_pago_rendicion`:**
   - Cada movimiento del arreglo `data.movimientos` ahora incluye `"codigo_banco"` y `"nombre_banco"`.
3. **Frontend Web y App Móvil:**
   - `src/lib/actions/rendiciones.ts` (`listarEntidadesBancariasAction`, validación de `codigo_banco` en `registrarRendicionCuentasAction`).
   - `src/app/(dashboard)/rendiciones/nuevo/nueva-rendicion-form.tsx` (selector **Entidad bancaria (BCV)** y validación de duplicados en el formulario).
   - `apps/mobile/lib/rendiciones.ts` y `apps/mobile/app/(app)/rendiciones/nueva.tsx` (selector de banco en la pantalla móvil de nueva rendición).

---

## 9. Formato Numérico de Tasa en Exportación Excel (23/10/2026)

- **Estado:** ✅ **COMPLETADO E IMPLEMENTADO AL 100% EN FRONTEND WEB.**
- **Archivos actualizados:**
  - `src/lib/export/cobranzas-excel.ts`
  - `src/lib/export/formas-pago-excel.ts`
- **Problema corregido:** En Excel con configuración regional en español, el punto decimal se interpretaba como separador de miles, convirtiendo `886.2271` en `8.862.271,00`.
- **Solución implementada:**
  - Se configuró la clase `td.tasa` con `mso-number-format: "#,##0.0000";` para que Excel respete estrictamente los 4 decimales oficiales del BCV (`886,2271`).
  - Se añadió la columna **Tasa BCV** con formato de 4 decimales en el Excel de formas de pago.

---

## 10. DIRECTIVA PARA FRONTEND MÓVIL (APK): Selector de Entidad Bancaria Emisora en Cobranzas (28/10/2026)

> [!IMPORTANT]
> **ACCIÓN REQUERIDA PARA EL PRÓXIMO BUILD DE LA APK (`apps/mobile`):**
> En el último build de la APK no quedó incluido el selector de la **Entidad Bancaria Emisora (BCV)** cuando se registra una cobranza con **Transferencia** o **Pago Móvil** (`fpago_info = true`).
> A continuación se detalla la especificación técnica completa y los archivos ya sincronizados en el repositorio para que el equipo Frontend los integre y verifique antes de compilar el próximo APK.

### 10.1. Resumen del Requerimiento Funcional en Cobranzas (APK)

Cuando el usuario registra una cobranza (Rendición de Cuentas) en la App Móvil (`apps/mobile/app/(app)/rendiciones/nueva.tsx`) y selecciona una forma de pago bancaria (`forma.fpago_info === true`, como **Transferencia** o **Pago Móvil**), el formulario **DEBE mostrar y exigir tres (3) datos bancarios obligatorios**:

1. **Entidad bancaria emisora (BCV) (`codigo_banco`):**
   - Banco desde el cual el cliente emite la transferencia o el pago móvil (catálogo oficial BCV de 4 dígitos: `0102 · Banco de Venezuela`, `0134 · Banesco`, `0105 · Banco Mercantil`, etc.).
   - Se obtiene invocando el RPC `retorna_entidades_bancarias({ p_solo_activas: true })` (con fallback a consulta directa de `public.entidades_bancarias` y catálogo BCV local).
2. **Cuenta bancaria destino de la empresa (`cuenta_bancaria_id`):**
   - Cuenta receptora de la empresa donde ingresó el dinero (`retorna_cuentas_bancarias_empresa`).
3. **Referencia bancaria (`referencia_bancaria`):**
   - Número o código de referencia de la operación.

### 10.2. Contratos RPC de Supabase (Ya Activos en Base de Datos)

#### A) Consultar catálogo de bancos emisores (BCV)
- **Nombre RPC:** `public.retorna_entidades_bancarias`
- **Parámetros:**
  ```typescript
  const { data, error } = await supabase.rpc('retorna_entidades_bancarias', {
    p_solo_activas: true
  });
  ```
- **Estructura de Respuesta JSON:**
  ```json
  {
    "success": true,
    "data": [
      {
        "codigo_eb": "0102",
        "nombre_eb": "Banco de Venezuela, S.A. Banco Universal",
        "nombre_corto": "Banco de Venezuela",
        "rif_eb": "G-20009997-6",
        "activo": true
      },
      {
        "codigo_eb": "0134",
        "nombre_eb": "Banesco Banco Universal, C.A.",
        "nombre_corto": "Banesco",
        "rif_eb": "J-07013380-5",
        "activo": true
      }
    ],
    "error": null
  }
  ```

#### B) Registrar Cobranza / Rendición con `codigo_banco`
- **Nombre RPC:** `public.registrar_rendicion_cuentas`
- **Payload de cada elemento dentro de `p_pagos`:**
  ```typescript
  const { data, error } = await supabase.rpc('registrar_rendicion_cuentas', {
    p_cliente_id: clienteId,
    p_observaciones: observaciones ?? null,
    p_creado_por: userId,
    p_tasa_cambio: tasaDia,
    p_ordenes: [
      {
        orden_id: 'uuid-orden',
        monto_recaudado: 50.00,
        monto_recaudado_bs: 44311.36
      }
    ],
    p_pagos: [
      {
        fpago_id: 'uuid-forma-pago',
        monto: 50.00,
        monto_usd: 50.00,
        monto_bs: 44311.36,
        codigo_banco: '0102',              // <-- OBLIGATORIO cuando fpago_info = true (Código BCV 4 dígitos)
        cuenta_bancaria_id: 'uuid-cuenta', // <-- OBLIGATORIO cuando fpago_info = true (Cuenta destino empresa)
        referencia_bancaria: '000225633',  // <-- OBLIGATORIO cuando fpago_info = true
        cuenta_bancaria: null,
        capture_url: null
      }
    ]
  });
  ```

#### C) Regla de Unicidad Compuesta `(codigo_banco, referencia_bancaria)`
- La tabla `public.detalle_rendicion_fpagos` tiene la restricción `CONSTRAINT uq_pago_banco_referencia UNIQUE (codigo_banco, referencia_bancaria)`.
- **Misma referencia en bancos distintos:** Permitido (ej. `0102` + `000225633` y `0134` + `000225633`).
- **Misma referencia en el mismo banco:** Rechazado automáticamente por el RPC con:
  ```json
  {
    "success": false,
    "error": {
      "code": "REFERENCIA_DUPLICADA",
      "message": "La referencia bancaria "000225633" para la entidad bancaria 0102 (Banco de Venezuela) ya fue registrada previamente en otra cobranza."
    }
  }
  ```

### 10.3. Archivos de la App Móvil (`apps/mobile`) Actualizados en el Repositorio

Al hacer `git pull origin main`, el desarrollador Frontend encontrará listos y tipados los siguientes archivos en `apps/mobile`:

1. **`apps/mobile/lib/rendiciones.ts`**:
   - Tipo `EntidadBancaria` y función `listarEntidadesBancarias()` (consume `retorna_entidades_bancarias`, con fallback a tabla `entidades_bancarias` y lista BCV offline).
   - Tipo `PagoInput` con `codigo_banco?: string | null`.
   - Validación en `registrarRendicion()`: exige `codigo_banco`, `cuenta_bancaria_id` y `referencia_bancaria` cuando `fpago_info === true`, verifica que no haya tuplas `(codigo_banco, referencia_bancaria)` repetidas en el mismo formulario y envía `codigo_banco` dentro de `p_pagos`.
   - `getRendicionDetalle()` y `reporteFormasPago()`: incluyen `codigo_banco` y `nombre_banco` para mostrar el banco emisor en las consultas.
2. **`apps/mobile/app/(app)/rendiciones/nueva.tsx`**:
   - Carga el catálogo de bancos emisores con `listarEntidadesBancarias()`.
   - Muestra el selector modal (`pickerBancoKey`) bajo la etiqueta **"Entidad bancaria emisora (BCV) *"**, diferenciado claramente de **"Cuenta bancaria destino (Empresa) *"** y **"Referencia bancaria *"**.
3. **`apps/mobile/app/(app)/rendiciones/[id].tsx`** y **`apps/mobile/app/(app)/rendiciones/formas-pago.tsx`**:
   - Muestran en el detalle de cada pago el banco emisor BCV (`codigo_banco` y `nombre_banco`) junto con el número de referencia y la cuenta destino.


---

## 11. INFORME TÉCNICO Y DIRECTIVA PARA FRONTEND: Corrección de Generación de Saldo a Favor en Cobranzas / Rendiciones (03/11/2026)

> [!IMPORTANT]
> **ACCIÓN REQUERIDA PARA EL ENCARGADO DE FRONTEND (`apps/mobile`):**
> En el build actual de la APK (`v0.2.4` / `versionCode 7`), cuando se registra una cobranza (Rendición de Cuentas) y el cliente paga de más, **no se le está sumando el excedente a su `saldo_favor`**.
> Se realizó la auditoría completa en **PostgreSQL (Supabase)** y en el **Frontend**. A continuación se presenta el informe técnico y las instrucciones exactas para que el encargado del Frontend aplique la corrección.

---

### 11.1. Verificación en PostgreSQL (Supabase) — ✅ Funciones Operativas

Se auditaron las funciones RPC en Supabase (`public.registrar_rendicion_cuentas` y `public.solicita_abonos_orden_distribucion`):

1. **`public.registrar_rendicion_cuentas`:**
   - Calcula `v_total_ordenes` sumando `monto_recaudado` de cada elemento en `p_ordenes` (lo que amortiza las facturas).
   - Calcula `v_total_pagos` sumando `monto_usd` (o `monto_bs / v_tasa_cambio`) de cada elemento en `p_pagos` (el dinero realmente entregado por el cliente).
   - **Regla de generación de Saldo a Favor en BD:**
     ```sql
     -- 8. Manejo de Excedente de Pago (Crédito a Favor Generado)
     IF v_total_pagos > v_total_ordenes THEN
         v_exceso := v_total_pagos - v_total_ordenes;
         v_exceso_bs := v_exceso * v_tasa_cambio;

         INSERT INTO public.movimientos_saldo_favor (
             cliente_id, rendicion_id, orden_id, monto, tipo, observaciones, created_at
         ) VALUES (
             p_cliente_id, v_rendicion_id, NULL, v_exceso, 'abono_recaudacion',
             'Excedente en formas de pago de rendición de cuentas ID: ' || v_rendicion_id, NOW()
         );

         UPDATE public.clientes
         SET saldo_favor = COALESCE(saldo_favor, 0.00) + v_exceso
         WHERE id = p_cliente_id;
     END IF;
     ```
   - Retorna en el JSON de respuesta:
     - `data.saldo_favor_usado`
     - `data.saldo_favor_generado`
     - `data.saldo_favor_generado_bs`
2. **`public.solicita_abonos_orden_distribucion`:**
   - Retorna `data.saldo_favor` y `data.saldo_favor_bs` directamente desde `public.clientes`.
3. **Condición obligatoria del contrato RPC:**
   - Para que PostgreSQL acredite el excedente en `clientes.saldo_favor`, el Frontend **DEBE** enviar:
     - En `p_ordenes`: `monto_recaudado` limitado al `saldo_pendiente` de cada orden (`montoAplicable(digitado, saldo_pendiente)`).
     - En `p_pagos`: el monto real total pagado por el cliente (incluyendo el sobrepago), de modo que `SUM(p_pagos.monto_usd) > SUM(p_ordenes.monto_recaudado)`.

---

### 11.2. Causa Raíz del Problema en el Frontend (`apps/mobile/app/(app)/rendiciones/nueva.tsx`)

En el archivo `apps/mobile/app/(app)/rendiciones/nueva.tsx` existen **dos fallos de lógica de sincronización** que impiden que el excedente llegue a `p_pagos`:

#### Fallo #1: `computeTotal` y `totalCobrarUsd` truncan el monto digitado antes de sincronizar la Forma de Pago
1. Supongamos que una orden tiene `saldo_pendiente = $50.00` y el cliente entrega `$60.00`.
2. Si el usuario entra a **"Abono parcial"** en la tarjeta de la orden y digita `60`, la UI le muestra el aviso (líneas 762–766):
   > `ℹ️ Se amortizan $50.00 y $10.00 quedarán como saldo a favor.`
3. Sin embargo, al escribir en ese input se ejecuta `handleOrderMontoChange` (líneas 313–320), que llama a `computeTotal` (líneas 253–263):
   ```typescript
   // ❌ CÓDIGO ACTUAL CON BUG EN nueva.tsx (líneas 253-263):
   const computeTotal = (
     ordersList: OrdenParaRendicion[],
     sel: Record<string, boolean>,
     m: Record<string, string>,
   ) => {
     return ordersList.reduce((acc, o) => {
       if (!sel[o.id]) return acc;
       const v = Number(String(m[o.id] ?? "0").replace(",", ".")) || 0;
       return acc + montoAplicable(v, Number(o.saldo_pendiente) || 0); // <-- Trunca 60 a 50
     }, 0);
   };
   ```
   Como `montoAplicable(60, 50)` hace `Math.min(60, 50) = 50`, `computeTotal` devuelve **`50`** en lugar de los **`60`** digitados.
4. Inmediatamente después, `handleOrderMontoChange` llama a `syncPaymentWithTotal(nextTotal)`, lo cual **sobreescribe automáticamente la Forma de Pago (Sección 2) con `$50.00`** (o su equivalente en Bs de `$50.00`), **descartando los `$10.00` de saldo a favor**.
5. Si el usuario pulsa **"Llenar restante"** en la forma de pago (`fillRemainingPayment`, líneas 421–439), también calcula el restante usando `totalCobrarUsd` (que también está truncado en `$50.00`).
6. Como resultado, al enviar `submit()`:
   - `p_ordenes` envía `monto_recaudado: 50.00`
   - `p_pagos` envía `monto_usd: 50.00`
   - PostgreSQL recibe `$50.00 == $50.00` y genera **`$0.00` de saldo a favor**.

*(Nota de referencia: En el Dashboard Web `src/app/(dashboard)/rendiciones/nuevo/nueva-rendicion-form.tsx` líneas 312–378 sí se separaron `totalOrdenes` y `totalDigitado`, precargando el pago con `totalDigitado`, pero en `apps/mobile` se usó el monto truncado).*

#### Fallo #2: Seleccionar órdenes pisa el monto de pago si el usuario escribió primero el pago mayor en la Sección 2
- Si el usuario escribe primero el pago recibido en **"2. Formas de pago recibidas"** (ej. `$60.00`) y luego toca **"Cobrar Total ($50.00)"** o **"Cobrar todas"** en la Sección 1, `selectOrderTotal` y `selectAllOrders` invocan `syncPaymentWithTotal(nextTotal)` sin verificar si el usuario ya había ingresado un monto mayor en la forma de pago, **rebajando el pago de `$60.00` a `$50.00`**.

---

### 11.3. Correcciones Exactas que Debe Aplicar el Encargado del Frontend en `apps/mobile/app/(app)/rendiciones/nueva.tsx`

#### 1. Separar `totalAmortizadoUsd` (`totalCobrarUsd`) de `totalDigitadoUsd`
En `apps/mobile/app/(app)/rendiciones/nueva.tsx` (alrededor de las líneas 195–203 y 253–263):

```typescript
  // Total que amortiza las órdenes seleccionadas (tope: saldo_pendiente por orden) -> va a p_ordenes
  const totalCobrarUsd = useMemo(() => {
    return ordenes.reduce((acc, o) => {
      if (!selectedOrders[o.id]) return acc;
      const v = Number(String(montos[o.id] ?? "0").replace(",", ".")) || 0;
      return acc + montoAplicable(v, Number(o.saldo_pendiente) || 0);
    }, 0);
  }, [ordenes, selectedOrders, montos]);

  // Total real digitado en las órdenes (incluyendo cualquier sobrepago digitado) -> sincroniza pagos
  const totalDigitadoUsd = useMemo(() => {
    return ordenes.reduce((acc, o) => {
      if (!selectedOrders[o.id]) return acc;
      const v = Number(String(montos[o.id] ?? "0").replace(",", ".")) || 0;
      return acc + Math.max(0, v);
    }, 0);
  }, [ordenes, selectedOrders, montos]);

  const excedenteDigitadoOrdenesUsd = Math.max(0, totalDigitadoUsd - totalCobrarUsd);
```

Y actualizar `computeTotal` (o renombrarlo a `computeTotalDigitado`) para que sume el monto digitado completo sin recortarlo con `montoAplicable` al sincronizar el input de pago:

```typescript
  const computeTotalDigitado = (
    ordersList: OrdenParaRendicion[],
    sel: Record<string, boolean>,
    m: Record<string, string>,
  ) => {
    return ordersList.reduce((acc, o) => {
      if (!sel[o.id]) return acc;
      const v = Number(String(m[o.id] ?? "0").replace(",", ".")) || 0;
      return acc + Math.max(0, v);
    }, 0);
  };
```

#### 2. Actualizar `fillRemainingPayment` y `addPago` para usar `totalDigitadoUsd`
En `addPago` (línea 399) y `fillRemainingPayment` (línea 431), usar `totalDigitadoUsd` en lugar de `totalCobrarUsd`:

```typescript
  const objetivoPagoUsd = Math.max(totalCobrarUsd, totalDigitadoUsd);
  const restanteUsd = Math.max(0, objetivoPagoUsd - otrosPagosUsd);
```

#### 3. Evitar que `selectOrderTotal` / `selectAllOrders` rebajen un pago mayor ya ingresado manualmente
En `syncPaymentWithTotal(newTotalUsd: number, preserveHigherPayment = false)`:
- Cuando se llama desde `selectOrderTotal` o `selectAllOrders`, si el pago único actual en USD ya es mayor que `newTotalUsd` (porque el cobrador escribió primero el billete/pago recibido de más en la Sección 2), conservar el monto mayor o permitir solo incrementarlo, mientras que en `handleOrderMontoChange` y `clearAllOrders` se sincroniza directamente con `computeTotalDigitado`.

#### 4. Mostrar claramente en el Resumen y en el Botón de Envío el monto recaudado y el saldo a favor a generar
- En el bloque de **Totalizador** y **Resumen de la cobranza** (líneas 804–820 y 1031–1079), si `excedenteDigitadoOrdenesUsd > 0.009`, mostrar el aviso de excedente.
- En el botón principal **"Registrar Cobranza"** (línea 1096), mostrar el monto real de los pagos (`totalPagosUsd`) en lugar de mostrar únicamente `totalCobrarUsd`, para que el cobrador vea exactamente cuánto dinero total se está registrando en la operación.
- Mantener en `submit()` (líneas 444–453) el envío de `ordenesPayload` con `monto_recaudado: montoAplicable(v, Number(o.saldo_pendiente) || 0)` (tope en el saldo de la factura) mientras `pagos` envía el monto total recibido. Así PostgreSQL recibirá `v_total_pagos > v_total_ordenes` y sumará automáticamente la diferencia en `clientes.saldo_favor`.



---

## 12. ESPECIFICACIÓN BACKEND Y DIRECTIVA PARA FRONTEND (WEB Y APK): Configuración de Días de Visita y Reversión de Entrega en Despacho (03/11/2026)

> [!IMPORTANT]
> **PARTE BACKEND IMPLEMENTADA EN SUPABASE (`20261103124500_dias_visita_clientes_y_reversar_entrega_od.sql`):**
> A continuación se detalla el contrato de base de datos, las nuevas columnas, los RPCs creados/actualizados y la **guía exacta de implementación** que debe ejecutar el encargado de **Frontend Web (`src/`)** y **Frontend APK (`apps/mobile/`)** para completar las Tareas 1 y 2 de `docs/task_20261103a.md`.

---

### 12.1. TAREA 1: Configuración de Días de Visita en Clientes y Filtro en `Visita / Cartera` (APK)

#### A. Cambios en Base de Datos (`public.clientes` y RPC `retorna_ordenes_por_liquidar`)

1. **Nuevas columnas en `public.clientes`:**
   - `dias_visita TEXT[] NOT NULL DEFAULT '{}'::TEXT[]`
     - Valores permitidos (máximo **2 días**): `'lunes'`, `'martes'`, `'miercoles'`, `'jueves'`, `'viernes'`, `'sabado'`, `'domingo'`.
     - Restricciones en BD:
       - `clientes_dias_visita_max_check`: `COALESCE(array_length(dias_visita, 1), 0) <= 2`
       - `clientes_dias_visita_valores_check`: valida que solo contenga nombres de días válidos en minúsculas sin tilde.
   - `visita_cualquier_dia BOOLEAN NOT NULL DEFAULT TRUE`
     - `TRUE`: El cliente puede ser visitado cualquier día de la semana (valor por defecto para clientes existentes o cuando `dias_visita` está vacío).
     - `FALSE`: El cliente solo se atiende en los días definidos en `dias_visita` (1 o 2 días).
   - **Trigger automático `trg_clientes_normalizar_dias_visita`:**
     - Normaliza automáticamente a minúsculas sin tilde (`Miércoles` $\rightarrow$ `miercoles`, `Sábado` $\rightarrow$ `sabado`), elimina duplicados y garantiza que si `dias_visita` queda vacío (`'{}'`), `visita_cualquier_dia` pase automáticamente a `TRUE`.

2. **Actualización del RPC `public.retorna_ordenes_por_liquidar()`:**
   - Ahora incluye en la raíz del JSON el campo `'dia_actual'` (ej. `'martes'`) y dentro de cada ítem de `data[]` los campos del cliente:
     ```json
     {
       "success": true,
       "dia_actual": "martes",
       "data": [
         {
           "cliente_id": "uuid",
           "razon_social": "Comercial Ejemplo C.A.",
           "rif_nit": "J-12345678-9",
           "vendedor_id": "uuid",
           "dias_visita": ["martes", "viernes"],
           "visita_cualquier_dia": false,
           "dias_vencidos": 5,
           "cant_ordenes": 2,
           "monto_por_liquidar": 120.50
         }
       ],
       "error": null
     }
     ```

---

#### B. Tareas a Realizar por el Encargado de Frontend Web (`src/`) — Tarea 1

1. **Actualizar Tipos (`src/types/database.ts`):**
   - En `Database["public"]["Tables"]["clientes"]` (`Row`, `Insert`, `Update`), agregar:
     ```typescript
     dias_visita: string[];
     visita_cualquier_dia: boolean;
     ```
2. **Actualizar Server Actions de Clientes (`src/lib/actions/clientes.ts`):**
   - Leer del `FormData` (o payload) `visita_cualquier_dia` (`boolean`) y `dias_visita` (`string[]`, máximo 2 valores entre `['lunes','martes','miercoles','jueves','viernes','sabado','domingo']`).
   - Si `visita_cualquier_dia === true`, enviar `dias_visita: []` y `visita_cualquier_dia: true`.
   - Si `visita_cualquier_dia === false`, validar que haya **1 o 2 días** seleccionados (si hay 0, mostrar error de validación o marcar `visita_cualquier_dia: true`).
3. **Actualizar Formularios Web de Creación y Edición de Clientes:**
   - Archivos:
     - `src/app/(dashboard)/clientes/nuevo/nuevo-cliente-form.tsx`
     - `src/app/(dashboard)/clientes/[id]/cliente-editar-form.tsx`
     - `src/app/(dashboard)/clientes/[id]/page.tsx` (incluir `dias_visita, visita_cualquier_dia` en el `SELECT` del cliente).
   - **Comportamiento UI requerido:**
     - Añadir sección **"Días de visita"**:
       - Checkbox / Switch: **"Cualquier día" (`visita_cualquier_dia`)**.
       - Botones/chips o checkboxes para los 7 días (`Lunes`, `Martes`, `Miércoles`, `Jueves`, `Viernes`, `Sábado`, `Domingo`) con valores internos `['lunes','martes','miercoles','jueves','viernes','sabado','domingo']`.
       - Si el usuario marca **"Cualquier día"**, se desmarcan/deshabilitan los días específicos.
       - Si desmarca **"Cualquier día"** (o toca directamente un día), puede elegir **hasta un máximo de 2 días** (al tener 2 seleccionados, los 5 restantes quedan deshabilitados hasta que desmarque uno).

---

#### C. Tareas a Realizar por el Encargado de Frontend APK (`apps/mobile/`) — Tarea 1

1. **Actualizar Servicio de Clientes (`apps/mobile/lib/clientes.ts`) y Rendiciones (`apps/mobile/lib/rendiciones.ts`):**
   - En `ClienteListaItem` y `ClienteVisita` (`apps/mobile/lib/clientes.ts`), añadir:
     ```typescript
     dias_visita?: string[] | null;
     visita_cualquier_dia?: boolean | null;
     ```
   - En `listClientesForProfile`, `buscarClientesForProfile` y `getClienteVisita`, incluir `dias_visita, visita_cualquier_dia` en el `.select(...)` de `supabase.from("clientes")`.
   - En `OrdenPorLiquidarCliente` (`apps/mobile/lib/rendiciones.ts`), mapear `dias_visita` (`string[]`) y `visita_cualquier_dia` (`boolean`) provenientes de `retorna_ordenes_por_liquidar`.
2. **Formularios Móviles de Creación/Edición de Cliente:**
   - Archivos:
     - `apps/mobile/app/(app)/clientes/nuevo.tsx`
     - `apps/mobile/app/(app)/clientes/[id]/editar.tsx`
   - Agregar el selector de **"Días de visita"** con la opción **"Cualquier día"** o selección de **máximo 2 días de la semana**, enviando `dias_visita` y `visita_cualquier_dia` en el `insert` / `update` de `public.clientes`.
3. **Filtro Automático por Día Actual en la Vista `Visita / Cartera` (`apps/mobile/app/(app)/visita/index.tsx`):**
   - Obtener el día actual del sistema en formato canónico:
     ```typescript
     const DIAS_SEMANA = [
       "domingo",
       "lunes",
       "martes",
       "miercoles",
       "jueves",
       "viernes",
       "sabado",
     ] as const;
     const diaActual = DIAS_SEMANA[new Date().getDay()];

     function correspondeVisitaHoy(c: {
       visita_cualquier_dia?: boolean | null;
       dias_visita?: string[] | null;
     }): boolean {
       const dias = Array.isArray(c.dias_visita) ? c.dias_visita : [];
       if (c.visita_cualquier_dia === true || dias.length === 0) return true;
       return dias.includes(diaActual);
     }
     ```
   - Aplicar `correspondeVisitaHoy(...)` tanto en `carteraFiltered` (pestaña **"Cartera"**) como en `todosFiltered` (pestaña **"Todos"** dentro de `Visita / Cartera`), de modo que la vista `Visita / Cartera` muestre exclusivamente:
     1. Clientes cuyo día programado en `dias_visita` coincida con el día actual (`diaActual`).
     2. Clientes configurados con `visita_cualquier_dia = true` (o sin días específicos).

---

### 12.2. TAREA 2: Reversión de Entrega en Despacho sin Anular la Orden

#### A. Nuevo RPC en Base de Datos: `public.reversar_entrega_orden_distribucion`

- **Firma:**
  ```sql
  public.reversar_entrega_orden_distribucion(
      p_orden_id UUID,
      p_motivo TEXT DEFAULT NULL
  ) RETURNS JSONB
  ```
- **Reglas de Negocio y Comportamiento Transaccional:**
  1. **Validaciones de bloqueo:**
     - Rechaza si el usuario no está autenticado (`NO_AUTENTICADO`).
     - Rechaza si la orden es un saldo inicial CxC (`ORDEN_SALDO_INICIAL`).
     - Rechaza si la orden **no** está en un estado de entrega procesada (`por_liquidar`, `despachada` o `devuelta`) $\rightarrow$ código `ESTADO_INVALIDO`.
     - Rechaza si la orden tiene una **rendición de cuentas activa** (`rc.estado <> 'reversada'`) $\rightarrow$ código `ORDEN_CON_RENDICION`.
     - Rechaza si la orden pertenece a un **Radar que ya fue aprobado/cerrado por Gerencia** (`radars.status_radar = TRUE`) $\rightarrow$ código `RADAR_APROBADO_BLOQUEADO`.
  2. **Reversión de Estado e Inventario según el Origen de la Orden (SIN anular la orden):**
     | Origen detectado (`data.origen_orden`) | Condición en `ordenes_distribucion` | Nuevo estado (`data.estado_nuevo`) | Reversión de Inventario y Líneas (`detalle_distribucion`) |
     | :--- | :--- | :--- | :--- |
     | **`VENTA_DIRECTA_ALMACEN`** | `origen_venta = 'ALMACEN'` | `'aprobada'` | Suma `cantidad_despachada` de vuelta a `inventario_almacen.stock_disponible`. Pone `cantidad_despachada = 0`, `estado_entrega = 'pendiente'`, `motivo_rechazo = NULL`, `contenedores_retirados = 0`. |
     | **`AUTOVENTA`** | `es_autoventa = TRUE` | `'en_transito'` | Resta `cantidad_despachada` de `inventario_movil.cantidad_entregada` (y `cantidad_devolucion` si aplica) en el camión asignado (`camion_id`). Pone `cantidad_despachada = cantidad_solicitada`, `estado_entrega = 'pendiente'`, `motivo_rechazo = NULL`, `contenedores_retirados = 0`. |
     | **`RADAR` / `RUTA`** | `radar_id IS NOT NULL` o ruta normal | `'en_transito'` | Resta de `inventario_movil` (`cantidad_entregada` y `cantidad_devolucion`) lo asentado en la entrega. Pone `cantidad_despachada = cantidad_solicitada`, `estado_entrega = 'pendiente'`, `motivo_rechazo = NULL`, `contenedores_retirados = 0`. |
  3. **Reversión de Contenedores / Envases:**
     - Revierte en `public.saldo_contenedores_clientes` los envases entregados y retirados en esa orden (`saldo_pendiente - total_entregados + total_retirados`) y limpia las filas de `public.movimientos_contenedores WHERE orden_id = p_orden_id`.
  4. **Auditoría en `public.logs_auditoria`:**
     - Inserta un registro con `tabla_afectada = 'ordenes_distribucion'`, `accion = 'REVERSAR_ENTREGA'`, `usuario_id = auth.uid()`, `registro_id = p_orden_id`, `valores_anteriores` (snapshot completo de orden, líneas y contenedores previos) y `valores_nuevos` (nuevo estado, origen detectado, motivo y timestamp).
- **Respuesta JSON exitosa:**
  ```json
  {
    "success": true,
    "message": "Entrega reversada exitosamente. La orden regresó a estado en_transito y la mercancía fue devuelta al inventario correspondiente.",
    "data": {
      "orden_id": "uuid-de-la-orden",
      "correlativo": 1045,
      "origen_orden": "RADAR",
      "estado_anterior": "por_liquidar",
      "estado_nuevo": "en_transito"
    },
    "error": null
  }
  ```

#### B. Actualización en RPCs de Consulta de Radar (`retorna_radar_despachador` y `retorna_ordenes_distribucion_segun_idradar`)

- **`public.retorna_radar_despachador()`:**
  - Ahora retorna tanto las paradas en `'en_transito'` / `'despachada'` como las paradas ya entregadas (`'por_liquidar'`, `'devuelta'`) cuyo Radar siga activo/abierto (`radars.status_radar = FALSE`).
  - Así, cuando el despachador termina una entrega en el Radar, la tarjeta de la parada permanece visible con badge **"Completado"** o **"Devuelta"** y permite mostrar el botón **"Reversar Entrega"** al lado de la parada procesada.
- **`public.retorna_ordenes_distribucion_segun_idradar(p_radar_id)`:**
  - Ahora incluye el campo `'estado'` de la orden en cada ítem de `data[]`.

---

#### C. Tareas a Realizar por el Encargado de Frontend Web (`src/`) — Tarea 2

1. **Agregar Tipado y Server Action:**
   - En `src/types/database.ts`, declarar la firma de `reversar_entrega_orden_distribucion`:
     ```typescript
     reversar_entrega_orden_distribucion: {
       Args: { p_orden_id: string; p_motivo?: string | null };
       Returns: Json;
     };
     ```
   - En `src/lib/actions/ordenes.ts` (o `src/lib/actions/radar.ts`), crear `reversarEntregaOrdenAction(ordenId: string, motivo?: string)` que invoque `supabase.rpc("reversar_entrega_orden_distribucion", { p_orden_id: ordenId, p_motivo: motivo ?? null })` y haga `revalidatePath("/ordenes")`, `revalidatePath(\`/ordenes/\${ordenId}\`)` y `revalidatePath("/radar")`.
2. **Añadir Botón "Reversar Entrega" en Vista de Detalle de Orden y Radar Web:**
   - **En `src/app/(dashboard)/ordenes/[id]/orden-estado-actions.tsx` (o `page.tsx`):**
     - Cuando `estadoActual` sea `'por_liquidar'`, `'despachada'` o `'devuelta'` (y no sea `es_saldo_inicial`), mostrar el botón **"Reversar Entrega"** (con modal de confirmación e input opcional para el motivo, similar al modal de anulación pero aclarando que **la orden NO se anulará**, sino que regresará a `'en_transito'` o `'aprobada'` y devolverá la mercancía al inventario).
   - **En `src/app/(dashboard)/radar/radar-paradas-despachador.tsx` y `src/app/(dashboard)/radar/radar-paradas-view.tsx`:**
     - En las paradas cuya entrega ya fue procesada (`!pendientes` o `orden.estado` en `['por_liquidar', 'despachada', 'devuelta']` mientras el radar no esté aprobado), mostrar el botón **"Reversar Entrega"** junto a las acciones de la parada.

---

#### D. Tareas a Realizar por el Encargado de Frontend APK (`apps/mobile/`) — Tarea 2

1. **Agregar Función Cliente en `apps/mobile/lib/ordenes.ts`:**
   ```typescript
   export async function reversarEntregaOrdenDistribucion(
     ordenId: string,
     motivo?: string,
   ): Promise<
     | { ok: true; estadoNuevo: string; origenOrden: string; message: string }
     | { ok: false; error: string }
   > {
     const { data, error } = await supabase.rpc(
       "reversar_entrega_orden_distribucion",
       {
         p_orden_id: ordenId,
         p_motivo: motivo?.trim() ? motivo.trim() : null,
       },
     );
     if (error) return { ok: false, error: error.message };
     const env = data as RpcEnvelope<{
       orden_id?: string;
       estado_nuevo?: string;
       origen_orden?: string;
     }> | null;
     if (!env || env.success === false) {
       return {
         ok: false,
         error:
           env?.message ??
           env?.error?.message ??
           "No se pudo reversar la entrega de la orden.",
       };
     }
     return {
       ok: true,
       estadoNuevo: env.data?.estado_nuevo ?? "",
       origenOrden: env.data?.origen_orden ?? "",
       message: env.message ?? "Entrega reversada exitosamente.",
     };
   }
   ```
2. **Añadir Botón "Reversar Entrega" en el Detalle de la Orden (`apps/mobile/src/features/ordenes/screens/OrdenDetalleScreen.tsx`):**
   - Cuando `orden.estado` sea `'por_liquidar'`, `'despachada'` o `'devuelta'`, agregar en la `BottomActionBar` (o en la tarjeta de acciones de entrega) la acción **"Reversar Entrega"** (ícono `refresh-outline` o `arrow-undo-outline`).
   - Al pulsar, mostrar `Alert.alert("¿Reversar Entrega?", "La orden NO será anulada: regresará a En Tránsito o Aprobada según su origen y los productos volverán al inventario móvil o almacén.", ...)` y ejecutar `reversarEntregaOrdenDistribucion(orden.id)`.
3. **Añadir Botón "Reversar Entrega" en la Pantalla de Despacho / Radar (`apps/mobile/app/(app)/radar/index.tsx`):**
   - En cada tarjeta de parada (`renderItem`), cuando `!pendientes` (es decir, la entrega ya fue procesada y aparece como `"Completado"` o `"Devuelta"`), mostrar al lado del botón `"Imprimir"` el botón **"Reversar Entrega"**, que confirme y llame a `reversarEntregaOrdenDistribucion(item.orden_id)` y recargue la lista (`void load()`).


---

### 12.3. TAREA 3 (APK): Edición Directa por Teclado de la Cantidad de Productos en Órdenes

> **Contexto para el Agente Frontend (`apps/mobile`):**
> Actualmente, en las pantallas de creación y edición de órdenes de la APK, cada línea de producto solo permite cambiar la cantidad pulsando los botones `−` y `+` (con un `<Text style={styles.qty}>{item.cantidad}</Text>` estático en el centro). Cuando un vendedor pide 50 o 100 unidades de un SKU, pulsar `+` cien veces es inviable.

#### Archivos que Deben Modificarse en `apps/mobile`:
1. `apps/mobile/app/(app)/ordenes/nueva.tsx` (alrededor de las líneas **410–427**)
2. `apps/mobile/app/(app)/ordenes/editar/[id].tsx` (sección de líneas de productos `qtyRow`)
3. `apps/mobile/app/(app)/ordenes/venta-directa.tsx` (sección de líneas de productos `qtyRow`)
4. `apps/mobile/app/(app)/autoventas/nueva.tsx` (sección de líneas de productos `qtyRow`)

#### Implementación Técnica Exacta:
Reemplazar el `<Text style={styles.qty}>{item.cantidad}</Text>` por un `<TextInput>` numérico editable entre los botones `−` y `+`:

```tsx
<View style={styles.qtyRow}>
  <Pressable
    style={styles.qtyBtn}
    onPress={() => updateCantidad(item.producto_id, item.cantidad - 1)}
  >
    <Text style={styles.qtyBtnText}>−</Text>
  </Pressable>

  <TextInput
    style={styles.qtyInput}
    keyboardType="number-pad"
    selectTextOnFocus
    value={String(item.cantidad)}
    onChangeText={(txt) => {
      const digits = txt.replace(/[^0-9]/g, "");
      if (!digits) {
        // Permitir edición temporal o fijar mínimo 1 al perder foco
        updateCantidad(item.producto_id, 1);
        return;
      }
      const parsed = parseInt(digits, 10);
      if (Number.isFinite(parsed) && parsed > 0) {
        updateCantidad(item.producto_id, parsed);
      }
    }}
  />

  <Pressable
    style={styles.qtyBtn}
    onPress={() => updateCantidad(item.producto_id, item.cantidad + 1)}
  >
    <Text style={styles.qtyBtnText}>+</Text>
  </Pressable>

  <Text style={styles.lineTotal}>
    ${formatMoney(item.cantidad * item.precio)}
  </Text>
</View>
```
- **Estilo recomendado para `qtyInput`:**
  ```ts
  qtyInput: {
    minWidth: 56,
    height: 36,
    borderWidth: 1,
    borderColor: "#CBD5E1",
    borderRadius: 8,
    backgroundColor: "#FFFFFF",
    textAlign: "center",
    fontSize: 16,
    fontWeight: "700",
    color: "#0F172A",
    paddingHorizontal: 8,
    paddingVertical: 4,
  }
  ```
- **Nota de UX:** Si el usuario borra temporalmente todos los dígitos mientras escribe un número nuevo (ej. borra `1` para escribir `25`), manejar un estado local de texto o permitir string vacío mientras tiene el foco y al `onBlur` asegurar `Math.max(1, cantidad)` (y en Venta Directa / Auto-Venta validar que no supere `stock_disponible` si aplica).

---

### 12.4. TAREA 4 (APK): Impresión de Órdenes en Impresoras Wi-Fi desde el Radar

> **Contexto para el Agente Frontend (`apps/mobile`):**
> Actualmente, el botón `"Imprimir"` en `apps/mobile/app/(app)/radar/index.tsx` (líneas 48–74) y en `OrdenDetalleScreen.tsx` invoca exclusivamente `imprimirTicketOrden(ordenId)` de `apps/mobile/lib/print-orden.ts`, el cual solo envía comandos ESC/POS por **Bluetooth clásico** (`react-native-bluetooth-classic`).
> Los **vendedores** (y usuarios en oficina/almacén) necesitan poder imprimir las órdenes desde el **Radar** hacia **impresoras conectadas por Wi-Fi / Red local**.

#### Implementación Técnica Exacta:

1. **Dependencia Expo (`expo-print`):**
   - Instalar en `apps/mobile` usando `npx expo install expo-print` (compatible con el runtime nativo de Expo SDK 57).
2. **Agregar Generador HTML e Impresión Wi-Fi en `apps/mobile/lib/print-orden.ts`:**
   - Crear la función `buildHtmlForOrden(orden: OrdenDetalle): Promise<string>` que construya el documento HTML limpio de la orden (encabezado de la empresa actual, correlativo `#orden.correlativo`, factura origen, fecha, datos del cliente, RIF, dirección, tabla de productos con código, descripción, cantidad, precio unitario, subtotal, total en USD y tabla de estado de cuenta de envases/vacíos).
   - Crear la función exportada `imprimirOrdenWifi(ordenOId: string | OrdenDetalle)`:
     ```typescript
     import * as Print from "expo-print";

     export async function imprimirOrdenWifi(
       ordenOId: string | OrdenDetalle,
     ): Promise<{ ok: true } | { ok: false; error: string }> {
       try {
         let orden: OrdenDetalle;
         if (typeof ordenOId === "string") {
           const res = await getOrdenDetalle(ordenOId);
           if (!res.ok) return { ok: false, error: res.error };
           orden = res.orden;
         } else {
           orden = ordenOId;
         }
         const html = await buildHtmlForOrden(orden);
         await Print.printAsync({ html });
         return { ok: true };
       } catch (err) {
         const msg = err instanceof Error ? err.message : String(err);
         // Si el usuario cancela el diálogo nativo de impresión, no tratarlo como fallo crítico
         if (msg.toLowerCase().includes("cancel") || msg.toLowerCase().includes("did not complete")) {
           return { ok: true };
         }
         return { ok: false, error: msg || "No se pudo imprimir por Wi-Fi." };
       }
     }
     ```
3. **Actualizar `apps/mobile/app/(app)/radar/index.tsx` y `apps/mobile/src/features/ordenes/screens/OrdenDetalleScreen.tsx`:**
   - En `radar/index.tsx` (`onImprimirOrden`):
     - Si el usuario tiene rol `vendedor` (o al tocar **"Imprimir"** en una parada del Radar), mostrar un selector rápido (`Alert.alert("Imprimir Orden", "Selecciona el método de impresión:", ...)`) con dos opciones:
       1. **🖨️ Impresora Wi-Fi / Red** $\rightarrow$ ejecuta `await imprimirOrdenWifi(ordenId)` (abre el spooler nativo de Android que detecta todas las impresoras Wi-Fi de la red).
       2. **🔵 Impresora Térmica Bluetooth** $\rightarrow$ ejecuta `await imprimirTicketOrden(ordenId)`.
     - Hacer lo mismo en `OrdenDetalleScreen.tsx` para que desde el detalle de cualquier orden también se pueda imprimir tanto por **Wi-Fi** como por **Bluetooth**.

---

### 12.5. TAREA 5 (APK): Cobranzas — Subir Capture (Galería), Tomar Foto (Cámara) y Separador de Miles en Montos

#### A. Subir Capture y Tomar Foto del Comprobante en Cobranzas (`apps/mobile/app/(app)/rendiciones/nueva.tsx`)

> **Contrato Backend en Supabase (YA ACTIVO):**
> - **Bucket de Storage:** `rendiciones-captures` (público para lectura, permite `INSERT`/`UPDATE` a usuarios `authenticated` hasta 10 MB; soporta `image/jpeg`, `image/png`, `image/webp`).
> - **Campo en el RPC `public.registrar_rendicion_cuentas`:** Cada objeto dentro del array `p_pagos` recibe la propiedad `"capture_url": "https://.../storage/v1/object/public/rendiciones-captures/..."` y la guarda en `public.detalle_formas_pago.capture_url`.

1. **Dependencia Expo (`expo-image-picker`):**
   - Instalar en `apps/mobile` con `npx expo install expo-image-picker`.
2. **Función de Subida a Supabase Storage (`apps/mobile/lib/rendiciones.ts`):**
   - Añadir helper `uploadCaptureRendicionMobile(uri: string, userId: string)`:
     ```typescript
     export async function uploadCaptureRendicionMobile(
       localUri: string,
       userId: string,
     ): Promise<{ ok: true; url: string } | { ok: false; error: string }> {
       try {
         const ext = localUri.split(".").pop()?.toLowerCase() || "jpg";
         const cleanExt = ["jpg", "jpeg", "png", "webp"].includes(ext) ? ext : "jpg";
         const contentType = cleanExt === "png" ? "image/png" : cleanExt === "webp" ? "image/webp" : "image/jpeg";
         const filePath = `${userId}/${Date.now()}-${Math.random().toString(36).slice(2, 7)}.${cleanExt}`;

         const response = await fetch(localUri);
         const arrayBuffer = await response.arrayBuffer();

         const { error } = await supabase.storage
           .from("rendiciones-captures")
           .upload(filePath, arrayBuffer, {
             contentType,
             cacheControl: "3600",
             upsert: false,
           });

         if (error) return { ok: false, error: error.message };

         const { data } = supabase.storage
           .from("rendiciones-captures")
           .getPublicUrl(filePath);

         return { ok: true, url: data.publicUrl };
       } catch (e) {
         return {
           ok: false,
           error: e instanceof Error ? e.message : "Error subiendo imagen del comprobante.",
         };
       }
     }
     ```
3. **Interfaz en cada Forma de Pago (`apps/mobile/app/(app)/rendiciones/nueva.tsx`):**
   - En el estado de cada línea de pago (`PagoLine`), agregar:
     - `capture_url?: string | null` (URL pública en Supabase Storage)
     - `capture_local_uri?: string | null` (URI local para preview inmediato)
     - `uploadingCapture?: boolean`
   - Debajo de los campos de la forma de pago, añadir la sección **"Comprobante / Capture de pago"** con dos botones claros:
     - **📷 Tomar foto**: solicita permiso con `ImagePicker.requestCameraPermissionsAsync()` y abre `ImagePicker.launchCameraAsync({ mediaTypes: ["images"], quality: 0.75 })`.
     - **🖼️ Subir capture (Galería)**: abre `ImagePicker.launchImageLibraryAsync({ mediaTypes: ["images"], quality: 0.75 })`.
   - Al obtener la imagen, subirla con `uploadCaptureRendicionMobile(asset.uri, profile.id)`, mostrar miniatura (`<Image source={{ uri }} />`) con botón de eliminar (`✕`), y enviar `capture_url: p.capture_url ?? null` dentro de cada elemento de `p_pagos` al llamar a `registrarRendicionCuentas`.
   - En la vista de detalle de rendición (`apps/mobile/app/(app)/rendiciones/[id].tsx`), si un pago tiene `capture_url`, mostrar miniatura o botón **"Ver comprobante"** para abrir la imagen.

---

#### B. Separador de Miles en los Montos (`apps/mobile/app/(app)/rendiciones/nueva.tsx` y `apps/mobile/lib/format.ts`)

> **Problema actual en `apps/mobile/app/(app)/rendiciones/nueva.tsx`:**
> 1. Varios estados y helpers (`selectOrderTotal`, `syncPaymentWithTotal`, `fillRemainingPayment`, `addPago`) asignan a los inputs valores con `.toFixed(2)` (ej. `"12500.50"` sin separador de miles).
> 2. Cuando el usuario escribe montos altos en Bolívares o USD en los `<TextInput>` de abono por orden o de monto de pago (ej. `1540000,50`), el número se muestra corrido sin separadores de miles (`1540000.50`), dificultando su lectura y causando errores de digitación.

#### Implementación Técnica Exacta:
1. **Crear helpers de formateo y parseo de inputs monetarios en `apps/mobile/lib/format.ts`:**
   ```typescript
   /**
    * Convierte cualquier string monetario (con puntos de miles y coma decimal,
    * o formato estándar con punto decimal) en un número flotante confiable.
    */
   export function parseMoneyInput(raw: string | number | null | undefined): number {
     if (typeof raw === "number") return Number.isFinite(raw) ? raw : 0;
     if (!raw) return 0;
     const s = String(raw).trim();
     if (!s) return 0;
     // Si contiene coma decimal (formato es-VE: "1.234,56"), quitar puntos de miles y cambiar coma por punto
     if (s.includes(",")) {
       const normalized = s.replace(/\./g, "").replace(",", ".");
       const n = Number(normalized);
       return Number.isFinite(n) ? n : 0;
     }
     // Si tiene múltiples puntos (ej. "1.234.567"), son separadores de miles
     const parts = s.split(".");
     if (parts.length > 2) {
       const n = Number(parts.join(""));
       return Number.isFinite(n) ? n : 0;
     }
     const n = Number(s);
     return Number.isFinite(n) ? n : 0;
   }

   /**
    * Formatea en vivo el texto de un TextInput monetario con separador de miles (.)
    * y coma decimal (,) para que el usuario vea "1.250,50" mientras escribe.
    */
   export function formatMoneyInputLive(raw: string): string {
     // Permitir dígitos y una coma o punto como separador decimal al escribir
     const cleaned = raw.replace(/[^0-9.,]/g, "");
     if (!cleaned) return "";

     // Detectar el último separador como decimal si el usuario está escribiendo decimales
     const lastComma = cleaned.lastIndexOf(",");
     const lastDot = cleaned.lastIndexOf(".");
     let intPart = cleaned;
     let decPart: string | null = null;

     if (lastComma !== -1 && lastComma > lastDot) {
       intPart = cleaned.slice(0, lastComma).replace(/[.,]/g, "");
       decPart = cleaned.slice(lastComma + 1).replace(/[.,]/g, "").slice(0, 2);
     } else if (lastDot !== -1 && cleaned.length - lastDot - 1 <= 2 && cleaned.indexOf(".") === lastDot) {
       // Un único punto con 0-2 dígitos detrás se trata como decimal
       intPart = cleaned.slice(0, lastDot).replace(/[.,]/g, "");
       decPart = cleaned.slice(lastDot + 1).replace(/[.,]/g, "").slice(0, 2);
     } else {
       intPart = cleaned.replace(/[.,]/g, "");
     }

     // Quitar ceros a la izquierda innecesarios (dejando al menos un "0" si hay decimales)
     intPart = intPart.replace(/^0+(?=\d)/, "");
     if (!intPart && decPart !== null) intPart = "0";

     const intFormatted = intPart.replace(/\B(?=(\d{3})+(?!\d))/g, ".");
     return decPart !== null ? `${intFormatted},${decPart}` : intFormatted;
   }

   /**
    * Formatea un número fijo (ej. al autocompletar un pago) como "1.250,50".
    */
   export function numberToMoneyInput(n: number): string {
     if (!Number.isFinite(n) || n <= 0) return "";
     const [intPart, decPart] = n.toFixed(2).split(".");
     const intFormatted = intPart.replace(/\B(?=(\d{3})+(?!\d))/g, ".");
     return `${intFormatted},${decPart}`;
   }
   ```
2. **Aplicar en `apps/mobile/app/(app)/rendiciones/nueva.tsx`:**
   - Reemplazar todos los `.toFixed(2)` que llenan el estado de los inputs (`selectOrderTotal`, `selectAllOrders`, `syncPaymentWithTotal`, `fillRemainingPayment`, `addPago`) por `numberToMoneyInput(...)`.
   - Reemplazar todos los `Number(String(...).replace(",", "."))` por `parseMoneyInput(...)`.
   - En el `onChangeText` del input de **abono parcial por orden** y del input de **monto de cada forma de pago**, aplicar `formatMoneyInputLive(v)` para que mientras el usuario digita vea el separador de miles en tiempo real (ej. `12.500,00`).

---

### 12.6. Resumen Ejecutivo de Tareas para el Agente Frontend (Checklist)

| # | Módulo / Plataforma | Tarea a Ejecutar por el Agente Frontend | Estado Backend (Supabase) |
| :-: | :--- | :--- | :--- |
| **1** | **Web + APK** (`clientes` y `visita/index.tsx`) | Selector de **Días de visita** (máx. 2 días o `"Cualquier día"`) en formularios de cliente y filtro automático por día actual en la vista **Visita / Cartera** de la APK. | ✅ **Listo en BD** (`clientes.dias_visita`, `clientes.visita_cualquier_dia`, `retorna_ordenes_por_liquidar`) |
| **2** | **Web + APK** (`ordenes/[id]` y `radar`) | Botón **"Reversar Entrega"** junto a las entregas procesadas que invoque el RPC `reversar_entrega_orden_distribucion` (regresa a `'en_transito'` o `'aprobada'` sin anular la orden). | ✅ **Listo en BD** (`reversar_entrega_orden_distribucion`, `logs_auditoria`, `retorna_radar_despachador`) |
| **3** | **APK** (`ordenes/nueva`, `editar`, `venta-directa`, `autoventas`) | Permitir **editar con teclado numérico** (`TextInput`) la cantidad de productos en las líneas de la orden, además de los botones `−` y `+`. | ✅ No requiere cambios adicionales en BD |
| **4** | **APK** (`radar/index.tsx`, `lib/print-orden.ts`) | Permitir a los vendedores **imprimir en impresoras Wi-Fi** desde el Radar (y detalle de orden) mediante `expo-print` (`Print.printAsync`). | ✅ No requiere cambios adicionales en BD |
| **5** | **APK** (`rendiciones/nueva.tsx`, `lib/format.ts`) | En Cobranzas: **1)** Botones para **Subir capture (Galería)** y **Tomar foto (Cámara)** hacia el bucket `rendiciones-captures` (`capture_url`), **2)** **Separador de miles** en vivo en los inputs de montos (`formatMoneyInputLive` / `parseMoneyInput`), y **3)** Corrección de saldo a favor de la **Sección 11**. | ✅ **Listo en BD** (Bucket `rendiciones-captures` y `capture_url` en `registrar_rendicion_cuentas`) |
| **6** | **APK + Web** (`contenedores`) | **Módulo de Retiro de Contenedores a Clientes sin Orden de Distribución** usando el nuevo RPC `registrar_movimiento_contenedores_a_clientes` (**PRIORIDAD CRÍTICA: debe quedar 100% activo y operativo en la APK**). | ✅ **Listo en BD** (`registrar_movimiento_contenedores_a_clientes` y actualización de `retorna_movimientos_contenedores_segun_cliente_id_rango_fechas`) |

---

## 13. Módulo de Retiro / Movimiento de Contenedores a Clientes sin Orden de Distribución (`registrar_movimiento_contenedores_a_clientes`) — Web y APK

> **🚨 ÉNFASIS CRÍTICO PARA EL ENCARGADO DE FRONTEND (ESPECIALMENTE EN LA APP MÓVIL / APK):**
> Este módulo **DEBE QUEDAR ACTIVO, VISIBLE Y TOTALMENTE OPERATIVO EN LA APK (`apps/mobile`)** además de la aplicación Web (`src/`).
> En campo, los choferes, despachadores, vendedores, cobradores y gerentes necesitan poder **retirar envases/contenedores vacíos a cualquier cliente sin necesidad de crear una Orden de Distribución**.
> Por ello, en la APK no basta con la vista de solo lectura actual (`/(app)/contenedores`): **es obligatorio habilitar la pantalla y botones de "Retirar Contenedores" dentro de `apps/mobile/app/(app)/contenedores/` y dejar el acceso activo en el menú lateral y accesos rápidos de la APK**.

**Parche de Base de Datos asociado:**
- `supabase/tenant_patches/20261104093000_registrar_movimiento_contenedores_a_clientes.sql`
- `supabase/migrations/20261104093000_registrar_movimiento_contenedores_a_clientes.sql`

---

### 13.1. Contrato Backend en Supabase: `public.registrar_movimiento_contenedores_a_clientes`

#### A. Firma SQL de la Función RPC
```sql
public.registrar_movimiento_contenedores_a_clientes(
    p_cliente_id UUID,
    p_movimientos JSONB DEFAULT NULL,
    p_observaciones TEXT DEFAULT NULL,
    p_creado_por UUID DEFAULT NULL,
    p_items JSONB DEFAULT NULL,
    p_usuario_id UUID DEFAULT NULL
) RETURNS JSONB
```

#### B. Parámetros de Entrada
| Parámetro | Tipo | Obligatorio | Descripción |
| :--- | :--- | :-: | :--- |
| `p_cliente_id` | `UUID` | **Sí** | ID del cliente (`public.clientes.id`) al que se le retiran (o ajustan) los contenedores. |
| `p_movimientos` | `JSONB` | **Sí** | Lista (array JSON) de movimientos por tipo de contenedor. También soporta recibir un objeto JSON único. |
| `p_observaciones` | `TEXT` | No | Nota u observación del retiro (ej. `"Retiro de vacíos en visita sin pedido"`). Se guarda en `public.movimientos_contenedores.observaciones`. |
| `p_creado_por` | `UUID` | No | ID del usuario que registra el movimiento. Si se omite (`NULL`), la función toma automáticamente `auth.uid()`. |

#### C. Estructura de `p_movimientos` (Payload JSONB)
Cada elemento del arreglo `p_movimientos` admite los siguientes campos:
```json
[
  {
    "contenedor_id": "uuid-del-tipo-contenedor",
    "cantidad_retirada": 10,
    "cantidad_entregada": 0
  }
]
```
- `contenedor_id` (`UUID`, obligatorio): ID existente en `public.tipos_contenedores`.
- `cantidad_retirada` (`INT >= 0`): Cantidad de envases retirados al cliente (también acepta los alias `"retirados"` o `"cantidad"`).
- `cantidad_entregada` (`INT >= 0`, opcional, por defecto `0`): Cantidad de envases entregados al cliente en caso de ajuste manual (también acepta el alias `"entregados"`).
- **Regla de saldo:** Calcula `saldo_actual = saldo_anterior + entregados - retirados` y actualiza `public.saldo_contenedores_clientes`. Permite saldos negativos (`< 0`, saldo a favor del cliente) si el cliente entrega más envases de los que tenía pendientes.
- **Sin Orden de Distribución:** Inserta en `public.movimientos_contenedores` con `orden_id = NULL`, `saldo_anterior`, `saldo_actual` y `observaciones`.

#### D. Estructura de Respuesta JSON (Contrato)
```json
{
  "success": true,
  "message": "Movimiento de contenedores registrado exitosamente.",
  "data": {
    "cliente_id": "uuid-del-cliente",
    "rif_nit": "J-12345678-9",
    "razon_social": "Comercial Ejemplo C.A.",
    "total_entregados": 0,
    "total_retirados": 10,
    "observaciones": "Retiro de vacíos en ruta sin orden de distribución",
    "fecha_movimiento": "2026-11-04T13:30:00.000Z",
    "contenedores": [
      {
        "movimiento_id": "uuid-del-movimiento",
        "contenedor_id": "uuid-del-contenedor",
        "codigo": "CAJA-24",
        "nombre": "Caja Plástica 24 Unid",
        "saldo_anterior": 15,
        "entregados": 0,
        "retirados": 10,
        "saldo_actual": 5
      }
    ]
  },
  "error": null
}
```

#### E. Códigos de Error Controlados (`error.code`)
- `PARAMETRO_INVALIDO`: Falta `p_cliente_id` o `p_movimientos` está vacío.
- `CLIENTE_INEXISTENTE`: El `p_cliente_id` no existe en `public.clientes`.
- `CONTENEDORES_INVALIDOS`: Algún ítem no tiene `contenedor_id`, o tiene cantidades negativas o decimales.
- `CANTIDADES_CERO`: Todas las líneas enviadas tienen `cantidad_retirada = 0` y `cantidad_entregada = 0`.
- `ERROR_INTERNO`: El `contenedor_id` no existe en `tipos_contenedores` u ocurrió una excepción SQL.

#### F. Actualización en `public.retorna_movimientos_contenedores_segun_cliente_id_rango_fechas`
Cada ítem dentro de `data.movimientos[]` ahora retorna adicionalmente:
- `es_movimiento_directo` (`boolean`): `true` cuando el movimiento se hizo sin Orden de Distribución (`orden_id IS NULL`).
- `saldo_anterior` (`number | null`): Saldo del cliente antes del movimiento.
- `saldo_actual` (`number | null`): Saldo resultante después del movimiento.
- `observaciones` (`string | null`): Nota registrada en el movimiento directo.

---

### 13.2. Implementación Obligatoria en la App Móvil / APK (`apps/mobile`)

> **⚠️ IMPORTANTE:** El módulo de retiro de contenedores sin orden **DEBE quedar activo en la APK** tanto desde la pantalla general de **Contenedores** (`/(app)/contenedores`) como desde el **Detalle de Contenedores de un Cliente** (`/(app)/contenedores/[clienteId]`), y habilitado para todos los roles operativos (`admin`, `gerente`, `vendedor`, `despachador`, `cobrador`, `chofer`).

#### Paso 1: Actualizar `apps/mobile/lib/contenedores.ts`
1. En el tipo `MovimientoContenedorRow`, añadir los nuevos campos:
   ```typescript
   export type MovimientoContenedorRow = {
     id: string;
     fecha_movimiento: string;
     orden_id: string | null;
     correlativo_orden: number | null;
     factura_origen_numero: string | null;
     es_movimiento_directo?: boolean;
     contenedor_id: string;
     codigo_contenedor: string | null;
     nombre_contenedor: string | null;
     cantidad_entregada: number;
     cantidad_retirada: number;
     saldo_anterior?: number | null;
     saldo_actual?: number | null;
     observaciones?: string | null;
   };
   ```
2. En `obtenerHistoricoContenedoresCliente`, mapear `es_movimiento_directo`, `saldo_anterior`, `saldo_actual` y `observaciones`:
   ```typescript
   es_movimiento_directo: Boolean(row.es_movimiento_directo ?? row.orden_id == null),
   saldo_anterior: row.saldo_anterior != null ? Number(row.saldo_anterior) : null,
   saldo_actual: row.saldo_actual != null ? Number(row.saldo_actual) : null,
   observaciones: row.observaciones ? String(row.observaciones) : null,
   ```
3. Agregar la función exportada `registrarMovimientoContenedoresAClientes`:
   ```typescript
   export type ItemMovimientoContenedorInput = {
     contenedor_id: string;
     cantidad_retirada: number;
     cantidad_entregada?: number;
   };

   export type ResultadoMovimientoContenedoresCliente = {
     cliente_id: string;
     rif_nit: string;
     razon_social: string;
     total_entregados: number;
     total_retirados: number;
     observaciones: string | null;
     fecha_movimiento: string;
     contenedores: Array<{
       movimiento_id: string;
       contenedor_id: string;
       codigo: string | null;
       nombre: string;
       saldo_anterior: number;
       entregados: number;
       retirados: number;
       saldo_actual: number;
     }>;
   };

   export async function registrarMovimientoContenedoresAClientes(input: {
     clienteId: string;
     movimientos: ItemMovimientoContenedorInput[];
     observaciones?: string | null;
   }): Promise<
     | { ok: true; data: ResultadoMovimientoContenedoresCliente; message: string }
     | { ok: false; error: string }
   > {
     const limpios = input.movimientos
       .map((m) => ({
         contenedor_id: m.contenedor_id.trim(),
         cantidad_retirada: Math.max(0, Math.floor(Number(m.cantidad_retirada) || 0)),
         cantidad_entregada: Math.max(0, Math.floor(Number(m.cantidad_entregada) || 0)),
       }))
       .filter((m) => m.contenedor_id && (m.cantidad_retirada > 0 || m.cantidad_entregada > 0));

     if (!input.clienteId?.trim()) {
       return { ok: false, error: "Debes seleccionar un cliente." };
     }
     if (limpios.length === 0) {
       return {
         ok: false,
         error: "Indica al menos una cantidad de contenedores a retirar mayor a 0.",
       };
     }

     const { data, error } = await supabase.rpc(
       "registrar_movimiento_contenedores_a_clientes",
       {
         p_cliente_id: input.clienteId.trim(),
         p_movimientos: limpios,
         p_observaciones: input.observaciones?.trim() || null,
       },
     );

     if (error) return { ok: false, error: error.message };
     if (!isRpcSuccess(data)) {
       return {
         ok: false,
         error: rpcFailMessage(
           data,
           "No se pudo registrar el retiro de contenedores.",
         ),
       };
     }

     const raw = unwrapRpcData<ResultadoMovimientoContenedoresCliente>(data);
     if (!raw) {
       return { ok: false, error: "Respuesta vacía del servidor." };
     }

     return {
       ok: true,
       data: raw,
       message: "Retiro de contenedores registrado exitosamente.",
     };
   }
   ```

#### Paso 2: Crear Pantalla de Retiro en la APK (`apps/mobile/app/(app)/contenedores/retirar.tsx`) y registrarla en `_layout.tsx`
1. En `apps/mobile/app/(app)/contenedores/_layout.tsx`, añadir la ruta `retirar`:
   ```tsx
   <Stack screenOptions={appHeaderScreenOptions}>
     <Stack.Screen name="index" options={stackIndexOptions("Contenedores")} />
     <Stack.Screen name="retirar" options={stackChildOptions("Retirar contenedores")} />
     <Stack.Screen name="[clienteId]" options={stackChildOptions("Detalle")} />
   </Stack>
   ```
2. Crear `apps/mobile/app/(app)/contenedores/retirar.tsx` con las siguientes capacidades:
   - Acepta parámetro opcional `useLocalSearchParams<{ clienteId?: string }>()`.
   - **Si no recibe `clienteId` (o el usuario desea cambiarlo):** muestra un buscador de clientes (`buscarClientesForProfile` / `listClientesForProfile` de `@/lib/clientes`) para elegir **cualquier cliente activo**, incluso si actualmente no tiene saldo de contenedores registrado (`saldo = 0`) o ya tiene saldo negativo (`< 0`).
   - **Una vez seleccionado el cliente:** llama a `obtenerSaldosEnvasesCliente(selectedClienteId)` de `@/lib/contenedores`, que devuelve todos los `tipos_contenedores` junto con el `saldo` actual del cliente.
   - **🚨 REGLA OBLIGATORIA DE SALDOS EN NEGATIVO EN LA APK (`saldo_actual < 0`):**
     - **NUNCA bloquear ni limitar `cantidad_retirada` al `saldo` actual del cliente.**
     - Un cliente con `saldo = 0` (o incluso con `saldo = -5`) o con `saldo = 10` puede entregar cualquier cantidad mayor (ej. `cantidad_retirada = 15`), quedando con **`nuevo_saldo = -5` (saldo a favor del cliente)**.
     - La base de datos y el RPC `registrar_movimiento_contenedores_a_clientes` soportan saldos negativos nativamente (`v_saldo_act := v_saldo_ant + entregados - retirados`), y la APK **DEBE permitir ingresarlo y guardarlo sin ningún tope máximo**.
   - **Por cada tipo de contenedor:** muestra:
     - Nombre y código del contenedor (`t.codigo — t.nombre`).
     - Badge con el **Saldo actual**:
       - Si `saldo > 0`: `"Pendiente: ${saldo}"`.
       - Si `saldo < 0`: `"${saldo} (Saldo a favor del cliente: ${Math.abs(saldo)})"` (en color verde `#059669`).
       - Si `saldo === 0`: `"Saldo: 0"`.
     - Controles para ingresar la **Cantidad a retirar**: botones `−` y `+` **y un `<TextInput keyboardType="number-pad">` editable en el centro** (sin límite superior respecto al saldo, más un botón rápido `"Todo"` solo cuando `saldo > 0` para autocompletar el saldo pendiente).
     - Vista previa en vivo del **Nuevo saldo** (`nuevoSaldo = saldo - cantidad_retirada`): si `nuevoSaldo < 0`, mostrar claramente `"Nuevo saldo: ${nuevoSaldo} (A favor del cliente)"`.
   - Campo opcional de **Observaciones** (`TextInput` multilínea, ej. `"Retiro de vacíos sin orden"`).
   - Botón principal **"Confirmar retiro de contenedores"** que invoca `registrarMovimientoContenedoresAClientes`, muestra alerta de éxito con el resumen actualizado y redirige a `/(app)/contenedores/${selectedClienteId}`.

#### Paso 3: Conectar Botones de Acción y Visualización de Saldos Negativos en `apps/mobile/app/(app)/contenedores/index.tsx` y `[clienteId].tsx`
1. **En `apps/mobile/app/(app)/contenedores/index.tsx`:**
   - Agregar un botón destacado en la parte superior **"+ Retirar contenedores a cliente"** que navegue a `router.push("/(app)/contenedores/retirar" as Href)`.
   - `listarSaldosContenedores({ soloConSaldo: true })` ya filtra con `.neq("saldo_pendiente", 0)`, por lo que incluye tanto saldos positivos (`> 0`) como saldos negativos (`< 0`). En la tarjeta de cada cliente, si `item.total_saldo < 0`, mostrar `"Saldo: ${item.total_saldo} (A favor del cliente)"`.
2. **En `apps/mobile/app/(app)/contenedores/[clienteId].tsx`:**
   - Debajo de los datos del cliente (o fijo abajo), agregar un botón primario **"Retirar contenedores"** que navegue a `router.push(\`/(app)/contenedores/retirar?clienteId=\${clienteId}\` as Href)`.
   - En las tarjetas de **Saldos**, si `s.saldo_pendiente < 0`, mostrar `"Saldo: ${s.saldo_pendiente} (A favor del cliente)"`.
   - En la lista de **Movimientos**, cuando `m.orden_id == null` (o `m.es_movimiento_directo`), mostrar la etiqueta `"Retiro directo (sin orden)"`, el cambio de saldo (`Ant. ${m.saldo_anterior} → Actual ${m.saldo_actual}`) y, si `m.observaciones` existe, mostrar la nota debajo de la fecha.

#### Paso 4: Asegurar Visibilidad del Módulo en Roles y Menú de la APK (`apps/mobile/lib/auth.ts`, `nav.ts`, `HomeScreen.tsx`)
1. En `apps/mobile/lib/auth.ts`:
   - Incluir `"/contenedores"` también en `ROLE_ALLOWED_HREFS.chofer` (para que todos los roles de ruta y campo —`admin`, `gerente`, `vendedor`, `despachador`, `chofer`, `cobrador`— tengan acceso al módulo en la APK).
2. En `apps/mobile/lib/nav.ts` y `apps/mobile/lib/auth.ts`:
   - Cambiar el label de `"Consulta de contenedores"` a **`"Contenedores (retiro y saldos)"`** para que quede claro en el Drawer que allí se retiran contenedores.
3. En `apps/mobile/src/features/shell/HomeScreen.tsx`:
   - Añadir un acceso directo (`ShortcutItem`) a **`/(app)/contenedores`** (`label: "Contenedores / Vacíos"`, `sub: "Retirar contenedores a clientes y consultar saldos"`, `icon: "layers-outline"`) para que el módulo esté inmediatamente accesible desde la pantalla de inicio de la APK.

---

### 13.3. Implementación en el Frontend Web (`src/`)

1. **Actualizar Tipos (`src/types/database.ts`):**
   - En `Database["public"]["Functions"]`, agregar:
     ```typescript
     registrar_movimiento_contenedores_a_clientes: {
       Args: {
         p_cliente_id: string;
         p_movimientos?: Json;
         p_observaciones?: string | null;
         p_creado_por?: string | null;
       };
       Returns: Json;
     };
     ```
2. **Crear Server Action (`src/lib/actions/contenedores.ts` o en `src/lib/actions/ordenes.ts`):**
   - Crear `registrarMovimientoContenedoresAClientesAction(input: { cliente_id: string; movimientos: Array<{ contenedor_id: string; cantidad_retirada: number; cantidad_entregada?: number }>; observaciones?: string })` que llame a `callDbProcedure("registrar_movimiento_contenedores_a_clientes", { p_cliente_id: input.cliente_id, p_movimientos: input.movimientos, p_observaciones: input.observaciones ?? null, p_creado_por: user.id })` y ejecute `revalidatePath("/contenedores")` y `revalidatePath(\`/contenedores/\${input.cliente_id}\`)`.
3. **Actualizar Vistas Web (`src/app/(dashboard)/contenedores/page.tsx` y `src/app/(dashboard)/contenedores/[clienteId]/page.tsx`):**
   - Añadir el botón y modal/formulario **"Retirar contenedores (sin orden)"** que permita elegir cliente (o usar el cliente actual en `[clienteId]`), ingresar las cantidades retiradas por tipo de contenedor y observación opcional, e invocar `registrarMovimientoContenedoresAClientesAction`.
   - En la tabla de historial de movimientos (`src/app/(dashboard)/contenedores/[clienteId]/page.tsx`), mostrar `"Retiro directo"` cuando `orden_id` sea `null`, junto con las `observaciones` del movimiento.



### 13.4. Estado de Implementación (Completado)
- **APK (`apps/mobile`):**
  - Pantalla `apps/mobile/app/(app)/contenedores/retirar.tsx` implementada con selección de cliente reactiva, selector de cantidades sin tope superior (admite saldos negativos / a favor del cliente), cálculo en vivo, observaciones y confirmación de retiro.
  - Registro de ruta en `apps/mobile/app/(app)/contenedores/_layout.tsx`.
  - Integración en `apps/mobile/app/(app)/contenedores/index.tsx` con botón `+ Retirar contenedores a cliente` y badges de saldo positivo/negativo.
  - Integración en `apps/mobile/app/(app)/contenedores/[clienteId].tsx` con botón `Retirar`, visualización de saldos a favor en verde y detalle de movimientos directos con notas.
  - Soporte de rol chofer en `apps/mobile/lib/auth.ts` y acceso directo desde `apps/mobile/src/features/shell/HomeScreen.tsx`.
  - Typecheck móvil verificado con 0 errores (`npx tsc --noEmit`).
- **Web (`src/`):**
  - Server Action `registrarMovimientoContenedoresAClientesAction` en `src/lib/actions/contenedores.ts`.
  - Modal `ModalRetirarContenedores` en `src/app/(dashboard)/contenedores/modal-retirar-contenedores.tsx`.
  - Vistas y tablas actualizadas en `src/app/(dashboard)/contenedores/[clienteId]/page.tsx` mostrando saldo neto a favor/pendiente y trazabilidad de movimientos directos.
  - Tipos en `src/types/database.ts` y `supabase/schema_base.sql` sincronizados.
  - Typecheck web verificado con 0 errores (`npx tsc --noEmit`).


---

## 14. INFORME DE VERIFICACIÓN Y REQUERIMIENTO DIRECTO PARA FRONTEND APK (`apps/mobile`) — Tareas Pendientes del Documento `task_20261103a.md` (05/11/2026)

> **Destinatario:** Encargado del Frontend Móvil / Desarrollador de la APK (`apps/mobile`)  
> **Estado:** ⚠️ **PENDIENTE DE IMPLEMENTACIÓN EN LA APK** (Comprobado al 05/11/2026: La versión Web y los RPCs/BD ya están operativos, pero la UI de la APK carece de las implementaciones requeridas).

A continuación se detalla el estado actual y las especificaciones exactas que deben ser implementadas en el código de la APK:

---

### 14.1. Tarea 1: Asignación de Días de Visita y Filtro en APK (`Cartera / Clientes / Visita`)

#### Diagnóstico en el Código Móvil:
- En `apps/mobile/lib/clientes.ts` ya se incluyeron `dias_visita` y `visita_cualquier_dia` en el `.select()`.
- **Falta en UI:**
  1. En `apps/mobile/app/(app)/clientes/nuevo.tsx` y formularios de cliente, no hay selectores para que el usuario elija los días de visita (máximo 2 días) o marque "Cualquier día".
  2. En `apps/mobile/app/(app)/clientes/index.tsx` (lista de cartera/clientes) y en `apps/mobile/app/(app)/visita/index.tsx` (módulo Visita/Cartera), **no se está aplicando el filtro por el día actual de la semana**.

#### Instrucciones de Implementación para el Frontend Móvil:
1. **Formularios de Cliente (`apps/mobile/app/(app)/clientes/nuevo.tsx`):**
   - Incorporar un selector/checkbox **"Cualquier día"** (`visita_cualquier_dia: boolean`, por defecto `true`).
   - Si se desmarca "Cualquier día", mostrar los 7 días de la semana (`['lunes', 'martes', 'miercoles', 'jueves', 'viernes', 'sabado', 'domingo']`) permitiendo seleccionar **hasta un máximo de 2 días** (`dias_visita: string[]`).
   - Al enviar, guardar ambos campos en `supabase.from("clientes").insert(...)`.

2. **Filtro Automático por Día Actual (`apps/mobile/app/(app)/visita/index.tsx` y `clientes/index.tsx`):**
   - Calcular el día actual:
     ```typescript
     const DIAS_SEMANA = ["domingo", "lunes", "martes", "miercoles", "jueves", "viernes", "sabado"] as const;
     const diaActual = DIAS_SEMANA[new Date().getDay()];

     function correspondeVisitaHoy(c: { visita_cualquier_dia?: boolean | null; dias_visita?: string[] | null }): boolean {
       const dias = Array.isArray(c.dias_visita) ? c.dias_visita : [];
       if (c.visita_cualquier_dia === true || dias.length === 0) return true;
       return dias.includes(diaActual);
     }
     ```
   - Filtrar la lista mostrada por defecto al vendedor para que solo aparezcan clientes donde `correspondeVisitaHoy(cliente) === true`.
   - Añadir un toggle o pestaña tipo *"Ver solo ruta de hoy ({diaActual})"* / *"Ver todos"*, permitiendo al vendedor alternar si necesita consultar un cliente fuera de ruta.

---

### 14.2. Tarea 2: Botón "Reversar Entrega" en Despacho / Órdenes (`apps/mobile`)

#### Diagnóstico en el Código Móvil:
- La función de servicio `reversarEntregaOrdenDistribucion` ya está lista en `apps/mobile/lib/ordenes.ts` llamando al RPC `reversar_entrega_orden_distribucion`.
- **Falta en UI:**
  - Ninguna pantalla de la APK la invoca. No existe el botón ni en la vista de detalle de la orden ni en el módulo de Radar.

#### Instrucciones de Implementación para el Frontend Móvil:
1. En `apps/mobile/src/features/ordenes/OrdenDetalleScreen.tsx` (y en las paradas entregadas de `apps/mobile/app/(app)/radar/index.tsx`):
   - Cuando una orden esté en estado entregado (`completada` / `entregada`) y el usuario tenga rol con permiso (`admin`, `gerente`, `despachador`), mostrar el botón/ícono **"Reversar Entrega"**.
   - Al presionarlo, solicitar confirmación con alerta: `¿Desea reversar la entrega de esta orden? La orden regresará al estado de tránsito o aprobada y el inventario será restituido.`
   - Ejecutar `reversarEntregaOrdenDistribucion(orden.id, "Reversión manual desde APK")`.
   - Al completar exitosamente, recargar los datos de la orden o radar y mostrar notificación de éxito.

---

### 14.3. Tarea 3: Edición Directa por Teclado de Cantidades en Líneas de Órdenes

#### Diagnóstico en el Código Móvil:
- En `apps/mobile/app/(app)/ordenes/nueva.tsx`, `editar/[id].tsx`, `venta-directa.tsx` y `autoventas/nueva.tsx`, el número de cantidad es solo un componente `<Text>{item.cantidad}</Text>`. El usuario está obligado a presionar decenas de veces los botones `+` / `−`.

#### Instrucciones de Implementación para el Frontend Móvil:
- Reemplazar el `<Text style={styles.qty}>{item.cantidad}</Text>` central por un `<TextInput>` numérico:
  ```tsx
  <TextInput
    style={styles.qtyInput}
    keyboardType="number-pad"
    value={String(item.cantidad)}
    onChangeText={(val) => {
      const num = parseInt(val.replace(/\D/g, ""), 10);
      updateCantidad(item.producto_id, isNaN(num) ? 0 : num);
    }}
    selectTextOnFocus
  />
  ```
- Mantener los botones `−` y `+` a los costados para sumar/restar 1 unidad.
- Al tipear cualquier número entero (ej. `50`), actualizar en tiempo real el subtotal de la línea y el monto total de la orden.

---

### 14.4. Tarea 4: Impresión por Impresoras Wi-Fi desde Radar (`expo-print`)

#### Diagnóstico en el Código Móvil:
- No está instalado `expo-print`. La aplicación móvil solo cuenta con la librería para impresoras térmicas Bluetooth en `apps/mobile/lib/bluetooth-print.ts`.

#### Instrucciones de Implementación para el Frontend Móvil:
1. Instalar la librería requerida en `apps/mobile`:
   ```bash
   npx expo install expo-print
   ```
2. En `apps/mobile/lib/print-orden.ts`:
   - Crear la función `imprimirOrdenWifi(orden: OrdenDetalle)` que genere el HTML de la nota de entrega / orden de distribución y ejecute:
     ```typescript
     import * as Print from "expo-print";
     await Print.printAsync({ html });
     ```
3. En `apps/mobile/app/(app)/radar/index.tsx` y en el detalle de la orden:
   - Ofrecer la opción de imprimir vía **"Impresora Wi-Fi / Sistema"** o **"Impresora Bluetooth"** mediante un selector o menú de opciones de impresión.

---

### 14.5. Tarea 5: Mejoras en Cobranzas / Rendiciones (Captures, Cámara y Separador de Miles)

#### Diagnóstico en el Código Móvil:
- En `apps/mobile/app/(app)/rendiciones/nueva.tsx`, los pagos solo admiten texto/referencia. No se permite adjuntar fotos ni seleccionar archivos de la galería. Además, los inputs numéricos carecen de formato de separador de miles.

#### Instrucciones de Implementación para el Frontend Móvil:
1. **Captura / Cámara con `expo-image-picker`:**
   - En cada fila de forma de pago (transferencia, cheque, etc.), agregar botones:
     - 📷 **"Tomar foto"** (`ImagePicker.launchCameraAsync`).
     - 🖼️ **"Subir capture"** (`ImagePicker.launchImageLibraryAsync`).
   - Subir la imagen en base64 o archivo blob al bucket de Supabase Storage **`rendiciones-captures`** en la ruta `${user.id}/${Date.now()}.jpg`.
   - Almacenar la URL pública obtenida en la propiedad `capture_url` del pago correspondiente para enviarlo a `registrar_rendicion_cuentas`.
   - Mostrar una miniatura (`<Image>`) con botón de eliminar/reemplazar.
2. **Separador de Miles en Vivo:**
   - Integrar máscara de formato numérico (`formatMoneyInputLive`) en los `TextInput` de abono y pagos, garantizando que el usuario visualice los miles separados (ej. `1.250,50`) sin que se altere el valor numérico flotante enviado al backend.

---

### 14.6. Tarea 6: Corrección de Generación de Saldo a Favor en Cobranzas

#### Diagnóstico en el Código Móvil:
- Sigue presente en `apps/mobile/app/(app)/rendiciones/nueva.tsx` el recorte por `montoAplicable` que trunca los excedentes de pago a la deuda total, impidiendo que el backend (`registrar_rendicion_cuentas`) reciba el sobrepago para abonarlo a `clientes.saldo_favor`.

#### Instrucciones de Implementación para el Frontend Móvil:
- Aplicar estrictamente lo documentado en la **Sección 11.3** de este archivo (`INTEGRACION-RPC.md`):
  1. No restringir el pago ingresado al total adeudado cuando el cliente paga de más.
  2. Separar `totalCobrarUsd` de `totalDigitadoUsd`.
  3. Preservar montos mayores en `syncPaymentWithTotal` y alimentar `fillRemainingPayment` con el total digitado real.

---


### 14.7. Estado de Implementación en APK Móvil (`apps/mobile`) — Completado (2026-11-05)

Todas las 6 tareas de la Sección 14 han sido implementadas y verificadas con `tsc --noEmit` (0 errores):

- **Tarea 1 (Días de Visita y Filtro en Cartera/Visita):**
  - Creado `apps/mobile/components/selector-dias-visita.tsx` e integrado en `apps/mobile/app/(app)/clientes/nuevo.tsx` y `apps/mobile/app/(app)/clientes/[id]/editar.tsx`.
  - Actualizado `apps/mobile/lib/clientes.ts` (`correspondeVisitaHoy`, `getDiaActualTexto`, `getDiaActualLabel`, `createCliente`, `updateCliente`).
  - Aplicado filtro por día actual por defecto con selector `"Ruta de hoy (<Día>)"` vs `"Todos"` en `apps/mobile/app/(app)/visita/index.tsx` y `apps/mobile/app/(app)/clientes/index.tsx`.
- **Tarea 2 (Reversión de Entrega Parcial en Despacho):**
  - Añadido botón **"Reversar Entrega"** con confirmación en `apps/mobile/src/features/ordenes/screens/OrdenDetalleScreen.tsx` y en paradas entregadas de `apps/mobile/app/(app)/radar/index.tsx`, invocando `reversarEntregaOrdenDistribucion(...)`.
- **Tarea 3 (Edición de Cantidades por Teclado en Órdenes):**
  - Reemplazado el texto estático central por `<TextInput keyboardType="number-pad" selectTextOnFocus />` entre `−` y `+` en `apps/mobile/app/(app)/ordenes/nueva.tsx`, `apps/mobile/app/(app)/ordenes/editar/[id].tsx`, `apps/mobile/app/(app)/ordenes/venta-directa.tsx` y `apps/mobile/app/(app)/autoventas/nueva.tsx`.
- **Tarea 4 (Impresión Wi-Fi desde Radar y Detalle con `expo-print`):**
  - Instalado `expo-print`, implementadas `buildHtmlForOrden` e `imprimirOrdenWifi` en `apps/mobile/lib/print-orden.ts`, y añadido selector entre **"Impresora Wi-Fi / Red"** e **"Impresora Bluetooth"** en `apps/mobile/app/(app)/radar/index.tsx` y `apps/mobile/src/features/ordenes/screens/OrdenDetalleScreen.tsx`.
- **Tarea 5 (Cobranzas - Fotos, Captures y Separador de Miles):**
  - Instalado `expo-image-picker`, añadidas `parseMoneyInput`, `formatMoneyInputLive` y `numberToMoneyInput` en `apps/mobile/lib/format.ts`, y `uploadCaptureRendicionMobile` en `apps/mobile/lib/rendiciones.ts`.
  - Integrados botones **"Tomar foto"** y **"Subir capture"** con vista previa y formato de miles en vivo en `apps/mobile/app/(app)/rendiciones/nueva.tsx`, y visualización de comprobantes en `apps/mobile/app/(app)/rendiciones/[id].tsx`.
- **Tarea 6 (Saldo a Favor en Cobranzas - Sección 11.3):**
  - Separados `totalCobrarUsd` y `totalDigitadoUsd` (`computeTotalDigitado`) en `apps/mobile/app/(app)/rendiciones/nueva.tsx`, preservando sobrepagos en `syncPaymentWithTotal`, `addPago` y `fillRemainingPayment` para que viajen completos a `registrar_rendicion_cuentas`.

## 7. Subida de imágenes de productos vía Edge Function

**Objetivo**: proporcionar al equipo Front‑end una API sencilla para subir fotografías de productos a Supabase Storage y registrar la ruta relativa (`imagen_path`) en la tabla `public.productos`.

### Endpoint
```
POST https://<PROJECT_REF>.functions.supabase.co/upload_product_image
```
*Requiere autenticación mediante el **Service Role** (la función está protegida y sólo será invocada desde el Front‑end usando la clave `SUPABASE_ANON_KEY` y el token de sesión del usuario).* 

### Parámetros (multipart/form‑data)
| Campo | Tipo | Descripción |
|------|------|-------------|
| `file` | File | Imagen del producto (WebP, JPG o PNG). Tamaño máximo 5 MB. |
| `product_id` | UUID | Identificador del producto al que se asociará la foto. |

### Respuesta JSON
```json
{ "ok": true, "imagen_path": "/productos/<timestamp>.<ext>" }
```
En caso de error:
```json
{ "ok": false, "error": "<mensaje>" }
```

### Flujo interno de la función
1. **Validación** de presencia y tamaño del archivo.  
2. Genera un nombre único (`<timestamp>.<ext>`).  
3. Usa `supabase.storage.from('productos').upload` para guardar el archivo en el bucket público `productos`.  
4. Ejecuta la RPC `actualizar_registro_productos_segun_id` (o actualización directa) para almacenar la ruta relativa en la columna `imagen_path` del producto.  
5. Devuelve la ruta relativa.

### Uso en el Front‑end (ejemplo TypeScript)
```ts
const form = new FormData();
form.append('file', selectedFile);
form.append('product_id', productId);
const res = await fetch('https://<PROJECT_REF>.functions.supabase.co/upload_product_image', {
  method: 'POST',
  body: form,
});
const data = await res.json();
if (data.ok) {
  // usar data.imagen_path con LogiImage o actualizar UI
}
```

### Consideraciones y Requisito Crítico Multi-Tenant para el Frontend
- El bucket `productos` debe existir y estar configurado como **público** en cada empresa (ver Guía Técnica en `docs/ESTANDAR-IMAGENES-STORAGE.md`).
- > [!IMPORTANT]
  > **Construcción de URL de imagen en Multi-Tenant (FRONTEND):**
  > En la arquitectura multi-tenant de LogiTrack, los archivos subidos residen en el Storage del **proyecto Supabase de la empresa activa del usuario** (ej: `https://<tenant_supabase_url>/storage/v1/object/public`).
  > **El Frontend NO debe usar una variable estática fija (`NEXT_PUBLIC_STORAGE_BASE_URL` apuntando a Central)** para resolver `imagen_path`. Debe resolver dinámicamente la URL base anteponiendo el host de la empresa activa del usuario (ejemplo: `${tenant.url}/storage/v1/object/public${imagen_path}` o leyendo la cookie/contexto del tenant actual). De lo contrario, Central retornará HTTP 404 y `LogiImage` volverá al placeholder SVG.
- La función de backend está implementada como **Supabase Edge Function** bajo `supabase/functions/upload_product_image/index.ts` y la Server Action asociada en `src/lib/actions/productos.ts` (`subirImagenProductoAction`).

> **Regla de Oro**: cualquier cambio que afecte la integración RPC debe ser documentado inmediatamente en este archivo y luego subir a GitHub (esperaremos autorización para el `git push`).


---

## 15. Tasa de Cambio según Fecha (`retorna_tasa_cambio_segun_fecha`) y Fecha de Pago / Registro en Cobranzas (`2026-11-06`)

### 15.1. Contexto Funcional
Muchas cobranzas (rendiciones de cuentas) se registran en el sistema días después de haberse efectuado el pago o abono real por parte del cliente. Para soportar este flujo:
1. Se consulta la tasa de cambio oficial registrada en la fecha efectiva del pago mediante `public.retorna_tasa_cambio_segun_fecha(dFecha)`.
2. Si para esa fecha no existe tasa cargada en `public.tasa_cambio`, la función informa exactamente **`"Tasa no registrada"`** y el formulario (Web y Mobile APK) permite al usuario **escribir la tasa manualmente**.
3. En la tabla cabecera `public.rendiciones_cuentas`:
   - `fecha_rendicion` almacena la **fecha efectiva del pago o abono**.
   - Se añade la columna `fecha_registro TIMESTAMPTZ NOT NULL DEFAULT NOW()` que almacena la **fecha y hora exacta en que se grabó la cobranza en el sistema**.
4. En `public.logs_auditoria` se graba el evento `INSERT` sobre `rendiciones_cuentas` con la fecha y hora exacta del momento (`NOW()`) y el `usuario_id` ejecutor.

### 15.2. Parche SQL Idempotente
- **Archivo en Tenants:** `supabase/tenant_patches/20261106134000_retorna_tasa_cambio_segun_fecha_y_fecha_cobranza.sql`
- **Migración Base:** `supabase/migrations/20261106134000_retorna_tasa_cambio_segun_fecha_y_fecha_cobranza.sql`

### 15.3. Contrato de la Función RPC: `public.retorna_tasa_cambio_segun_fecha`

- **Firma SQL:**
  ```sql
  public.retorna_tasa_cambio_segun_fecha(dfecha date) RETURNS json
  ```
- **Parámetros de entrada:**
  | Parámetro | Tipo | Requerido | Descripción |
  | :--- | :--- | :---: | :--- |
  | `dfecha` | `date` (`YYYY-MM-DD`) | Sí | Fecha del pago o abono a consultar en `public.tasa_cambio`. |

- **Respuesta JSON cuando la tasa está registrada:**
  ```json
  {
    "success": true,
    "message": "Tasa de cambio obtenida exitosamente.",
    "data": {
      "fecha_tasa": "2026-11-04",
      "tasa_cambio": 45.2500,
      "created_at": "2026-11-04T08:00:00.000Z"
    },
    "error": null
  }
  ```

- **Respuesta JSON cuando la tasa NO está registrada (`TASA_NO_REGISTRADA`):**
  ```json
  {
    "success": false,
    "message": "Tasa no registrada",
    "data": null,
    "error": {
      "code": "TASA_NO_REGISTRADA",
      "message": "Tasa no registrada",
      "details": "No existe tasa de cambio registrada para la fecha 2026-11-04"
    }
  }
  ```

### 15.4. Actualización de `public.registrar_rendicion_cuentas`

- **Nueva firma retrocompatible:**
  ```sql
  public.registrar_rendicion_cuentas(
      p_cliente_id uuid,
      p_observaciones text,
      p_creado_por uuid,
      p_ordenes jsonb,
      p_pagos jsonb,
      p_tasa_cambio numeric DEFAULT NULL::numeric,
      p_fecha_pago date DEFAULT NULL::date
  ) RETURNS json
  ```
- **Comportamiento de tasa y fechas:**
  - Si `p_tasa_cambio` es enviado (`> 0`), se utiliza dicha tasa (ya sea la obtenida de `retorna_tasa_cambio_segun_fecha` o la **escrita manualmente por el usuario** cuando la fecha indicó `"Tasa no registrada"`).
  - Si `p_tasa_cambio` es `NULL` y se envía `p_fecha_pago`, busca la tasa de `p_fecha_pago` en `public.tasa_cambio` (y como último recurso usa la última tasa registrada).
  - Guarda la fecha del pago en `rendiciones_cuentas.fecha_rendicion` y el timestamp exacto del momento (`NOW()`) en `rendiciones_cuentas.fecha_registro` y en `logs_auditoria.fecha_registro`.
- **Nuevos campos en `data` de respuesta:**
  - `fecha_rendicion`: fecha del pago registrada.
  - `fecha_registro`: timestamp exacto del momento del registro.
