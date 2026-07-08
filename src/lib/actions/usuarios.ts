"use server";

import { createClient } from "@/lib/supabase/server";
import type { UsuarioListaRpc } from "@/types/database";

export async function listarUsuariosAction(
  parametro: string,
): Promise<
  | { ok: true; usuarios: UsuarioListaRpc[] }
  | { ok: false; error: string }
> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc(
    "retorna_lista_usuarios_segun_parametro",
    { p_parametro: parametro.trim() },
  );

  if (error) {
    return { ok: false, error: error.message };
  }

  return { ok: true, usuarios: (data ?? []) as UsuarioListaRpc[] };
}
