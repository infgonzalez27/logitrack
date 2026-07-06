"use server";

import { createClient } from "@/lib/supabase/server";
import type { ProductoListaRpc } from "@/types/database";

export async function buscarProductosOrdenAction(
  parametro: string,
): Promise<
  | { ok: true; productos: ProductoListaRpc[] }
  | { ok: false; error: string }
> {
  const p = parametro.trim();

  if (!p) {
    return { ok: false, error: "Ingresa un nombre o código de barras para buscar." };
  }

  if (p.length < 2) {
    return {
      ok: false,
      error: "El parámetro de búsqueda debe tener al menos 2 caracteres.",
    };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc(
    "retorna_lista_productos_segun_parametros",
    { p_parametro: p },
  );

  if (error) {
    return { ok: false, error: error.message };
  }

  return { ok: true, productos: (data ?? []) as ProductoListaRpc[] };
}
