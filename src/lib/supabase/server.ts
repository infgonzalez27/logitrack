import { createCentralClient } from "@/lib/supabase/central";

/**
 * Cliente Supabase para Server Components / Server Actions.
 * Auth y sesion viven en la BD Central (NEXT_PUBLIC_* / CENTRAL_*).
 * No enruta al tenant lt_* aqui: un JWT de Central no es valido en otro
 * proyecto Supabase y provoca ERR_TOO_MANY_REDIRECTS.
 */
export async function createClient() {
  return createCentralClient();
}