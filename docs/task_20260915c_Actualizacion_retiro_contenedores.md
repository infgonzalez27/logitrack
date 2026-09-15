# TASK: Actualización de Saldos de Contenedores al Momento del Despacho

## 1. Resumen Ejecutivo
Modificar el momento del ciclo de vida en el que se ejecuta la actualización del inventario/saldo de contenedores asignados a clientes. El trigger actual (aprobación de orden) debe ser desacoplado y trasladado al evento de confirmación/actualización por parte del despachador en la **orden de distribución**.

---

## 2. Contexto y Comportamiento Esperado

### 2.1. Comportamiento Anterior vs. Nuevo Comportamiento
* **Anterior:** El saldo de contenedores por cliente se calculaba y aplicaba al **aprobar la orden**.
* **Nuevo:** El saldo de contenedores por cliente se debe calcular y asentar únicamente cuando el **despachador actualiza/confirma la orden de distribución**.

---

## 3. Reglas de Negocio y Lógica de Cálculo

### 3.1. Relación Producto - Contenedor
En el modelo/tabla `productos`, considerar los siguientes campos:
* `contenedor_id` (identificador foráneo del tipo de contenedor, nullable).
* `unidades_por_contenedor` (número de unidades de producto que caben en un contenedor).

### 3.2. Criterios de Evaluación por Ítem en Despacho
1. Si un SKU despachado **NO** tiene `contenedor_id` asignado:
   * No computa para entregas de contenedores.
2. Si un SKU despachado **SÍ** tiene `contenedor_id` asignado:
   * Cantidad de contenedores a entregar = $\lceil \text{cantidad\_despachada} / \text{unidades\_por\_contenedor} \rceil$ (o la regla de conversión definida en el negocio).
3. Contenedores Retirados:
   * La cantidad de contenedores devueltos o retirados durante la entrega debe restar o conciliar el total de contenedores según su respectivo `contenedor_id`.

### 3.3. Caso de Uso de Referencia
* **SKU A:** 4 unidades despachadas (`contenedor_id = NULL`).
* **SKU B:** 10 unidades despachadas (`contenedor_id = 101`, `unidades_por_contenedor = 1`).
* **Retiros registrados en el despacho:** 0 contenedores devueltos.
* **Resultado para `contenedor_id = 101`:**
  * Contenedores entregados: 10
  * Contenedores retirados: 0
  * Saldo pendiente generado: +10

---

## 4. Impacto en Base de Datos

1. **Tabla `saldo_contenedores_clientes`**:
   * Actualizar los saldos acumulados consolidados por `(cliente_id, contenedor_id)`.
   * Sumar las unidades entregadas y restar las unidades retiradas.

2. **Tabla `movimientos_contenedores`**:
   * Registrar cada evento individual de despacho/devolución con trazabilidad:
     * `cliente_id`
     * `orden_distribucion_id`
     * `contenedor_id`
     * `cantidad_entregada`
     * `cantidad_retirada`
     * `fecha_movimiento` / `timestamp`
     * `usuario_despachador_id`

---

## 5. Criterios de Aceptación (DoD)

- [ ] Se eliminó la ejecución del cálculo/asiento de saldos de contenedores en el hook/evento de **aprobación de orden**.
- [ ] Se implementó el cálculo y persistencia en el hook/endpoint ejecutado al **guardar/confirmar la orden de distribución** por parte del despachador.
- [ ] Los productos sin `contenedor_id` son ignorados en el balance de contenedores.
- [ ] Se actualizan correctamente los totales en `saldo_contenedores_clientes` agrupados por `cliente_id` y `contenedor_id`.
- [ ] Se inserta el log correspondiente en `movimientos_contenedores`.
- [ ] Las operaciones sobre base de datos deben ejecutarse dentro de una **transacción ACID** para evitar discrepancias de inventario.