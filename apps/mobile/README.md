# LogiTrack Mobile (APK)

Paridad operativa con el dashboard web Next.js: **mismas secciones NAV**, mismos roles (`admin`, `gerente`, `despachador`, `vendedor`, `chofer`, `cobrador`) y los mismos RPCs/tablas vía cliente Supabase anon + RLS.

La web sigue como backoffice (service role solo en servidor). La APK **nunca** incluye `service_role`. Alta de usuario / reset de clave van por **Edge Functions** (`registrar-usuario`, `reset-password`).

> `apps/mobile-print` está deprecada; la impresión Bluetooth vive aquí.

## Requisitos

- Node 20+
- Cuenta Expo (EAS Build) o Android Studio
- Impresora térmica Bluetooth emparejada (campo)
- Variables en `.env` (copia de `.env.example`):

```env
EXPO_PUBLIC_SUPABASE_URL=https://....supabase.co
EXPO_PUBLIC_SUPABASE_ANON_KEY=eyJ...
```

## Desarrollo

```bash
cd apps/mobile
npm install
npx expo start --dev-client
npm run typecheck
```

**Bluetooth Classic no funciona en Expo Go.** Usa development build / APK:

```bash
npx eas build --profile development --platform android
# o
npx expo prebuild --platform android && npx expo run:android
```

## Módulos (paridad web)

| Área | Rutas móvil |
|---|---|
| Distribución | Visita/cartera, Órdenes (+ nueva/editar), AutoVentas (carga/reverso), Radar |
| Maestros | Clientes (+ descuentos), Rutas, Proveedores, Camiones, Productos, Choferes |
| Inventario | Almacén, Móvil |
| Rendición | Listado, por liquidar, formas de pago, aprobar, Contenedores |
| Compras | Facturas, Pagos proveedores |
| Admin | Tasas, Cuentas bancarias, Usuarios (+ registrar vía Edge) |
| Campo | Impresora BT, Cuenta |

Navegación: **Drawer** filtrado por `ROLE_ALLOWED_HREFS` (espejo web).

## Roles — checklist QA

| Rol | Entrada | Verificar |
|---|---|---|
| admin | Drawer completo | CRUD maestros, aprobar rendición, registrar usuario, tasas |
| gerente | Casi todo (sin registrar usuario si no aplica) | Por liquidar, formas de pago, KPIs home |
| despachador | Radar home | Radar, AutoVentas carga, órdenes consulta, contenedores |
| vendedor | Home | Visita, órdenes nueva, radar, rendición, AutoVentas |
| chofer | Órdenes | Órdenes + inventario móvil |
| cobrador | Rendiciones | Por liquidar, nueva rendición, contenedores, clientes |

## Impresión

1. Emparejar térmica en Ajustes → Bluetooth.
2. Menú → Impresora → Usar + Probar.
3. Órdenes → detalle → Imprimir ticket.

## Edge Functions (admin auth)

Desplegar desde la raíz del monorepo:

```bash
supabase functions deploy registrar-usuario
supabase functions deploy reset-password
```

Requieren `SUPABASE_SERVICE_ROLE_KEY` en el entorno de la función.

## Criterio de paridad

1. Ruta móvil equivalente accesible según el mismo rol.
2. Mutaciones con el mismo RPC/tabla (o Edge Function si exige service role).
3. `npm run typecheck` en `apps/mobile` pasa.
4. Checklist del rol OK en dispositivo.
