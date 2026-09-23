import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import type { Empresa } from "@/types/database";

/**
 * Crea un cliente de Supabase conectado a la Base de Datos Central (DB_CENTRAL).
 * La BD Central contiene auth.users, public.empresas y public.usuarios_empresas.
 */
export async function createCentralClient() {
  const cookieStore = await cookies();

  const centralUrl =
    process.env.NEXT_PUBLIC_CENTRAL_SUPABASE_URL ||
    process.env.NEXT_PUBLIC_SUPABASE_URL!;
  const centralAnonKey =
    process.env.NEXT_PUBLIC_CENTRAL_SUPABASE_ANON_KEY ||
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;

  return createServerClient(centralUrl, centralAnonKey, {
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
            "[Central Supabase] No se pudieron guardar cookies de sesión:",
            error instanceof Error ? error.message : error,
          );
        }
      },
    },
  });
}

/**
 * Resuelve la empresa (tenant lt_*) asignada a un usuario desde la BD Central.
 */
export async function resolveUserEmpresa(userId: string): Promise<Empresa | null> {
  const centralClient = await createCentralClient();

  const { data, error } = await centralClient
    .from("usuarios_empresas")
    .select("empresa_id, empresas(*)")
    .eq("user_id", userId)
    .single();

  if (error || !data || !data.empresas) {
    return null;
  }

  return data.empresas as unknown as Empresa;
}
