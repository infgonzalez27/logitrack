# Feature: Consulta y gestión directa de descuentos por cliente
Acceso directo desde el módulo de clientes para consultar clientes con descuentos, activar/desactivar descuentos de forma masiva o por producto, editar porcentajes y agregar productos con descuento.
Opera sobre la tabla `descuentos_cliente_producto` manteniendo el flujo actual de registro en el cliente.

## Specs
- S1: "Es necesario consultar los descuentos de forma directa, para eso, en el módulo de clientes, crea un botón titulado descuentos, cuando el usuario haga clic en ese botón que muestre los clientes que tienen descuentos"
- S2: "y en ese módulo crea un botón que se titule \"Desactivar descuentos\" este botón debe desactivar todos los descuentos de todos los productos en los clientes que tengan descuentos, es decir, de la tabla descuentos_cliente_producto cambiar el campo activo a false de todos los productos de todos los clientes."
- S3: "Cuando todos los descuentos estén desactivados, entonces el título del botón debe decir \"Activar descuentos\""
- S4: "En el listado de clientes con descuentos, al darle clic e un cliente, en un nuevo módulo que muestra los productos con descuentos de ese cliente, los porcentajes de descuentos deben ser editables para poder modificarlo y por cada producto, un botón para desactivar o activar el descuento"
- S5: "y un botón para agregar un producto con descuento."
- S6: "Que se mantenga la manera de registrar productos con descuentos a los clientes como se viene haciendo actualmente."
- S7: "analice si es necesario crear Funciones dentro de Supabase."
- S8: "primero haga un análisis e informe los procedimientos que se deben hacer antes de implementar"
- S9: "\"Activar descuentos\" reactiva todos los descuentos. Si el usuario desactiva todos los descuentos, y luego se mete en un cliente especifico y activa algún descuento, entonces el botón en general vuelve a \"Desactivar descuentos\" porque existe al menos un descuento activo."
- S10: "Esto solo lo puede hacer el rol de gerente" — "a todo el módulo" (validar en UI, rutas y server actions que `rol === "gerente"`).
- Decisión T0: no se crean funciones/RPC ni parches SQL; todo con server actions en `src/lib/actions/descuentos.ts`.

## Tasks
- [x] T0 (S7, S8): Analizar si es necesario crear funciones/RPC en Supabase (o si alcanza con consultas/updates directos sobre `descuentos_cliente_producto`) e informar al usuario los procedimientos a realizar antes de implementar. Resultado: no se requiere RPC; todo con server actions (ver informe en chat). Route: inline. Commit: n/a
- [x] T1 (S1, S2, S3, S9, S10): Server actions en `src/lib/actions/descuentos.ts` (`obtenerClientesConDescuentosAction`, `toggleTodosDescuentosAction`) con guardia `rol === "gerente"`. Route: inline. Commit: pendiente
- [x] T2 (S4, S5, S10): Server actions en `src/lib/actions/descuentos.ts` (`obtenerTodosDescuentosClienteAction`, `actualizarPorcentajeDescuentoAction`, `toggleDescuentoProductoAction`) con guardia `rol === "gerente"` y reutilización de `guardarDescuentoClienteAction`. Route: inline. Commit: pendiente
- [x] T3 (S1, S2, S3, S9, S10): Botón `Descuentos` en `src/app/(dashboard)/clientes/page.tsx` (solo gerente) y módulo `/clientes/descuentos` con listado de clientes con descuentos y botón `"Desactivar descuentos"` / `"Activar descuentos"`. Route: inline. Commit: pendiente
- [x] T4 (S4, S5, S10): Módulo `/clientes/descuentos/[clienteId]` con edición de `porcentaje_descuento`, botón `Desactivar`/`Activar` por producto y modal para agregar producto con descuento. Route: inline. Commit: pendiente
- [x] T5 (S6): Verificar que el registro actual de productos con descuentos en clientes se mantiene intacto y validar con `npx tsc --noEmit` (OK, exit code 0). Route: inline. Commit: pendiente

## Log
- L1: "Crea un documento en la carpeta de tasks con la siguiente solicitud de tarea
Es necesario consultar los descuentos de forma directa, para eso, en el módulo de clientes, crea un botón titulado descuentos, cuando el usuario haga clic en ese botón que muestre los clientes que tienen descuentos y en ese módulo crea un botón que se titule 
"Desactivar descuentos" este botón debe desactivar todos los descuentos de todos los productos en los clientes que tengan descuentos, es decir, de la tabla descuentos_cliente_producto cambiar el campo activo a false de todos los productos de todos los clientes.
Cuando todos los descuentos estén desactivados, entonces el título del botón debe decir "Activar descuentos"
En el listado de clientes con descuentos, al darle clic e un cliente, en un nuevo módulo que muestra los productos con descuentos de ese cliente, los porcentajes de descuentos deben ser editables para poder modificarlo y por cada producto, un botón para desactivar o activar el descuento
y un botón para agregar un producto con descuento.
Que se mantenga la manera de registrar productos con descuentos a los clientes como se viene haciendo actualmente."
- L2: "Agrega en el documento que analice si es necesario crear Funciones dentro de Supabase.
Agrega que primero haga un análisis e informe los procedimientos que se deben hacer antes de implementar"
- L3: "\"Activar descuentos\" reactiva todos los descuentos. Si el usuario desactiva todos los descuentos, y luego se mete en un cliente especifico y activa algún descuento, entonces el botón en general vuelve a \"Desactivar descuentos\" porque existe al menos un descuento activo.
Esto solo lo puede hacer el rol de gerente"
- L4: "a todo el módulo"
