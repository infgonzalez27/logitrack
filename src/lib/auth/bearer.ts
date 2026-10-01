import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { normalizeRolNombre, type RolNombre } from "@/lib/auth/roles";
import { createCentralAdminClient } from "@/lib/supabase/admin";
import { resolverEmpresaAsignada } from "@/lib/supabase/empresa-asignada";
import { joinOne } from "@/lib/supabase/join";
import {
  tenantFromEmpresa,
  type CurrentTenant,
} from "@/lib/supabase/tenant-context";
import { getTenantServiceKey } from "@/lib/tenants/management";

export type BearerActor = {
  userId: string;
  rol: RolNombre | null;
  tenant: CurrentTenant | null;
  /** Service role sobre la BD donde viven los datos del actor (tenant o Central). */
  data: SupabaseClient;
};

/**
 * Autentica llamadas de la app móvil (`Authorization: Bearer <JWT de Central>`)
 * y resuelve empresa y rol del usuario igual que la sesión web.
 */
export async function getBearerActor(
  request: Request,
): Promise<
  { ok: true; actor: BearerActor } | { ok: false; status: number; error: string }
> {
  const token = request.headers
    .get("authorization")
    ?.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!token) {
    return { ok: false, status: 401, error: "Falta el token de sesión." };
  }

  const central = createCentralAdminClient();
  const {
    data: { user },
    error: userError,
  } = await central.auth.getUser(token);
  if (userError || !user) {
    return { ok: false, status: 401, error: "Sesión inválida o expirada." };
  }

  const empresa = await resolverEmpresaAsignada(central, user.id);
  if (empresa && !empresa.activo) {
    return { ok: false, status: 403, error: "La empresa está inactiva." };
  }

  const tenant = tenantFromEmpresa(empresa);
  const data: SupabaseClient = tenant
    ? createClient(tenant.url, await getTenantServiceKey(tenant.projectRef), {
        auth: { autoRefreshToken: false, persistSession: false },
      })
    : central;

  const { data: perfil } = await data
    .from("perfiles_usuario")
    .select("roles(nombre)")
    .eq("id", user.id)
    .maybeSingle();
  const rol = normalizeRolNombre(
    joinOne(
      perfil?.roles as { nombre?: string } | { nombre?: string }[] | null | undefined,
    )?.nombre,
  );

  return { ok: true, actor: { userId: user.id, rol, tenant, data } };
}
