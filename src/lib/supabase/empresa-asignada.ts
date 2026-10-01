import type { SupabaseClient } from "@supabase/supabase-js";
import { joinOne } from "@/lib/supabase/join";
import type { Empresa } from "@/types/database";

/**
 * Empresa (tenant lt_*) en la que trabaja el usuario, leída de la BD Central.
 * null = trabaja sobre Central.
 *
 * - Un admin con perfil en Central es el superadmin de la plataforma: se queda
 *   en Central aunque tenga filas en usuarios_empresas.
 * - Con varias empresas asignadas se toma siempre la más antigua.
 */
export async function resolverEmpresaAsignada(
  central: SupabaseClient,
  userId: string,
): Promise<Empresa | null> {
  const { data: perfilCentral } = await central
    .from("perfiles_usuario")
    .select("roles(nombre)")
    .eq("id", userId)
    .maybeSingle();
  const rolCentral = joinOne(
    perfilCentral?.roles as { nombre?: string } | { nombre?: string }[] | null | undefined,
  )?.nombre;
  if (rolCentral === "admin") return null;

  const { data, error } = await central
    .from("usuarios_empresas")
    .select("empresas(*)")
    .eq("user_id", userId)
    .order("created_at", { ascending: true })
    .limit(1)
    .maybeSingle();
  if (error || !data) return null;

  return joinOne(data.empresas as Empresa | Empresa[] | null | undefined);
}
