import { supabase } from "./supabase";

export type CamionOption = { id: string; placa: string };

type RpcCamion = {
  id?: string;
  camion_id?: string;
  placa?: string;
  estado?: string;
};

function unwrapList(payload: unknown): RpcCamion[] {
  if (Array.isArray(payload)) return payload as RpcCamion[];
  if (payload && typeof payload === "object") {
    const env = payload as { success?: boolean; data?: unknown };
    if (Array.isArray(env.data)) return env.data as RpcCamion[];
  }
  return [];
}

export async function listarCamiones(): Promise<
  { ok: true; camiones: CamionOption[] } | { ok: false; error: string }
> {
  const { data, error } = await supabase.rpc("retorna_lista_camiones");
  if (error) {
    const fallback = await supabase
      .from("camiones")
      .select("id, placa, estado")
      .order("placa");
    if (fallback.error) return { ok: false, error: fallback.error.message };
    return {
      ok: true,
      camiones: (fallback.data ?? [])
        .filter((c) => c.estado !== "inactivo")
        .map((c) => ({ id: c.id, placa: c.placa })),
    };
  }

  const rows = unwrapList(data);
  return {
    ok: true,
    camiones: rows
      .map((c) => ({
        id: String(c.id ?? c.camion_id ?? ""),
        placa: String(c.placa ?? ""),
        estado: c.estado,
      }))
      .filter((c) => c.id && c.placa && c.estado !== "inactivo")
      .map(({ id, placa }) => ({ id, placa }))
      .sort((a, b) => a.placa.localeCompare(b.placa, "es")),
  };
}

export async function retornaUltimaTasa(): Promise<
  { ok: true; tasa: number; fecha: string | null } | { ok: false; error: string }
> {
  const { data, error } = await supabase.rpc("retorna_ultima_tasa_cambio");
  if (error) return { ok: false, error: error.message };

  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    return { ok: false, error: "No hay tasa registrada." };
  }
  const r = row as { tasa_cambio?: number; tasa?: number; fecha_tasa?: string };
  const tasa = Number(r.tasa_cambio ?? r.tasa);
  if (!Number.isFinite(tasa) || tasa <= 0) {
    return { ok: false, error: "No hay tasa registrada." };
  }
  return { ok: true, tasa, fecha: r.fecha_tasa ?? null };
}
