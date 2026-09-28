import { supabase } from "./supabase";
import { isRpcSuccess, rpcFailMessage, unwrapRpcData } from "./rpc";

export type TasaCambio = {
  fecha_tasa: string;
  tasa_cambio: number;
  created_at?: string | null;
};

function asTasa(raw: unknown): TasaCambio | null {
  if (!raw || typeof raw !== "object") return null;
  const r = raw as Record<string, unknown>;
  const tasa = Number(r.tasa_cambio ?? r.tasa);
  const fecha = String(r.fecha_tasa ?? "").slice(0, 10);
  if (!fecha || !Number.isFinite(tasa) || tasa <= 0) return null;
  return {
    fecha_tasa: fecha,
    tasa_cambio: tasa,
    created_at: (r.created_at as string) ?? null,
  };
}

export async function retornaUltimaTasaCambio(): Promise<
  { ok: true; tasa: TasaCambio | null } | { ok: false; error: string }
> {
  const { data, error } = await supabase.rpc("retorna_ultima_tasa_cambio");
  if (error) {
    const fallback = await supabase
      .from("tasa_cambio")
      .select("fecha_tasa, tasa_cambio, created_at")
      .order("fecha_tasa", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (fallback.error) return { ok: false, error: fallback.error.message };
    return { ok: true, tasa: asTasa(fallback.data) };
  }

  if (!isRpcSuccess(data)) {
    return {
      ok: false,
      error: rpcFailMessage(data, "No se pudo consultar la última tasa."),
    };
  }

  const unwrapped = unwrapRpcData<unknown>(data);
  const row = Array.isArray(unwrapped) ? unwrapped[0] : unwrapped;
  return { ok: true, tasa: asTasa(row) };
}

export async function listTasasCambio(limit = 60): Promise<
  { ok: true; tasas: TasaCambio[] } | { ok: false; error: string }
> {
  const { data, error } = await supabase
    .from("tasa_cambio")
    .select("fecha_tasa, tasa_cambio, created_at")
    .order("fecha_tasa", { ascending: false })
    .limit(limit);

  if (error) return { ok: false, error: error.message };

  return {
    ok: true,
    tasas: (data ?? [])
      .map((row) => asTasa(row))
      .filter((t): t is TasaCambio => t != null),
  };
}

export async function insertaTasaCambio(input: {
  fecha_tasa: string;
  tasa: number;
}): Promise<{ ok: true; tasa: TasaCambio } | { ok: false; error: string }> {
  const fecha = input.fecha_tasa.trim();
  const tasa = Number(input.tasa);
  if (!fecha) return { ok: false, error: "La fecha es requerida." };
  if (!Number.isFinite(tasa) || tasa <= 0) {
    return { ok: false, error: "La tasa debe ser un número mayor a 0." };
  }

  const { data, error } = await supabase.rpc("inserta_tasa_cambio", {
    p_fecha_tasa: fecha,
    p_tasa: tasa,
  });

  if (error) {
    const insert = await supabase.from("tasa_cambio").insert({
      fecha_tasa: fecha,
      tasa_cambio: tasa,
    });
    if (insert.error) return { ok: false, error: insert.error.message };
    return { ok: true, tasa: { fecha_tasa: fecha, tasa_cambio: tasa } };
  }

  if (!isRpcSuccess(data)) {
    return {
      ok: false,
      error: rpcFailMessage(data, "No se pudo registrar la tasa."),
    };
  }

  const unwrapped = unwrapRpcData<{ fecha_tasa?: string; tasa_cambio?: number }>(
    data,
  );
  return {
    ok: true,
    tasa: {
      fecha_tasa: String(unwrapped?.fecha_tasa ?? fecha).slice(0, 10),
      tasa_cambio: Number(unwrapped?.tasa_cambio ?? tasa),
    },
  };
}

export function hoyIsoLocal(): string {
  const now = new Date();
  const y = now.getFullYear();
  const m = String(now.getMonth() + 1).padStart(2, "0");
  const d = String(now.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}
