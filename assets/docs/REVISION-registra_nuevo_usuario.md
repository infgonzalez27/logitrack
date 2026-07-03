# Revisión SP `registra_nuevo_usuario` (versión DB admin)

## Síntoma

- RPC devuelve `success: true`
- Login → `500 Database error querying schema`

---

## Qué está bien en el script actual

- Valida que el rol exista
- Usa `crypt(..., gen_salt('bf'))` para la contraseña
- Incluye `instance_id`, `aud`, `role`, `email_confirmed_at`
- Agregó `is_anonymous = FALSE` (columna nueva en Auth 2026)
- `SECURITY DEFINER` es correcto para escribir en `auth.*`

---

## Problemas detectados (3 críticos)

### 1. Falta `auth.identities` (el más grave)

GoTrue **no puede** hacer login email/password sin una fila en `auth.identities` con `provider = 'email'`.

El script solo inserta en `auth.users`. El registro “parece” exitoso, pero el login explota al consultar el esquema/identidad.

**Fix:** `INSERT INTO auth.identities (...)` después del insert en `auth.users`.

### 2. Tokens en NULL (causa clásica del error 500)

No se setean estas columnas → quedan `NULL`:

- `confirmation_token`
- `recovery_token`
- `email_change_token_new`
- `email_change`
- `email_change_token_current`
- `phone_change`
- `phone_change_token`
- `reauthentication_token`

GoTrue espera **string vacío `''`**, no `NULL`.  
Documentación Supabase: [scan error on confirmation_token](https://github.com/supabase/supabase/blob/master/apps/docs/content/troubleshooting/scan-error-on-column-confirmation_token-converting-null-to-string-is-unsupported-during-auth-login-a0c686.mdx)

`is_anonymous` no sustituye esto.

### 3. `UPDATE perfiles_usuario` en lugar de `INSERT`

```sql
UPDATE public.perfiles_usuario SET rol_id = v_rol_id WHERE id = v_user_id;
```

Si no hay trigger que cree el perfil al insertar en `auth.users`, el `UPDATE` **no toca ninguna fila** → usuario sin perfil/rol en la app.

**Fix:** `INSERT ... ON CONFLICT (id) DO UPDATE`.

---

## Detalles menores

| Tema | Observación |
|------|-------------|
| `last_sign_in_at = NOW()` al crear | Innecesario; puede omitirse |
| `phone_confirmed_at = NOW()` | Raro si no hay login por teléfono; mejor `NULL` |
| `instance_id` fallback `00000000-...` | Mejor leer de `auth.instances` primero |
| Sin validar email duplicado | El `EXCEPTION` devuelve mensaje críptico de unique constraint |
| `EXCEPTION WHEN OTHERS` | Oculta errores parciales (user creado sin identity) |

---

## Script corregido

El SP vive en Supabase (PostgreSQL), no en este repositorio.

El DB admin debe:

1. Ejecutar el SP corregido en SQL Editor de Supabase
2. (Opcional) Reparar usuarios viejos con SQL de limpieza en `auth.users` / `auth.identities`
3. Crear identidades faltantes para emails ya registrados:

```sql
INSERT INTO auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
SELECT
  gen_random_uuid(),
  u.id,
  u.id::TEXT,
  'email',
  jsonb_build_object('sub', u.id::TEXT, 'email', u.email, 'email_verified', TRUE, 'phone_verified', FALSE),
  NOW(), NOW(), NOW()
FROM auth.users u
WHERE u.email LIKE '%@logitrack.com'
  AND NOT EXISTS (SELECT 1 FROM auth.identities i WHERE i.user_id = u.id);
```

---

## Cómo validar después del fix

1. Registrar usuario nuevo desde `/register`
2. Login en `/login` → debe devolver `200` y `login OK` en logs
3. En SQL: `SELECT * FROM auth.identities WHERE user_id = '<nuevo_id>'` → debe existir 1 fila
