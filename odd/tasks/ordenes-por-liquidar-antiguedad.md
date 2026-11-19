# Feature: Órdenes por liquidar por antigüedad (Cobranzas)
Menú Cobranzas > Órdenes por liquidar, agrupadas por tramos de días vencidos, con exportación a Excel.
"Días vencidos" se cuenta desde la fecha de despacho (`ordenes_distribucion.fecha_despacho`).

## Specs
- S1: "En el menú Cobranzas opción Órdenes por liquidar que se muestren las órdenes por liquidar según la cantidad de días vencidos en el siguiente orden:"
- S2: Tramos, en este orden exacto:
  - "Vencidas menores de 7 días"
  - "entre 7 y 15 días"
  - "entre 16 y 30 días"
  - "entre 31 y 45 días"
  - "entre 46 y 90 días"
  - "Vencidas mayores a 90 días"
  - Aclaración aprobada: 0–6, 7–15, 16–30, 31–45, 46–90, >90 (sin solapes ni huecos).
- S3: "Y que se pueda exportar a excel"
- S4: "Días vencidos" = `CURRENT_DATE - fecha_despacho::date`, calculado por orden (no por cliente).
- S5: Base de datos: nuevo SP `retorna_ordenes_por_liquidar_antiguedad()`, una fila por orden. No modificar `retorna_ordenes_por_liquidar()`. Parche idempotente en `supabase/tenant_patches/`, aplicado solo en `lt_igtest` hasta autorización explícita.
- S6: Documentar el contrato en `docs/INTEGRACION-RPC.md`.

## Tasks
- [x] T1 (S4, S5): Parche SQL idempotente con el SP por orden (`supabase/tenant_patches/20261119134500_ordenes_por_liquidar_antiguedad.sql`). Route: inline. Commit: pendiente
- [ ] T2 (S5): Aplicar en `lt_igtest` y probar. Requiere autorización previa de Jorge. Route: inline. Commit: n/a
- [x] T3 (S1, S2): Tipo en `src/types/database.ts` (`OrdenPorLiquidarDetalle`, `TramoAntiguedadKey`) y action en `src/lib/actions/rendiciones.ts` (`retornaOrdenesPorLiquidarAntiguedadAction`). Route: inline. Commit: pendiente
- [x] T4 (S1, S2): UI en `rendiciones/por-liquidar` con 6 secciones en orden, subtotales (órdenes y monto) y buscador (`src/lib/rendiciones/antiguedad.ts`, `page.tsx`, `por-liquidar-lista.tsx`). Route: inline. Commit: pendiente
- [x] T5 (S3): Excel con un bloque por tramo y resumen (`src/lib/export/por-liquidar-excel.ts`, `export-por-liquidar-excel-button.tsx`). Route: inline. Commit: pendiente
- [x] T6 (S6): Documentar en `docs/INTEGRACION-RPC.md` (sección 23). Route: inline. Commit: pendiente
- [ ] T7: Typecheck (`npx tsc --noEmit` OK). Pasar a producción solo con autorización explícita. Route: inline. Commit: n/a

## Log
- L1: "He creado en raíz una carpeta titulada ODD y dentro de ella, una carpeta titulada tasks.
Dejamos de usar SDD para usar ODD. Necesito que crees una task en formato .md bajo los lineamientos de ODD según gentle-ai.
En el menú Cobranzas opción Órdenes por liquidar que se muestren las órdenes por liquidar según la cantidad de días vencidos en el siguiente orden:
Vencidas menores de 7 días
entre 7 y 15 días
entre 16 y 30 días
entre 31 y 45 días
entre 46 y 90 días
Vencidas mayores a 90 días

Y que se pueda exportar a excel

Analiza si es necesario crear Store procedure en Postgresql y los cambios en el Frontend, me informas antes de crear el documento y proceder"
- L2: "\"Días vencidos\" se cuenta desde la fecha de despacho. Crea el documento"
- L3: "Ahora las tareas se almacenarán en D:\ProyectosWeb\LogiTrack\odd\tasks, guárdalo en tu mente. Ejecuta la tarea ordenes-por-liquidar-antiguedad.md"
