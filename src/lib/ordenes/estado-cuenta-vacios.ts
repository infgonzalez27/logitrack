import type { SupabaseClient } from "@supabase/supabase-js";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";

export type EstadoCuentaVacioLinea = {
  contenedor_id: string;
  nombre: string;
  entregado: number;
  saldo_anterior: number;
  retirado: number;
  /** Saldo a mostrar: proyectado si radar no aprobado; DB si ya aprobado. */
  saldo_nuevo: number;
};

export type EstadoCuentaVacios = {
  lineas: EstadoCuentaVacioLinea[];
  /** true = saldos DB ya reflejan retiros; no restar de nuevo. */
  radarAprobado: boolean;
  provisional: boolean;
};

type DetalleVacios = {
  cantidad_despachada?: number | null;
  cantidad_solicitada?: number | null;
  contenedores_retirados?: number | null;
  contenedor_id?: string | null;
  productos?:
    | {
        contenedor_id?: string | null;
        unidades_por_contenedor?: number | null;
      }
    | {
        contenedor_id?: string | null;
        unidades_por_contenedor?: number | null;
      }[]
    | null;
};

function productoDeLinea(linea: DetalleVacios) {
  return Array.isArray(linea.productos) ? linea.productos[0] : linea.productos;
}

function contenedorIdDeLinea(linea: DetalleVacios): string | null {
  const directo =
    typeof linea.contenedor_id === "string" && linea.contenedor_id.trim()
      ? linea.contenedor_id.trim()
      : null;
  if (directo) return directo;
  const p = productoDeLinea(linea);
  return p?.contenedor_id?.trim() || null;
}

/** Agrega retiros de detalle por contenedor_id (detalle o producto). */
export function agregarRetirosPorContenedor(
  detalle: DetalleVacios[],
): Map<string, number> {
  const map = new Map<string, number>();
  for (const d of detalle) {
    const qty = Number(d.contenedores_retirados ?? 0);
    if (!Number.isFinite(qty) || qty <= 0) continue;
    const cid = contenedorIdDeLinea(d);
    if (!cid) continue;
    map.set(cid, (map.get(cid) ?? 0) + qty);
  }
  return map;
}

function agregarEntregadosPorContenedor(
  detalle: DetalleVacios[],
): Map<string, number> {
  const map = new Map<string, number>();
  for (const d of detalle) {
    const p = productoDeLinea(d);
    const cid = contenedorIdDeLinea(d);
    if (!cid) continue;
    const unidades = Math.max(1, Number(p?.unidades_por_contenedor) || 1);
    const cantidad =
      Number(d.cantidad_despachada) || Number(d.cantidad_solicitada) || 0;
    const vacios = Math.floor(cantidad / unidades);
    if (vacios <= 0) continue;
    map.set(cid, (map.get(cid) ?? 0) + vacios);
  }
  return map;
}

async function dbClient(): Promise<SupabaseClient> {
  try {
    return createAdminClient();
  } catch {
    return createClient();
  }
}

/**
 * Estado de cuenta de vacíos para ticket.
 * Prefiere service role (despachador a menudo no lee saldos por RLS).
 * Antes de aprobar radar: proyecta saldo_DB − retiros de la orden.
 * Después de aprobar: muestra saldo DB (ya actualizado).
 */
export async function retornaEstadoCuentaVaciosOrden(input: {
  clienteId: string;
  ordenId?: string | null;
  radarId?: string | null;
  detalle: DetalleVacios[];
}): Promise<EstadoCuentaVacios> {
  const db = await dbClient();
  const retiros = agregarRetirosPorContenedor(input.detalle);
  const entregados = agregarEntregadosPorContenedor(input.detalle);

  let radarAprobado = false;
  if (input.radarId) {
    const { data: radar } = await db
      .from("radars")
      .select("status_radar")
      .eq("id", input.radarId)
      .maybeSingle();
    radarAprobado = Boolean(radar?.status_radar);
  }

  const { data: saldos } = await db
    .from("saldo_contenedores_clientes")
    .select("contenedor_id, saldo_pendiente")
    .eq("cliente_id", input.clienteId);

  const saldoById = new Map<string, number>();
  for (const row of saldos ?? []) {
    const id = String(row.contenedor_id ?? "").trim();
    if (!id) continue;
    saldoById.set(id, Number(row.saldo_pendiente ?? 0));
  }

  // Incluir tipos de envase de la orden aunque saldo/retiro aún no existan.
  for (const d of input.detalle) {
    const cid = contenedorIdDeLinea(d);
    if (!cid) continue;
    if (!saldoById.has(cid) && !retiros.has(cid) && !entregados.has(cid)) {
      entregados.set(cid, 0);
    }
  }

  const ids = new Set<string>([
    ...saldoById.keys(),
    ...retiros.keys(),
    ...entregados.keys(),
  ]);

  const nombres = new Map<string, string>();
  if (ids.size) {
    const { data: tipos } = await db
      .from("tipos_contenedores")
      .select("id, nombre, codigo")
      .in("id", [...ids]);
    for (const t of tipos ?? []) {
      const id = String(t.id);
      const label =
        t.codigo && String(t.codigo).trim()
          ? `${t.codigo} — ${t.nombre}`
          : String(t.nombre ?? id);
      nombres.set(id, label);
    }
  }

  const lineas: EstadoCuentaVacioLinea[] = [...ids]
    .map((contenedor_id) => {
      const entregado = entregados.get(contenedor_id) ?? 0;
      const retirado = retiros.get(contenedor_id) ?? 0;
      const saldoDb = saldoById.get(contenedor_id) ?? 0;
      // Si el crédito de esta orden aún no figura en DB, usa entregado como piso.
      const saldo_anterior =
        saldoDb > 0 || radarAprobado ? saldoDb : Math.max(saldoDb, entregado);
      const saldo_nuevo = radarAprobado
        ? saldoDb
        : Math.max(0, saldo_anterior - retirado);
      return {
        contenedor_id,
        nombre: nombres.get(contenedor_id) ?? contenedor_id.slice(0, 8),
        entregado,
        saldo_anterior,
        retirado,
        saldo_nuevo,
      };
    })
    .filter(
      (l) =>
        l.saldo_anterior > 0 ||
        l.retirado > 0 ||
        l.saldo_nuevo > 0 ||
        l.entregado > 0 ||
        // Mostrar envase de la orden aunque todo esté en 0.
        nombres.has(l.contenedor_id),
    )
    .sort((a, b) => a.nombre.localeCompare(b.nombre, "es"));

  return {
    lineas,
    radarAprobado,
    provisional: !radarAprobado && lineas.some((l) => l.retirado > 0),
  };
}
