# REQUERIMIENTO LOGITRACK: AUTOMATIZACIÓN DE SALDOS Y MOVIMIENTOS DE CONTENEDORES

**Contexto del Negocio:**
Dentro del catálogo, existen productos que están asociados a un envase o contenedor (tienen un `contenedor_id` asignado, ej. cajas, botellas retornables, paletas). Necesitamos automatizar el control de estos contenedores cuando se genera una Orden de Distribución (OD), específicamente para los flujos de "Auto-Venta" y "Venta Directa".

## 🎯 LÓGICA DE NEGOCIO Y REGLAS DE OPERACIÓN

### 1. Cálculo Automático de Entregas (Auto-Venta y Venta Directa)
Cuando el usuario crea una OD en estas modalidades, **no debe ingresar manualmente cuántos contenedores está entregando**. El sistema debe deducirlo automáticamente:
- Al procesar la OD, la base de datos verificará cuáles de los productos vendidos tienen un `contenedor_id` no nulo.
- Generará automáticamente los registros en `movimientos_contenedores` (Tipo: ENTREGA).
- Sumará automáticamente estas cantidades a la tabla `saldo_contenedor_clientes`.

### 2. Ingreso Manual de Retiros (UI)
El único dato de contenedores que el usuario (vendedor/despachador) ingresará manualmente en el Frontend al momento de hacer la OD es la cantidad de **Contenedores Retirados** (los vacíos que el cliente está devolviendo en ese momento).
- Esto debe generar automáticamente el registro en `movimientos_contenedores` (Tipo: RETIRO).
- Restará esta cantidad del `saldo_contenedor_clientes`.

### 3. Visualización en la Orden Impresa (Ticket / Recibo)
Para el control físico, la Orden de Distribución impresa debe incorporar un bloque de "Resumen de Contenedores" con 4 valores:
1. **Saldo Anterior:** Cuántos contenedores debía el cliente antes de esta factura.
2. **Entregados:** Cantidad calculada automáticamente.
3. **Retirados:** Cantidad que el cliente devolvió (input del usuario).
4. **Saldo Actual:** (`Saldo Anterior` + `Entregados` - `Retirados`).

## 🛠️ PASOS DE EJECUCIÓN OBLIGATORIOS PARA CURSOR

1. **Diseño Transaccional (Backend - Supabase):**
   **Debes crear una función RPC (PL/pgSQL)** que centralice esta operación. La función debe recibir el detalle de la OD y los "Contenedores Retirados". En una **única transacción atómica**, la función debe:
   - Insertar la Orden y sus detalles.
   - Calcular los contenedores entregados.
   - Insertar en `movimientos_contenedores` (Entregas y Retiros).
   - Actualizar `saldo_contenedor_clientes`.
   - **CRÍTICO:** La función debe hacer un `RETURNS jsonb` devolviendo el ID de la orden creada y el resumen de saldos exacto (Anterior, Entregados, Retirados, Actual) para evitar que el Frontend tenga que hacer un fetching adicional.

2. **Actualización de la Interfaz (Frontend):**
   Modifica el formulario de creación de Orden de Distribución (Auto-venta y Venta Directa) agregando un campo numérico para "Contenedores Retirados" (opcional, default 0).

3. **Modificación del Ticket/Reporte:**
   Utiliza el JSON retornado por la nueva función RPC para renderizar el bloque de "Resumen de Contenedores" en el pie del documento impreso, mostrando los 4 rubros calculados.