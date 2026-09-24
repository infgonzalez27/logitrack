/**
 * Deja un tenant lt_* listo para usarse con la sesión de la BD Central:
 * - Third-Party Auth: el tenant acepta los JWT firmados por Central (JWKS).
 * - supabase/seed_base.sql: catálogos y productos base (agente BD).
 * - supabase/tenant_bootstrap.sql: buckets y políticas de Storage.
 * - Espejo de usuarios: fila en auth.users (sin contraseña, solo para FKs)
 *   y perfil en perfiles_usuario con el mismo UUID que en Central; el rol se
 *   resuelve por nombre porque los UUID de roles difieren entre proyectos.
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

async function runSqlFile(projectRef: string, fileName: string): Promise<void> {
  const sqlPath = path.join(process.cwd(), "supabase", fileName);
  if (!fs.existsSync(sqlPath)) {
    throw new Error(`Falta supabase/${fileName} en el deploy.`);
  }
  await runProjectSql(projectRef, fs.readFileSync(sqlPath, "utf8"));
}

export async function bootstrapTenant(projectRef: string): Promise<void> {
  await configureTenantTrust(projectRef);
  await runSqlFile(projectRef, "seed_base.sql");
  await runSqlFile(projectRef, "tenant_bootstrap.sql");
}

export type TenantUserMirror = {
  id: string;
  email: string;
  rol_nombre: string;
  nombre_completo: string;
  telefono?: string | null;
  activo?: boolean;
};

function sqlLiteral(value: string): string {
  return `'${value.replace(/'/g, "''")}'`;
}

/**
 * Crea/actualiza la cuenta espejo (sin contraseña) y el perfil en el tenant.
 * `sobrescribirPerfil: false` solo crea el perfil si falta, para no pisar
 * cambios de rol o nombre hechos dentro del tenant.
 */
export async function syncUserToTenant(
  projectRef: string,
  user: TenantUserMirror,
  options: { sobrescribirPerfil?: boolean } = {},
): Promise<void> {
  const roles = (await runProjectSql(
    projectRef,
    `SELECT id FROM public.roles WHERE nombre = ${sqlLiteral(user.rol_nombre)};`,
  )) as Array<{ id: string }>;
  if (!roles.length) {
    throw new Error(
      `El rol "${user.rol_nombre}" no existe en el tenant ${projectRef} (ver supabase/seed_base.sql).`,
    );
  }

  const payload = sqlLiteral(
    JSON.stringify({
      id: user.id,
      email: user.email,
      rol_id: roles[0].id,
      nombre_completo: user.nombre_completo,
      telefono: user.telefono ?? "",
      activo: user.activo ?? true,
    }),
  );

  const onConflictPerfil =
    options.sobrescribirPerfil === false
      ? "ON CONFLICT (id) DO NOTHING"
      : `ON CONFLICT (id) DO UPDATE SET
  rol_id = EXCLUDED.rol_id,
  nombre_completo = EXCLUDED.nombre_completo,
  telefono = EXCLUDED.telefono,
  activo = EXCLUDED.activo`;

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
${onConflictPerfil};
`,
  );
}

type CentralAdminClient = ReturnType<typeof createCentralAdminClient>;

/** Borra el perfil que el usuario tenga en Central si ningún dato de Central lo usa. */
async function eliminarPerfilCentralHuerfano(
  central: CentralAdminClient,
  userId: string,
): Promise<void> {
  const referencias = await Promise.all([
    central.from("choferes").select("perfil_id", { count: "exact", head: true }).eq("perfil_id", userId),
    central
      .from("clientes")
      .select("id", { count: "exact", head: true })
      .or(`vendedor_id.eq.${userId},despachador_id.eq.${userId}`),
    central
      .from("ordenes_distribucion")
      .select("id", { count: "exact", head: true })
      .or(`vendedor_id.eq.${userId},despachador_id.eq.${userId}`),
    central.from("radars").select("id", { count: "exact", head: true }).eq("despachador_id", userId),
  ]);
  if (referencias.some((r) => r.error || (r.count ?? 0) > 0)) return;

  await central.from("perfiles_usuario").delete().eq("id", userId);
}

/**
 * Asegura que un usuario asignado a la empresa exista en el tenant.
 * El rol sale de usuarios_empresas; el nombre, del perfil antiguo en Central
 * (si existe) o de los metadatos de la cuenta. Luego limpia ese perfil antiguo.
 */
export async function mirrorCentralUserToTenant(
  projectRef: string,
  userId: string,
  rolAsignado: string,
): Promise<void> {
  const central = createCentralAdminClient();

  const { data: authData, error: authError } =
    await central.auth.admin.getUserById(userId);
  const authUser = authData?.user;
  if (authError || !authUser?.email) {
    throw new Error(`No se encontró la cuenta ${userId} en la BD Central.`);
  }

  const { data: perfilCentral } = await central
    .from("perfiles_usuario")
    .select("nombre_completo, telefono, activo")
    .eq("id", userId)
    .maybeSingle();

  const metadata = (authUser.user_metadata ?? {}) as {
    nombre_completo?: string;
    telefono?: string;
  };

  await syncUserToTenant(
    projectRef,
    {
      id: userId,
      email: authUser.email,
      rol_nombre: rolAsignado,
      nombre_completo:
        perfilCentral?.nombre_completo ||
        metadata.nombre_completo ||
        authUser.email.split("@")[0],
      telefono: perfilCentral?.telefono ?? metadata.telefono ?? "",
      activo: perfilCentral?.activo ?? true,
    },
    { sobrescribirPerfil: false },
  );

  if (perfilCentral) {
    await eliminarPerfilCentralHuerfano(central, userId);
  }
}

