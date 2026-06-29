import { createClient } from "@/lib/supabase/server";
import type { PerfilUsuario } from "@/types/database";

export async function getSessionUser() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  return user;
}

export async function getCurrentProfile(): Promise<PerfilUsuario | null> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) return null;

  const { data } = await supabase
    .from("perfiles_usuario")
    .select("*, roles(*)")
    .eq("id", user.id)
    .single();

  return data;
}
