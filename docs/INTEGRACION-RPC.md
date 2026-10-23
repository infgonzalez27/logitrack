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


