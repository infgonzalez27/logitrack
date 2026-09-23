import { getDynamicTenantClient } from "@/lib/supabase/tenant-router";

/**
 * Retorna el cliente de Supabase para Server Components / Server Actions.
 * Resuelve dinámicamente el tenant (lt_*) asignado al usuario actual.
 */
export async function createClient() {
  return getDynamicTenantClient();
}
