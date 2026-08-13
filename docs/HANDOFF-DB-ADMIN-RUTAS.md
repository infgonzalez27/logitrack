# Handoff DB Admin — Rutas y despachadores (DB-020 / DB-021 / DB-022)

**Proyecto:** LogiTrack  
**Fecha:** 2026-08-13  
**Solicitante:** Front/Backend  
**Estado front:** listo en `main` (commit `516fe27`) — pendiente aplicar SQL en Supabase  

El frontend ya consume estos RPCs. Sin aplicar este SQL, fallarán:

- `/rutas` (listar / editar)
- Alta de cliente (selects de ruta y despachador)

---

## 1. Qué hay que aplicar (en este orden)

Todos los scripts están en el repo, rama `main`:

| Orden | Archivo | Qué hace |
|------:|---------|----------|
| 1 | `supabase/migrations/20260813121700_agregar_despachador_id_clientes.sql` | Columna `clientes.despachador_id` (UUID → `perfiles_usuario`) |
| 2 | `supabase/migrations/20260813124400_crear_tabla_rutas_y_relacion_clientes.sql` | Tabla `rutas` + RLS + `clientes.id_ruta` |
| 3 | `supabase/migrations/20260813125100_retorna_lista_rutas.sql` | RPC `retorna_lista_rutas()` — **DB-020** |
| 4 | `supabase/migrations/20260813125200_retorna_usuarios_despachadores.sql` | RPC `retorna_usuarios_despachadores()` — **DB-021** |
| 5 | `supabase/migrations/20260813125600_actualiza_registro_rutas_segun_uuid.sql` | RPC `actualiza_registro_rutas_segun_uuid(...)` — **DB-022** |

Copia de referencia de las funciones (mismo SQL):

- `db/functions/retorna_lista_rutas.sql`
- `db/functions/retorna_usuarios_despachadores.sql`
- `db/functions/actualiza_registro_rutas_segun_uuid.sql`

**Cómo aplicarlo:** SQL Editor de Supabase (proyecto `egwryptydgxdnjvwtrfq`), ejecutando cada archivo completo, en el orden de la tabla.  
Si usan CLI: `supabase db push` / migraciones locales equivalentes.

---

## 2. Grants obligatorios (no están en las migraciones)

Tras crear las funciones `SECURITY DEFINER`, conceder ejecución a autenticados:

```sql
GRANT EXECUTE ON FUNCTION public.retorna_lista_rutas() TO authenticated;
GRANT EXECUTE ON FUNCTION public.retorna_usuarios_despachadores() TO authenticated;
GRANT EXECUTE ON FUNCTION public.actualiza_registro_rutas_segun_uuid(UUID, TEXT, TEXT) TO authenticated;
```

Sin esto, el cliente Supabase del front puede recibir error de permiso al llamar `.rpc(...)`.

---

## 3. Contratos esperados por el front

### `retorna_lista_rutas()`
Sin parámetros. Respuesta:

```json
{
  "success": true,
  "total_registros": 2,
  "data": [
    {
      "id_ruta": "uuid",
      "nombre_ruta": "Ruta Centro",
      "descripcion_ruta": "…",
      "created_at": "2026-08-13T12:00:00+00:00"
    }
  ],
  "error": null
}
```

### `retorna_usuarios_despachadores()`
Sin parámetros. Solo perfiles **activos** con `roles.nombre = 'despachador'`:

```json
{
  "success": true,
  "data": [
    {
      "id": "uuid",
      "nombre_completo": "…",
      "telefono": "+58…"
    }
  ],
  "error": null
}
```

### `actualiza_registro_rutas_segun_uuid(p_id_ruta, p_nombre_ruta, p_descripcion_ruta)`
Éxito / fallo con códigos:

- `PARAMETRO_INVALIDO`
- `RUTA_INEXISTENTE`

Detalle completo: `docs/INTEGRACION-RPC.md` §§ 2.12–2.14 (rama `feature/database-sdd-setup` o copiar a `main` si aún no está).

---

## 4. Verificación rápida (post-deploy)

Ejecutar en SQL Editor:

```sql
-- Estructura
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'clientes'
  AND column_name IN ('despachador_id', 'id_ruta');

SELECT to_regclass('public.rutas');

-- RPCs
SELECT public.retorna_lista_rutas();
SELECT public.retorna_usuarios_despachadores();
```

Smoke test de update (usar un `id_ruta` real):

```sql
SELECT public.actualiza_registro_rutas_segun_uuid(
  'UUID-DE-PRUEBA'::uuid,
  'Ruta de prueba',
  'Descripción de prueba'
);
```

Checklist:

- [ ] Migraciones 1→5 aplicadas sin error
- [ ] `GRANT EXECUTE` a `authenticated` en las 3 funciones
- [ ] `retorna_lista_rutas` responde `success: true`
- [ ] `retorna_usuarios_despachadores` lista usuarios con rol `despachador` activos
- [ ] Update de ruta inexistente retorna `RUTA_INEXISTENTE`
- [ ] Front: `/rutas` carga lista; `/clientes/nuevo` muestra selects de ruta y despachador

---

## 5. Notas operativas

1. **RLS en `rutas`:** SELECT para `authenticated`; INSERT/UPDATE/DELETE solo `admin` y `gerente`. El alta de rutas desde el front usa insert directo (no hay RPC de creación en INTEGRACION-RPC).
2. **Rol esperado:** el filtro de despachadores usa exactamente `roles.nombre = 'despachador'` (no alias legado).
3. **Idempotencia:** las migraciones usan `IF NOT EXISTS` / `CREATE OR REPLACE`; se pueden reaplicar con cuidado, pero preferible una sola pasada ordenada.
4. **Datos semilla (opcional):** si `/rutas` queda vacío, insertar 1–2 rutas de prueba para validar UI:

```sql
INSERT INTO public.rutas (nombre_ruta, descripcion_ruta)
VALUES
  ('Ruta Centro - Comercial', 'Atención a clientes del casco central'),
  ('Ruta Norte - Industrial', NULL);
```

---

## 6. Contacto / bloqueadores

Si alguna migración falla (columna ya tipada distinto, FK, política RLS duplicada), reportar el mensaje SQL completo y el archivo exacto. No omitir pasos: el front ya asume columnas + RPCs disponibles.
