# ANÁLISIS ARQUITECTÓNICO: ÓRDENES DE DISTRIBUCIÓN POR CORTESÍA

**Rol:** Eres Antigravity DB, el ingeniero de datos en Supabase (PostgreSQL) para el proyecto Logitrack.

**Contexto del Negocio:**
Ocasionalmente, la empresa entrega productos sin costo a los clientes mediante "Órdenes de Distribución por Cortesía".
- **Regla 1 (Inventario):** Estas órdenes SÍ deben rebajar el inventario (afectan el stock móvil/almacén exactamente igual que una venta normal).
- **Regla 2 (Rendición/Finanzas):** Estas órdenes NO deben sumar al cálculo de dinero en la rendición de cuentas del camión, ni generar deudas en cuentas por cobrar. 
- **Regla 3 (Alcance):** La cortesía se aplica a nivel de cabecera (toda la orden es de cortesía), por lo que todos los productos incluidos en esa orden específica no tendrán precio de venta ni costo cobrable.

**Mi Propuesta Inicial:**
Estoy evaluando modificar la tabla `ordenes_distribucion` añadiendo un campo booleano (ej. `es_cortesia = true`), por defecto estaría en false y agregando un nuevo estado/tipo (ej. `estado = 'cortesia'`).

## TAREA REQUERIDA ANTES DE PROGRAMAR

Analiza mi solicitud basándote en tu conocimiento del esquema actual y de las funciones RPC existentes. Estás plenamente autorizado para evaluar mi propuesta y sugerir la vía más óptima, segura y escalable a nivel de base de datos.

**Entregable Inmediato:**
NO ejecutes código DDL ni alteres la base de datos todavía. Preséntame primero un **IMPLEMENTATION-PLAN** detallado que contenga:

1. **Evaluación de Alternativas:** ¿Qué opción recomiendas para PostgreSQL en este contexto? ¿Un booleano, un enum de estado, o un "tipo de documento"? Justifica tu respuesta considerando la indexación y las consultas de rendición.
2. **Manejo del Detalle:** ¿Cómo propones que manejemos los precios en el detalle de la orden? (¿Forzar a que se inserten con valor 0.00 desde el RPC, o ignorarlos mediante un condicional en las consultas de rendición basándonos en la cabecera?).
3. **Análisis de Impacto (RPCs):** Identifica qué funciones existentes (como la de rendición de camión) tendrían que ser refactorizadas obligatoriamente para excluir estas órdenes del flujo de dinero, pero mantenerlas en el flujo de "productos despachados".