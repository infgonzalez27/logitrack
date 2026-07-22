# Ciclo de Vida del Agente (Agent Loop) y Backlog de Tareas de Base de Datos

**Proyecto:** LogiTrack  
**Propósito:** Definir el proceso iterativo que deben seguir los agentes de IA (u otros programadores de base de datos) para implementar funciones SQL en Supabase, y listar el backlog priorizado de tareas del sistema.

---

## 1. El Ciclo de Operación del Agente (Agent Loop)

Cada vez que comiences a trabajar en una tarea de base de datos, debes ejecutar el siguiente ciclo iterativo para asegurar consistencia, prevenir regresiones y garantizar una excelente experiencia para el desarrollador del Front/Backend.

```mermaid
graph TD
    A[1. Leer Tarea y Analizar Esquema] --> B[2. Diseñar Firma del RPC y Contrato JSON]
    B --> C[3. Crear/Modificar Archivo SQL en db/functions/]
    C --> D[4. Actualizar docs/INTEGRACION-RPC.md]
    D --> E[5. Validar Sintaxis y Consistencia del SQL]
    E --> F{¿Todo Correcto?}
    F -- No --> C
    F -- Sí --> G[6. Registrar Progreso en Backlog y Terminar]
```

### Paso a paso:

1. **Leer Tarea y Analizar Esquema:** Revisa el requerimiento del negocio y busca las tablas implicadas en [docs/Tablas.md](file:///d:/ProyectosWeb/LogiTrack/docs/Tablas.md) o [assets/docs/Estructuras de tablas.txt](file:///d:/ProyectosWeb/LogiTrack/assets/docs/Estructuras%20de%20tablas.txt).
2. **Diseñar Firma del RPC y Contrato JSON:** Define qué parámetros requiere la función (prefijo `p_`) y cómo estructurará el JSON de retorno (siguiendo el estándar de [docs/SUPABASE-SDD.md](file:///d:/ProyectosWeb/LogiTrack/docs/SUPABASE-SDD.md)).
3. **Crear/Modificar Archivo SQL:** Escribe el script SQL correspondiente en la carpeta `db/functions/`. Usa sentencias `CREATE OR REPLACE FUNCTION`.
4. **Actualizar Guía de Integración:** Añade o actualiza la sección correspondiente de la función en [docs/INTEGRACION-RPC.md](file:///d:/ProyectosWeb/LogiTrack/docs/INTEGRACION-RPC.md) con ejemplos claros de código para el cliente de Supabase.
5. **Validar Sintaxis y Consistencia:** Haz una revisión de linter mental o simulada del código SQL. Asegura que los tipos coincidan y que los bloques `EXCEPTION` capturen posibles errores.
6. **Registrar Progreso:** Cambia el estado de la tarea en este backlog a completada (`[x]`).

---

## 2. Backlog de Tareas de Base de Datos (LogiTrack)

Este es el backlog oficial de las tareas de base de datos pendientes para el sistema logístico de LogiTrack. Las tareas deben ejecutarse en orden secuencial debido a dependencias entre módulos.

### Módulo de Distribución y Flujo de Inventario (Prioridad Alta)

- `[ ]` **Tarea DB-001: Crear Orden de Distribución con Detalles (`crear_orden_distribucion`)**
  - **Función:** Inserta de forma atómica una orden (`ordenes_distribucion`) y su detalle correspondiente (`detalle_distribucion`).
  - **Inputs:** `p_cliente_id UUID`, `p_camion_id UUID`, `p_chofer_id UUID`, `p_factura_origen_numero VARCHAR`, `p_creado_por UUID`, `p_detalles JSONB` (Lista de items con `producto_id`, `cantidad`, `valor_unitario`).
  - **Comportamiento:** Valida que el cliente, camión y chofer estén registrados y activos. Calcula el peso total de la orden multiplicando la cantidad de productos por su peso en la tabla `productos`. Inserta la cabecera con estado inicial `borrador`, autogenerando el correlativo, e inserta las líneas de detalles en secuencia.
  - **Output:** JSON `{ success: boolean, data: { orden_id: UUID, correlativo: INT, peso_total_calculado: NUMERIC }, error: object }`.

- `[ ]` **Tarea DB-002: Aprobación de Orden y Reserva de Stock (`aprobar_orden_distribucion`)**
  - **Función:** Transiciona una orden al estado `aprobada` (Gerente aprueba) y compromete el stock físico en el almacén principal.
  - **Inputs:** `p_orden_id UUID`.
  - **Comportamiento:** Valida que el estado actual sea `borrador`. Para cada línea de detalle, verifica si hay suficiente `stock_disponible` en `inventario_almacen`. Si la verificación es exitosa:
    1. Resta la cantidad solicitada de `stock_disponible`.
    2. Suma la cantidad solicitada a `stock_comprometido`.
    3. Cambia el estado de la orden a `aprobada`.
  - **Output:** JSON `{ success: boolean, data: { orden_id: UUID, nuevo_estado: "aprobada" }, error: object }`.

- `[ ]` **Tarea DB-003: Carga a Inventario Móvil (`cargar_inventario_movil`)**
  - **Función:** Transiciona una orden al estado `en_transito` y traspasa los productos del almacén principal al camión.
  - **Inputs:** `p_orden_id UUID`.
  - **Comportamiento:** Valida que la orden esté en `aprobada`. Para cada producto del detalle:
    1. Resta la cantidad de `stock_comprometido` en `inventario_almacen` (sale físicamente del almacén).
    2. Inserta o actualiza un registro en `inventario_movil` para el `camion_id` (por ID de camión) asociado a la orden, sumando la cantidad despachada al campo `cantidad_cargada`.
    3. Actualiza el estado de la orden a `en_transito`.
    4. Cambia el estado del camión y del chofer asignado a `en_ruta`.
  - **Output:** JSON `{ success: boolean, data: { orden_id: UUID, nuevo_estado: "en_transito" }, error: object }`.

- `[ ]` **Tarea DB-004: Registro de Entregas y Devoluciones (`registrar_entrega_detalle`)**
  - **Función:** Registra el resultado del despacho de una línea de producto específica en ruta por parte del chofer (Radar).
  - **Inputs:** `p_detalle_id UUID`, `p_cantidad_despachada INT` (entregada), `p_estado_entrega TEXT`, `p_motivo_rechazo TEXT`.
  - **Comportamiento:** Valida que la orden asociada esté en estado `en_transito`.
    1. Actualiza `cantidad_despachada`, `estado_entrega` y `motivo_rechazo` en `detalle_distribucion`.
    2. Actualiza `inventario_movil` para el camión de la orden:
       - Suma `p_cantidad_despachada` a `cantidad_entregada`.
       - Calcula la diferencia (`cantidad_solicitada - p_cantidad_despachada`) y la suma a `cantidad_devolucion`.
    3. Si todas las líneas de detalle de la orden han sido procesadas (tienen un estado diferente a 'pendiente'), cambia el estado de la orden a `por_liquidar`.
  - **Output:** JSON `{ success: boolean, data: { detalle_id: UUID, estado_entrega: TEXT, orden_estado: TEXT }, error: object }`.

- `[ ]` **Tarea DB-004b: Registrar Movimiento de Contenedores en Ruta (`registrar_movimiento_contenedores`)**
  - **Función:** Registra las entregas y retiros físicos de envases/contenedores retornables realizados por el despachador para un cliente y orden.
  - **Inputs:** `p_cliente_id UUID`, `p_orden_id UUID`, `p_contenedor_id UUID`, `p_cantidad_entregada INT`, `p_cantidad_retirada INT`, `p_creado_por UUID`.
  - **Comportamiento:** Registra la transacción en `movimientos_contenedores`.
  - **Output:** JSON `{ success: boolean, data: { movimiento_id: UUID }, error: object }`.

- `[ ]` **Tarea DB-005: Aprobación de Recaudación y Liquidación (`liquidar_orden_distribucion`)**
  - **Función:** Cierra la orden financieramente y consolida el saldo de contenedores cuando el gerente aprueba la recaudación.
  - **Inputs:** `p_orden_id UUID`.
  - **Comportamiento:**
    1. Valida que la orden esté en `por_liquidar`.
    2. Valida que exista una recaudación aprobada (`rendiciones_cuentas.estado = 'aprobada'`) vinculada a esta orden en `detalle_rendicion_ordenes` y que el monto recaudado cubra la cobranza requerida. Si no, lanza error `COBRANZA_PENDIENTE`.
    3. Por cada línea de detalle:
       - Suma la cantidad devuelta/rechazada a `stock_disponible` en `inventario_almacen` y la resta de `inventario_movil` del camión.
    4. Por cada movimiento registrado en `movimientos_contenedores` para esta orden:
       - Actualiza `saldo_contenedores_clientes` del cliente sumando `cantidad_entregada` y restando `cantidad_retirada`.
    5. Cambia el estado de la orden a `liquidada` y libera camión/chofer a `disponible`.
  - **Output:** JSON `{ success: boolean, data: { orden_id: UUID, nuevo_estado: "liquidada" }, error: object }`.

- `[ ]` **Tarea DB-006: Anulación de Orden (`anular_orden_distribucion`)**
  - **Función:** Cancela la orden y revierte cualquier asignación de inventario realizada.
  - **Inputs:** `p_orden_id UUID`.
  - **Comportamiento:**
    - Si la orden está en `borrador`: cambia el estado directamente a `anulada`.
    - Si la orden está en `aprobada`: reversa las reservas de inventario (resta de `stock_comprometido` y suma a `stock_disponible` en `inventario_almacen` para cada producto del detalle) y cambia a `anulada`.
    - Si está en `en_transito` o `liquidada`: bloquea la acción.
  - **Output:** JSON `{ success: boolean, data: { orden_id: UUID, nuevo_estado: "anulada" }, error: object }`.

### Módulo de Seguridad y Auditoría (Prioridad Media)

- `[ ]` **Tarea DB-007: Configuración de RLS y Funciones de Seguridad**
  - **Función:** Crear triggers de auditoría automática en tablas críticas e implementar funciones auxiliares para validar el rol del usuario autenticado actual desde el cliente de Supabase.
  - **Detalle:**
    1. Crear función trigger `audit_changes_trigger()` que inserte registros en `logs_auditoria` con valores anteriores y nuevos al hacer INSERT/UPDATE/DELETE.
    2. Crear políticas RLS en `ordenes_distribucion` para que un chofer (`chofer_cobrador`) solo pueda leer las órdenes asignadas a su `chofer_id` (que mapea a su ID de usuario en auth).
