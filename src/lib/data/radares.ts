import { createClient } from "@/lib/supabase/server";
import type { RadarListaItem } from "@/types/database";

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
