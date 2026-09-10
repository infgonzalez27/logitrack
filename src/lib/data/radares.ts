import { createClient } from "@/lib/supabase/server";
import type { RadarListaItem, RadarListaRangoItem } from "@/types/database";

type RadarRow = {
  id: string;
  correlativo: number;
  despachador_id: string;
  fecha_despacho: string;
  total_cantidad_solicitada: number | null;
  total_cantidad_despachada: number | null;
  total_contenedores_retirados: number | null;
  status_radar: boolean;
  created_at: string;
  perfiles_usuario:
    | { nombre_completo: string }
    | { nombre_completo: string }[]
    | null;
};

function joinOne<T>(value: T | T[] | null | undefined): T | null {
  if (value == null) return null;
  return Array.isArray(value) ? (value[0] ?? null) : value;
}

/** Lista radares desde tabla `radars` (RLS lectura autenticados). */
export async function listarRadares(opts?: {
  despachadorId?: string;
  limit?: number;
}): Promise<RadarListaItem[]> {
  const supabase = await createClient();
  let query = supabase
    .from("radars")
    .select(
      `
      id, correlativo, despachador_id, fecha_despacho,
      total_cantidad_solicitada, total_cantidad_despachada,
      total_contenedores_retirados, status_radar, created_at,
      perfiles_usuario(nombre_completo)
    `,
    )
    .order("fecha_despacho", { ascending: false })
    .order("correlativo", { ascending: false })
    .limit(opts?.limit ?? 80);

  if (opts?.despachadorId) {
    query = query.eq("despachador_id", opts.despachadorId);
  }

  const { data, error } = await query;
  if (error) {
    console.error("[listarRadares]", error.message);
    return [];
  }

  const rows = (data ?? []) as RadarRow[];
  const ids = rows.map((r) => r.id);
  const counts = new Map<string, number>();

  if (ids.length) {
    const { data: ordenes } = await supabase
      .from("ordenes_distribucion")
      .select("radar_id")
      .in("radar_id", ids);
    for (const o of ordenes ?? []) {
      if (!o.radar_id) continue;
      counts.set(o.radar_id, (counts.get(o.radar_id) ?? 0) + 1);
    }
  }

  return rows.map((row) => {
    const perfil = joinOne(row.perfiles_usuario);
    return {
      id: row.id,
      correlativo: row.correlativo,
      despachador_id: row.despachador_id,
      despachador_nombre: perfil?.nombre_completo ?? "—",
      fecha_despacho: row.fecha_despacho,
      total_cantidad_solicitada: Number(row.total_cantidad_solicitada ?? 0),
      total_cantidad_despachada: Number(row.total_cantidad_despachada ?? 0),
      total_contenedores_retirados: Number(row.total_contenedores_retirados ?? 0),
      status_radar: row.status_radar,
      total_ordenes: counts.get(row.id) ?? 0,
      created_at: row.created_at,
    };
  });
}

/**
 * Fallback local equivalente a §2.30 cuando el RPC no está disponible
 * o cuando el rol debe ver todos los radares (no solo los propios).
 */
export async function listarRadaresPorRangoLocal(opts: {
  fechaInicial: string;
  fechaLimite: string;
  despachadorId?: string | null;
}): Promise<RadarListaRangoItem[]> {
  const supabase = await createClient();

  async function fetchRows() {
    let q = supabase
      .from("radars")
      .select("id, correlativo, despachador_id, fecha_despacho, status_radar")
      .gte("fecha_despacho", opts.fechaInicial)
      .lte("fecha_despacho", opts.fechaLimite)
      .order("fecha_despacho", { ascending: false })
      .order("correlativo", { ascending: false })
      .limit(200);
    if (opts.despachadorId) {
      q = q.eq("despachador_id", opts.despachadorId);
    }
    return q;
  }

  const { data, error } = await fetchRows();

  if (error) {
    console.error("[listarRadaresPorRangoLocal]", error.message);
    return [];
  }

  const rows = (data ?? []) as unknown as RadarRow[];
  if (!rows.length) return [];

  const ids = rows.map((r) => r.id);
  const { data: ordenes } = await supabase
    .from("ordenes_distribucion")
    .select(
      `
      id, radar_id,
      detalle_distribucion(producto_id, cantidad_despachada, cantidad_solicitada)
    `,
    )
    .in("radar_id", ids);

  type Det = {
    producto_id: string | null;
    cantidad_despachada: number | null;
    cantidad_solicitada: number | null;
  };
  type Ord = {
    id: string;
    radar_id: string | null;
    detalle_distribucion: Det[] | Det | null;
  };

  const stats = new Map<
    string,
    { paradas: number; items: number; skus: Set<string> }
  >();

  for (const o of (ordenes ?? []) as Ord[]) {
    if (!o.radar_id) continue;
    let s = stats.get(o.radar_id);
    if (!s) {
      s = { paradas: 0, items: 0, skus: new Set() };
      stats.set(o.radar_id, s);
    }
    s.paradas += 1;
    const dets = Array.isArray(o.detalle_distribucion)
      ? o.detalle_distribucion
      : o.detalle_distribucion
        ? [o.detalle_distribucion]
        : [];
    for (const d of dets) {
      s.items += Number(d.cantidad_despachada ?? d.cantidad_solicitada ?? 0);
      if (d.producto_id) s.skus.add(d.producto_id);
    }
  }

  return rows.map((row) => {
    const s = stats.get(row.id);
    return {
      fecha_despacho: String(row.fecha_despacho).slice(0, 10),
      id_radar: row.id,
      correlativo: Number(row.correlativo ?? 0),
      total_paradas: s?.paradas ?? 0,
      items: s?.items ?? 0,
      sku: s?.skus.size ?? 0,
      status_radar: Boolean(row.status_radar),
    };
  });
}
