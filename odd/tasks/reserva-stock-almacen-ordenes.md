# Feature: Reserva Inmediata de Stock en Almacén para Notas de Distribución

- **Objective**: Enforce immediate warehouse stock reservation (`stock_disponible` -> `stock_comprometido`) on distribution note creation/editing, release/consume accurately on cancellation/dispatch/truck-load, and align Web + Mobile APK UI validations.
- **Branch**: `fix/reserva-stock-almacen-ordenes` | **Delivery Strategy**: `ask-on-risk` | **Checks**: `npx tsc --noEmit` (Web), `npm --prefix apps/mobile run typecheck` (Mobile), SQL static/idempotency review (DB staging `lt_igtest` pending explicit user authorization).

## Specs

- **S1**: "Revisar el manejo de existencia en inventario almacén al momento de crear o registrar una nota de distribucción a nivel de Supabase, Frontend y APK. Cuando el inventario de cualquier producto está en cero, el aplicativo no permite el registro de disho producto, pero cuando existe al menos uno en inventario de cualquier producto, y el pedido supera el mismo, el sistema lo está permitiendo."
- **S2**: "El esquema 1, reserva inmediata en almacén. Importante, si quedan 5 unidades en almacén, el vendedor no puede comprometer mas de esas unidades."
  - **Acceptance (DB)**:
    - `ordenes_distribucion.stock_reservado BOOLEAN NOT NULL DEFAULT FALSE` tracks whether an order currently holds reserved units in `inventario_almacen.stock_comprometido`.
    - `crear_orden_distribucion` locks `inventario_almacen FOR UPDATE` (ordered by `producto_id`), aggregates requested qty per SKU, rejects if `stock_disponible < cantidad_solicitada` (`STOCK_INSUFICIENTE_ALMACEN`), and atomically moves `stock_disponible -> stock_comprometido` with `stock_reservado = TRUE`.
    - `actualiza_orden_distribucion_segun_correlativo` locks affected SKUs `FOR UPDATE`, computes net delta (when `stock_reservado = TRUE`) or full qty (when `stock_reservado = FALSE`), rejects if insufficient `stock_disponible`, adjusts `stock_disponible` / `stock_comprometido`, and sets `stock_reservado = TRUE`.
    - `anular_orden_distribucion` releases reserved `stock_comprometido -> stock_disponible` when cancelling a `borrador`/`aprobada` order with `stock_reservado = TRUE`, setting `stock_reservado = FALSE`.
    - `generar_despacho_orden_almacen` consumes `stock_comprometido` first when `stock_reservado = TRUE` (preventing double deduction), validates remaining against `stock_disponible`, and sets `stock_reservado = FALSE`.
    - `solicita_cargar_inventario_movil_desde_almacen` locks `inventario_almacen FOR UPDATE`, consumes `stock_comprometido` ONLY up to what this Radar's reserved orders hold (0 for AutoVentas), strictly rejects if `stock_disponible < faltante` (`STOCK_INSUFICIENTE_ALMACEN`) instead of clamping with `GREATEST(0, ...)`, and clears `stock_reservado = FALSE` on radar orders moving to `en_transito`.
    - Document contract changes in `docs/INTEGRACION-RPC.md`.
- **S3**: Web Frontend & Mobile APK stock enforcement:
  - **Web**: `ProductoCatalogo` clamps default/typed quantity to `stock_disponible`, disables/blocks exceeding `stock_disponible` including repeated "Añadir más" (respecting already-in-cart qty); `NuevaOrdenForm`, `EditarOrdenForm`, and `AutoVentasClient` enforce `cantidad <= maxDisponible` (for `EditarOrdenForm`, `maxDisponible = stock_disponible + cantidad_previa_en_orden` when editing an existing reserved line); Server Actions validate positive integers and propagate clear RPC errors.
  - **Mobile APK**: `NuevaOrdenScreen`, `EditarOrdenScreen`, and `AutoVentasScreen` disable/block `stock_disponible <= 0` and enforce `cantidad <= maxDisponible` on add, increment, manual edit, and submit.
- **S4**: "Crea los parches y me informas cuando vayas a implantar en Supabase"
  - **Safety gate**: Do NOT execute `supabase db push` or apply SQL patches to `lt_igtest` or production, do NOT `git push`, and do NOT run `eas build` without explicit user authorization.

## Tasks

- [x] **T1** (S1, S2, S4) | Route: `inline` (single coherent DB unit) | Risk: High (Items 1, 3, 4) | Created idempotent patch `supabase/tenant_patches/20261124160000_reserva_stock_almacen_ordenes.sql` + documented §24 in `docs/INTEGRACION-RPC.md`. Commit: `0533e28`.
- [x] **T2** (S1, S2, S3) | Route: `inline` (small UI changes) | Risk: Medium | Enforced stock caps in Web (`ProductoCatalogo`, `NuevaOrdenForm`, `EditarOrdenForm`, `AutoVentasClient`) + verified `npx tsc --noEmit` (exit 0). Commit: `5c0a3b1`.
- [x] **T3** (S1, S2, S3) | Route: `inline` (small UI changes) | Risk: Medium | Enforced stock=0 block and upper stock caps in Mobile APK (`nueva.tsx`, `editar/[id].tsx`, `autoventas/index.tsx`) + verified `npm --prefix apps/mobile run typecheck` (0 errors in touched files; 2 pre-existing `TS2307` in untouched `rendiciones/nueva.tsx` and `lib/print-orden.ts`). Commit: `84175b4`.
- [x] **T4** (S2, S3, S4) | Route: `delegated` (`odd-verifier`, read-only) | Independent verification passed all specs `S1..S4` with 0 blockers (5 minor advisories noted). Pending explicit user authorization to apply SQL patch to `lt_igtest`.

## Log

- **L1 (2026-11-24)**: User request verbatim:
  > Revisar el manejo de existencia en inventario almacén al momento de crear o registrar una nota de distribucción a nivel de Supabase, Frontend y APK. Cuando el inventario de cualquier producto está en cero, el aplicativo no permite el registro de disho producto, pero cuando existe al menos uno en inventario de cualquier producto, y el pedido supera el mismo, el sistema lo está permitiendo.  Analiza y verifica seguiendo la reglas de ODD y me informas antes de proceder
- **L2 (2026-11-24)**: User authorization verbatim:
  > El esquema 1, reserva inmediata en almacén. Importante, si quedan 5 unidades en almacén, el vendedor no puede comprometer mas de esas unidades. Crea los parches y me informas cuando vayas a implantar en Supabase
- **L3 (2026-11-24)**: Architectural analysis: Adding `ordenes_distribucion.stock_reservado BOOLEAN NOT NULL DEFAULT FALSE` cleanly distinguishes pre-patch/reversed/reprogrammed orders from newly reserved orders so `actualiza_orden_distribucion_segun_correlativo`, `anular_orden_distribucion`, `generar_despacho_orden_almacen`, and `solicita_cargar_inventario_movil_desde_almacen` maintain `physical_stock == stock_disponible + stock_comprometido` with zero double-deduction and zero phantom truck stock.
- **L4 (2026-11-24)**: Verification & Status:
  - Commits on `fix/reserva-stock-almacen-ordenes`: `0533e28` (T1 DB patch + `docs/INTEGRACION-RPC.md`), `5c0a3b1` (T2 Web), `84175b4` (T3 Mobile APK).
  - Checks: `npx tsc --noEmit` (Web) passed (exit 0); `npm --prefix apps/mobile run typecheck` passed with 0 errors in touched files (2 pre-existing `TS2307` on `expo-image-picker`/`expo-print` in untouched files); independent read-only verifier (`odd-verifier`) passed `S1..S4` with 0 blockers.
  - Next step: Present exact deployment plan for Supabase staging `lt_igtest` (`dcikhsfzmnzoktkxxxuy`) and wait for explicit user authorization before executing any remote DB or git push action.
- **L5 (2026-11-24)**: User authorized and confirmed testing in `lt_igtest`, then authorized applying the patch to the principal Supabase project (`egwryptydgxdnjvwtrfq`) and pushing to GitHub. Patch applied to both `lt_igtest` (`dcikhsfzmnzoktkxxxuy`) and principal (`egwryptydgxdnjvwtrfq`).
