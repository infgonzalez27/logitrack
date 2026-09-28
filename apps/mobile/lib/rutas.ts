import { supabase } from "./supabase";
import {
  isRpcSuccess,
  rpcFailMessage,
  unwrapRpcData,
} from "./rpc";

export type Ruta = {
  id_ruta: string;
  nombre_ruta: string;
  descripcion_ruta: string | null;
  created_at?: string;
};

export async function listRutas(): Promise<
  { ok: true; rutas: Ruta[] } | { ok: false; error: string }
> {
  const { data, error } = await supabase.rpc("retorna_lista_rutas");
  if (error) {
    const fallback = await supabase
      .from("rutas")
      .select("id_ruta, nombre_ruta, descripcion_ruta, created_at")
      .order("nombre_ruta");
    if (fallback.error) return { ok: false, error: fallback.error.message };
    return { ok: true, rutas: (fallback.data ?? []) as Ruta[] };
  }

  if (!isRpcSuccess(data)) {
    return {
      ok: false,
      error: rpcFailMessage(data, "No se pudieron consultar las rutas."),
    };
  }

  const rutas = unwrapRpcData<Ruta[]>(data) ?? [];
  return { ok: true, rutas: Array.isArray(rutas) ? rutas : [] };
}

export async function getRuta(
  id: string,
): Promise<{ ok: true; ruta: Ruta } | { ok: false; error: string }> {
  const list = await listRutas();
  if (!list.ok) return list;
  const ruta = list.rutas.find((r) => r.id_ruta === id);
  if (!ruta) return { ok: false, error: "Ruta no encontrada." };
  return { ok: true, ruta };
}

export async function createRuta(input: {
  nombre_ruta: string;
  descripcion_ruta?: string | null;
}): Promise<{ ok: true; id: string } | { ok: false; error: string }> {
  const nombre = input.nombre_ruta.trim();
  if (!nombre) return { ok: false, error: "El nombre de la ruta es obligatorio." };

  const { data, error } = await supabase
    .from("rutas")
    .insert({
      nombre_ruta: nombre,
      descripcion_ruta: input.descripcion_ruta?.trim() || null,
    })
    .select("id_ruta")
    .single();

  if (error) return { ok: false, error: error.message };
  return { ok: true, id: data.id_ruta as string };
}

export async function updateRuta(input: {
  id_ruta: string;
  nombre_ruta: string;
  descripcion_ruta?: string | null;
}): Promise<{ ok: true; ruta: Ruta } | { ok: false; error: string }> {
  const id = input.id_ruta.trim();
  const nombre = input.nombre_ruta.trim();
  if (!id) return { ok: false, error: "La ruta es requerida." };
  if (!nombre) return { ok: false, error: "El nombre de la ruta es obligatorio." };

  const { data, error } = await supabase.rpc(
    "actualiza_registro_rutas_segun_uuid",
    {
      p_id_ruta: id,
      p_nombre_ruta: nombre,
      p_descripcion_ruta: input.descripcion_ruta?.trim() || null,
    },
  );

  if (error) return { ok: false, error: error.message };
  if (!isRpcSuccess(data)) {
    return {
      ok: false,
      error: rpcFailMessage(data, "No se pudo actualizar la ruta."),
    };
  }

  const ruta = unwrapRpcData<Ruta>(data);
  if (!ruta) return { ok: false, error: "No se pudo actualizar la ruta." };
  return { ok: true, ruta };
}
