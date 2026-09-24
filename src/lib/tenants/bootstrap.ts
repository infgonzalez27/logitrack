/**
 * Deja un tenant lt_* listo para usarse con la sesión de la BD Central:
 * - Third-Party Auth: el tenant acepta los JWT firmados por Central (JWKS).
 * - supabase/tenant_bootstrap.sql: catálogos, buckets y políticas de Storage.
 * - Espejo de usuarios: fila en auth.users (sin contraseña, solo para FKs)
 *   y perfil en perfiles_usuario con el mismo UUID que en Central.
 */

import fs from "fs";
import path from "path";
import { createCentralAdminClient } from "@/lib/supabase/admin";
import { managementFetch, runProjectSql } from "@/lib/tenants/management";

function centralUrl(): string {
  const url =
    process.env.NEXT_PUBLIC_CENTRAL_SUPABASE_URL ||
    process.env.NEXT_PUBLIC_SUPABASE_URL;
  if (!url) {
    throw new Error("Falta NEXT_PUBLIC_SUPABASE_URL de la BD Central.");
  }
  return url.replace(/\/$/, "");
}

type ThirdPartyAuth = {
  id?: string;
  oidc_issuer_url?: string | null;
  jwks_url?: string | null;
  resolved_at?: string | null;
};

export async function configureTenantTrust(projectRef: string): Promise<void> {
  const issuer = `${centralUrl()}/auth/v1`;
  const basePath = `/projects/${projectRef}/config/auth/third-party-auth`;

  const listRes = await managementFetch(basePath);
  if (!listRes.ok) {
    throw new Error(
      `No se pudo leer Third-Party Auth de ${projectRef}: ${listRes.status} ${await listRes.text()}`,
    );
  }

  const existing = (await listRes.json()) as ThirdPartyAuth[];
  if (existing.some((i) => i.oidc_issuer_url === issuer)) {
    return;
  }

  const createRes = await managementFetch(basePath, {
    method: "POST",
    body: JSON.stringify({ oidc_issuer_url: issuer }),
  });
  if (!createRes.ok) {
    throw new Error(
      `No se pudo configurar Third-Party Auth en ${projectRef}: ${createRes.status} ${await createRes.text()}`,
    );
  }
}

export async function bootstrapTenant(projectRef: string): Promise<void> {
  await configureTenantTrust(projectRef);

  const sqlPath = path.join(process.cwd(), "supabase", "tenant_bootstrap.sql");
  if (!fs.existsSync(sqlPath)) {
    throw new Error("Falta supabase/tenant_bootstrap.sql en el deploy.");
  }
  await runProjectSql(projectRef, fs.readFileSync(sqlPath, "utf8"));
}

export type TenantUserMirror = {
  id: string;
  email: string;
  rol_id: string;
  nombre_completo: string;
  telefono?: string | null;
  activo?: boolean;
};

function sqlLiteral(value: string): string {
  return `'${value.replace(/'/g, "''")}'`;
}

export async function syncUserToTenant(
  projectRef: string,
  user: TenantUserMirror,
): Promise<void> {
  const payload = sqlLiteral(
    JSON.stringify({
      id: user.id,
      email: user.email,
      rol_id: user.rol_id,
      nombre_completo: user.nombre_completo,
      telefono: user.telefono ?? "",
      activo: user.activo ?? true,
    }),
  );

  await runProjectSql(
    projectRef,
    `
WITH u AS (SELECT * FROM json_to_record(${payload}::json)
  AS x(id uuid, email text, rol_id uuid, nombre_completo text, telefono text, activo boolean))
INSERT INTO auth.users (instance_id, id, aud, role, email, created_at, updated_at)
SELECT '00000000-0000-0000-0000-000000000000', id, 'authenticated', 'authenticated', email, now(), now() FROM u
ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email, updated_at = now();

WITH u AS (SELECT * FROM json_to_record(${payload}::json)
  AS x(id uuid, email text, rol_id uuid, nombre_completo text, telefono text, activo boolean))
INSERT INTO public.perfiles_usuario (id, rol_id, nombre_completo, telefono, activo)
SELECT id, rol_id, nombre_completo, telefono, activo FROM u
ON CONFLICT (id) DO UPDATE SET
  rol_id = EXCLUDED.rol_id,
  nombre_completo = EXCLUDED.nombre_completo,
  telefono = EXCLUDED.telefono,
  activo = EXCLUDED.activo;
`,
  );
}

/** Copia al tenant la cuenta (sin contraseña) y el perfil que el usuario tiene en Central. */
export async function mirrorCentralUserToTenant(
  projectRef: string,
  userId: string,
): Promise<void> {
  const central = createCentralAdminClient();

  const { data: authData, error: authError } =
    await central.auth.admin.getUserById(userId);
  if (authError || !authData.user?.email) {
    throw new Error(`No se encontró la cuenta ${userId} en la BD Central.`);
  }

  const { data: perfil, error: perfilError } = await central
    .from("perfiles_usuario")
    .select("rol_id, nombre_completo, telefono, activo")
    .eq("id", userId)
    .maybeSingle();
  if (perfilError || !perfil?.rol_id) {
    throw new Error(`El usuario ${authData.user.email} no tiene perfil con rol en Central.`);
  }

  await syncUserToTenant(projectRef, {
    id: userId,
    email: authData.user.email,
    rol_id: perfil.rol_id,
    nombre_completo: perfil.nombre_completo,
    telefono: perfil.telefono,
    activo: perfil.activo,
  });
}
