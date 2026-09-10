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

- `[x]` **Tarea DB-000: Aplicar Cambios Estructurales en la Base de Datos (Migraciones)**
  - **Función:** Aplicar el esquema DDL aprobado en [docs/PROPOSICION-CAMBIOS-DB.md](file:///d:/ProyectosWeb/LogiTrack/docs/PROPOSICION-CAMBIOS-DB.md) para habilitar el doble inventario de contenedores y los nuevos estados de la orden.
  - **Comportamiento:**
    1. Crear la tabla maestra `tipos_contenedores` y el saldo por cliente `saldo_contenedores_clientes`.
    2. Modificar la tabla `productos` para relacionarla a contenedores.
    3. Crear la tabla de transacciones `movimientos_contenedores`.
    4. Actualizar la restricción CHECK del estado en `ordenes_distribucion` para añadir `por_liquidar`.
  - **Output:** Estructura de base de datos de Supabase actualizada con éxito.

- `[x]` **Tarea DB-002: Aprobación de Orden y Reserva de Stock (`aprobar_orden_distribucion`)**
  - **Función:** Transiciona una orden al estado `aprobada` (Gerente aprueba) y compromete el stock físico en el almacén principal.
  - **Inputs:** `p_orden_id UUID`.
  - **Comportamiento:** Valida que el estado actual sea `borrador`. Para cada línea de detalle, verifica si hay suficiente `stock_disponible` en `inventario_almacen`. Si la verificación es exitosa:
    1. Resta la cantidad solicitada de `stock_disponible`.
    2. Suma la cantidad solicitada a `stock_comprometido`.
    3. Cambia el estado de la orden a `aprobada`.
  - **Output:** JSON `{ success: boolean, data: { orden_id: UUID, nuevo_estado: "aprobada" }, error: object }`.

- `[x]` **Tarea DB-003: Carga a Inventario Móvil (`cargar_inventario_movil`)**
  - **Función:** Transiciona una orden al estado `en_transito` y traspasa los productos del almacén principal al camión.
  - **Inputs:** `p_orden_id UUID`.
  - **Comportamiento:** Valida que la orden esté en `aprobada`. Para cada producto del detalle:
    1. Resta la cantidad de `stock_comprometido` en `inventario_almacen` (sale físicamente del almacén).
    2. Inserta o actualiza un registro en `inventario_movil` para el `camion_id` (por ID de camión) asociado a la orden, sumando la cantidad despachada al campo `cantidad_cargada`.
    3. Actualiza el estado de la orden a `en_transito`.
    4. Cambia el estado del camión y del chofer asignado a `en_ruta`.
  - **Output:** JSON `{ success: boolean, data: { orden_id: UUID, nuevo_estado: "en_transito" }, error: object }`.

- `[x]` **Tarea DB-004: Registro de Entregas y Devoluciones (`registrar_entrega_detalle`)**
  - **Función:** Registra el resultado del despacho de una línea de producto específica en ruta por parte del chofer (Radar).
  - **Inputs:** `p_detalle_id UUID`, `p_cantidad_despachada INT` (entregada), `p_estado_entrega TEXT`, `p_motivo_rechazo TEXT`.
  - **Comportamiento:** Valida que la orden asociada esté en estado `en_transito`.
    1. Actualiza `cantidad_despachada`, `estado_entrega` y `motivo_rechazo` en `detalle_distribucion`.
    2. Actualiza `inventario_movil` para el camión de la orden:
       - Suma `p_cantidad_despachada` a `cantidad_entregada`.
       - Calcula la diferencia (`cantidad_solicitada - p_cantidad_despachada`) y la suma a `cantidad_devolucion`.
    3. Si todas las líneas de detalle de la orden han sido procesadas (tienen un estado diferente a 'pendiente'), cambia el estado de la orden a `por_liquidar`.
  - **Output:** JSON `{ success: boolean, data: { detalle_id: UUID, estado_entrega: TEXT, orden_estado: TEXT }, error: object }`.

- `[x]` **Tarea DB-004b: Registrar Movimiento de Contenedores en Ruta (`registrar_movimiento_contenedores`)**
  - **Función:** Registra las entregas y retiros físicos de envases/contenedores retornables realizados por el despachador para un cliente y orden.
  - **Inputs:** `p_cliente_id UUID`, `p_orden_id UUID`, `p_contenedor_id UUID`, `p_cantidad_entregada INT`, `p_cantidad_retirada INT`, `p_creado_por UUID`.
  - **Comportamiento:** Registra la transacción en `movimientos_contenedores`.
  - **Output:** JSON `{ success: boolean, data: { movimiento_id: UUID }, error: object }`.

- `[x]` **Tarea DB-005: Aprobación de Recaudación y Liquidación (`liquidar_orden_distribucion`)**
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

- `[x]` **Tarea DB-006: Anulación de Orden (`anular_orden_distribucion`)**
  - **Función:** Cancela la orden y revierte cualquier asignación de inventario realizada.
  - **Inputs:** `p_orden_id UUID`.
  - **Comportamiento:**
    - Si la orden está en `borrador`: cambia el estado directamente a `anulada`.
    - Si la orden está en `aprobada`: reversa las reservas de inventario (resta de `stock_comprometido` y suma a `stock_disponible` en `inventario_almacen` para cada producto del detalle) y cambia a `anulada`.
    - Si está en `en_transito` o `liquidada`: bloquea la acción.
  - **Output:** JSON `{ success: boolean, data: { orden_id: UUID, nuevo_estado: "anulada" }, error: object }`.

### Módulo de Seguridad y Auditoría (Prioridad Media)

- `[x]` **Tarea DB-007: Configuración de RLS y Funciones de Seguridad**
  - **Función:** Crear triggers de auditoría automática en tablas críticas e implementar funciones auxiliares para validar el rol del usuario autenticado actual desde el cliente de Supabase.
  - **Detalle:**
    1. Crear función trigger `audit_changes_trigger()` que inserte registros en `logs_auditoria` con valores anteriores y nuevos al hacer INSERT/UPDATE/DELETE.
    2. Crear políticas RLS en `ordenes_distribucion` para que un chofer (`chofer_cobrador`) solo pueda leer las órdenes asignadas a su `chofer_id` (que mapea a su ID de usuario en auth).

### Módulo de Rendición de Cuentas y Crédito (Prioridad Alta)

- `[x]` **Tarea DB-008: Registro de Rendición de Cuentas (`registrar_rendicion_cuentas`)**
  - **Función:** Registra de forma atómica la recaudación asociando múltiples órdenes y formas de pago, gestionando automáticamente el saldo a favor del cliente y el trigger de liquidación de órdenes.
  - **Inputs:** `p_cliente_id UUID`, `p_observaciones TEXT`, `p_creado_por UUID`, `p_ordenes JSONB`, `p_pagos JSONB`.
  - **Comportamiento:** Registra la cabecera en `rendiciones_cuentas` y los detalles en `detalle_rendicion_ordenes` y `detalle_rendicion_fpagos`. Si la suma de los pagos supera lo recaudado de las órdenes, calcula y abona la diferencia como crédito en `saldo_favor` del cliente.
  - **Output:** JSON `{ success: boolean, data: { rendicion_id: UUID, total_ordenes: NUMERIC, total_pagos: NUMERIC, saldo_favor_generado: NUMERIC }, error: object }`.

  ### Tabla formas de pago 

- `[x]` **Tarea DB-009: Creación de tabla fpagos con las distintas formas de pago**
  - **Función:** Registros con formas de pago para ser utilizado en el módulo de Rendición de cuentas y pago a proveedores
  - **Inputs:** `fpago_id UUID PK, fpago_concepto TEXT, fpago_info BOOLEAN`.
  - **Registros:** Insertar los siguientes registros: `Pago movil`, .T.; `Transferencia`,.T.;`Efectivo Bs`, .F.; `Efectivo USD`, .F.; `ZELLE`, .T.;`BINANCE`,.T.
  - **Output:** No OUTPUT

  ### Foreign Key 

- `[x]` **Tarea DB-010: Creación de un foreign key en la tabla detalle_rendicion_fpagos**
  - **Función:** Solo almacenar en la tabla detalle_rendicion_fpagos el fpago_id. Eliminar el campo metodo_pago. (Nota: Se actualizaron `registrar_rendicion_cuentas` y `cargar_datos_demo_dashboard` para usar `fpago_id`).
  
### Consulta a la tabla formas de pago

- `[x]` **Tarea DB-011: Crear Function consulta_registros_formas_pago, en Supabase para consultar todos los registros de la tabla fpagos (`Retorna_`)**
  - **Función:** Retorna todos los campos de todos los registros de la tabla fpagos
  - **Inputs:** No hay Inputs.
  - **Output:** JSON (Estructura: `{ "success": true, "data": [{"fpago_id": "...", "fpago_concepto": "...", "fpago_info": ...}], "error": null }`) 

### Control de Acceso y Modificación de Órdenes

- `[x]` **Tarea DB-012: Restricción de Modificación de Órdenes de Distribución (Vendedor vs Gerente)**
  - **Función:** Un vendedor solo puede modificar o anular las órdenes que él mismo ha registrado (`creado_por = auth.uid()`), mientras que un gerente o admin puede modificar cualquier orden.
  - **Inputs:** `p_orden_id UUID`, `creado_por UUID`.
  - **Comportamiento:**
    1. Modificar políticas RLS en `ordenes_distribucion` para UPDATE/DELETE.
    2. Modificar `actualizar_estado_orden_distribucion` y `anular_orden_distribucion` para validar autoría cuando el ejecutor es vendedor.
  - **Output:** JSON o Excepción `ACCESO_DENEGADO`.

### Módulo de Tasa de Cambio y Multimoneda (Prioridad Alta)

- `[x]` **Tarea DB-013: Creación de la Tabla `tasa_cambio` y RPCs de Gestión (`inserta_tasa_cambio`, `elimina_tasa_cambio`, `retorna_ultima_tasa_cambio`, `retorna_tasas_cambio_por_rango`)**
  - **Función:** Almacena y gestiona las tasas de cambio oficiales (BCV) por fecha.
  - **Tabla `tasa_cambio`:** `fecha_tasa DATE PRIMARY KEY`, `tasa_cambio NUMERIC NOT NULL`, `created_at TIMESTAMPTZ`.
  - **RPC `inserta_tasa_cambio`:**
    - **Inputs:** `p_fecha_tasa DATE` (o `tdfecha_tasa`), `p_tasa NUMERIC` (o `tnTasa`).
    - **Comportamiento:** Inserta un registro de tasa de cambio. Valida que no existan dos fechas iguales. Si la fecha ya existe, retorna excepción.
  - **RPC `elimina_tasa_cambio`:**
    - **Inputs:** `p_fecha_tasa DATE` (o `tdFecha_tasa`).
    - **Comportamiento:** Elimina el registro correspondiente a la fecha dada. (Para modificar una tasa, se debe eliminar primero la fecha y luego insertarla).
  - **RPC `retorna_ultima_tasa_cambio`:**
    - **Inputs:** Ninguno.
    - **Comportamiento:** Retorna el registro con la fecha de tasa más reciente (`ORDER BY fecha_tasa DESC LIMIT 1`).
  - **RPC `retorna_tasas_cambio_por_rango`:**
    - **Inputs:** `p_fecha_desde DATE`, `p_fecha_hasta DATE`.
    - **Comportamiento:** Retorna el arreglo de tasas de cambio registradas entre las fechas indicadas inclusivas.
  - **Output:** JSON `{ success: boolean, data: object, error: object }`.

- `[x]` **Tarea DB-014: Asignación de Vendedor en Ficha de Clientes (`clientes.vendedor_id`)**
  - **Función:** Vincular un usuario con rol vendedor a cada cliente para control de accesos y asignación automática de órdenes.
  - **Modificación DDL:** Agregar columna `vendedor_id UUID REFERENCES perfiles_usuario(id)` en la tabla `clientes`.
  - **Comportamiento:** Permite registrar y consultar el vendedor asignado a cada cliente.

- `[x]` **Tarea DB-015: Campos Multimoneda en Órdenes y Detalle de Distribución**
  - **Función:** Adaptar las estructuras de órdenes de distribución y sus detalles para soportar doble moneda (Bs / USD) y corregir la asignación del total a recaudar en Bolívares.
  - **Modificaciones DDL:**
    - `ordenes_distribucion`: Agregar `tasa_cambio NUMERIC`, `total_recaudar_bs NUMERIC`, `total_recaudar_usd NUMERIC`.
    - `detalle_distribucion`: Agregar `valor_unitario_usd NUMERIC`, `subtotal_recaudar_usd NUMERIC`.
  - **Regla Financiera:** El monto total a recaudar en Bs (`total_recaudar_bs`) debe registrarse como la suma de `subtotal_recaudar` de la tabla `detalle_distribucion`. (Se corrige el uso previo donde se sobreescribía por error `peso_total_calculado`).

- `[x]` **Tarea DB-016: Reglas de Asignación Automática de Tasa de Cambio y Control por Rol al Crear Órdenes**
  - **Función:** Validar la tasa de cambio vigente y aplicar la restricción de cartera de clientes según el rol del usuario al crear una orden de distribución.
  - **Reglas de Negocio:**
    1. **Tasa de Cambio Obligatoria:** Al crear una orden de distribución se debe asignar automáticamente la `tasa_cambio` registrada en `tasa_cambio` para la fecha de la orden (`fecha_despacho::date` o fecha actual). Si no existe tasa para dicha fecha, arroja una excepción `EXCEPCION_TASA_NO_ENCONTRADA`.
    2. **Creación por Rol Vendedor:** El usuario con rol `vendedor` solo puede crear órdenes de distribución para los clientes que tiene asignados (`clientes.vendedor_id = auth.uid()`).
    3. **Creación por Rol Gerente/Admin:** Un usuario con rol `gerente` o `admin` puede crear órdenes a cualquier cliente; el vendedor de la orden será automáticamente el que el cliente tiene configurado en la tabla `clientes`.

- `[x]` **Tarea DB-016b: Modificación de `crear_orden_distribucion` para Incluir Campos Multimoneda**
  - **Función:** Actualizar la función RPC `crear_orden_distribucion` en Supabase para soportar e insertar los nuevos campos de la cabecera y el detalle según la nueva estructura de [docs/Tablas.md](file:///d:/ProyectosWeb/LogiTrack/docs/Tablas.md).
  - **Nuevos Campos a Incluir:**
    - Cabecera (`ordenes_distribucion`): `tasa_cambio`, `total_recaudar_bs` (suma de `subtotal_recaudar` de los detalles), `total_recaudar_usd` (suma de `subtotal_recaudar_usd` de los detalles).
    - Detalle (`detalle_distribucion`): `valor_unitario_usd`, `subtotal_recaudar_usd` (`cantidad_solicitada * valor_unitario_usd`).
  - **Inputs:** `p_vendedor_id UUID`, `p_chofer_id UUID`, `p_cliente_id UUID`, `p_camion_id UUID`, `p_tasa_cambio NUMERIC`, `p_productos_json JSONB` (donde cada objeto contiene `producto_id`, `cantidad`, `valor_unitario_recaudar` (Bs), `valor_unitario_usd` (USD)).
  - **Comportamiento:**
    1. Valida parámetros de entrada y calcula acumulados de peso total (`peso_total_calculado`), total en Bolívares (`total_recaudar_bs`) y total en USD (`total_recaudar_usd`).
    2. Registra la cabecera en `ordenes_distribucion` incluyendo `tasa_cambio`, `total_recaudar_bs` y `total_recaudar_usd`.
    3. Registra cada producto en `detalle_distribucion` guardando `valor_unitario_recaudar`, `subtotal_recaudar` (Bs), `valor_unitario_usd` y `subtotal_recaudar_usd` (USD).
  - **Output:** JSON `{ success: boolean, message: text, orden_id: UUID }`.


- `[x]` **Tarea DB-017: RPC de Actualización de Orden por Correlativo (`actualiza_orden_distribucion_segun_correlativo`)**
  - **Función:** Permite modificar una orden de distribución existente y su detalle a partir de su correlativo numérico.
  - **Inputs:** `p_correlativo INT` (o `tnCorrelativo`), `p_header JSONB`, `p_detalle JSONB`.
  - **Comportamiento:**
    - Actualiza en `ordenes_distribucion`: `cliente_id`, `chofer_id`, `camion_id`, `fecha_despacho`, `peso_total_calculado`, `factura_origen_numero`, `tasa_cambio`, `total_recaudar_bs`, `total_recaudar_usd`.
    - Actualiza en `detalle_distribucion`: `producto_id`, `cantidad_solicitada`, `valor_unitario_recaudar`, `valor_unitario_usd`, `subtotal_recaudar_usd`.
    - Valida que la tasa de cambio exista para la fecha y verifica permisos según el rol del solicitante.
  - **Output:** JSON `{ success: boolean, data: { correlativo: INT, orden_id: UUID }, error: object }`.

- `[x]` **Tarea DB-018: RPC de Consulta de Órdenes por Estado y Rol (`retorna_ordenes_distribucion_segun_estado`)**
  - **Función:** Retorna el listado de órdenes de distribución según un estado especificado (`p_estado TEXT` / `tcEstado`), filtrando los resultados automáticamente según el rol del usuario autenticado.
  - **Inputs:** `p_estado TEXT`.
  - **Comportamiento:**
    - Si el solicitante es un **Vendedor**, retorna únicamente las órdenes de los clientes asignados a su ID (`clientes.vendedor_id = auth.uid()`).
    - Si el solicitante es un **Gerente** o **Admin**, retorna las órdenes de todos los clientes.
  - **Output:** JSON `{ success: boolean, data: ARRAY[ordenes], error: object }`.

- `[x]` **Tarea DB-019: RPC Consulta de Lista de Contenedores (`retorna_lista_contenedores`)**
  - **Función:** Crear la función `retorna_lista_contenedores` que retornará el listado de los contenedores registrados en la tabla `tipos_contenedores`.
  - **Inputs:** Ninguno.
  - **Comportamiento:** Consulta la tabla `tipos_contenedores` devolviendo una lista con los campos `id` y `nombre`.
  - **Output:** JSON `{ success: boolean, data: ARRAY[{ id: UUID, nombre: TEXT }], error: object }`.

- `[x]` **Tarea DB-020: RPC Consulta de Lista de Rutas (`retorna_lista_rutas`)**
  - **Función:** Crear un procedure/función `retorna_lista_rutas` que retorne todos los registros de la tabla `rutas` y la cantidad total de registros retornados.
  - **Inputs:** Ninguno.
  - **Comportamiento:** Consulta la tabla `rutas` devolviendo el listado completo (`id_ruta`, `nombre_ruta`, `descripcion_ruta`, `created_at`) junto con el conteo de registros (`total_registros`).
  - **Output:** JSON `{ success: boolean, total_registros: INT, data: ARRAY[{ id_ruta: UUID, nombre_ruta: TEXT, descripcion_ruta: TEXT, created_at: TIMESTAMP }], error: object }`.
  - **Documentación:** Actualizar `docs/INTEGRACION-RPC.md` con las instrucciones de petición para el programador backend.

- `[x]` **Tarea DB-021: RPC Consulta de Usuarios con Rol Despachador (`retorna_usuarios_despachadores`)**
  - **Función:** Crear un procedure/función `retorna_usuarios_despachadores` que retorne de la tabla `perfiles_usuario` únicamente a las personas con el rol de `despachador`.
  - **Inputs:** Ninguno.
  - **Comportamiento:** Filtra en `perfiles_usuario` aquellos usuarios vinculados al rol `despachador` en la tabla `roles`. Devolviendo `id`, `nombre_completo` y `telefono`.
  - **Output:** JSON `{ success: boolean, data: ARRAY[{ id: UUID, nombre_completo: TEXT, telefono: TEXT }], error: object }`.
  - **Documentación:** Actualizar `docs/INTEGRACION-RPC.md` con las instrucciones de petición para el programador backend.

- `[x]` **Tarea DB-022: RPC Actualización de Ruta por UUID (`actualiza_registro_rutas_segun_uuid`)**
  - **Función:** Crear un procedure/función `actualiza_registro_rutas_segun_uuid` para actualizar la información de una ruta (`nombre_ruta`, `descripcion_ruta`) en la tabla `rutas` según su `id_ruta` (UUID).
  - **Inputs:** `p_id_ruta UUID`, `p_nombre_ruta TEXT`, `p_descripcion_ruta TEXT DEFAULT NULL`.
  - **Comportamiento:** Valida la existencia del `id_ruta` y no vacuidad del nombre. Actualiza los campos y retorna el registro modificado.
  - **Output:** JSON `{ success: boolean, message: TEXT, data: { id_ruta: UUID, nombre_ruta: TEXT, descripcion_ruta: TEXT, created_at: TIMESTAMP }, error: object }`.
  - **Documentación:** Actualizar `docs/INTEGRACION-RPC.md` con las instrucciones de petición para el programador backend.

- `[x]` **Tarea DB-023: RPC Actualización de Cliente por UUID (`actualiza_registro_cliente_segun_uuid`)**
  - **Función:** Crear un procedure/función `actualiza_registro_cliente_segun_uuid` para actualizar las modificaciones hechas desde el formulario frontend a la tabla `clientes` según su `id` (`tnId`).
  - **Inputs:** `p_id UUID` (o `tnId`), `p_rif_nit TEXT DEFAULT NULL`, `p_razon_social TEXT DEFAULT NULL`, `p_direccion_fiscal TEXT DEFAULT NULL`, `p_telefono TEXT DEFAULT NULL`, `p_movil1 TEXT DEFAULT NULL`, `p_movil2 TEXT DEFAULT NULL`, `p_movil3 TEXT DEFAULT NULL`, `p_correo_e TEXT DEFAULT NULL`, `p_cond_liq NUMERIC DEFAULT NULL`, `p_max_liq NUMERIC DEFAULT NULL`, `p_vendedor_id UUID DEFAULT NULL`, `p_despachador_id UUID DEFAULT NULL`, `p_id_ruta UUID DEFAULT NULL`, `p_activo BOOLEAN DEFAULT NULL`.
  - **Comportamiento:** Valida la existencia del cliente por su ID, valida que el RIF/NIT no esté duplicado en otro cliente si es modificado, y actualiza los campos correspondientes en la tabla `public.clientes`.
  - **Output:** JSON `{ success: boolean, message: TEXT, data: { id: UUID, rif_nit: TEXT, razon_social: TEXT, ... }, error: object }`.
  - **Documentación:** Actualizada en `docs/INTEGRACION-RPC.md` con instrucciones de llamado RPC en TypeScript/Next.js.

- `[x]` **Tarea DB-024: Módulo Radar del Despachador (`retorna_radar_despachador`, `registrar_despacho_cliente_radar` y actualización de `liquidar_orden_distribucion`)**
  - **Función:** Proporcionar la vista automática del Radar para el despachador logueado (`c.despachador_id = auth.uid()`), registrar atómicamente en ruta la entrega de mercancía y envases retirados provisionales (`detalle_distribucion`), y procesar la acreditación definitiva a `movimientos_contenedores` y `saldo_contenedores_clientes` al momento de la liquidación aprobada por la gerencia.
  - **Inputs:**
    - `retorna_radar_despachador`: Ninguno (toma `auth.uid()`).
    - `registrar_despacho_cliente_radar`: `p_orden_id UUID`, `p_detalles_json JSONB` (`[{ detalle_id, cantidad_despachada, estado_entrega, motivo_rechazo, contenedores_retirados, contenedor_id }]`).
  - **Comportamiento:**
    - `retorna_radar_despachador` retorna las órdenes `en_transito` de los clientes asignados al despachador logueado.
    - `registrar_despacho_cliente_radar` actualiza `detalle_distribucion` e `inventario_movil` y transiciona la orden a `por_liquidar`.
    - `liquidar_orden_distribucion` toma los envases retirados provisionales al aprobar el cierre de día, genera el registro oficial en `movimientos_contenedores`, rebaja el `saldo_contenedores_clientes` y marca la orden como `liquidada`.
  - **Output:** JSON `{ success: boolean, data: object, error: object }`.
  - **Documentación:** Actualizada en `docs/INTEGRACION-RPC.md` con instrucciones de petición.

- `[x]` **Tarea DB-025: Incorporación de `imagen_path` en `productos` y `perfiles_usuario` y Estándar de Storage**
  - **Función:** Agregar la columna `imagen_path TEXT` a las tablas `public.productos` y `public.perfiles_usuario` para almacenar las rutas relativas de fotografías y avatares, actualizar RPCs de consulta y documentar el estándar para el equipo de desarrollo Front/Backend.
  - **DDL:**
    - `ALTER TABLE public.productos ADD COLUMN IF NOT EXISTS imagen_path TEXT;`
    - `ALTER TABLE public.perfiles_usuario ADD COLUMN IF NOT EXISTS imagen_path TEXT;`
  - **Comportamiento:** Almacena rutas relativas (ej: `/productos/harina-pan.webp`, `/usuarios/avatar-001.webp`). Los RPCs de consulta de productos y radar retornan la propiedad `imagen_path`.
  - **Documentación:** Creada la guía técnica [docs/ESTANDAR-IMAGENES-STORAGE.md](file:///d:/ProyectosWeb/LogiTrack/docs/ESTANDAR-IMAGENES-STORAGE.md) con componentes de Next.js, fallback de imágenes y Server Actions para subida de archivos.

- `[x]` **Tarea DB-026: Módulo de Control de Radares por Despachador (`radars`)**
  - **Función:** Soporte para el control centralizado de radares por fecha y despachador (Sección 4 de `PROPOSICION-CAMBIOS-DB.md`), generación de reportes impresos/digitales, reasignación de órdenes no despachadas y registro atómico del resultado del despacho.
  - **DDL & Estructura:**
    - `CREATE TABLE public.radars (id, correlativo, despachador_id, fecha_despacho, total_cantidad_solicitada, total_cantidad_despachada, total_contenedores_retirados, status_radar, created_at);`
    - `ALTER TABLE public.ordenes_distribucion ADD COLUMN radar_id UUID REFERENCES public.radars(id);`
  - **RPCs Implementadas:**
    - `crear_o_obtener_radar(p_despachador_id, p_fecha_despacho)`: Crea o recupera el radar y vincula órdenes.
    - `retorna_radar_detalle_reporte(p_radar_id)`: Genera el JSON estructurado para el reporte global y detalle de órdenes.
    - `reasignar_orden_a_radar(p_orden_id, p_nuevo_radar_id, p_nueva_fecha)`: Mueve una orden a otro radar o fecha.
    - `guardar_resultado_despacho_radar(p_radar_id, p_despacho_json)`: Guarda atómicamente la hoja de ruta, `movimientos_contenedores`, actualiza estados a `por_liquidar` y marca `status_radar = true`.
  - **Documentación:** Especificado en [docs/INTEGRACION-RPC.md](file:///d:/ProyectosWeb/LogiTrack/docs/INTEGRACION-RPC.md#L700).


### Módulo Backend & Scraping Tasa BCV (Prioridad Media/Alta)

- `[x]` **Tarea MOD-001: Módulo de Mantenimiento de Tasas de Cambio & Scraping BCV Contingencia**
  - **Función:** Proporcionar la interfaz UI para mantenimiento de tasas de cambio y automatizar la captura oficial BCV.
  - **Comportamiento del Módulo de Mantenimiento (UI):**
    1. **Carga Inicial:** Por defecto debe invocar `retorna_ultima_tasa_cambio` para mostrar la última tasa registrada con su fecha.
    2. **Registro y Eliminación:** Permitir al usuario registrar una tasa (`inserta_tasa_cambio`) o eliminar una tasa existente (`elimina_tasa_cambio`).
    3. **Consulta Histórica por Rango:** Permitir filtrar y listar las tasas de cambio dentro de un rango de fechas definido por el usuario (`retorna_tasas_cambio_por_rango`).
  - **Backend Scraping:**
    - Servicio backend que consulta https://www.bcv.org.ve/ para obtener la tasa del día e insertarla en `tasa_cambio`.

- `[x]` **Tarea DB-027: Módulo de Políticas de Crédito y Permisos de Despacho Gerenciales (`clientes` y Radar)**
  - **Función:** Incorporar políticas de crédito en `public.clientes`, controlar el acceso y edición de órdenes en el Radar del despachador según estado crediticio, y permitir otorgar/consumir excepciones de despacho de uso único por parte de la Gerencia.
  - **DDL:**
    - `ALTER TABLE public.clientes ADD COLUMN IF NOT EXISTS limite_credito NUMERIC(14,2) DEFAULT 0.00;`
    - `ALTER TABLE public.clientes ADD COLUMN IF NOT EXISTS max_facturas_vencidas INT DEFAULT 0;`
    - `ALTER TABLE public.clientes ADD COLUMN IF NOT EXISTS permiso_despacho_manual BOOLEAN DEFAULT TRUE;`
    - `ALTER TABLE public.clientes ADD COLUMN IF NOT EXISTS excepcion_despacho_gerencia BOOLEAN DEFAULT FALSE;`
  - **RPCs / Lógica:**
    1. **`retorna_radar_despachador` & `retorna_radar_detalle_reporte`**: Calcular la mora del cliente (deuda acumulada vs `limite_credito` y cantidad de facturas pendientes vs `max_facturas_vencidas`). Si excede los límites y `excepcion_despacho_gerencia = FALSE`, retornar `despacho_permitido = FALSE`.
    2. **`otorgar_excepcion_despacho_gerencia(p_cliente_id UUID)`**: RPC exclusivo para rol `gerente` o `admin` que activa `excepcion_despacho_gerencia = TRUE`.
    3. **`guardar_resultado_despacho_radar` & `registrar_despacho_cliente_radar`**: Al procesar el despacho de la orden, si el cliente estaba bajo excepción gerencial (`excepcion_despacho_gerencia = TRUE`), resetear automáticamente el campo a `FALSE`.
  - **Documentación:** [docs/PROPOSICION-CAMBIOS-DB.md](file:///d:/ProyectosWeb/LogiTrack/docs/PROPOSICION-CAMBIOS-DB.md#L130).

- `[x]` **Tarea DB-028: RPCs de Consulta de Radares por Fecha y Detalle por Radar ID (`retorna_lista_radars_segun_rango_fechas` y `retorna_ordenes_distribucion_segun_idradar`)**
  - **Función:** Proporcionar las consultas almacenadas RPC requeridas por la interfaz Frontend para listar radares ordenados por fecha según rango dado para un despachador y para obtener el detalle resumido de las órdenes contenidas dentro de un `id_radar`.
  - **RPCs Implementadas:**
    1. `retorna_lista_radars_segun_rango_fechas(p_despachador_id UUID, p_fecha_inicial DATE, p_fecha_limite DATE)`: Retorna la lista de radares en el rango con `fecha_despacho`, `id_radar`, `correlativo`, `total_paradas`, `items`, `sku`, `status_radar` y `aprobado`.
    2. `retorna_ordenes_distribucion_segun_idradar(p_radar_id UUID)`: Retorna las órdenes del radar especificado con `id_orden_distribucion`, `correlativo`, `ruta`, `razon_social`, `direccion_fiscal`, `items`, `sku` y `contenedores_retirados`.
  - **Documentación:** Actualizar `docs/INTEGRACION-RPC.md`.

- `[x]` **Tarea DB-029: RPC Cuentas por Liquidar agrupadas por Cliente (`retorna_ordenes_por_liquidar`) y Script de Depuración DB**
  - **Función:** Crear la función RPC `retorna_ordenes_por_liquidar` que agrupa las órdenes en `por_liquidar` por cliente, ordenadas por mayor cantidad de días vencidos, y ejecutar el script de depuración (eliminar órdenes sin detalle y reducir `camiones` a los 3 primeros registros).
  - **RPC Implementada:** `retorna_ordenes_por_liquidar()`
  - **Depuración DB:**
    - `DELETE FROM public.ordenes_distribucion WHERE NOT EXISTS (SELECT 1 FROM public.detalle_distribucion d WHERE d.orden_id = ordenes_distribucion.id);`
    - `UPDATE ordenes_distribucion/inventario_movil SET camion_id = NULL WHERE camion_id NOT IN (SELECT id FROM camiones ORDER BY created_at ASC LIMIT 3);`
    - `DELETE FROM public.camiones WHERE id NOT IN (SELECT id FROM camiones ORDER BY created_at ASC LIMIT 3);`
  - **Documentación:** [docs/INTEGRACION-RPC.md](file:///d:/ProyectosWeb/LogiTrack/docs/INTEGRACION-RPC.md#L1020).

- `[x]` **Tarea DB-030: Módulo de Aprobación de Radar (`solicita_aprobar_radar`), Estado `devuelta`, Transición a `anulada` y Reingreso de Inventario a Almacén (`retorna_inventario_no_despachado_para_almacen`)**
  - **Función:** Actualizar `registrar_despacho_cliente_radar` para que si la cantidad despachada es 0 la orden pase a estado `devuelta` registrando envases devueltos; crear `solicita_aprobar_radar` para cambiar `status_radar = true`, actualizar saldos de contenedores del cliente, reingresar stock no entregado a almacén (`productos.stock_disponible`) y transicionar las órdenes `devuelta` a `anulada`.
  - **DDL & RPCs:**
    - `ALTER TABLE public.radars DROP COLUMN IF EXISTS aprobado;` (estandarización a `status_radar`).
    - Update constraint `ordenes_distribucion_estado_check` para incluir `'devuelta'`.
    - `registrar_despacho_cliente_radar(p_orden_id, p_detalles_json)`: Si despachado = 0 transiciona a `'devuelta'`. Si `status_radar = true` retorna `RADAR_APROBADO_BLOQUEADO`.
    - `solicita_aprobar_radar(p_radar_id)`: Establece `status_radar = true`, acredita contenedores retirados a cliente, reingresa inventario a almacén y pasa órdenes `'devuelta'` a `'anulada'`.
    - `retorna_inventario_no_despachado_para_almacen(p_radar_id)`: Reingresa stock devuelto/no entregado al almacén principal y ajusta `inventario_movil`.
  - **Documentación:** [docs/INTEGRACION-RPC.md](file:///d:/ProyectosWeb/LogiTrack/docs/INTEGRACION-RPC.md#L1053).

- `[x]` **Tarea DB-031: Corrección de Totales Multimoneda (`total_recaudar_bs` vs `total_recaudar_usd`) en Órdenes de Distribución**
  - **Función:** Corregir la asignación de precios unitarios y cálculos multimoneda en `crear_orden_distribucion` y `actualiza_orden_distribucion_segun_correlativo`, asegurando que `total_recaudar_usd` contenga el monto real en USD y `total_recaudar_bs` sea igual a `total_recaudar_usd * tasa_cambio`. Ejecutar script de recálculo de datos en `detalle_distribucion` y `ordenes_distribucion`.
  - **Migración:** `20260909170000_fix_totales_multimoneda_ordenes.sql` aplicada en Supabase.
  - **Documentación:** Actualizada en `docs/INTEGRACION-RPC.md`.

- `[x]` **Tarea DB-032: Omitir Registro de Campos en Bolívares en Órdenes de Distribución (Campos Calculados Exclusivamente en USD)**
  - **Función:** Modificar `crear_orden_distribucion` y `actualiza_orden_distribucion_segun_correlativo` para no registrar valores en `valor_unitario_recaudar`, `subtotal_recaudar` ni `total_recaudar_bs` (fijados como `NULL`). Garantizar la correcta asignación de `valor_unitario_usd` (desde `productos.precio_lista1`), `subtotal_recaudar_usd` y `total_recaudar_usd`. Ejecutar script de actualización de registros existentes y ajustar la interfaz frontend en Next.js.
  - **Migración:** `20260910123500_campos_calculados_ordenes_usd_only.sql`.

- `[x]` **Tarea DB-033: Actualización de Aprobación Gerencial de Radar (`solicita_aprobar_radar`) con Carga de Contenedores Entregados y Políticas de Crédito**
  - **Función:** Actualizar `solicita_aprobar_radar(p_radar_id UUID)` para:
    1. Cargar en el estado de cuenta del cliente (`saldo_contenedores_clientes`) y registrar en `movimientos_contenedores` (`cantidad_entregada`) los envases entregados calculados como `CEIL(cantidad_despachada * unidades_por_contenedor)` para todos los productos despachados con contenedor asignado.
    2. Evaluar para cada cliente participante en el radar si la cantidad de órdenes pendientes por liquidar (`estado = 'por_liquidar'`) alcanza o supera su límite (`max_facturas_vencidas > 0`), en cuyo caso deshabilita su permiso de despacho manual (`clientes.permiso_despacho_manual = FALSE`).
  - **Inputs:** `p_radar_id UUID`.
  - **Output:** JSON `{ success: boolean, message: text, data: { radar_id: UUID, status_radar: true, contenedores_entregados_procesados: INT, contenedores_retirados_procesados: INT, clientes_deshabilitados_credito: INT, ordenes_anuladas: INT, inventario_reintegrado: ARRAY }, error: object }`.

- `[x]` **Tarea DB-034: Recálculo Masivo de Contenedores (`movimientos_contenedores` y `saldo_contenedores_clientes`)**
  - **Función:** Ejecutar un script masivo PL/pgSQL para recalcular atómicamente todos los movimientos de entrega (`CEIL(cantidad_despachada * unidades_por_contenedor)`) y retiros de envases de todas las órdenes despachadas en radares aprobados de la base de datos, resincronizando `saldo_contenedores_clientes`.
  - **Migración:** `20260910181500_recalcular_movimientos_y_saldos_contenedores_masivo.sql`.




