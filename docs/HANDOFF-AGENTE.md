# LogiTrack — Documentación de handoff para agente / desarrollador

> **Repositorio:** https://github.com/infgonzalez27/logitrack  
> **Stack:** Next.js 16 (App Router) + TypeScript + Tailwind CSS v4 + Supabase  
> **Idioma UI:** Español  
> **Última actualización:** Junio 2026

---

## 1. Objetivo del proyecto

**LogiTrack** es un sistema de distribución, inventario y despacho logístico. El frontend consume Supabase (PostgreSQL + Auth + RLS). La lógica crítica de negocio (transiciones de estado, stock, liquidaciones) **aún debe implementarse en stored procedures** en la BD; el front hoy hace CRUD directo y updates simples de estado.

**Módulo prioritario:** Módulo 3 — Órdenes de distribución (`ordenes_distribucion` + `detalle_distribucion`).

---

## 2. Inicio rápido

```bash
git clone https://github.com/infgonzalez27/logitrack.git
cd logitrack
npm install
cp .env.example .env.local   # o .env
# Completar variables (ver sección 3)
npm run dev
```

Abrir http://localhost:3000 → redirige a `/login` o `/ordenes` según sesión.

```bash
npm run build   # verificar producción
npm run lint
```

---

## 3. Variables de entorno

| Variable | Dónde obtenerla | Uso |
|----------|-----------------|-----|
| `NEXT_PUBLIC_SUPABASE_URL` | Supabase → Project Settings → API → **Project URL** | Cliente browser + servidor |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | API → **anon public** | Cliente público (con RLS) |
| `SUPABASE_SERVICE_ROLE_KEY` | API → **service_role** (secreta) | Solo servidor: registro RPC, health check, lectura roles |

**Nunca** commitear `.env`. **Nunca** exponer `service_role` en el cliente ni en variables `NEXT_PUBLIC_*`.

Archivo plantilla: `.env.example`

---

## 4. Supabase — proyecto y esquema

- **Project ref:** `egwryptydgxdnjvwtrfq`
- **URL:** `https://egwryptydgxdnjvwtrfq.supabase.co`
- DDL completo de tablas: `assets/docs/Estructuras de tablas.txt`

### Módulos de tablas

| Módulo | Tablas principales |
|--------|-------------------|
| 0 — Seguridad | `roles`, `permisos`, `roles_permisos`, `perfiles_usuario`, `logs_auditoria` |
| 1 — Maestros | `clientes`, `proveedores`, `camiones`, `choferes` |
| 2 — Inventario | `productos`, `inventario_almacen`, `inventario_movil` |
| 3 — Distribución | `ordenes_distribucion`, `detalle_distribucion` |
| 4 — Rendiciones | `rendiciones_cuentas`, `detalle_rendicion_ordenes`, `detalle_rendicion_pagos` |
| 5 — Compras | `facturas_compras`, `detalle_facturas_compras`, `pagos_proveedores`, `detalle_pago_facturas`, `detalle_pago_metodos` |

### Roles en BD (seed existente)

- `admin`
- `despachador`
- `chofer_cobrador`
- `gerente`

### RLS

En desarrollo hay políticas abiertas para `authenticated` en varias tablas. La tabla `roles` **no** es legible con anon key; el front usa **service role en servidor** para poblar el selector de roles (`src/lib/data/roles.ts`).

---

## 5. RPC crítico — Registro de usuarios

El programador de BD indicó usar este patrón (solo con **admin client** en servidor):

```typescript
const { data, error } = await supabaseAdmin.rpc('registra_nuevo_usuario', {
  p_email: email,
  p_password: password,
  p_nombre_completo: nombre,
  p_telefono: telefono,
  p_rol_nombre: rol,
});
```

Implementado en: `src/lib/actions/auth.ts` → `registerUserAction`

Rutas de registro:
- `/register` (pública en dev)
- `/usuarios/registrar` (dentro del dashboard)

---

## 6. Autenticación y sesión

| Ruta | Descripción |
|------|-------------|
| `/login` | Login con `signInWithPassword` en el **cliente** (`src/app/(auth)/login/login-form.tsx`) |
| `/register` | Registro vía RPC + server action |
| Middleware | `src/middleware.ts` → `src/lib/supabase/middleware.ts` protege rutas; públicas: `/login`, `/register`, `/api/*` |

### Clientes Supabase

| Archivo | Uso |
|---------|-----|
| `src/lib/supabase/client.ts` | Navegador |
| `src/lib/supabase/server.ts` | Server Components / actions |
| `src/lib/supabase/admin.ts` | Service role (solo servidor) |
| `src/lib/supabase/middleware.ts` | Refresh de sesión + redirect |

### Diagnóstico

```
GET /api/health
GET /api/health?email=usuario@dominio.com
```

Devuelve conteo de roles/perfiles y estado del usuario en Auth (requiere service role).

---

## 7. Problema conocido — Login / Auth API

**Síntoma reportado:** al iniciar sesión aparece *"No se pudo conectar con el servidor. Intenta de nuevo."*

**Causa probable:** la API de Supabase Auth (`/auth/v1/...`) falla desde el entorno del cliente o servidor con errores serializados como JSON `{"url":"..."}`. La API REST (`/rest/v1/...`) sí responde (roles, perfiles OK).

**Qué revisar en Supabase Dashboard:**

1. **Authentication → Providers → Email** — habilitado
2. **Authentication → Users** — el usuario existe y está confirmado
3. **Project Settings → API** — URL y keys coinciden con `.env`
4. En desarrollo: desactivar *Confirm email* o confirmar manualmente al usuario
5. Verificar que el proyecto no esté pausado

**Usuario de prueba mencionado:** `gonzalezadonis16@gmail.com` (verificar en Auth → Users)

**Código de errores:** `src/lib/errors.ts` → `formatSupabaseError` / `toDisplayError`

---

## 8. Estructura del frontend

```
src/
├── app/
│   ├── (auth)/          # login, register
│   ├── (dashboard)/     # app principal con sidebar
│   │   ├── ordenes/     # Módulo 3 (listado, nuevo, [id])
│   │   ├── clientes/, proveedores/, camiones/, choferes/
│   │   ├── productos/, inventario-almacen/, inventario-movil/
│   │   ├── rendiciones/, facturas-compras/, pagos-proveedores/
│   │   └── usuarios/
│   └── api/health/      # diagnóstico BD
├── components/          # UI (button, input, table, sidebar…)
├── lib/
│   ├── actions/         # server actions (auth, entities, ordenes)
│   ├── supabase/
│   ├── data/roles.ts
│   ├── constants.ts     # estados, navegación
│   └── errors.ts
├── types/database.ts    # tipos TypeScript del esquema
└── middleware.ts
```

### Rutas principales

| Ruta | Función |
|------|---------|
| `/ordenes` | Listado órdenes de distribución |
| `/ordenes/nuevo` | Crear orden (maestro-detalle en borrador) |
| `/ordenes/[id]` | Detalle + cambio de estado |
| `/clientes`, `/productos`, etc. | CRUD maestros |
| `/usuarios` | Listado perfiles |

### Estados orden (`ordenes_distribucion.estado`)

`borrador` → `lista_para_carga` → `en_transito` → `liquidada` | `anulada`

Transiciones actuales: updates directos en `src/lib/actions/ordenes.ts` → **reemplazar por SP cuando existan**.

---

## 9. Pendientes (prioridad para el siguiente agente)

### Alta prioridad

1. **Resolver login / Auth API** — ver sección 7
2. **Implementar stored procedures** en BD para:
   - Crear orden + líneas
   - `lista_para_carga` (reservar stock almacén)
   - Carga a `inventario_movil`
   - `en_transito`, entregas parciales/rechazos
   - `liquidada`, `anulada`
3. Conectar front a RPC/SP en lugar de inserts/updates directos

### Media prioridad

4. Permisos por rol (RLS definitivo + UI condicional)
5. Detalle completo módulos 4 y 5 (rendiciones con detalles, facturas con líneas)
6. Regenerar tipos desde Supabase CLI (`supabase gen types typescript`)
7. Pantalla móvil para choferes

### Baja prioridad

8. shadcn/ui u otro design system si se requiere
9. Tests E2E (Playwright)

---

## 10. Convenciones de código

- App Router, Server Components por defecto; `"use client"` solo para formularios interactivos
- Server Actions en `src/lib/actions/`
- Mensajes de error vía `toDisplayError()` — no renderizar objetos crudos
- Joins Supabase pueden devolver objeto o array → usar `joinOne()` en `src/lib/supabase/join.ts`
- No commitear secretos; `.gitignore` incluye `.env`

---

## 11. Contacto / contexto

- Esquema BD: `assets/docs/Estructuras de tablas.txt`
- Registro usuarios: RPC `registra_nuevo_usuario` (definido en BD, no en este repo)
- Stored procedures: **pendientes** — coordinar con programador de BD

---

## 12. Comandos útiles

```bash
# Desarrollo
npm run dev

# Si el puerto 3000 está ocupado
npx kill-port 3000   # o taskkill en Windows

# Verificar usuario
curl "http://localhost:3000/api/health?email=TU_EMAIL"

# Build producción
npm run build && npm start
```

---

*Documento generado para continuidad entre equipos. Actualizar al resolver login y al integrar stored procedures.*
