import { createClient } from "@supabase/supabase-js";
import {
  getTenantForCurrentUser,
  withCentralAuth,
} from "@/lib/supabase/tenant-context";
import { getTenantServiceKey } from "@/lib/tenants/management";

const serviceClientOptions = {
  auth: {
    autoRefreshToken: false,
    persistSession: false,
  },
};

/**
 * Service role para datos. Si el usuario en sesión pertenece a una empresa
 * lt_*, los datos van al tenant; `auth.admin` sigue apuntando a Central.
 */
export async function createAdminClient() {
  const central = createCentralAdminClient();

  let tenant = null;
  try {
    tenant = await getTenantForCurrentUser();
  } catch {
    tenant = null;
  }
  if (!tenant) return central;

  const serviceKey = await getTenantServiceKey(tenant.projectRef);
  const data = createClient(tenant.url, serviceKey, serviceClientOptions);
  return withCentralAuth(data, central.auth) as unknown as typeof central;
}

/**
 * Service role sobre la BD Central (auth, empresas / usuarios_empresas).
 */
export function createCentralAdminClient() {
  const url =
    process.env.NEXT_PUBLIC_CENTRAL_SUPABASE_URL ||
    process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey =
    process.env.CENTRAL_SUPABASE_SERVICE_ROLE_KEY ||
    process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!url || !serviceRoleKey) {
    throw new Error(
      "Faltan URL o service role de la BD Central (CENTRAL_* o SUPABASE_*).",
    );
  }

  return createClient(url, serviceRoleKey, serviceClientOptions);
}
