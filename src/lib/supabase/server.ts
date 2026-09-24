import { createClient as createSupabaseClient } from "@supabase/supabase-js";
import { createCentralClient } from "@/lib/supabase/central";
import {
  getTenantForCurrentUser,
  withCentralAuth,
} from "@/lib/supabase/tenant-context";

/**
 * Cliente Supabase para Server Components / Server Actions.
 * Auth y sesión viven en la BD Central. Si el usuario pertenece a una empresa
 * lt_* (usuarios_empresas), los datos van a ese proyecto con el JWT de Central,
 * que el tenant acepta vía Third-Party Auth (ver lib/tenants/bootstrap.ts).
 */
export async function createClient() {
  const central = await createCentralClient();
  const tenant = await getTenantForCurrentUser();
  if (!tenant) return central;

  const data = createSupabaseClient(tenant.url, tenant.anonKey, {
    accessToken: async () => {
      const { data: sessionData } = await central.auth.getSession();
      return sessionData.session?.access_token ?? null;
    },
  });

  return withCentralAuth(data, central.auth) as unknown as typeof central;
}
