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
- **Firma SQL:** `crear_orden_distribucion(p_cliente_id UUID, p_camion_id UUID, p_chofer_id UUID, p_factura_origen_numero VARCHAR, p_creado_por UUID, p_detalles JSONB)`
- **Uso en Frontend (RPC):**
  ```typescript
  const { data, error } = await supabase.rpc('crear_orden_distribucion', {
    p_cliente_id: 'UUID_DEL_CLIENTE',
    p_camion_id: 'UUID_DEL_CAMION',
    p_chofer_id: 'UUID_DEL_CHOFER',
    p_factura_origen_numero: 'FACT-2026-001',
    p_creado_por: 'UUID_DEL_DESPACHADOR',
    p_detalles: [
      { producto_id: 'UUID_PRODUCTO_1', cantidad: 5, valor_unitario: 12.50 },
      { producto_id: 'UUID_PRODUCTO_2', cantidad: 2, valor_unitario: 50.00 }
    ] // Supabase SDK se encarga de serializar arrays/objetos a JSONB
  });
  ```
- **Respuesta esperada en `data`:**
  ```json
  {
    "success": true,
    "data": {
      "orden_id": "UUID_DE_LA_NUEVA_ORDEN",
      "correlativo": 105,
      "peso_total_calculado": 125.40
    },
    "error": null
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
      { metodo_pago: 'pago_movil', monto: 150.00, referencia_bancaria: 'REF1234', cuenta_bancaria: '0102-XXXX', capture_url: 'storage-url' },
      { metodo_pago: 'efectivo_usd', monto: 100.00, referencia_bancaria: null, cuenta_bancaria: null, capture_url: null }
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

---

## 3. Códigos de Error Comunes para Control en Frontend

Cuando `success` sea `false`, el frontend puede leer `error.code` para disparar notificaciones o flujos condicionales específicos. Aquí tienes la lista de códigos de error planificados:

| Código de Error | Descripción | Acción recomendada en Frontend |
|-----------------|-------------|--------------------------------|
| `PARAMETRO_INVALIDO` | Algún parámetro requerido viene vacío o nulo. | Mostrar alerta de validación local. |
| `CLIENTE_INEXISTENTE` | El cliente ingresado no existe o está inactivo. | Bloquear la creación de la orden. |
| `STOCK_INSUFICIENTE` | Uno o más productos no disponen de stock en almacén. | Mostrar cuáles productos fallaron y sus cantidades. |
| `ESTADO_INVALIDO` | La orden no está en el estado requerido para la acción (ej: anular una orden liquidada). | Bloquear el botón o refrescar el estado de la pantalla. |
| `SQL_ERROR` | Error interno inesperado en PostgreSQL. | Mostrar error genérico de base de datos e informar al administrador. |
