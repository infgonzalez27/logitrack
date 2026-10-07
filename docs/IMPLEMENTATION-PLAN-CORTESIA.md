# IMPLEMENTATION-PLAN: Órdenes de Distribución por Cortesía

## 1. Evaluación de Alternativas (Esquema de Base de Datos)
**Recomendación:** Agregar un campo **booleano** `es_cortesia BOOLEAN DEFAULT FALSE` a la tabla `ordenes_distribucion`.

**Justificación:**
*   **Preservación del Ciclo de Vida:** Si usáramos `estado = 'cortesia'`, romperíamos la máquina de estados logísticos (`borrador` -> `aprobada` -> `en_transito` -> `despachada` -> `liquidada`). Una orden de cortesía sigue necesitando ser preparada en almacén, subida al camión y entregada físicamente al cliente. El booleano permite que el flujo logístico sea idéntico al de una venta normal.
*   **Consistencia de Diseño:** La tabla ya utiliza un patrón de flags booleanos para identificar naturalezas de la orden (ej. `es_autoventa BOOLEAN DEFAULT FALSE`). Añadir `es_cortesia` mantiene la coherencia con el esquema existente sin requerir una migración masiva a un modelo de `tipo_documento`.

## 2. Manejo del Detalle y Precios
**Recomendación:** **Forzar la inserción de valor `0.00`** en la cabecera y en los detalles directamente desde los RPC de creación, en lugar de ignorarlos condicionalmente en las consultas de lectura y rendición.

**Justificación:**
Si guardáramos el "precio real" en la base de datos pero pidiéramos a todas las consultas financieras que hagan un `WHERE es_cortesia = false`, crearíamos un riesgo enorme. Si en el futuro se crea un nuevo dashboard o reporte y el programador olvida incluir esa cláusula, las ventas de la empresa aparecerían infladas. 
Al forzar que en el momento del `INSERT` la cabecera (`total_recaudar_usd`, `total_recaudar_bs`) y el detalle (`valor_unitario_usd`, `subtotal_recaudar_usd`, `monto_descuento_usd`) sean `0.00`, aseguramos que **cualquier función de agregación estándar (`SUM()`) resolverá naturalmente a cero dinero**, eliminando el riesgo de cuentas por cobrar fantasmas. (El peso y las cantidades sí se mantienen intactos para rebajar el inventario correctamente).

## 3. Análisis de Impacto en Funciones RPC
La implementación obligará a refactorizar las siguientes funciones:

1.  **`crear_orden_distribucion.sql` (Impacto Alto):**
    *   **Cambio:** Recibir nuevo parámetro `p_es_cortesia BOOLEAN DEFAULT FALSE`.
    *   **Lógica:** Si es `true`, saltar las reglas de `descuentos_cliente_producto` y asignar `0.00` a las variables de subtotal y precio, e insertar el flag `es_cortesia = true` en la cabecera. Esto aplicará también a las **Ventas Directas** que utilicen este flujo.

2.  **Ventas Directas (Impacto Medio):**
    *   **Cambio:** Asegurar que el flujo de Ventas Directas (sea a través de `crear_orden_distribucion` u otro RPC dedicado) reciba el parámetro `p_es_cortesia`.
    *   **Lógica:** Al ser venta directa por cortesía, el inventario se rebajará inmediatamente (o según el flujo normal), pero no generará obligación de pago ni se reflejará en ingresos financieros.

3.  **`registrar_venta_en_ruta_autoventa.sql` (Impacto Medio):**
    *   **Cambio:** Recibir parámetro `p_es_cortesia`. Forzar los valores monetarios a 0.00 y guardar el flag `es_cortesia = true`.

4.  **`solicita_abonos_orden_distribucion.sql` (Impacto Preventivo):**
    *   **Cambio:** Añadir una validación temprana que arroje una excepción (`RAISE EXCEPTION`) si se intenta registrar un abono / pago a una orden donde `es_cortesia = true`.

5.  **`retorna_resumen_autoventas_jornada.sql` / Resúmenes de Ventas (Impacto Visual):**
    *   **Cambio:** Excluir explícitamente las cortesías de las sumatorias de "ventas del día", o mejor aún, añadir un contador separado para "Cortesías Entregadas" que sume las unidades/kilos pero no dinero.

6.  **`reporte_formas_pago_rendicion.sql` (Sin Impacto / Seguro):**
    *   Dado que este reporte lee de `detalle_rendicion_fpagos` (pagos reales registrados), las cortesías simplemente no generarán pagos (al ser de valor cero), por lo que no aparecerán aquí. La estrategia de forzar precio `0.00` protege este flujo de forma natural.

## 4. Pasos Siguientes
1. Crear el parche de base de datos idempotente (`supabase/tenant_patches/AAAAMMDDHHMMSS_add_es_cortesia.sql`) añadiendo la columna.
2. Modificar el RPC `crear_orden_distribucion.sql` y flujos de Ventas Directas/Autoventa.
3. Modificar el RPC `solicita_abonos_orden_distribucion.sql` (bloqueo preventivo).
4. Actualizar `docs/INTEGRACION-RPC.md` informando al Frontend de los nuevos parámetros.
