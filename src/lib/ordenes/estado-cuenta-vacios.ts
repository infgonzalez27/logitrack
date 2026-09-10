import { createClient } from "@/lib/supabase/server";

export type EstadoCuentaVacioLinea = {
  contenedor_id: string;
  nombre: string;
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

type DetalleRetiro = {
  contenedores_retirados?: number | null;
  contenedor_id?: string | null;
  productos?:
    | { contenedor_id?: string | null }
    | { contenedor_id?: string | null }[]
    | null;
};

function productoContenedorId(linea: DetalleRetiro): string | null {
  const p = Array.isArray(linea.productos)
    ? linea.productos[0]
    : linea.productos;
  return p?.contenedor_id ?? null;
}

/** Agrega retiros de detalle por contenedor_id (detalle o producto). */
export function agregarRetirosPorContenedor(
  detalle: DetalleRetiro[],
): Map<string, number> {
  const map = new Map<string, number>();
  for (const d of detalle) {
    const qty = Number(d.contenedores_retirados ?? 0);
    if (!Number.isFinite(qty) || qty <= 0) continue;
    const cid =
      (typeof d.contenedor_id === "string" && d.contenedor_id.trim()
        ? d.contenedor_id.trim()
        : null) ?? productoContenedorId(d);
    if (!cid) continue;
    map.set(cid, (map.get(cid) ?? 0) + qty);
  }
  return map;
}

/**
 * Estado de cuenta de vacíos para ticket.
 * Antes de aprobar radar: proyecta saldo_DB − retiros de la orden (front).
 * Después de aprobar: muestra saldo DB (ya actualizado).
 */
export async function retornaEstadoCuentaVaciosOrden(input: {
  clienteId: string;
  radarId?: string | null;
  detalle: DetalleRetiro[];
}): Promise<EstadoCuentaVacios> {
  const supabase = await createClient();
  const retiros = agregarRetirosPorContenedor(input.detalle);

  let radarAprobado = false;
  if (input.radarId) {
    const { data: radar } = await supabase
      .from("radars")
      .select("status_radar")
      .eq("id", input.radarId)
      .maybeSingle();
    radarAprobado = !!(radar && radar.status_radar === true);
  }

  const { data: saldos } = await supabase
    .from("saldo_contenedores_clientes")
    .select("contenedor_id, saldo_pendiente")
    .eq("cliente_id", input.clienteId);

  const saldoById = new Map<string, number>();
  for (const row of saldos ?? []) {
    const id = row.contenedor_id as string;
    if (!id) continue;
    saldoById.set(id, Number(row.saldo_pendiente ?? 0));
  }

  const ids = new Set<string>([...saldoById.keys(), ...retiros.keys()]);
  const nombres = new Map<string, string>();
  if (ids.size) {
    const { data: tipos } = await supabase
      .from("tipos_contenedores")
      .select("id, nombre, codigo")
      .in("id", [...ids]);
    for (const t of tipos ?? []) {
      const label =
        t.codigo && String(t.codigo).trim()
          ? `${t.codigo} — ${t.nombre}`
          : String(t.nombre ?? t.id);
      nombres.set(t.id as string, label);
    }
  }

  const lineas: EstadoCuentaVacioLinea[] = [...ids]
    .map((contenedor_id) => {
      const saldo_anterior = saldoById.get(contenedor_id) ?? 0;
      const retirado = retiros.get(contenedor_id) ?? 0;
      const saldo_nuevo = radarAprobado
        ? saldo_anterior
        : Math.max(0, saldo_anterior - retirado);
      return {
        contenedor_id,
        nombre: nombres.get(contenedor_id) ?? contenedor_id.slice(0, 8),
        saldo_anterior,
        retirado,
        saldo_nuevo,
      };
    })
    .filter((l) => l.saldo_anterior > 0 || l.retirado > 0 || l.saldo_nuevo > 0)
    .sort((a, b) => a.nombre.localeCompare(b.nombre, "es"));

  return {
    lineas,
    radarAprobado,
    provisional: !radarAprobado && lineas.some((l) => l.retirado > 0),
  };
}
