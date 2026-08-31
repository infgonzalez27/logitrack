# Guía de Integración de Stored Procedures (RPC) para Front & Backend

**Proyecto:** LogiTrack  
**Propósito:** Proveer instrucciones de código y contratos para consumir las funciones de base de datos desde Next.js Server Actions o componentes del cliente.  
**Desarrollado para:** Desarrollador Front/Backend del equipo de LogiTrack.

---

## 1. Patrón General de Consumo en TypeScript

Todas las llamadas a funciones de negocio en PostgreSQL deben realizarse utilizando el método `.rpc()` del cliente de Supabase.

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
    // Error crítico de red o de comunicación de la API de Supabase
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

### 1.2. Ejemplo de Integración en un Server Action de Next.js
Aquí se muestra cómo el desarrollador de Back/Front debe invocar la función en un Server Action para cambiar la interfaz de usuario de acuerdo al resultado.

```typescript
'use server';

import { callDbProcedure } from '@/lib/actions/db-helper'; // Supuesta ubicación del helper
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
    p_detalles: JSON.stringify(formData.detalles) // Debe pasarse como string de JSON para ser leído como JSONB
  };

  const response = await callDbProcedure<CrearOrdenData>('crear_orden_distribucion', params);

  if (!response.success) {
    // Controlar error lógico (ej: STOCK_INSUFICIENTE, CLIENTE_INEXISTENTE)
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

## 2. Catálogo de Stored Procedures e Indicaciones de Parámetros

A continuación se listan las firmas de los procedimientos almacenados que el equipo de base de datos implementará. Utiliza esta sección como referencia para preparar tus componentes de frontend.

### 2.1. Crear Orden de Distribución (`crear_orden_distribucion`)
- **Firma SQL:** `crear_orden_distribucion(p_vendedor_id UUID, p_cliente_id UUID, p_camion_id UUID, p_tasa_cambio NUMERIC DEFAULT NULL, p_productos_json JSONB DEFAULT '[]'::jsonb, p_despachador_id UUID DEFAULT NULL, p_id_ruta UUID DEFAULT NULL)`
- **Campos multimoneda y relaciones asociadas automáticamente en DB:**
  - `ordenes_distribucion`: `tasa_cambio`, `total_recaudar_bs`, `total_recaudar_usd`, `vendedor_id`, `despachador_id` e `id_ruta` (se obtienen del perfil del cliente si no se pasan explícitamente).
  - `detalle_distribucion`: `valor_unitario_recaudar` (Bs), `subtotal_recaudar` (Bs), `valor_unitario_usd` (USD), `subtotal_recaudar_usd` (USD).
- **Uso en Frontend (RPC) / Cursor Editor:**
  ```typescript
  const { data, error } = await supabase.rpc('crear_orden_distribucion', {
    p_vendedor_id: 'UUID_DEL_VENDEDOR',
    p_cliente_id: 'UUID_DEL_CLIENTE',
    p_camion_id: 'UUID_DEL_CAMION',
    p_tasa_cambio: 50.25, // Opcional (si se omite/es null, toma la tasa oficial más reciente de la tabla tasa_cambio)
    p_despachador_id: 'UUID_OPCIONAL_DESPACHADOR', // Opcional
    p_id_ruta: 'UUID_OPCIONAL_RUTA', // Opcional
    p_productos_json: [
      {
        producto_id: 'UUID_PRODUCTO_1',
        cantidad: 5,
        valor_unitario_recaudar: 500.00, // Precio unitario en Bolívares (Bs)
        valor_unitario_usd: 9.95        // Precio unitario en Dólares (USD)
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
    "message": "Orden de distribución creada exitosamente.",
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

### 2.2. Aprobación de Orden y Reserva de Stock (`aprobar_orden_distribucion`)
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

### 2.3. Carga a Inventario Móvil (`cargar_inventario_movil`)
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

### 2.4. Registro de Entregas y Devoluciones en Ruta (`registrar_entrega_detalle`)
- **Firma SQL:** `registrar_entrega_detalle(p_detalle_id UUID, p_cantidad_despachada INT, p_estado_entrega TEXT, p_motivo_rechazo TEXT)`
- **Uso en Frontend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('registrar_entrega_detalle', {
    p_detalle_id: 'UUID_DEL_DETALLE_LINEA',
    p_cantidad_despachada: 4, // Cantidad que realmente recibió el cliente
    p_estado_entrega: 'entregado_parcial', // 'entregado', 'entregado_parcial', 'rechazado'
    p_motivo_rechazo: '2 unidades dañadas en el trayecto' // Null si es 'entregado' completo
  });
  ```
- **Respuesta esperada en `data`:**
  ```json
  {
    "success": true,
    "data": {
      "detalle_id": "UUID_DEL_DETALLE_LINEA",
      "estado_entrega": "entregado_parcial",
      "orden_estado": "por_liquidar" // o "en_transito" si aún hay líneas pendientes
    },
    "error": null
  }
  ```

### 2.5. Liquidación de Despacho (`liquidar_orden_distribucion`)
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

### 2.6. Anulación de Orden (`anular_orden_distribucion`)
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

### 2.8. Registrar Rendición de Cuentas (`registrar_rendicion_cuentas`)
- **Firma SQL:** `registrar_rendicion_cuentas(p_cliente_id UUID, p_observaciones TEXT, p_creado_por UUID, p_ordenes JSONB, p_pagos JSONB)`
- **Uso en Frontend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('registrar_rendicion_cuentas', {
    p_cliente_id: 'UUID_DEL_CLIENTE',
    p_observaciones: 'Rendición de la cobranza de la tarde',
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

### 2.10. Módulo de Mantenimiento de Tasas de Cambio (`tasa_cambio`)

El **Módulo de Mantenimiento de Tasas de Cambio** gestiona las tasas oficiales utilizadas en la facturación y cobranza en multimoneda.

#### Comportamiento Esperado del Módulo en Frontend:
1. **Carga Inicial por Defecto:** Al ingresar al módulo, debe invocar `retorna_ultima_tasa_cambio` para mostrar la tasa más reciente registrada con su fecha.
2. **Registro de Nueva Tasa:** Permite ingresar una fecha y monto de tasa con `inserta_tasa_cambio`. (No permite fechas duplicadas).
3. **Eliminación de Tasa:** Permite eliminar la tasa de una fecha con `elimina_tasa_cambio`. (Para actualizar una tasa, se debe eliminar la fecha y registrarla de nuevo).
4. **Consulta Histórica por Rango:** Permite al usuario consultar el listado de tasas en un rango de fechas con `retorna_tasas_cambio_por_rango`.

---

#### 2.10.1. Consultar Última Tasa Registrada (`retorna_ultima_tasa_cambio`)
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
- **Regla:** No se permiten fechas duplicadas. Si la fecha ya existe, retorna error de restricción `FECHA_TASA_DUPLICADA`.
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
      { "id": "11111111-1111-1111-1111-111111111111", "nombre": "Caja Plástica 24 Unidades" },
      { "id": "22222222-2222-2222-2222-222222222222", "nombre": "Cesta Térmica 50L" }
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
        "descripcion_ruta": "Atención a clientes del casco central",
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
        "nombre_completo": "Carlos Pérez (Despachador)",
        "telefono": "+584141112233"
      },
      {
        "id": "6d1b27f3-4455-7766-1122-ddeeff004455",
        "nombre_completo": "José Rodríguez",
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
    p_descripcion_ruta: 'Nueva descripción de la ruta comercial' // Opcional / Acepta null
  });
  ```
- **Respuesta esperada en `data` (Éxito):**
  ```json
  {
    "success": true,
    "message": "Ruta actualizada exitosamente.",
    "data": {
      "id_ruta": "3a8f94c0-1122-4433-8899-aabbccdd1122",
      "nombre_ruta": "Ruta Centro - Actualizada",
      "descripcion_ruta": "Nueva descripción de la ruta comercial",
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
      "message": "No se encontró ninguna ruta con el id_ruta especificado."
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
- **Respuesta esperada en `data` (Éxito):**
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
      "message": "No se encontró ningún cliente con el ID especificado."
    }
  }
  ```

### 2.16. Consulta de Radar del Despachador (`retorna_radar_despachador`)
- **Firma SQL:** `retorna_radar_despachador()`
- **Uso en Frontend / Backend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('retorna_radar_despachador');
  ```
- **Respuesta esperada en `data` (Éxito):**
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
            "nombre_contenedor": "Cesta Plástica Estándar",
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
        motivo_rechazo: 'Cliente no requería las 2 unidades sobrantes',
        contenedores_retirados: 5,
        contenedor_id: 'e5f6a7b8-c9d0-1234-ef01-567890abcdef'
      }
    ]
  });
  ```
- **Respuesta esperada en `data` (Éxito):**
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

### 2.18. Aprobación de Despacho por Gerencia / Almacén (`aprobar_despacho_orden_distribucion`)
- **Firma SQL:** `aprobar_despacho_orden_distribucion(p_orden_id UUID)`
- **Uso en Frontend / Backend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('aprobar_despacho_orden_distribucion', {
    p_orden_id: 'b2c3d4e5-f6a7-8901-bcde-234567890abc'
  });
  ```
- **Respuesta esperada en `data` (Éxito):**
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
- **Respuesta esperada en `data` (Éxito):**
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
- **Respuesta esperada en `data` (Éxito):**
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
        "nombre_completo": "Carlos Pérez",
        "telefono": "+584141112233",
        "correo_e": "carlos.perez@logitrack.com",
        "ci_rif": "V-18234567"
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
- **Respuesta esperada en `data` (Éxito):**
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
- **Respuesta esperada en `data` (Éxito):**
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

---

## 3. Códigos de Error Comunes para Control en Frontend

Cuando `success` sea `false`, el frontend puede leer `error.code` para disparar notificaciones o flujos condicionales específicos. Aquí tienes la lista de códigos de error planificados:

| Código de Error | Descripción | Acción recomendada en Frontend |
|-----------------|-------------|--------------------------------|
| `PARAMETRO_INVALIDO` | Algún parámetro requerido viene vacío o nulo. | Mostrar alerta de validación local. |
| `CLIENTE_INEXISTENTE` | El cliente ingresado no existe o está inactivo. | Bloquear la creación de la orden o indicar error. |
| `RIF_DUPLICADO` | El RIF/NIT especificado ya pertenece a otro cliente registrado. | Notificar al usuario para corregir el RIF/NIT. |
| `RUTA_INEXISTENTE` | La ruta ingresada no existe en el sistema. | Notificar al usuario que la ruta no fue encontrada. |
| `STOCK_INSUFICIENTE` | Uno o más productos no disponen de stock en almacén. | Mostrar cuáles productos fallaron y sus cantidades. |
| `EXCEPCION_TASA_NO_ENCONTRADA` | No existe tasa de cambio registrada para la fecha. | Redirigir o solicitar registro en el Módulo de Mantenimiento de Tasas. |
| `FECHA_TASA_DUPLICADA` | Se intentó registrar una tasa para una fecha que ya existe. | Indicar que debe eliminar la fecha previa antes de modificar. |
| `ESTADO_INVALIDO` | La orden no está en el estado requerido para la acción. | Bloquear el botón o refrescar la pantalla. |
| `SQL_ERROR` | Error interno inesperado en PostgreSQL. | Mostrar error genérico de base de datos e informar al administrador. |


