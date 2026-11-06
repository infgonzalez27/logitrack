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
  if (error) {
    const fallback = await supabase
      .from("tasa_cambio")
      .select("fecha_tasa, tasa_cambio")
      .order("fecha_tasa", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (fallback.error || !fallback.data) {
      return { ok: false, error: error.message };
    }
    const tasaFb = Number(fallback.data.tasa_cambio);
    if (!Number.isFinite(tasaFb) || tasaFb <= 0) {
      return { ok: false, error: "Tasa no válida." };
    }
    return { ok: true, tasa: tasaFb, fecha: fallback.data.fecha_tasa ?? null };
  }

  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    return { ok: false, error: "No hay tasa registrada." };
  }
  const inner = (row as { data?: unknown }).data ?? row;
  const r = (Array.isArray(inner) ? inner[0] : inner) as {
    tasa_cambio?: number;
    tasa?: number;
    fecha_tasa?: string;
  };
  const tasa = Number(r?.tasa_cambio ?? r?.tasa);
  if (!Number.isFinite(tasa) || tasa <= 0) {
    return { ok: false, error: "No hay tasa registrada." };
  }
  return { ok: true, tasa, fecha: r?.fecha_tasa ?? null };
}

export async function retornaTasaSegunFecha(
  dFecha: string,
): Promise<
  { ok: true; tasa: number; fecha: string } | { ok: false; error: string }
> {
  const fecha = dFecha?.trim().slice(0, 10);
  if (!fecha || !/^\d{4}-\d{2}-\d{2}$/.test(fecha)) {
    return { ok: false, error: "Fecha inválida." };
  }

  const { data, error } = await supabase.rpc(
    "retorna_tasa_cambio_segun_fecha",
    { dfecha: fecha },
  );

  if (!error && data && typeof data === "object") {
    const env = data as {
      success?: boolean;
      message?: string;
      data?: { tasa_cambio?: number; fecha_tasa?: string } | null;
      error?: { code?: string; message?: string } | null;
    };
    if (env.success === true && env.data) {
      const tasa = Number(env.data.tasa_cambio);
      if (Number.isFinite(tasa) && tasa > 0) {
        return {
          ok: true,
          tasa,
          fecha: env.data.fecha_tasa ?? fecha,
        };
      }
    }
    if (env.success === false) {
      return {
        ok: false,
        error:
          env.error?.message ||
          env.message ||
          "Tasa no registrada",
      };
    }
  }

  const fallback = await supabase
    .from("tasa_cambio")
    .select("fecha_tasa, tasa_cambio")
    .eq("fecha_tasa", fecha)
    .maybeSingle();

  if (fallback.error || !fallback.data) {
    return { ok: false, error: "Tasa no registrada" };
  }

  const tasaFb = Number(fallback.data.tasa_cambio);
  if (!Number.isFinite(tasaFb) || tasaFb <= 0) {
    return { ok: false, error: "Tasa no registrada" };
  }

  return {
    ok: true,
    tasa: tasaFb,
    fecha: fallback.data.fecha_tasa ?? fecha,
  };
}
