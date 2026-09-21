import { supabase } from "./supabase";

export const PRINT_ROLES = ["vendedor", "gerente", "admin"] as const;
export type PrintRole = (typeof PRINT_ROLES)[number];

export type AppProfile = {
  id: string;
  nombre_completo: string;
  rol: PrintRole | string;
};

export function isPrintRole(rol: string | null | undefined): rol is PrintRole {
  return !!rol && (PRINT_ROLES as readonly string[]).includes(rol);
}

export async function signIn(email: string, password: string) {
  const { data, error } = await supabase.auth.signInWithPassword({
    email: email.trim(),
    password,
  });
  if (error) return { ok: false as const, error: error.message };
  return { ok: true as const, session: data.session };
}

export async function signOut() {
  await supabase.auth.signOut();
}

export async function getSessionUserId(): Promise<string | null> {
  const { data } = await supabase.auth.getSession();
  return data.session?.user?.id ?? null;
}

export async function fetchProfile(
  userId: string,
): Promise<{ ok: true; profile: AppProfile } | { ok: false; error: string }> {
  const { data, error } = await supabase
    .from("perfiles_usuario")
    .select("id, nombre_completo, roles(nombre)")
    .eq("id", userId)
    .maybeSingle();

  if (error) return { ok: false, error: error.message };
  if (!data) return { ok: false, error: "Perfil no encontrado." };

  const roles = data.roles as { nombre?: string } | { nombre?: string }[] | null;
  const rolNombre = Array.isArray(roles)
    ? roles[0]?.nombre
    : roles?.nombre;

  if (!isPrintRole(rolNombre)) {
    return {
      ok: false,
      error:
        "Tu rol no puede usar esta app. Solo vendedor, gerente o admin.",
    };
  }

  return {
    ok: true,
    profile: {
      id: data.id,
      nombre_completo: data.nombre_completo ?? "Usuario",
      rol: rolNombre,
    },
  };
}
