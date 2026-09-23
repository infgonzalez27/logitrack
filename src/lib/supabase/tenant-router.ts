import { createServerClient, createBrowserClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { createCentralClient, resolveUserEmpresa } from "@/lib/supabase/central";
import type { Empresa } from "@/types/database";

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
 * Resuelve el cliente de Supabase dinámico para la empresa (tenant lt_*) asignada al usuario actual.
 * Si el usuario no posee tenant asignado o falla la resolución, utiliza el cliente con credenciales por defecto.
 */
export async function getDynamicTenantClient() {
  const cookieStore = await cookies();
  const cachedUrl = cookieStore.get(TENANT_URL_COOKIE_NAME)?.value;
  const cachedKey = cookieStore.get(TENANT_KEY_COOKIE_NAME)?.value;

  if (cachedUrl && cachedKey) {
    return createTenantServerClient(cachedUrl, cachedKey);
  }

  // Si no está en caché en cookies, resolver desde auth.users y BD Central
  const centralClient = await createCentralClient();
  const { data: { user } } = await centralClient.auth.getUser();

  if (user) {
    const empresa = await resolveUserEmpresa(user.id);
    if (empresa && empresa.activo && empresa.supabase_url && empresa.supabase_anon_key) {
      return createTenantServerClient(empresa.supabase_url, empresa.supabase_anon_key);
    }
  }

  // Fallback a las variables por defecto (Máster Template LogiTrack)
  return createTenantServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  );
}
