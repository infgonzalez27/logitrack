import { createAdminClient } from "@/lib/supabase/admin";

/** Nombres de perfil cuando RLS bloquea el join anidado en consultas con sesión. */
export async function getNombresPerfilByIds(
  ids: string[],
): Promise<Record<string, string>> {
  const unique = [...new Set(ids.map((id) => id.trim()).filter(Boolean))];
  if (!unique.length) return {};

  try {
    const { data } = await createAdminClient()
      .from("perfiles_usuario")
      .select("id, nombre_completo")
      .in("id", unique);

    return Object.fromEntries(
      (data ?? []).map((perfil) => [perfil.id, perfil.nombre_completo]),
    );
  } catch {
    return {};
  }
}
