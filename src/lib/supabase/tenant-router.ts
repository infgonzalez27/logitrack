import { createServerClient, createBrowserClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { createCentralClient, resolveUserEmpresa } from "@/lib/supabase/central";

export const TENANT_COOKIE_NAME = "lt_tenant_id";
export const TENANT_URL_COOKIE_NAME = "lt_tenant_url";
export const TENANT_KEY_COOKIE_NAME = "lt_tenant_key";

/**
 * Crea un cliente de Supabase dinámicamente apuntando a la base de datos de un Tenant (lt_*) específico en el servidor.
 */
export async function createTenantServerClient(tenantUrl: string, tenantKey: string) {
  const cookieStore = await cookies();

  return createServerClient(tenantUrl, tenantKey, {
    cookies: {
      getAll() {
        return cookieStore.getAll();
      },
      setAll(cookiesToSet) {
        try {
          cookiesToSet.forEach(({ name, value, options }) =>
            cookieStore.set(name, value, options),
          );
        } catch (error) {
          console.error(
            "[Tenant Supabase] No se pudieron guardar cookies de sesión:",
            error instanceof Error ? error.message : error,
          );
        }
      },
    },
  });
}

/**
 * Crea un cliente de Supabase dinámicamente para un Tenant (lt_*) en el navegador.
 */
export function createTenantBrowserClient(tenantUrl: string, tenantKey: string) {
  return createBrowserClient(tenantUrl, tenantKey);
}

/**
 * Resuelve el cliente de datos de un tenant lt_* cuando la URL coincide con
 * Central (mismo proyecto) o cuando en el futuro exista un puente de auth.
 * Si el tenant es otro proyecto Supabase, NO se cambia de host: el JWT de
 * sesión no es portable y rompe getUser / middleware.
 */
export async function getDynamicTenantClient() {
  const centralUrl =
    process.env.NEXT_PUBLIC_CENTRAL_SUPABASE_URL ||
    process.env.NEXT_PUBLIC_SUPABASE_URL!;
  const centralKey =
    process.env.NEXT_PUBLIC_CENTRAL_SUPABASE_ANON_KEY ||
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;

  const cookieStore = await cookies();
  const cachedUrl = cookieStore.get(TENANT_URL_COOKIE_NAME)?.value;
  const cachedKey = cookieStore.get(TENANT_KEY_COOKIE_NAME)?.value;

  if (cachedUrl && cachedKey && sameSupabaseHost(cachedUrl, centralUrl)) {
    return createTenantServerClient(cachedUrl, cachedKey);
  }

  const centralClient = await createCentralClient();
  const {
    data: { user },
  } = await centralClient.auth.getUser();

  if (user) {
    const empresa = await resolveUserEmpresa(user.id);
    if (
      empresa?.activo &&
      empresa.supabase_url &&
      empresa.supabase_anon_key &&
      sameSupabaseHost(empresa.supabase_url, centralUrl)
    ) {
      return createTenantServerClient(
        empresa.supabase_url,
        empresa.supabase_anon_key,
      );
    }
  }

  return createTenantServerClient(centralUrl, centralKey);
}

function sameSupabaseHost(a: string, b: string): boolean {
  try {
    return new URL(a).host === new URL(b).host;
  } catch {
    return a === b;
  }
}
