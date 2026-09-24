# GuÃ­a de IntegraciÃ³n de Stored Procedures (RPC) para Front & Backend

**Proyecto:** LogiTrack  
**PropÃ³sito:** Proveer instrucciones de cÃ³digo y contratos para consumir las funciones de base de datos desde Next.js Server Actions o componentes del cliente.  
**Desarrollado para:** Desarrollador Front/Backend del equipo de LogiTrack.

---

## 1. PatrÃ³n General de Consumo en TypeScript

Todas las llamadas a funciones de negocio en PostgreSQL deben realizarse utilizando el mÃ©todo `.rpc()` del cliente de Supabase.

### 1.1. Manejo de la Respuesta Estandarizada
Dado que las funciones devuelven una estructura JSON unificada (ver [docs/SUPABASE-SDD.md](file:///d:/ProyectosWeb/LogiTrack/docs/SUPABASE-SDD.md)), la llamada en Next.js debe deserializarse e interpretarse del siguiente modo:

```typescript
import { createClient } from '@/lib/supabase/server'; // O tu cliente correspondiente

interface RPCResponse<T> {
  success: boolean;
  data: T | null;
  error: {
    code: string;
    message: string;
    details: string | null;
  } | null;
}

export async function callDbProcedure<T>(procedureName: string, params: Record<string, any>) {
  const supabase = await createClient(); // Cliente del lado del servidor
  
  const { data, error } = await supabase.rpc(procedureName, params);
  
  if (error) {
    // Error crÃ­tico de red o de comunicaciÃ³n de la API de Supabase
    return {
      success: false,
      data: null,
      error: {
        code: 'NETWORK_OR_API_ERROR',
        message: error.message,
        details: error.details
      }
    };
  }

  // Cast de la respuesta estructurada de PostgreSQL
  const response = data as RPCResponse<T>;
  return response;
}
```

### 1.2. Ejemplo de IntegraciÃ³n en un Server Action de Next.js
AquÃ­ se muestra cÃ³mo el desarrollador de Back/Front debe invocar la funciÃ³n en un Server Action para cambiar la interfaz de usuario de acuerdo al resultado.

```typescript
'use server';

import { callDbProcedure } from '@/lib/actions/db-helper'; // Supuesta ubicaciÃ³n del helper
import { revalidatePath } from 'next/cache';

interface CrearOrdenData {
  orden_id: string;
  correlativo: number;
  peso_total_calculado: number;
}

export async function submitCrearOrdenAction(formData: any) {
  const params = {
    p_cliente_id: formData.clienteId,
    p_camion_id: formData.camionId,
    p_chofer_id: formData.choferId,
    p_factura_origen_numero: formData.facturaNumero,
    p_creado_por: formData.usuarioId,
    p_detalles: JSON.stringify(formData.detalles) // Debe pasarse como string de JSON para ser leÃ­do como JSONB
  };

  const response = await callDbProcedure<CrearOrdenData>('crear_orden_distribucion', params);

  if (!response.success) {
    // Controlar error lÃ³gico (ej: STOCK_INSUFICIENTE, CLIENTE_INEXISTENTE)
    return {
      error: response.error?.message || 'Error desconocido al crear la orden.',
      code: response.error?.code
    };
  }

  // Si fue exitoso, revalidamos la ruta para refrescar el listado
  revalidatePath('/ordenes');
  
  return {
    success: true,
    data: response.data
  };
}
```

---

## 2. CatÃ¡logo de Stored Procedures e Indicaciones de ParÃ¡metros

A continuaciÃ³n se listan las firmas de los procedimientos almacenados que el equipo de base de datos implementarÃ¡. Utiliza esta secciÃ³n como referencia para preparar tus componentes de frontend.

### 2.1. Crear Orden de DistribuciÃ³n (`crear_orden_distribucion`)
- **Firma SQL:** `crear_orden_distribucion(p_vendedor_id UUID, p_cliente_id UUID, p_camion_id UUID, p_tasa_cambio NUMERIC DEFAULT NULL, p_productos_json JSONB DEFAULT '[]'::jsonb, p_despachador_id UUID DEFAULT NULL, p_id_ruta UUID DEFAULT NULL)`
- **Campos multimoneda y relaciones asociadas automÃ¡ticamente en DB:**
  - `ordenes_distribucion`: `tasa_cambio`, `total_recaudar_bs`, `total_recaudar_usd`, `vendedor_id`, `despachador_id` e `id_ruta` (se obtienen del perfil del cliente si no se pasan explÃ­citamente).
  - `detalle_distribucion`: `valor_unitario_recaudar` (Bs), `subtotal_recaudar` (Bs), `valor_unitario_usd` (USD), `subtotal_recaudar_usd` (USD).
- **Uso en Frontend (RPC) / Cursor Editor:**
  ```typescript
  const { data, error } = await supabase.rpc('crear_orden_distribucion', {
    p_vendedor_id: 'UUID_DEL_VENDEDOR',
    p_cliente_id: 'UUID_DEL_CLIENTE',
    p_camion_id: 'UUID_DEL_CAMION',
    p_tasa_cambio: 50.25, // Opcional (si se omite/es null, toma la tasa oficial mÃ¡s reciente de la tabla tasa_cambio)
    p_despachador_id: 'UUID_OPCIONAL_DESPACHADOR', // Opcional
    p_id_ruta: 'UUID_OPCIONAL_RUTA', // Opcional
    p_productos_json: [
      {
        producto_id: 'UUID_PRODUCTO_1',
        cantidad: 5,
        valor_unitario_recaudar: 500.00, // Precio unitario en BolÃ­vares (Bs)
        valor_unitario_usd: 9.95        // Precio unitario en DÃ³lares (USD)
      },
      {
        producto_id: 'UUID_PRODUCTO_2',
        cantidad: 2,
        valor_unitario_recaudar: 1000.00,
        valor_unitario_usd: 19.90
      }
    ]
  });
  ```
- **Respuesta esperada en `data`:**
  ```json
  {
    "success": true,
    "message": "Orden de distribuciÃ³n creada exitosamente.",
    "orden_id": "UUID_DE_LA_NUEVA_ORDEN",
    "data": {
      "orden_id": "UUID_DE_LA_NUEVA_ORDEN",
      "correlativo": 105,
      "tasa_cambio": 50.25,
      "total_recaudar_bs": 4500.00,
      "total_recaudar_usd": 89.55,
      "peso_total_calculado": 125.40
    }
  }
  ```

### 2.2. AprobaciÃ³n de Orden y Reserva de Stock (`aprobar_orden_distribucion`)
- **Firma SQL:** `aprobar_orden_distribucion(p_orden_id UUID)`
- **Uso en Frontend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('aprobar_orden_distribucion', {
    p_orden_id: 'UUID_DE_LA_ORDEN'
  });
  ```
- **Respuesta esperada en `data`:**
  ```json
  {
    "success": true,
    "data": {
      "orden_id": "UUID_DE_LA_ORDEN",
      "nuevo_estado": "aprobada"
    },
    "error": null
  }
  ```

### 2.3. Carga a Inventario MÃ³vil por Orden (`cargar_inventario_movil`)
- **Firma SQL:** `cargar_inventario_movil(p_orden_id UUID)`
- **Uso en Frontend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('cargar_inventario_movil', {
    p_orden_id: 'UUID_DE_LA_ORDEN'
  });
  ```
- **Respuesta esperada en `data`:**
  ```json
  {
    "success": true,
    "data": {
      "orden_id": "UUID_DE_LA_ORDEN",
      "nuevo_estado": "en_transito"
    },
    "error": null
  }
  ```

### 2.3.1. Carga Consolidada a Inventario MÃ³vil desde Resumen de Radar (`solicita_cargar_inventario_movil_desde_almacen`)
- **Firma SQL:** `solicita_cargar_inventario_movil_desde_almacen(p_camion_id UUID, p_resumen_productos JSONB, p_radar_id UUID DEFAULT NULL)`
- **Uso en Frontend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('solicita_cargar_inventario_movil_desde_almacen', {
    p_camion_id: 'uuid-del-camion',
    p_resumen_productos: [
      {
        producto_id: 'uuid-del-producto-1',
        codigo_producto: '1187',
        nombre_producto: 'Zulia Lata 295 ml',
        cantidad_solicitada: 22,
        cantidad_despachada: 22
      },
      {
        producto_id: 'uuid-del-producto-2',
        codigo_producto: '1086',
        nombre_producto: 'Zulia Retornable 222 ml',
        cantidad_solicitada: 15,
        cantidad_despachada: 15
      }
    ],
    p_radar_id: 'uuid-del-radar' // Opcional
  });
  ```
- **Notas de Comportamiento:**
  - Toma `cantidad_solicitada` por cada producto para descontar del `inventario_almacen` e incrementar `cantidad_cargada` en `inventario_movil`.
  - Actualiza automÃ¡ticamente el estado del camiÃ³n a `'en_ruta'`.
  - Transiciona el estado de las Ã³rdenes asociadas a `'en_transito'` **manteniendo su `fecha_despacho` original**.
  - Establece `carga_inventario_movil = TRUE` en la tabla `radars`.
- **Respuesta esperada en `data`:**
  ```json
  {
    "success": true,
    "message": "Carga a inventario mÃ³vil procesada exitosamente desde el almacÃ©n.",
    "data": {
      "camion_id": "uuid-del-camion",
      "radar_id": "uuid-del-radar",
      "carga_inventario_movil": true,
      "total_productos_cargados": 2,
      "unidades_totales": 37,
      "ordenes_despachadas": 5
    },
    "error": null
  }
  ```

### 2.3.2. Reverso de Carga de Inventario MÃ³vil al AlmacÃ©n (`solicita_reversar_carga_inventario_movil_a_almacen`)
- **Firma SQL:** `solicita_reversar_carga_inventario_movil_a_almacen(p_camion_id UUID, p_resumen_productos JSONB DEFAULT NULL, p_radar_id UUID DEFAULT NULL)`
- **Uso en Frontend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('solicita_reversar_carga_inventario_movil_a_almacen', {
    p_camion_id: 'uuid-del-camion',
    p_radar_id: 'uuid-del-radar' // Opcional
  });
  ```
- **Notas de Comportamiento:**
  - Devuelve la mercancÃ­a del `inventario_movil` del camiÃ³n al `inventario_almacen`.
  - Transiciona las Ã³rdenes de la ruta de `'en_transito'` de vuelta a `'aprobada'` **manteniendo su `fecha_despacho` original**.
  - Cambia el estado del camiÃ³n a `'asignado'`.
  - Restablece `carga_inventario_movil = FALSE` en la tabla `radars`.
  - Retorna error `REVERSO_BLOQUEADO_POR_ENTREGAS` si ya se registraron despachos a clientes en esa ruta.
- **Respuesta esperada en `data`:**
  ```json
  {
    "success": true,
    "message": "Reverso de inventario mÃ³vil al almacÃ©n procesado exitosamente.",
    "data": {
      "camion_id": "uuid-del-camion",
      "radar_id": "uuid-del-radar",
      "carga_inventario_movil": false,
      "total_productos_reversados": 2,
      "unidades_totales": 37,
      "ordenes_reversadas": 5
    },
    "error": null
  }
  ### 2.3.3. EdiciÃ³n y Re-sincronizaciÃ³n de Radar (`solicita_editar_o_sincronizar_radar`)
- **Firma SQL:** `solicita_editar_o_sincronizar_radar(p_radar_id UUID)`
- **Uso en Frontend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('solicita_editar_o_sincronizar_radar', {
    p_radar_id: 'uuid-del-radar'
  });
  ```
- **Notas de Comportamiento:**
  - **Fase 1 (DesvinculaciÃ³n):** Desvincula las Ã³rdenes actualmente asignadas al radar que estÃ©n en estado `'aprobada'`.
  - **Fase 2 (RevinculaciÃ³n):** Re-vincula todas las Ã³rdenes aprobadas pertenecientes a clientes del despachador y con la misma `fecha_despacho::date` del radar.
  - Recalcula acumulados de `total_cantidad_solicitada`, `total_cantidad_despachada` y `total_contenedores_retirados`.
  - Retorna el error `RADAR_INVENTARIO_CARGADO` (`'Para modificar el Radar debe reversar el inventario movil al almacÃ©n'`) si `carga_inventario_movil = TRUE`.
  - Retorna el error `RADAR_APROBADO_BLOQUEADO` si `status_radar = TRUE`.
- **Respuesta esperada en `data`:**
  ```json
  {
    "success": true,
    "message": "Radar re-sincronizado y actualizado exitosamente.",
    "data": {
      "radar_id": "uuid-del-radar",
      "correlativo": 104,
      "despachador_id": "uuid-del-despachador",
      "fecha_despacho": "2026-09-15",
      "ordenes_desvinculadas": 8,
      "ordenes_vinculadas": 8,
      "total_cantidad_solicitada": 120,
      "total_cantidad_despachada": 0,
      "total_contenedores_retirados": 0
    },
### 2.3.4. Consulta de Lista de Radares Pendientes por Rango de Fechas (`retorna_lista_radars_pendiente_segun_rango_fechas`)
- **Firma SQL:** `retorna_lista_radars_pendiente_segun_rango_fechas(p_despachador_id UUID DEFAULT NULL, p_fecha_inicial DATE DEFAULT NULL, p_fecha_limite DATE DEFAULT NULL)`
- **Uso en Frontend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('retorna_lista_radars_pendiente_segun_rango_fechas', {
    p_despachador_id: 'uuid-del-despachador', // Opcional
    p_fecha_inicial: '2026-09-01',
    p_fecha_limite: '2026-09-15'
  });
  ```
- **Notas de Comportamiento:**
  - Retorna Ãºnicamente los radares en estado **pendiente** (`status_radar = FALSE`).
  - Mismos parÃ¡metros y estructura de retorno que `retorna_lista_radars_segun_rango_fechas`.

### 2.3.5. Consulta de Lista de Radares Aprobados por Rango de Fechas (`retorna_lista_radars_aprobado_segun_rango_fechas`)
- **Firma SQL:** `retorna_lista_radars_aprobado_segun_rango_fechas(p_despachador_id UUID DEFAULT NULL, p_fecha_inicial DATE DEFAULT NULL, p_fecha_limite DATE DEFAULT NULL)`
- **Uso en Frontend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('retorna_lista_radars_aprobado_segun_rango_fechas', {
    p_despachador_id: 'uuid-del-despachador', // Opcional
    p_fecha_inicial: '2026-09-01',
    p_fecha_limite: '2026-09-15'
  });
  ```
- **Notas de Comportamiento:**
  - Retorna Ãºnicamente los radares en estado **aprobado** (`status_radar = TRUE`).
  - Mismos parÃ¡metros y estructura de retorno que `retorna_lista_radars_segun_rango_fechas`.

### 2.4. Registrar Despacho Cliente en Radar (`registrar_despacho_cliente_radar`)
- **Firma SQL:** `registrar_despacho_cliente_radar(p_orden_id UUID, p_detalles_json JSONB)`
- **Uso en Frontend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('registrar_despacho_cliente_radar', {
    p_orden_id: 'uuid-de-la-orden',
    p_detalles_json: [
      {
        detalle_id: 'uuid-del-detalle-linea',
        cantidad_despachada: 10,
        estado_entrega: 'entregado',
        motivo_rechazo: null,
        contenedores_retirados: 2,
        contenedor_id: 'uuid-contenedor-opcional'
      }
    ]
  });
  ```
- **Notas de Comportamiento:**
  - Asienta atÃ³micamente en `movimientos_contenedores` e incrementa/decrementa `saldo_contenedores_clientes` al momento de la confirmaciÃ³n del despacho.
  - Para cada SKU despachado con `contenedor_id`, calcula contenedores entregados = `CEIL(cantidad_despachada / unidades_por_contenedor)`.
  - Es **idempotente**: si la orden es re-editada en el radar, revierte los movimientos previos de esa orden antes de asentar los nuevos.
  - Retorna `contenedores_resumen` con el `saldo_anterior`, movimiento (`cantidad_entregada`, `cantidad_retirada`) y `saldo_actualizado` para ser presentado en la interfaz grÃ¡fica.
- **Respuesta esperada en `data`:**
  ```json
  {
    "success": true,
    "message": "Despacho registrado en radar exitosamente.",
    "data": {
      "orden_id": "uuid-de-la-orden",
      "nuevo_estado": "por_liquidar",
      "total_despachado": 10,
      "contenedores_resumen": [
        {
          "contenedor_id": "uuid-del-contenedor",
          "saldo_anterior": 15,
          "cantidad_entregada": 10,
          "cantidad_retirada": 2,
          "saldo_actualizado": 23
        }
      ]
    },
    "error": null
  }
  ```

### 2.4.1. Registrar Entrega Detalle Lineal (`registrar_entrega_detalle`)
- **Firma SQL:** `registrar_entrega_detalle(p_detalle_id UUID, p_cantidad_despachada INT, p_estado_entrega TEXT, p_motivo_rechazo TEXT)`
- **Uso en Frontend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('registrar_entrega_detalle', {
    p_detalle_id: 'UUID_DEL_DETALLE_LINEA',
    p_cantidad_despachada: 4, // Cantidad que realmente recibiÃ³ el cliente
    p_estado_entrega: 'entregado_parcial', // 'entregado', 'entregado_parcial', 'rechazado'
    p_motivo_rechazo: '2 unidades daÃ±adas en el trayecto' // Null si es 'entregado' completo
  });
  ```
- **Respuesta esperada en `data`:**
  ```json
  {
    "success": true,
    "data": {
      "detalle_id": "UUID_DEL_DETALLE_LINEA",
      "estado_entrega": "entregado_parcial",
      "orden_estado": "por_liquidar" // o "en_transito" si aÃºn hay lÃ­neas pendientes
    },
    "error": null
  }
  ```

### 2.5. LiquidaciÃ³n de Despacho (`liquidar_orden_distribucion`)
- **Firma SQL:** `liquidar_orden_distribucion(p_orden_id UUID)`
- **Uso en Frontend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('liquidar_orden_distribucion', {
    p_orden_id: 'UUID_DE_LA_ORDEN'
  });
  ```
- **Respuesta esperada en `data`:**
  ```json
  {
    "success": true,
    "data": {
      "orden_id": "UUID_DE_LA_ORDEN",
      "nuevo_estado": "liquidada"
    },
    "error": null
  }
  ```

### 2.6. AnulaciÃ³n de Orden (`anular_orden_distribucion`)
- **Firma SQL:** `anular_orden_distribucion(p_orden_id UUID)`
- **Uso en Frontend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('anular_orden_distribucion', {
    p_orden_id: 'UUID_DE_LA_ORDEN'
  });
  ```
- **Respuesta esperada en `data`:**
  ```json
  {
    "success": true,
    "data": {
      "orden_id": "UUID_DE_LA_ORDEN",
      "nuevo_estado": "anulada"
    },
    "error": null
  }
  ```

### 2.7. Registrar Movimiento de Contenedores (`registrar_movimiento_contenedores`)
- **Firma SQL:** `registrar_movimiento_contenedores(p_cliente_id UUID, p_orden_id UUID, p_contenedor_id UUID, p_cantidad_entregada INT, p_cantidad_retirada INT, p_creado_por UUID)`
- **Uso en Frontend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('registrar_movimiento_contenedores', {
    p_cliente_id: 'UUID_DEL_CLIENTE',
    p_orden_id: 'UUID_DE_LA_ORDEN',
    p_contenedor_id: 'UUID_DEL_CONTENEDOR',
    p_cantidad_entregada: 5,
    p_cantidad_retirada: 3,
    p_creado_por: 'UUID_DEL_DESPACHADOR'
  });
  ```
- **Respuesta esperada en `data`:**
  ```json
  {
    "success": true,
    "data": {
      "movimiento_id": "UUID_DEL_REGISTRO_MOVIMIENTO"
    },
    "error": null
  }
  ```

### 2.8. Registrar RendiciÃ³n de Cuentas (`registrar_rendicion_cuentas`)
- **Firma SQL:** `registrar_rendicion_cuentas(p_cliente_id UUID, p_observaciones TEXT, p_creado_por UUID, p_ordenes JSONB, p_pagos JSONB)`
- **Uso en Frontend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('registrar_rendicion_cuentas', {
    p_cliente_id: 'UUID_DEL_CLIENTE',
    p_observaciones: 'RendiciÃ³n de la cobranza de la tarde',
    p_creado_por: 'UUID_DEL_VENDEDOR',
    p_ordenes: [
      { orden_id: 'UUID_DE_LA_ORDEN_1', monto_recaudado: 120.00 },
      { orden_id: 'UUID_DE_LA_ORDEN_2', monto_recaudado: 80.00 }
    ],
    p_pagos: [
      { fpago_id: '1a5b84c8-47bc-4ee0-880c-7833215be11b', monto: 150.00, referencia_bancaria: 'REF1234', cuenta_bancaria: '0102-XXXX', capture_url: 'storage-url' },
      { fpago_id: '4d8eb7fb-7ade-4113-bb3f-ab66548e144e', monto: 100.00, referencia_bancaria: null, cuenta_bancaria: null, capture_url: null }
    ]
  });
  ```
- **Respuesta esperada en `data`:**
  ```json
  {
    "success": true,
    "data": {
      "rendicion_id": "UUID_DE_LA_NUEVA_RENDICION",
      "total_ordenes": 200.00,
      "total_pagos": 250.00,
      "saldo_favor_generado": 50.00
    },
    "error": null
  }
  ```

### 2.9. Consulta de Registros de Formas de Pago (`consulta_registros_formas_pago`)
- **Firma SQL:** `consulta_registros_formas_pago()`
- **Uso en Frontend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('consulta_registros_formas_pago');
  ```
- **Respuesta esperada en `data`:**
  ```json
  {
    "success": true,
    "data": [
      { "fpago_id": "6fa0d91d-9c00-4335-dd5f-cd88760a366a", "fpago_concepto": "BINANCE", "fpago_info": true },
      { "fpago_id": "3c7da6ea-69de-4002-aa2e-9a55437d033d", "fpago_concepto": "Efectivo Bs", "fpago_info": false },
      { "fpago_id": "4d8eb7fb-7ade-4113-bb3f-ab66548e144e", "fpago_concepto": "Efectivo USD", "fpago_info": false },
      { "fpago_id": "1a5b84c8-47bc-4ee0-880c-7833215be11b", "fpago_concepto": "Pago movil", "fpago_info": true },
      { "fpago_id": "2b6c95d9-58cd-4ff1-991d-8944326cf22c", "fpago_concepto": "Transferencia", "fpago_info": true },
      { "fpago_id": "5e9fc80c-8bef-4224-cc4f-bc77659f255f", "fpago_concepto": "ZELLE", "fpago_info": true }
    ],
    "error": null
  }
  ```

### 2.10. MÃ³dulo de Mantenimiento de Tasas de Cambio (`tasa_cambio`)

El **MÃ³dulo de Mantenimiento de Tasas de Cambio** gestiona las tasas oficiales utilizadas en la facturaciÃ³n y cobranza en multimoneda.

#### Comportamiento Esperado del MÃ³dulo en Frontend:
1. **Carga Inicial por Defecto:** Al ingresar al mÃ³dulo, debe invocar `retorna_ultima_tasa_cambio` para mostrar la tasa mÃ¡s reciente registrada con su fecha.
2. **Registro de Nueva Tasa:** Permite ingresar una fecha y monto de tasa con `inserta_tasa_cambio`. (No permite fechas duplicadas).
3. **EliminaciÃ³n de Tasa:** Permite eliminar la tasa de una fecha con `elimina_tasa_cambio`. (Para actualizar una tasa, se debe eliminar la fecha y registrarla de nuevo).
4. **Consulta HistÃ³rica por Rango:** Permite al usuario consultar el listado de tasas en un rango de fechas con `retorna_tasas_cambio_por_rango`.

---

#### 2.10.1. Consultar Ãltima Tasa Registrada (`retorna_ultima_tasa_cambio`)
- **Firma SQL:** `retorna_ultima_tasa_cambio()`
- **Uso en Frontend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('retorna_ultima_tasa_cambio');
  ```
- **Respuesta esperada en `data`:**
  ```json
  {
    "success": true,
    "data": {
      "fecha_tasa": "2026-07-30",
      "tasa_cambio": 36.54,
      "created_at": "2026-07-30T14:00:00Z"
    },
    "error": null
  }
  ```

#### 2.10.2. Registrar Nueva Tasa (`inserta_tasa_cambio`)
- **Firma SQL:** `inserta_tasa_cambio(p_fecha_tasa DATE, p_tasa NUMERIC)`
- **Regla:** No se permiten fechas duplicadas. Si la fecha ya existe, retorna error de restricciÃ³n `FECHA_TASA_DUPLICADA`.
- **Uso en Frontend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('inserta_tasa_cambio', {
    p_fecha_tasa: '2026-07-30',
    p_tasa: 36.54
  });
  ```
- **Respuesta esperada en `data`:**
  ```json
  {
    "success": true,
    "data": {
      "fecha_tasa": "2026-07-30",
      "tasa_cambio": 36.54
    },
    "error": null
  }
  ```

#### 2.10.3. Eliminar Tasa por Fecha (`elimina_tasa_cambio`)
- **Firma SQL:** `elimina_tasa_cambio(p_fecha_tasa DATE)`
- **Uso en Frontend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('elimina_tasa_cambio', {
    p_fecha_tasa: '2026-07-30'
  });
  ```
- **Respuesta esperada en `data`:**
  ```json
  {
    "success": true,
    "data": {
      "fecha_tasa": "2026-07-30",
      "eliminado": true
    },
    "error": null
  }
  ```

#### 2.10.4. Consultar Tasas por Rango de Fechas (`retorna_tasas_cambio_por_rango`)
- **Firma SQL:** `retorna_tasas_cambio_por_rango(p_fecha_desde DATE, p_fecha_hasta DATE)`
- **Uso en Frontend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('retorna_tasas_cambio_por_rango', {
    p_fecha_desde: '2026-07-01',
    p_fecha_hasta: '2026-07-30'
  });
  ```
- **Respuesta esperada en `data`:**
  ```json
  {
    "success": true,
    "data": [
      { "fecha_tasa": "2026-07-30", "tasa_cambio": 36.54 },
      { "fecha_tasa": "2026-07-29", "tasa_cambio": 36.50 },
      { "fecha_tasa": "2026-07-28", "tasa_cambio": 36.48 }
    ],
    "error": null
  }
  ```

### 2.11. Consulta de Lista de Contenedores (`retorna_lista_contenedores`)
- **Firma SQL:** `retorna_lista_contenedores()`
- **Uso en Frontend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('retorna_lista_contenedores');
  ```
- **Respuesta esperada en `data`:**
  ```json
  {
    "success": true,
    "data": [
      { "id": "11111111-1111-1111-1111-111111111111", "nombre": "Caja PlÃ¡stica 24 Unidades" },
      { "id": "22222222-2222-2222-2222-222222222222", "nombre": "Cesta TÃ©rmica 50L" }
    ],
    "error": null
  }
  ```

### 2.12. Consulta de Lista de Rutas (`retorna_lista_rutas`)
- **Firma SQL:** `retorna_lista_rutas()`
- **Uso en Frontend / Backend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('retorna_lista_rutas');
  ```
- **Respuesta esperada en `data`:**
  ```json
  {
    "success": true,
    "total_registros": 2,
    "data": [
      {
        "id_ruta": "3a8f94c0-1122-4433-8899-aabbccdd1122",
        "nombre_ruta": "Ruta Centro - Comercial",
        "descripcion_ruta": "AtenciÃ³n a clientes del casco central",
        "created_at": "2026-08-13T12:00:00+00:00"
      },
      {
        "id_ruta": "4b9f05d1-2233-5544-9900-bbccddee2233",
        "nombre_ruta": "Ruta Norte - Industrial",
        "descripcion_ruta": null,
        "created_at": "2026-08-13T12:05:00+00:00"
      }
    ],
    "error": null
  }
  ```

### 2.13. Consulta de Usuarios Despachadores (`retorna_usuarios_despachadores`)
- **Firma SQL:** `retorna_usuarios_despachadores()`
- **Uso en Frontend / Backend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('retorna_usuarios_despachadores');
  ```
- **Respuesta esperada en `data`:**
  ```json
  {
    "success": true,
    "data": [
      {
        "id": "5c0a16e2-3344-6655-0011-ccddeeff3344",
        "nombre_completo": "Carlos PÃ©rez (Despachador)",
        "telefono": "+584141112233"
      },
      {
        "id": "6d1b27f3-4455-7766-1122-ddeeff004455",
        "nombre_completo": "JosÃ© RodrÃ­guez",
        "telefono": "+584129998877"
      }
    ],
    "error": null
  }
  ```

### 2.14. Actualizar Registro de Ruta por UUID (`actualiza_registro_rutas_segun_uuid`)
- **Firma SQL:** `actualiza_registro_rutas_segun_uuid(p_id_ruta UUID, p_nombre_ruta TEXT, p_descripcion_ruta TEXT DEFAULT NULL)`
- **Uso en Frontend / Backend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('actualiza_registro_rutas_segun_uuid', {
    p_id_ruta: '3a8f94c0-1122-4433-8899-aabbccdd1122',
    p_nombre_ruta: 'Ruta Centro - Actualizada',
    p_descripcion_ruta: 'Nueva descripciÃ³n de la ruta comercial' // Opcional / Acepta null
  });
  ```
- **Respuesta esperada en `data` (Ãxito):**
  ```json
  {
    "success": true,
    "message": "Ruta actualizada exitosamente.",
    "data": {
      "id_ruta": "3a8f94c0-1122-4433-8899-aabbccdd1122",
      "nombre_ruta": "Ruta Centro - Actualizada",
      "descripcion_ruta": "Nueva descripciÃ³n de la ruta comercial",
      "created_at": "2026-08-13T12:00:00+00:00"
    }
  }
  ```
- **Respuesta esperada en `data` (Fallo - Ruta Inexistente):**
  ```json
  {
    "success": false,
    "error": {
      "code": "RUTA_INEXISTENTE",
      "message": "No se encontrÃ³ ninguna ruta con el id_ruta especificado."
    }
  }
  ```

### 2.15. Actualizar Registro de Cliente por UUID (`actualiza_registro_cliente_segun_uuid`)
- **Firma SQL:** `actualiza_registro_cliente_segun_uuid(p_id UUID, p_rif_nit TEXT DEFAULT NULL, p_razon_social TEXT DEFAULT NULL, p_direccion_fiscal TEXT DEFAULT NULL, p_telefono TEXT DEFAULT NULL, p_movil1 TEXT DEFAULT NULL, p_movil2 TEXT DEFAULT NULL, p_movil3 TEXT DEFAULT NULL, p_correo_e TEXT DEFAULT NULL, p_cond_liq NUMERIC DEFAULT NULL, p_max_liq NUMERIC DEFAULT NULL, p_vendedor_id UUID DEFAULT NULL, p_despachador_id UUID DEFAULT NULL, p_id_ruta UUID DEFAULT NULL, p_activo BOOLEAN DEFAULT NULL)`
- **Uso en Frontend / Backend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('actualiza_registro_cliente_segun_uuid', {
    p_id: 'a1b2c3d4-e5f6-7890-abcd-1234567890ab',
    p_rif_nit: 'J-12345678-9',
    p_razon_social: 'Comercializadora Ejemplo C.A.',
    p_direccion_fiscal: 'Av. Principal, Edf. LogiTrack, Piso 3',
    p_telefono: '+582121112233',
    p_movil1: '+584141234567',
    p_correo_e: 'contacto@ejemplo.com',
    p_cond_liq: 15,
    p_max_liq: 5000,
    p_vendedor_id: '8a9b7c6d-5e4f-3a2b-1c0d-9e8f7a6b5c4d',
    p_despachador_id: '5c0a16e2-3344-6655-0011-ccddeeff3344',
    p_id_ruta: '3a8f94c0-1122-4433-8899-aabbccdd1122',
    p_activo: true
  });
  ```
- **Respuesta esperada en `data` (Ãxito):**
  ```json
  {
    "success": true,
    "message": "Cliente actualizado exitosamente.",
    "data": {
      "id": "a1b2c3d4-e5f6-7890-abcd-1234567890ab",
      "rif_nit": "J-12345678-9",
      "razon_social": "Comercializadora Ejemplo C.A.",
      "direccion_fiscal": "Av. Principal, Edf. LogiTrack, Piso 3",
      "telefono": "+582121112233",
      "movil1": "+584141234567",
      "movil2": null,
      "movil3": null,
      "correo_e": "contacto@ejemplo.com",
      "cond_liq": 15,
      "max_liq": 5000,
      "vendedor_id": "8a9b7c6d-5e4f-3a2b-1c0d-9e8f7a6b5c4d",
      "despachador_id": "5c0a16e2-3344-6655-0011-ccddeeff3344",
      "id_ruta": "3a8f94c0-1122-4433-8899-aabbccdd1122",
      "activo": true,
      "created_at": "2026-08-01T10:00:00+00:00"
    }
  }
  ```
- **Respuesta esperada en `data` (Fallo - Cliente Inexistente):**
  ```json
  {
    "success": false,
    "error": {
      "code": "CLIENTE_INEXISTENTE",
      "message": "No se encontrÃ³ ningÃºn cliente con el ID especificado."
    }
  }
  ```

### 2.16. Consulta de Radar del Despachador (`retorna_radar_despachador`)
- **Firma SQL:** `retorna_radar_despachador()`
- **Uso en Frontend / Backend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('retorna_radar_despachador');
  ```
- **Respuesta esperada en `data` (Ãxito):**
  ```json
  {
    "success": true,
    "total_ordenes": 1,
    "data": [
      {
        "orden_id": "b2c3d4e5-f6a7-8901-bcde-234567890abc",
        "correlativo": 1025,
        "estado": "en_transito",
        "fecha_despacho": "2026-08-14T08:00:00+00:00",
        "tasa_cambio": 36.50,
        "total_recaudar_bs": 1825.00,
        "total_recaudar_usd": 50.00,
        "cliente": {
          "id": "a1b2c3d4-e5f6-7890-abcd-1234567890ab",
          "razon_social": "Comercializadora Ejemplo C.A.",
          "rif_nit": "J-12345678-9",
          "direccion_fiscal": "Av. Principal, Edf. LogiTrack, Piso 3",
          "telefono": "+582121112233",
          "movil1": "+584141234567",
          "nombre_ruta": "Ruta Centro"
        },
        "detalles": [
          {
            "detalle_id": "c3d4e5f6-a7b8-9012-cdef-34567890abcd",
            "producto_id": "d4e5f6a7-b8c9-0123-def0-4567890abcde",
            "codigo_producto": "PROD-001",
            "nombre_producto": "Harina Pan 1kg",
            "cantidad_solicitada": 10,
            "cantidad_despachada": 0,
            "valor_unitario_recaudar": 182.50,
            "subtotal_recaudar": 1825.00,
            "valor_unitario_usd": 5.00,
            "subtotal_recaudar_usd": 50.00,
            "estado_entrega": "pendiente",
            "motivo_rechazo": null,
            "contenedores_retirados": 0,
            "contenedor_id": null
          }
        ],
        "saldo_contenedores": [
          {
            "contenedor_id": "e5f6a7b8-c9d0-1234-ef01-567890abcdef",
            "nombre_contenedor": "Cesta PlÃ¡stica EstÃ¡ndar",
            "saldo_pendiente": 5
          }
        ]
      }
    ]
  }
  ```

### 2.17. Registrar Despacho de Cliente en Radar (`registrar_despacho_cliente_radar`)
- **Firma SQL:** `registrar_despacho_cliente_radar(p_orden_id UUID, p_detalles_json JSONB)`
- **Uso en Frontend / Backend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('registrar_despacho_cliente_radar', {
    p_orden_id: 'b2c3d4e5-f6a7-8901-bcde-234567890abc',
    p_detalles_json: [
      {
        detalle_id: 'c3d4e5f6-a7b8-9012-cdef-34567890abcd',
        cantidad_despachada: 8,
        estado_entrega: 'entregado_parcial',
        motivo_rechazo: 'Cliente no requerÃ­a las 2 unidades sobrantes',
        contenedores_retirados: 5,
        contenedor_id: 'e5f6a7b8-c9d0-1234-ef01-567890abcdef'
      }
    ]
  });
  ```
- **Respuesta esperada en `data` (Ãxito):**
  ```json
  {
    "success": true,
    "message": "Despacho registrado en radar exitosamente.",
    "data": {
      "orden_id": "b2c3d4e5-f6a7-8901-bcde-234567890abc",
      "nuevo_estado_orden": "despachada"
    }
  }
  ```

### 2.18. AprobaciÃ³n de Despacho por Gerencia / AlmacÃ©n (`aprobar_despacho_orden_distribucion`)
- **Firma SQL:** `aprobar_despacho_orden_distribucion(p_orden_id UUID)`
- **Uso en Frontend / Backend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('aprobar_despacho_orden_distribucion', {
    p_orden_id: 'b2c3d4e5-f6a7-8901-bcde-234567890abc'
  });
  ```
- **Respuesta esperada en `data` (Ãxito):**
  ```json
  {
    "success": true,
    "message": "Despacho de orden aprobado exitosamente. Orden pasa a estado por_liquidar.",
    "data": {
      "orden_id": "b2c3d4e5-f6a7-8901-bcde-234567890abc",
      "nuevo_estado": "por_liquidar"
    }
  }
  ```

### 2.19. Crear u Obtener Radar por Despachador y Fecha (`crear_o_obtener_radar`)
- **Firma SQL:** `crear_o_obtener_radar(p_despachador_id UUID DEFAULT NULL, p_fecha_despacho DATE DEFAULT CURRENT_DATE)`
- **Uso en Frontend / Backend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('crear_o_obtener_radar', {
    p_despachador_id: '5c0a16e2-3344-6655-0011-ccddeeff3344', // Opcional (toma auth.uid() si es null)
    p_fecha_despacho: '2026-08-31' // Opcional (toma CURRENT_DATE si es null)
  });
  ```
- **Respuesta esperada en `data` (Ãxito):**
  ```json
  {
    "success": true,
    "message": "Radar obtenido/creado exitosamente.",
    "data": {
      "id": "e1f2a3b4-c5d6-7890-ef01-234567890abc",
      "correlativo": 1,
      "despachador_id": "5c0a16e2-3344-6655-0011-ccddeeff3344",
      "fecha_despacho": "2026-08-31",
      "status_radar": false,
      "total_cantidad_solicitada": 150,
      "total_cantidad_despachada": 0,
      "total_contenedores_retirados": 0,
      "total_ordenes": 3
    }
  }
  ```

### 2.20. Reporte Detallado del Radar (`retorna_radar_detalle_reporte`)
- **Firma SQL:** `retorna_radar_detalle_reporte(p_radar_id UUID)`
- **Uso en Frontend / Backend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('retorna_radar_detalle_reporte', {
    p_radar_id: 'e1f2a3b4-c5d6-7890-ef01-234567890abc'
  });
  ```
- **Respuesta esperada en `data` (Ãxito):**
  ```json
  {
    "success": true,
    "data": {
      "radar": {
        "id": "e1f2a3b4-c5d6-7890-ef01-234567890abc",
        "correlativo": 1,
        "fecha_despacho": "2026-08-31",
        "status_radar": false,
        "total_cantidad_solicitada": 150,
        "total_cantidad_despachada": 0,
        "total_contenedores_retirados": 0,
        "created_at": "2026-08-31T15:30:00+00:00"
      },
      "despachador": {
        "id": "5c0a16e2-3344-6655-0011-ccddeeff3344",
        "nombre_completo": "Carlos PÃ©rez",
        "telefono": "+584141112233",
        "correo_e": "carlos.perez@logitrack.com"
      },
      "resumen_productos": [
        {
          "producto_id": "d4e5f6a7-b8c9-0123-def0-4567890abcde",
          "codigo_producto": "PROD-001",
          "nombre_producto": "Harina Pan 1kg",
          "imagen_path": "/productos/harina-pan.webp",
          "cantidad_solicitada": 100,
          "cantidad_despachada": 0
        }
      ],
      "ordenes": [...]
    }
  }
  ```

### 2.21. Reasignar Orden a un Nuevo Radar (`reasignar_orden_a_radar`)
- **Firma SQL:** `reasignar_orden_a_radar(p_orden_id UUID, p_nuevo_radar_id UUID DEFAULT NULL, p_nueva_fecha DATE DEFAULT NULL)`
- **Uso en Frontend / Backend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('reasignar_orden_a_radar', {
    p_orden_id: 'b2c3d4e5-f6a7-8901-bcde-234567890abc',
    p_nuevo_radar_id: 'f2a3b4c5-d6e7-8901-2345-67890abcdef1',
    p_nueva_fecha: '2026-09-01'
  });
  ```
- **Respuesta esperada en `data` (Ãxito):**
  ```json
  {
    "success": true,
    "message": "Orden reasignada exitosamente.",
    "data": {
      "orden_id": "b2c3d4e5-f6a7-8901-bcde-234567890abc",
      "radar_id": "f2a3b4c5-d6e7-8901-2345-67890abcdef1",
      "fecha_despacho": "2026-09-01"
    }
  }
  ```

### 2.22. Guardar Resultado del Despacho del Radar (`guardar_resultado_despacho_radar`)
- **Firma SQL:** `guardar_resultado_despacho_radar(p_radar_id UUID, p_despacho_json JSONB)`
- **Uso en Frontend / Backend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('guardar_resultado_despacho_radar', {
    p_radar_id: 'e1f2a3b4-c5d6-7890-ef01-234567890abc',
    p_despacho_json: {
      "ordenes": [
        {
          "orden_id": "b2c3d4e5-f6a7-8901-bcde-234567890abc",
          "detalles": [
            {
              "detalle_id": "c3d4e5f6-a7b8-9012-cdef-34567890abcd",
              "cantidad_despachada": 10,
              "estado_entrega": "entregado",
              "motivo_rechazo": null,
              "contenedores_retirados": 2,
              "contenedor_id": "e5f6a7b8-c9d0-1234-ef01-567890abcdef"
            }
          ]
        }
      ]
    }
  });
  ```
- **Respuesta esperada en `data` (Ãxito):**
  ```json
  {
    "success": true,
    "message": "Resultado del despacho registrado en el radar exitosamente.",
    "data": {
      "radar_id": "e1f2a3b4-c5d6-7890-ef01-234567890abc",
      "status_radar": true,
      "total_cantidad_solicitada": 150,
      "total_cantidad_despachada": 145,
      "total_contenedores_retirados": 12
    }
  }
  ```

### 2.23. Otorgar ExcepciÃ³n Gerencial de Despacho (`otorgar_excepcion_despacho_gerencia`)
- **Firma SQL:** `otorgar_excepcion_despacho_gerencia(p_cliente_id UUID)`
- **Permisos:** Exclusivo para usuarios autenticados con rol `gerente` o `admin`.
- **DescripciÃ³n:** Permite a la Gerencia autorizar de manera extraordinaria un **Ãºnico despacho** para un cliente que se encuentra bloqueado por polÃ­tica de crÃ©dito. Una vez completado el despacho en el Radar, el permiso se consume y desactiva automÃ¡ticamente.
- **Uso en Frontend / Backend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('otorgar_excepcion_despacho_gerencia', {
    p_cliente_id: 'a1b2c3d4-e5f6-7890-abcd-1234567890ab'
  });
  ```
- **Respuesta esperada en `data` (Ãxito):**
  ```json
  {
    "success": true,
    "message": "ExcepciÃ³n de despacho otorgada exitosamente por gerencia (VÃ¡lida por 1 despacho).",
    "data": {
      "cliente_id": "a1b2c3d4-e5f6-7890-abcd-1234567890ab",
      "excepcion_despacho_gerencia": true
    }
  }
  ```

### 2.24. Consulta de Abonos u Ãrdenes Pendientes del Cliente (`solicita_abonos_orden_distribucion`)
- **Firma SQL:** `solicita_abonos_orden_distribucion(p_cliente_id UUID)`
- **DescripciÃ³n:** Obtiene el saldo a favor actual del cliente y la lista de sus Ã³rdenes en estado `por_liquidar` con el total de abonos acumulados aprobados a la fecha y el saldo pendiente.
- **Uso en Frontend / Backend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('solicita_abonos_orden_distribucion', {
    p_cliente_id: 'a1b2c3d4-e5f6-7890-abcd-1234567890ab'
  });
  ```
- **Respuesta esperada en `data` (Ãxito):**
  ```json
  {
    "success": true,
    "data": {
      "cliente_id": "a1b2c3d4-e5f6-7890-abcd-1234567890ab",
      "saldo_favor": 150.00,
      "ordenes": [
        {
          "orden_id": "b2c3d4e5-f6a7-8901-bcde-234567890abc",
          "correlativo": 1025,
          "fecha_despacho": "2026-08-14",
          "monto_total_orden": 500.00,
          "abonos_acumulados": 200.00,
          "saldo_pendiente": 300.00
        }
      ]
    },
    "error": null
  }
  ```

### 2.25. Reporte Gerencial de Recaudaciones (`reporte_recaudaciones_gerenciales`)
- **Firma SQL:** `reporte_recaudaciones_gerenciales(p_fecha_desde DATE DEFAULT NULL, p_fecha_hasta DATE DEFAULT NULL)`
- **DescripciÃ³n:** Genera el reporte consolidado de rendiciones de cuentas procesadas en un rango de fechas con desglose por cliente, vendedor/auditor, mÃ©todo de pago y Ã³rdenes abonadas.
- **Uso en Frontend / Backend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('reporte_recaudaciones_gerenciales', {
    p_fecha_desde: '2026-09-01',
    p_fecha_hasta: '2026-09-30'
  });
  ```
- **Respuesta esperada en `data` (Ãxito):**
  ```json
  {
    "success": true,
    "data": [
      {
        "rendicion_id": "c1d2e3f4-a5b6-7890-cdef-1234567890ab",
        "fecha_rendicion": "2026-09-08T11:00:00Z",
        "tasa_cambio": 50.00,
        "cliente_id": "a1b2c3d4-e5f6-7890-abcd-1234567890ab",
        "cliente_nombre": "Comercializadora Ejemplo C.A.",
        "cliente_rif": "J-12345678-9",
        "estado": "aprobada",
        "total_efectivo_recaudado": 100.00,
        "total_transferencias_recaudado": 200.00,
        "total_recaudado_usd": 300.00,
        "total_recaudado_bs": 15000.00,
        "observaciones": "Cobranza ruta centro",
        "detalle_fpagos": [
          { "fpago_id": "...", "concepto": "Pago movil", "monto": 200.00, "monto_bs": 10000.00, "monto_usd": 200.00, "cuenta_bancaria": "0102-XXXX" }
        ],
        "detalle_ordenes": [
          { "orden_id": "...", "correlativo": 1025, "recaudado": 300.00, "recaudado_bs": 15000.00 }
        ]
      }
    ],
    "error": null
  }
  ```

### 2.26. Crear Cuenta Bancaria de la Empresa (`crear_cuenta_bancaria_empresa`)
- **Firma SQL:** `crear_cuenta_bancaria_empresa(p_cuenta_bancaria TEXT, p_entidad_bancaria TEXT)`
- **Uso en Frontend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('crear_cuenta_bancaria_empresa', {
    p_cuenta_bancaria: '0102-0123-45-6789012345',
    p_entidad_bancaria: 'Banco de Venezuela'
  });
  ```

### 2.27. Actualizar Cuenta Bancaria de la Empresa (`actualizar_cuenta_bancaria_empresa`)
- **Firma SQL:** `actualizar_cuenta_bancaria_empresa(p_id UUID, p_cuenta_bancaria TEXT DEFAULT NULL, p_entidad_bancaria TEXT DEFAULT NULL, p_status_cuenta BOOLEAN DEFAULT NULL)`
- **Uso en Frontend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('actualizar_cuenta_bancaria_empresa', {
    p_id: 'UUID_CUENTA',
    p_cuenta_bancaria: '0105-0987-65-4321098765',
    p_entidad_bancaria: 'Mercantil Banco',
    p_status_cuenta: true
  });
  ```

### 2.28. Cambiar Estatus / Suspender Cuenta Bancaria (`cambiar_status_cuenta_bancaria_empresa`)
- **Firma SQL:** `cambiar_status_cuenta_bancaria_empresa(p_id UUID, p_status_cuenta BOOLEAN)`
- **Uso en Frontend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('cambiar_status_cuenta_bancaria_empresa', {
    p_id: 'UUID_CUENTA',
    p_status_cuenta: false // false para suspender / dar de baja, true para reactivar
  });
  ```

### 2.29. Consultar Cuentas Bancarias de la Empresa (`retorna_cuentas_bancarias_empresa`)
- **Firma SQL:** `retorna_cuentas_bancarias_empresa(p_solo_activas BOOLEAN DEFAULT TRUE)`
- **Uso en Frontend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('retorna_cuentas_bancarias_empresa', {
    p_solo_activas: true
  });
  ```

### 2.30. Lista de Radares segÃºn Rango de Fechas (`retorna_lista_radars_segun_rango_fechas`)
- **Firma SQL:** `retorna_lista_radars_segun_rango_fechas(p_despachador_id UUID DEFAULT NULL, p_fecha_inicial DATE DEFAULT NULL, p_fecha_limite DATE DEFAULT NULL)`
- **DescripciÃ³n:** Retorna el listado de radares asignados a un despachador ordenados por fecha descendente en un rango de fechas especificado, incluyendo paradas (Ã³rdenes), unidades despachadas (items), tipos de productos (SKU) y estado del radar (`status_radar = true` indica cerrado, `status_radar = false` indica abierto).
- **Uso en Frontend / Backend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('retorna_lista_radars_segun_rango_fechas', {
    p_despachador_id: 'a1b2c3d4-e5f6-7890-abcd-1234567890ab', // Opcional (si se omite usa auth.uid())
    p_fecha_inicial: '2026-08-01',
    p_fecha_limite: '2026-08-31'
  });
  ```
- **Respuesta esperada en `data` (Ãxito):**
  ```json
  {
    "success": true,
    "data": [
      {
        "fecha_despacho": "2026-08-25",
        "id_radar": "f1e2d3c4-b5a6-7890-1234-567890abcdef",
        "correlativo": 48,
        "total_paradas": 12,
        "items": 320,
        "sku": 2,
        "status_radar": true
      }
    ],
    "error": null
  }
  ```

### 2.31. Detalle Resumido de Ãrdenes por Radar ID (`retorna_ordenes_distribucion_segun_idradar`)
- **Firma SQL:** `retorna_ordenes_distribucion_segun_idradar(p_radar_id UUID)`
- **DescripciÃ³n:** Retorna el detalle resumido de las Ã³rdenes contenidas dentro de un radar especÃ­fico identificado por su `p_radar_id`.
- **Uso en Frontend / Backend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('retorna_ordenes_distribucion_segun_idradar', {
    p_radar_id: 'f1e2d3c4-b5a6-7890-1234-567890abcdef'
  });
  ```
- **Respuesta esperada en `data` (Ãxito):**
  ```json
  {
    "success": true,
    "data": [
      {
        "id_orden_distribucion": "b1a2c3d4-e5f6-7890-abcd-1234567890ab",
        "correlativo": 1024,
        "ruta": "Ruta Centro 01",
        "razon_social": "Supermercado El Ejemplo C.A.",
        "direccion_fiscal": "Av. Principal #123, Caracas"
      }
    ],
    "error": null
  }
  ```

### 2.32. Cuentas por Liquidar agrupadas por Cliente (`retorna_ordenes_por_liquidar`)
- **Firma SQL:** `retorna_ordenes_por_liquidar()`
- **DescripciÃ³n:** Retorna la lista de Ã³rdenes en estado `por_liquidar` agrupadas por cliente y ordenadas por la mayor cantidad de dÃ­as vencidos desde su fecha de despacho (`dias_vencidos DESC`).
- **Uso en Frontend / Backend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('retorna_ordenes_por_liquidar');
  ```
- **Respuesta esperada en `data` (Ãxito):**
  ```json
  {
    "success": true,
    "data": [
      {
        "cliente_id": "a1b2c3d4-e5f6-7890-abcd-1234567890ab",
        "razon_social": "Comercializadora Ejemplo C.A.",
        "rif_nit": "J-12345678-9",
        "dias_vencidos": 28,
        "cant_ordenes": 1,
        "monto_por_liquidar": 1200.00
      },
      {
        "cliente_id": "b2c3d4e5-f6a7-8901-bcde-234567890abc",
        "razon_social": "Distribuidora Los Andes S.A.",
        "rif_nit": "J-98765432-1",
        "dias_vencidos": 7,
        "cant_ordenes": 1,
        "monto_por_liquidar": 800.00
      }
    ],
    "error": null
  }
  ```

### 2.33. AprobaciÃ³n Gerencial de Radar (`solicita_aprobar_radar`)
- **Firma SQL:** `solicita_aprobar_radar(p_radar_id UUID)`
- **DescripciÃ³n:** Aprueba el radar (`status_radar = true`), liquida los envases entregados (`CEIL(cantidad_despachada * unidades_por_contenedor)`) y envases retirados acreditÃ¡ndolos al estado de cuenta del cliente (`saldo_contenedores_clientes`), evalÃºa las polÃ­ticas de crÃ©dito deshabilitando `permiso_despacho_manual` si `ordenes_por_liquidar >= max_facturas_vencidas`, restituye la mercancÃ­a no entregada al almacÃ©n principal (`productos.stock_disponible`) y transiciona automÃ¡ticamente todas las Ã³rdenes en estado `devuelta` a `anulada`.
- **Uso en Frontend / Backend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('solicita_aprobar_radar', {
    p_radar_id: 'f1e2d3c4-b5a6-7890-1234-567890abcdef'
  });
  ```
- **Respuesta esperada en `data` (Ãxito):**
  ```json
  {
    "success": true,
    "message": "Radar aprobado exitosamente. Saldos de contenedores actualizados, polÃ­ticas de crÃ©dito evaluadas, inventario restituido a almacÃ©n y Ã³rdenes devueltas anuladas.",
    "data": {
      "radar_id": "f1e2d3c4-b5a6-7890-1234-567890abcdef",
      "status_radar": true,
      "contenedores_entregados_procesados": 25,
      "contenedores_retirados_procesados": 15,
      "clientes_deshabilitados_credito": 1,
      "ordenes_anuladas": 2,
      "inventario_reintegrado": [
        { "producto_id": "...", "codigo_producto": "HAR-001", "nombre_producto": "Harina PAN", "cantidad_devuelta": 50 }
      ]
    },
    "error": null
  }
  ```


### 2.35. Reglas de CÃ¡lculo y ConversiÃ³n Multimoneda en Ãrdenes de DistribuciÃ³n
- **DescripciÃ³n:** Los precios base de lista de productos en LogiTrack estÃ¡n cotizados en **USD** (`precio_lista1` en `productos`). Al crear (`crear_orden_distribucion`) o actualizar (`actualiza_orden_distribucion_segun_correlativo`) una orden:
  - Las Ã³rdenes de distribuciÃ³n siempre nacen en estado por liquidar (o aprobadas/pendientes). Debido a que la tasa de cambio puede variar al momento de la liquidaciÃ³n final, los montos en BolÃ­vares (`valor_unitario_recaudar`, `subtotal_recaudar` y `total_recaudar_bs`) se registran como `NULL` para evitar confusiones.
  - `valor_unitario_usd`: Es el precio unitario del producto en USD (tomado de `precio_lista1` o parÃ¡metro explÃ­cito).
  - `subtotal_recaudar_usd`: Suma en USD por lÃ­nea de producto (`cantidad * valor_unitario_usd`).
  - `total_recaudar_usd`: Suma total en USD de la cabecera de la orden (`SUM(subtotal_recaudar_usd)`).
  - `valor_unitario_recaudar`, `subtotal_recaudar`, `total_recaudar_bs`: Se registran en `NULL` durante la creaciÃ³n/ediciÃ³n y se determinan al liquidar la orden.

### 2.36. Registro de Nuevo Producto (`registra_nuevo_producto_retorna_id`)
- **Firma SQL:** `registra_nuevo_producto_retorna_id(p_codigo_producto TEXT, p_nombre TEXT, p_codigo_barras TEXT DEFAULT NULL, p_descripcion TEXT DEFAULT NULL, p_cant_unidad_medida NUMERIC DEFAULT NULL, p_precio_lista1 NUMERIC DEFAULT 0, p_precio_lista2 NUMERIC DEFAULT 0, p_precio_lista3 NUMERIC DEFAULT 0, p_contenedor_id UUID DEFAULT NULL, p_unidades_por_contenedor NUMERIC DEFAULT 1, p_imagen_path TEXT DEFAULT NULL)`
- **DescripciÃ³n:** Registra un nuevo producto en la tabla `public.productos` y devuelve el `UUID` generado. Si `p_codigo_barras` viene vacÃ­o o con espacios, se guarda automÃ¡ticamente como `NULL` para evitar violaciones de la restricciÃ³n de unicidad (`UNIQUE`).
- **Uso en Frontend / Backend (RPC):**
  ```typescript
  const { data: productoId, error } = await supabase.rpc('registra_nuevo_producto_retorna_id', {
    p_codigo_producto: 'HAR-001',
    p_nombre: 'Harina PAN 1kg',
    p_codigo_barras: '7591000123456', // opcional / null
    p_descripcion: 'Harina de maÃ­z blanco precozida', // opcional / null
    p_cant_unidad_medida: 1, // opcional / null
    p_precio_lista1: 1.20, // opcional, default 0
    p_precio_lista2: 1.10, // opcional, default 0
    p_precio_lista3: 1.00, // opcional, default 0
    p_contenedor_id: 'uuid-del-contenedor', // opcional / null
    p_unidades_por_contenedor: 20, // opcional, default 1
    p_imagen_path: '/productos/harina.png' // opcional / null
  });
  ```
- **Respuesta esperada en `data` (Ãxito):**
  ```json
  "a1b2c3d4-e5f6-7890-abcd-1234567890ab"
  ```

### 2.37. ActualizaciÃ³n de Registro de Producto (`actualizar_registro_productos_segun_id`)
- **Firma SQL:** `actualizar_registro_productos_segun_id(p_id UUID, p_codigo_producto TEXT, p_nombre TEXT, p_codigo_barras TEXT DEFAULT NULL, p_precio_lista1 NUMERIC DEFAULT 0, p_precio_lista2 NUMERIC DEFAULT 0, p_precio_lista3 NUMERIC DEFAULT 0, p_descripcion TEXT DEFAULT NULL, p_cant_unidad_medida NUMERIC DEFAULT NULL, p_contenedor_id UUID DEFAULT NULL, p_unidades_por_contenedor NUMERIC DEFAULT 1, p_imagen_path TEXT DEFAULT NULL)`
- **DescripciÃ³n:** Actualiza la informaciÃ³n de un producto existente identificado por `p_id`. Si `p_codigo_barras` viene vacÃ­o o con espacios, se convierte a `NULL`.
- **Uso en Frontend / Backend (RPC):**
  ```typescript
  const { data: exito, error } = await supabase.rpc('actualizar_registro_productos_segun_id', {
    p_id: 'a1b2c3d4-e5f6-7890-abcd-1234567890ab',
    p_codigo_producto: 'HAR-001',
    p_nombre: 'Harina PAN 1kg Modificada',
    p_codigo_barras: '7591000123456',
    p_precio_lista1: 1.25,
    p_precio_lista2: 1.15,
    p_precio_lista3: 1.05,
    p_descripcion: 'Harina de maÃ­z blanco enriquecida',
    p_cant_unidad_medida: 1,
    p_contenedor_id: 'uuid-del-contenedor',
    p_unidades_por_contenedor: 24,
    p_imagen_path: '/productos/harina_v2.png'
  });
  ```
- **Respuesta esperada en `data` (Ãxito):**
  ```json
  true
  ```

### 2.38. Solicitar AprobaciÃ³n del Radar (`solicita_aprobar_radar`)
- **Firma SQL:** `solicita_aprobar_radar(p_radar_id UUID)`
- **DescripciÃ³n:** Aprueba y cierra un radar de despacho (`status_radar = true`). Ejecuta de forma atÃ³mica:
  1. Registra movimientos de contenedores/envases entregados y retirados en `movimientos_contenedores` y actualiza `saldo_contenedores_clientes`.
  2. **Movimiento Doble de Inventario:** Restituye la mercancÃ­a no despachada (Ã³rdenes devueltas), **descontÃ¡ndola del inventario mÃ³vil del camiÃ³n (`inventario_movil`)** e **incrementando de vuelta el stock en el almacÃ©n principal (`inventario_almacen.stock_disponible`)**.
  3. Transiciona las Ã³rdenes completamente devueltas a estado `anulada`.
  4. Mantiene activos a todos los clientes involucrados sin aplicar bloqueos morosos temporales.
- **Uso en Frontend / Backend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('solicita_aprobar_radar', {
    p_radar_id: 'e1f2a3b4-c5d6-7890-ef01-234567890abc'
  });
  ```
- **Respuesta esperada en `data` (Ãxito):**
  ```json
  {
    "success": true,
    "message": "Radar aprobado exitosamente. Saldos de contenedores actualizados, inventario restituido a almacÃ©n y Ã³rdenes devueltas anuladas.",
    "data": {
      "radar_id": "e1f2a3b4-c5d6-7890-ef01-234567890abc",
      "status_radar": true,
      "contenedores_entregados_procesados": 12,
      "contenedores_retirados_procesados": 8,
      "clientes_deshabilitados_credito": 0,
      "ordenes_anuladas": 1,
      "inventario_reintegrado": [
        {
          "producto_id": "d4e5f6a7-b8c9-0123-def0-4567890abcde",
          "codigo_producto": "PROD-001",
          "nombre_producto": "Harina Pan 1kg",
          "cantidad_devuelta": 5
        }
      ]
    },
    "error": null
  }
### 2.39. Actualizar / Editar Orden de DistribuciÃ³n por Correlativo (`actualiza_orden_distribucion_segun_correlativo`)
- **Firma SQL:** `actualiza_orden_distribucion_segun_correlativo(p_correlativo INT, p_header JSONB, p_detalle JSONB)`
- **DescripciÃ³n:** Permite la actualizaciÃ³n y modificaciÃ³n de cabecera y detalles de Ã³rdenes de distribuciÃ³n que se encuentren en estado **`aprobada`** (o `borrador`). Permite ajustar cliente, camiÃ³n, fecha de despacho, factura de origen y la lista de productos solicitados.
- **Uso en Frontend / Backend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('actualiza_orden_distribucion_segun_correlativo', {
    p_correlativo: 105,
    p_header: {
      cliente_id: 'a1b2c3d4-e5f6-7890-abcd-1234567890ab',
      camion_id: 'c1d2e3f4-a5b6-7890-cdef-1234567890cd',
      fecha_despacho: '2026-09-15T08:00:00Z',
      factura_origen_numero: 'FAC-000105'
    },
    p_detalle: [
      {
        producto_id: 'd4e5f6a7-b8c9-0123-def0-4567890abcde',
        cantidad_solicitada: 15,
        valor_unitario_usd: 5.00
      }
    ]
  });
  ```
- **Respuesta esperada en `data` (Ãxito):**
  ```json
  {
    "success": true,
    "data": {
      "correlativo": 105,
      "orden_id": "b2c3d4e5-f6a7-8901-bcde-234567890abc",
      "tasa_cambio": 50.25,
      "total_recaudar_bs": null,
      "total_recaudar_usd": 75.00
    },
    "error": null
  }
  ```

---

### 2.40. Registro de Venta en Ruta AutoVenta (`registrar_venta_en_ruta_autoventa`)
- **Firma SQL:** `registrar_venta_en_ruta_autoventa(p_vendedor_id UUID, p_cliente_id UUID, p_camion_id UUID, p_productos_json JSONB, p_contenedores_json JSONB DEFAULT '[]'::jsonb, p_observaciones TEXT DEFAULT NULL, p_tasa_cambio NUMERIC DEFAULT NULL)`
- **DescripciÃ³n:** Registra una venta en caliente directamente desde el camiÃ³n en ruta (AutoVenta sin radar). Genera la orden en estado `por_liquidar`, valida la existencia del stock en `inventario_movil` del camiÃ³n, descuenta el stock entregado y asienta el movimiento de envases/contenedores prestados y retirados.
- **Uso en Frontend / Backend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('registrar_venta_en_ruta_autoventa', {
    p_vendedor_id: 'a1b2c3d4-e5f6-7890-abcd-1234567890ab',
    p_cliente_id: 'b2c3d4e5-f6a7-8901-bcde-234567890abc',
    p_camion_id: 'c3d4e5f6-a7b8-9012-cdef-34567890abcd',
    p_productos_json: [
      { producto_id: 'd4e5f6a7-b8c9-0123-def0-4567890abcde', cantidad: 10, precio_unitario: 5.00 }
    ],
    p_contenedores_json: [
      { contenedor_id: 'e5f6a7b8-c9d0-1234-ef01-567890abcdef', cantidad_entregada: 2, cantidad_retirada: 1 }
    ],
    p_observaciones: 'Venta realizada en ruta'
  });
  ```
- **Respuesta esperada en `data` (Ãxito):**
  ```json
  {
    "success": true,
    "message": "Venta en ruta (AutoVenta) registrada exitosamente.",
    "data": {
      "orden_id": "f6a7b8c9-d0e1-2345-f012-67890abcdef1",
      "correlativo": 1050,
      "factura_origen_numero": "AV-001050",
      "cliente_id": "b2c3d4e5-f6a7-8901-bcde-234567890abc",
      "camion_id": "c3d4e5f6-a7b8-9012-cdef-34567890abcd",
      "estado": "por_liquidar",
      "es_autoventa": true,
      "total_recaudar_usd": 50.00,
      "total_recaudar_bs": 2500.00,
      "tasa_cambio": 50.00
    },
    "error": null
  }
  ```

---

### 2.41. Resumen de Jornada AutoVentas (`retorna_resumen_autoventas_jornada`)
- **Firma SQL:** `retorna_resumen_autoventas_jornada(p_camion_id UUID, p_fecha DATE DEFAULT CURRENT_DATE)`
- **DescripciÃ³n:** Devuelve el resumen consolidado de la jornada activa de AutoVentas para un camiÃ³n: inventario cargado, vendido y disponible por producto, mÃ¡s el resumen financiero de facturas registradas en la ruta.
- **Uso en Frontend / Backend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('retorna_resumen_autoventas_jornada', {
    p_camion_id: 'c3d4e5f6-a7b8-9012-cdef-34567890abcd',
    p_fecha: '2026-09-17'
  });
  ```
- **Respuesta esperada en `data` (Ãxito):**
  ```json
  {
    "success": true,
    "data": {
      "camion_id": "c3d4e5f6-a7b8-9012-cdef-34567890abcd",
      "fecha": "2026-09-17",
      "total_ordenes_autoventa": 5,
      "total_facturado_usd": 450.00,
      "total_facturado_bs": 22500.00,
      "inventario_movil": [
        {
          "producto_id": "d4e5f6a7-b8c9-0123-def0-4567890abcde",
          "codigo": "PROD-001",
          "nombre": "Harina Pan 1kg",
          "cantidad_cargada": 100,
          "cantidad_entregada": 40,
          "cantidad_disponible": 60
        }
      ],
      "ventas": [
        {
          "orden_id": "f6a7b8c9-d0e1-2345-f012-67890abcdef1",
          "correlativo": 1050,
          "factura_origen_numero": "AV-001050",
          "cliente_nombre": "Comercializadora Ejemplo C.A.",
          "estado": "por_liquidar",
          "total_recaudar_usd": 50.00,
          "total_recaudar_bs": 2500.00,
          "created_at": "2026-09-17T14:30:00Z"
        }
      ]
    },
    "error": null
  }
  ```

---

### 2.42. Reporte Gerencial de Formas de Pago por Rango de Fecha (`reporte_formas_pago_rendicion`)
- **Firma SQL:** `reporte_formas_pago_rendicion(p_fecha_desde DATE DEFAULT NULL, p_fecha_hasta DATE DEFAULT NULL, p_solo_bancarios BOOLEAN DEFAULT FALSE)`
- **DescripciÃ³n:** Genera la consulta detallada e informe gerencial de las Formas de Pago recibidas en rendiciones de cuentas aprobadas durante un rango de fechas. Soporta filtrado exclusivo de transacciones bancarias/electrÃ³nicas (donde `es_bancario = TRUE`: Pago MÃ³vil, Transferencia, Zelle, Binance).
- **Uso en Frontend / Backend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('reporte_formas_pago_rendicion', {
    p_fecha_desde: '2026-09-01',
    p_fecha_hasta: '2026-09-30',
    p_solo_bancarios: true
  });
  ```
- **Respuesta esperada en `data` (Ãxito):**
  ```json
  {
    "success": true,
    "data": {
      "fecha_desde": "2026-09-01",
      "fecha_hasta": "2026-09-30",
      "solo_bancarios": true,
      "total_registros": 12,
      "monto_total_bs": 45000.00,
      "monto_total_usd": 900.00,
      "movimientos": [
        {
          "rendicion_id": "c1d2e3f4-a5b6-7890-cdef-1234567890ab",
          "fecha_rendicion": "2026-09-15T10:30:00Z",
          "tasa_cambio": 50.00,
          "cliente_id": "a1b2c3d4-e5f6-7890-abcd-1234567890ab",
          "cliente_nombre": "Comercializadora Ejemplo C.A.",
          "cliente_rif": "J-12345678-9",
          "fpago_id": "1a5b84c8-47bc-4ee0-880c-7833215be11b",
          "fpago_concepto": "Pago movil",
          "es_bancario": true,
          "referencia_bancaria": "REF-987654",
          "cuenta_bancaria": "0102-XXXX",
          "capture_url": null,
          "monto_bs": 10000.00,
          "monto_usd": 200.00
        }
      ]
    },
    "error": null
  }
  ```

---

## 3. CÃ³digos de Error Comunes para Control en Frontend

Cuando `success` sea `false`, el frontend puede leer `error.code` para disparar notificaciones o flujos condicionales especÃ­ficos. AquÃ­ tienes la lista de cÃ³digos de error planificados:

| CÃ³digo de Error | DescripciÃ³n | AcciÃ³n recomendada en Frontend |
|-----------------|-------------|--------------------------------|
| `PARAMETRO_INVALIDO` | AlgÃºn parÃ¡metro requerido viene vacÃ­o o nulo. | Mostrar alerta de validaciÃ³n local. |
| `CLIENTE_INEXISTENTE` | El cliente ingresado no existe o estÃ¡ inactivo. | Bloquear la creaciÃ³n de la orden o indicar error. |
| `RIF_DUPLICADO` | El RIF/NIT especificado ya pertenece a otro cliente registrado. | Notificar al usuario para corregir el RIF/NIT. |
| `DESPACHO_BLOQUEADO_CREDITO` | El cliente estÃ¡ bloqueado por morosidad/polÃ­tica de crÃ©dito y no posee excepciÃ³n gerencial. | Deshabilitar botÃ³n de ediciÃ³n en Radar o solicitar excepciÃ³n a Gerencia. |
| `ACCESO_DENEGADO` | El usuario no cuenta con el rol requerido (ej. gerente/admin) para ejecutar la acciÃ³n. | Mostrar mensaje de permisos insuficientes. |
| `RUTA_INEXISTENTE` | La ruta ingresada no existe en el sistema. | Notificar al usuario que la ruta no fue encontrada. |
| `STOCK_INSUFICIENTE` | Uno o mÃ¡s productos no disponen de stock en almacÃ©n. | Mostrar cuÃ¡les productos fallaron y sus cantidades. |
| `EXCEPCION_TASA_NO_ENCONTRADA` | No existe tasa de cambio registrada para la fecha. | Redirigir o solicitar registro en el MÃ³dulo de Mantenimiento de Tasas. |
| `FECHA_TASA_DUPLICADA` | Se intentÃ³ registrar una tasa para una fecha que ya existe. | Indicar que debe eliminar la fecha previa antes de modificar. |
| `ESTADO_INVALIDO` | La orden no estÃ¡ en el estado requerido para la acciÃ³n. | Bloquear el botÃ³n o refrescar la pantalla. |
| `SQL_ERROR` | Error interno inesperado en PostgreSQL. | Mostrar error genÃ©rico de base de datos e informar al administrador. |



---

## RPCs de Envases y Saldo de Contenedores por Cliente

### 1. retorna_saldo_contenedores_segun_clientes

- **DescripciÃ³n:** Consulta el saldo corriente de contenedores/envases prestados a clientes. Si p_cliente_id es NULL, devuelve la lista de clientes con saldo_pendiente > 0. Si se pasa p_cliente_id, retorna el saldo de ese cliente (o saldo 0 con sus datos si no posee registros previos).
- **ParÃ¡metros:**
  - p_cliente_id (UUID, Opcional, por defecto NULL).

---

### 2. retorna_movimientos_contenedores_segun_cliente_id_rango_fechas

- **DescripciÃ³n:** Consulta el historial detallado de entregas y retiros de envases por cliente en un rango de fechas especificado, calculando el saldo acumulado anterior a la fecha inicial.
- **ParÃ¡metros:**
  - p_cliente_id (UUID, Requerido).
  - p_fecha_inicial (DATE, Opcional, por defecto hace 30 dÃ­as).
  - p_fecha_limite (DATE, Opcional, por defecto fecha actual).

---

## RPCs y Contratos para Descuentos de Clientes por Producto

### 1. `retorna_lista_productos_segun_parametros`

- **DescripciÃ³n:** Consulta el catÃ¡logo de productos por bÃºsqueda de texto o `.F.`. Si se suministra `p_cliente_id`, calcula de forma dinÃ¡mica los precios netos finales considerando los descuentos configurados en la tabla `descuentos_cliente_producto`.
- **Firma SQL:** `retorna_lista_productos_segun_parametros(p_parametro TEXT, p_cliente_id UUID DEFAULT NULL)`
- **ParÃ¡metros:**
  - `p_parametro` (`TEXT`): Cadena de texto a buscar o `.F.` para retornar todos los productos.
  - `p_cliente_id` (`UUID`, Opcional, defecto `NULL`): ID del cliente para consultar y aplicar reglas de descuento.
- **Campos Retornados:**
  - `id` (`UUID`)
  - `nombre` (`TEXT`)
  - `codigo_barras` (`TEXT`)
  - `precio` (`NUMERIC`): Precio unitario final cobrable en USD (post-descuento).
  - `stock_disponible` (`INT`)
  - `imagen_path` (`TEXT`)
  - `precio_lista` (`NUMERIC`): Precio de lista original en USD (`precio_lista1`).
  - `porcentaje_descuento` (`NUMERIC`): Porcentaje de descuento % activo para el cliente.
  - `precio_final_usd` (`NUMERIC`): Precio final neto en USD.

- **Uso en Server Action / Componentes (Next.js):**
  ```typescript
  import { listarProductosAction } from "@/lib/actions/productos";

  // Obtenemos catÃ¡logo personalizado para un cliente especÃ­fico
  const { ok, productos } = await listarProductosAction("", clienteId);
  ```

---

### 2. Comportamiento en `crear_orden_distribucion` con Descuentos de Cliente

- Al ejecutar `crear_orden_distribucion`:
  - Para cada Ã­tem del `p_productos_json`, la RPC verifica si el cliente posee un descuento activo en `descuentos_cliente_producto`.
  - Si existe un porcentaje de descuento o precio pactado, ajusta de manera automÃ¡tica el `valor_unitario_usd` y calcula los subtotales/totales netos de la orden.
  - Registra en `detalle_distribucion` los campos de trazabilidad: `precio_lista_usd`, `porcentaje_descuento`, `monto_descuento_usd` y `valor_unitario_usd`.

---

### 3. Server Actions para GestiÃ³n de Descuentos (`src/lib/actions/descuentos.ts`)

Para interactuar con la tabla `descuentos_cliente_producto` desde los componentes de Next.js (ej. modal en la lista de clientes):

- `obtenerDescuentosClienteAction(clienteId: string)`: Obtiene los descuentos del cliente con informaciÃ³n del producto.
- `guardarDescuentoClienteAction(input: { cliente_id, producto_id, porcentaje_descuento, precio_pactado_usd })`: Guarda o actualiza la regla de descuento de un cliente.
- `eliminarDescuentoClienteAction(id: string, clienteId: string)`: Elimina la regla de descuento.

---

### 4. `retorna_radar_despachador` (Metadatos de Descuentos en Detalle)

- **Firma SQL:** `retorna_radar_despachador()`
- **ActualizaciÃ³n:** En el array `detalles` de cada orden de distribuciÃ³n, se incluyen los siguientes campos adicionales de auditorÃ­a de descuento:
  - `precio_lista_usd` (`NUMERIC`): Precio de lista base del producto en USD.
  - `porcentaje_descuento` (`NUMERIC`): Porcentaje de descuento % aplicado al producto.
  - `monto_descuento_usd` (`NUMERIC`): Monto total descontado en USD en la lÃ­nea.
- **Estructura JSON de cada Ã­tem en `detalles`:**
  ```json
  {
    "detalle_id": "UUID_DETALLE",
    "producto_id": "UUID_PRODUCTO",
    "codigo_producto": "PROD-001",
    "nombre_producto": "Queso Paisa 1kg",
    "cantidad_solicitada": 10,
    "cantidad_despachada": 10,
    "valor_unitario_usd": 8.50,
    "subtotal_recaudar_usd": 85.00,
    "precio_lista_usd": 10.00,
    "porcentaje_descuento": 15.00,
    "monto_descuento_usd": 15.00,
    "estado_entrega": "pendiente"
  }
  ```

---

### 2.17. GestiÃ³n Multi-Tenant (Base de Datos Central)

Esta secciÃ³n define las funciones para gestionar el aprovisionamiento central de tenants, es decir, el registro de nuevas bases de datos clÃ³nicas en el esquema de enrutamiento y la asignaciÃ³n de operadores.

#### 2.17.1. Crear Nueva Empresa (`crea_nueva_empresa`)
- **Firma SQL:** `crea_nueva_empresa(p_codigo_empresa VARCHAR, p_nombre_empresa VARCHAR, p_supabase_url TEXT, p_supabase_anon_key TEXT)`
- **Uso en Backend (Server Action):**
  ```typescript
  const { data, error } = await supabase.rpc('crea_nueva_empresa', {
    p_codigo_empresa: 'LT-RAMIREZ',
    p_nombre_empresa: 'Distribuidora Ramirez C.A.',
    p_supabase_url: 'https://xyzxyz.supabase.co',
    p_supabase_anon_key: 'eyJhbGciOiJIUzI1Ni...'
  });
  ```
- **Respuesta esperada en `data`:**
  ```json
  {
    "success": true,
    "message": "Empresa creada exitosamente.",
    "data": {
      "empresa_id": "UUID_DE_LA_EMPRESA",
      "codigo_empresa": "LT-RAMIREZ",
      "nombre_empresa": "Distribuidora Ramirez C.A."
    },
    "error": null
  }
  ```

#### 2.17.2. Asignar Usuario a Empresa (`asignar_usuario_empresa`)
- **Firma SQL:** `asignar_usuario_empresa(p_user_id UUID, p_empresa_id UUID, p_rol VARCHAR DEFAULT 'operador')`
- **Uso en Backend (Server Action):**
  ```typescript
  const { data, error } = await supabase.rpc('asignar_usuario_empresa', {
    p_user_id: 'UUID_DEL_USUARIO_EN_AUTH',
    p_empresa_id: 'UUID_DE_LA_EMPRESA',
    p_rol: 'operador'
  });
  ```
- **Respuesta esperada en `data`:**
  ```json
  {
    "success": true,
    "message": "Usuario asignado a la empresa exitosamente.",
    "data": {
      "asignacion_id": "UUID_DE_LA_ASIGNACION",
      "user_id": "UUID_DEL_USUARIO_EN_AUTH",
      "empresa_id": "UUID_DE_LA_EMPRESA",
      "rol": "operador"
    },
    "error": null
  }
  ```

### 2.17. Crear Empresa y Gerente (Server Action: `submitCrearEmpresaAction`)
- **Descripción:** Este método no es un RPC directo desde el cliente, sino un Server Action que orquesta la creación de la empresa en el enrutador central y simultáneamente crea al usuario "Gerente" en la base de datos de Auth, asignándole su rol.
- **Ubicación:** `src/lib/actions/empresas.ts`
- **Campos del FormData requeridos:**
  - `codigoEmpresa` (string)
  - `nombreEmpresa` (string)
  - `gerenteEmail` (string)
  - `gerentePassword` (string)
- **Uso en Frontend (Componente de Cliente):**
  ```typescript
  import { submitCrearEmpresaAction } from "@/lib/actions/empresas";

  // En el onSubmit del form:
  const formData = new FormData(event.currentTarget);
  const response = await submitCrearEmpresaAction(formData);

  if (response.success) {
    alert(response.data.mensaje); // Muestra: "¡Empresa X y su Gerente creados exitosamente!"
  } else {
    alert("Error: " + response.error);
  }
  ```
- **Respuesta esperada en `response`:**
  ```json
  {
    "success": true,
    "data": {
      "empresa_id": "UUID_EMPRESA",
      "codigo_empresa": "CODIGO",
      "nombre_empresa": "Nombre Empresa",
      "gerente_id": "UUID_GERENTE_AUTH",
      "gerente_email": "gerente@ejemplo.com",
      "mensaje": "¡Empresa Nombre Empresa y su Gerente creados exitosamente!"
    }
  }
  ```


- **?? REQUISITOS DE ENTORNO (IMPORTANTE PARA VERCEL Y LOCAL):**
  - Se ha a�adido la librer�a `postgres` al proyecto para inyectar autom�ticamente el esquema en los nuevos tenants. Debes hacer **`npm install`** localmente.
  - El backend ahora se comunica con la Management API de Supabase de manera invisible. Para que esto funcione en la nube, debes agregar las siguientes variables de entorno en el **Panel de Vercel (Environment Variables)** y en tu `.env.local`:
    - `SUPABASE_ORG_ID` = `ozotmtdltfhmtihtsals`
    - `SUPABASE_ACCESS_TOKEN` = (Solicita este token al administrador del backend)



## [2026-09-24] Fix Enrutamiento Multi-Tenant Cliente
Se modific� el archivo `src/lib/supabase/middleware.ts` para que, al iniciar sesi�n, el middleware obtenga autom�ticamente la URL y Key del Tenant desde la base de datos central y los inyecte como cookies (`lt_tenant_url` y `lt_tenant_key`). Adem�s, se modific� `src/lib/supabase/client.ts` para que priorice estas cookies al inicializar el cliente del navegador. Esto soluciona el problema de que los usuarios quedaban viendo los datos del proyecto base en lugar de su tenant privado. 
**Acci�n Requerida (Frontend):** Haz un \git pull\ o mezcla estos cambios en tu rama principal y realiza un nuevo despliegue en Vercel (\ercel --prod\). Pide al usuario de prueba que cierre sesi�n y vuelva a entrar para que el middleware genere las cookies de enrutamiento.


## [2026-09-24] Inyecci�n de Datos Semilla Automatizada
Se cre� un nuevo archivo maestro en `supabase/seed_base.sql` que contiene los datos base unificados (roles depurados, formas de pago, cami�n base, ruta base y el cat�logo completo de 66 productos).
**Acci�n Requerida (Frontend):** Al momento de aprovisionar un nuevo Tenant, justo despu�s de ejecutar satisfactoriamente la inyecci�n del esquema (`schema_base.sql`) v�a la Management API, debes agregar la l�gica para leer y ejecutar tambi�n el contenido de `supabase/seed_base.sql` contra esa misma base de datos reci�n creada. As�, cada nueva empresa nacer� con su estructura y sus datos operacionales listos desde el primer segundo.


## [2026-09-24] Nombre de Empresa en Cookies
Se actualiz� `src/lib/supabase/middleware.ts` para que, junto a las credenciales, tambi�n consulte el campo `nombre_empresa` desde la base de datos central al momento del login. Este nombre ahora se inyecta directamente al navegador del usuario a trav�s de la cookie `lt_tenant_name`. 
**Acci�n Requerida (Frontend):** Si necesitas mostrar el nombre de la empresa en la que est� logueado el usuario (por ejemplo, en el Navbar o el Sidebar), ahora puedes simplemente leer el valor de la cookie `lt_tenant_name` de manera est�tica desde el cliente, sin necesidad de hacer fetch o consultas adicionales a la BD Central.


## [2026-09-24] InyecciÃ³n de Gerente en Nuevo Tenant (SoluciÃ³n 'Sin Rol')
Tras la creaciÃ³n de una empresa, el usuario gerente debe existir tanto en la BD Central como en la BD Tenant para que el enrutamiento y las polÃ­ticas de seguridad (RLS) funcionen correctamente en el sistema local.
**AcciÃ³n Requerida (Frontend):** En el archivo `src/lib/actions/empresas.ts`, dentro de `submitCrearEmpresaAction`, despuÃ©s de ejecutar el esquema (`schema_base.sql`) y la semilla (`seed_base.sql`), DEBES conectarte a la base de datos Tenant e inyectar al gerente manualmente preservando el UUID de la Central. Agrega el siguiente bloque de cÃ³digo:
```typescript
// InyecciÃ³n del gerente en la base de datos Tenant
try {
  const sql = postgres(dbUrl, { max: 1, idle_timeout: 10 });
  const gerenteId = authData.user.id;
  const gerenteEmail = authData.user.email;

  await sql`
    INSERT INTO auth.users (id, instance_id, email, aud, role, email_confirmed_at, encrypted_password)
    VALUES (
      ${gerenteId}, 
      '00000000-0000-0000-0000-000000000000', 
      ${gerenteEmail}, 
      'authenticated', 
      'authenticated', 
      NOW(), 
      crypt('DUMMY_TENANT_PASS_NOT_USED', gen_salt('bf'))
    );
    
    INSERT INTO auth.identities (id, user_id, identity_data, provider, provider_id, created_at, updated_at)
    VALUES (
      gen_random_uuid(), 
      ${gerenteId}, 
      jsonb_build_object('sub', ${gerenteId}::text, 'email', ${gerenteEmail}, 'email_verified', true), 
      'email', 
      ${gerenteId}::text, 
      NOW(), 
      NOW()
    );

    INSERT INTO public.perfiles_usuario (id, rol_id, nombre_completo, activo)
    SELECT ${gerenteId}, id, 'Gerente Principal', true
    FROM public.roles WHERE nombre = 'gerente';
  `;
  await sql.end();
} catch (err) {
  console.error('Error inyectando gerente en Tenant:', err);
}
```
