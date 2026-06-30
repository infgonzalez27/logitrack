-- =============================================================================
-- ELIMINAR usuario dañado por RPC (confirmation_token NULL)
-- Supabase → SQL Editor → pegar y ejecutar TODO el bloque
-- =============================================================================

BEGIN;

-- 1) Reparar tokens NULL para que GoTrue pueda leer el registro (si hace falta)
UPDATE auth.users
SET
  confirmation_token = COALESCE(confirmation_token, ''),
  recovery_token = COALESCE(recovery_token, ''),
  email_change_token_new = COALESCE(email_change_token_new, ''),
  email_change = COALESCE(email_change, ''),
  phone_change = COALESCE(phone_change, ''),
  phone_change_token = COALESCE(phone_change_token, ''),
  reauthentication_token = COALESCE(reauthentication_token, '')
WHERE email = 'gonzalezadonis16@gmail.com';

-- 2) Borrar identidades y usuario
DELETE FROM auth.identities
WHERE user_id IN (
  SELECT id FROM auth.users WHERE email = 'gonzalezadonis16@gmail.com'
);

DELETE FROM auth.users
WHERE email = 'gonzalezadonis16@gmail.com';

COMMIT;

-- 3) Verificar (debe devolver 0 filas)
SELECT id, email FROM auth.users WHERE email = 'gonzalezadonis16@gmail.com';

-- Después: registrar de nuevo en http://localhost:3000/register
