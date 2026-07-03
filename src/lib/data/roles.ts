import { createAdminClient } from "@/lib/supabase/admin";

/** Roles definidos en el esquema (fallback si no hay service role key). */
export const ROLES_FALLBACK = [
  { value: "admin", label: "admin" },
  { value: "gerente", label: "gerente" },
  { value: "despachador", label: "despachador" },
  { value: "vendedor", label: "vendedor" },
  { value: "chofer", label: "chofer" },
  { value: "cobrador", label: "cobrador" },
] as const;

export async function getRolesOptions() {
  try {
    const supabaseAdmin = createAdminClient();
    const { data, error } = await supabaseAdmin
      .from("roles")
      .select("nombre, descripcion")
      .order("nombre");

    if (error || !data?.length) {
      return [...ROLES_FALLBACK];
    }

    return data.map((rol) => ({
      value: rol.nombre,
      label: rol.descripcion
        ? `${rol.nombre} — ${rol.descripcion}`
        : rol.nombre,
    }));
  } catch {
    return [...ROLES_FALLBACK];
  }
}
