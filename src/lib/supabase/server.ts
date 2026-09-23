import { getDynamicTenantClient } from "@/lib/supabase/tenant-router";

/**
 * Returns the Supabase client for Server Components / Server Actions.
 * Dynamically resolves the tenant (lt_*) assigned to the current user.
 */
export async function createClient() {
  return getDynamicTenantClient();
}