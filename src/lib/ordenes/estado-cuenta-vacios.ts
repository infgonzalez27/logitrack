import type { SupabaseClient } from "@supabase/supabase-js";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";

export type EstadoCuentaVacioLinea = {
  contenedor_id: string;
  nombre: string;
  entregado: number;
  saldo_anterior: number;
  retirado: number;
  /** Saldo a mostrar: proyectado si radar no aprobado; consolidado si ya aprobado. */
  saldo_nuevo: number;
};

export type EstadoCuentaVacios = {
  lineas: EstadoCuentaVacioLinea[];
  radarAprobado: boolean;
  provisional: boolean;
};

/** Fila de `contenedores_resumen` en `registrar_despacho_cliente_radar` (DB-036). */
export type ContenedorResumenDespacho = {
  contenedor_id: string;
  saldo_anterior: number;
  cantidad_entregada: number;
  cantidad_retirada: number;
  saldo_actualizado: number;
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
    // Misma fórmula que registrar_despacho_cliente_radar (DB-036):
    // CEIL(cantidad_despachada / GREATEST(unidades_por_contenedor, 1))
    const unidades = Math.max(1, Number(p?.unidades_por_contenedor) || 1);
    const cantidad =
      Number(d.cantidad_despachada) || Number(d.cantidad_solicitada) || 0;
    if (cantidad <= 0) continue;
    const vacios = Math.ceil(cantidad / unidades);
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
 *
 * DB-036: al confirmar despacho, `registrar_despacho_cliente_radar` asienta
 * movimientos y saldo. El ticket prioriza esos movimientos; si aún no hay
 * asiento (orden sin despachar), proyecta desde el detalle.
 */
export async function retornaEstadoCuentaVaciosOrden(input: {
  clienteId: string;
  ordenId?: string | null;
  radarId?: string | null;
  detalle: DetalleVacios[];
}): Promise<EstadoCuentaVacios> {
  const db = await dbClient();
  const retirosDetalle = agregarRetirosPorContenedor(input.detalle);
  const entregadosDetalle = agregarEntregadosPorContenedor(input.detalle);

  let radarAprobado = false;
  if (input.radarId) {
    const { data: radar } = await db
      .from("radars")
      .select("status_radar")
      .eq("id", input.radarId)
      .maybeSingle();
    radarAprobado = Boolean(radar?.status_radar);
  }

  // Fuente viva: movimientos (asentados al despachar — DB-036).
  const { data: movimientos } = await db
    .from("movimientos_contenedores")
    .select("orden_id, contenedor_id, cantidad_entregada, cantidad_retirada")
    .eq("cliente_id", input.clienteId);

  const saldoMovById = new Map<string, number>();
  const entregadoOrdenMov = new Map<string, number>();
  const retiradoOrdenMov = new Map<string, number>();

  for (const m of movimientos ?? []) {
    const id = String(m.contenedor_id ?? "").trim();
    if (!id) continue;
    const ent = Number(m.cantidad_entregada) || 0;
    const ret = Number(m.cantidad_retirada) || 0;
    saldoMovById.set(id, (saldoMovById.get(id) ?? 0) + ent - ret);
    if (input.ordenId && String(m.orden_id) === input.ordenId) {
      if (ent > 0) {
        entregadoOrdenMov.set(id, (entregadoOrdenMov.get(id) ?? 0) + ent);
      }
      if (ret > 0) {
        retiradoOrdenMov.set(id, (retiradoOrdenMov.get(id) ?? 0) + ret);
      }
    }
  }

  const asentadoEnDespacho =
    entregadoOrdenMov.size > 0 || retiradoOrdenMov.size > 0;

  // Fallback / complemento: tabla consolidada (ahora también se actualiza al despachar).
  const { data: saldos } = await db
    .from("saldo_contenedores_clientes")
    .select("contenedor_id, saldo_pendiente")
    .eq("cliente_id", input.clienteId);

  const saldoTablaById = new Map<string, number>();
  for (const row of saldos ?? []) {
    const id = String(row.contenedor_id ?? "").trim();
    if (!id) continue;
    saldoTablaById.set(id, Number(row.saldo_pendiente ?? 0));
  }

  const ids = new Set<string>([
    ...saldoMovById.keys(),
    ...saldoTablaById.keys(),
    ...retirosDetalle.keys(),
    ...entregadosDetalle.keys(),
  ]);

  for (const d of input.detalle) {
    const cid = contenedorIdDeLinea(d);
    if (cid) ids.add(cid);
  }

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
      const entregado =
        (entregadoOrdenMov.get(contenedor_id) ?? 0) ||
        (entregadosDetalle.get(contenedor_id) ?? 0);
      const retiradoDetalle = retirosDetalle.get(contenedor_id) ?? 0;
      const retiradoMov = retiradoOrdenMov.get(contenedor_id) ?? 0;
      const retirado = asentadoEnDespacho
        ? retiradoMov || retiradoDetalle
        : Math.max(retiradoDetalle, retiradoMov);

      const saldoMov = saldoMovById.get(contenedor_id);
      const saldoTabla = saldoTablaById.get(contenedor_id);

      let saldo_anterior =
        saldoMov != null
          ? saldoMov
          : saldoTabla != null
            ? saldoTabla
            : entregado;

      if (
        !asentadoEnDespacho &&
        saldoMov != null &&
        (entregadoOrdenMov.get(contenedor_id) ?? 0) === 0 &&
        (entregadosDetalle.get(contenedor_id) ?? 0) > 0
      ) {
        saldo_anterior += entregadosDetalle.get(contenedor_id) ?? 0;
      }

      // Con asiento al despachar, el saldo consolidado ya refleja retiros.
      const saldo_nuevo =
        asentadoEnDespacho || radarAprobado
          ? Math.max(
              0,
              saldoTabla != null
                ? saldoTabla
                : saldoMov != null
                  ? saldoMov
                  : saldo_anterior,
            )
          : Math.max(0, saldo_anterior - (retiradoDetalle - retiradoMov));

      // Antes del asiento, saldo_anterior en movimientos incluye la entrega;
      // para mostrar "saldo anterior" visual = saldo_nuevo + retirado - entregado
      // no hace falta: el ticket usa entregado/retirado/saldo_nuevo.

      return {
        contenedor_id,
        nombre: nombres.get(contenedor_id) ?? contenedor_id.slice(0, 8),
        entregado,
        saldo_anterior: Math.max(0, saldo_anterior),
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
        nombres.has(l.contenedor_id),
    )
    .sort((a, b) => a.nombre.localeCompare(b.nombre, "es"));

  return {
    lineas,
    radarAprobado,
    // Ya no es provisional tras el asiento en despacho (DB-036).
    provisional:
      !asentadoEnDespacho &&
      !radarAprobado &&
      lineas.some((l) => l.retirado > 0),
  };
}

/** Convierte `contenedores_resumen` del RPC de despacho a líneas de ticket. */
export async function lineasDesdeContenedoresResumen(
  resumen: ContenedorResumenDespacho[],
): Promise<EstadoCuentaVacioLinea[]> {
  if (!resumen.length) return [];
  const db = await dbClient();
  const ids = [
    ...new Set(
      resumen
        .map((r) => String(r.contenedor_id ?? "").trim())
        .filter(Boolean),
    ),
  ];
  const nombres = new Map<string, string>();
  if (ids.length) {
    const { data: tipos } = await db
      .from("tipos_contenedores")
      .select("id, nombre, codigo")
      .in("id", ids);
    for (const t of tipos ?? []) {
      const id = String(t.id);
      nombres.set(
        id,
        t.codigo && String(t.codigo).trim()
          ? `${t.codigo} — ${t.nombre}`
          : String(t.nombre ?? id),
      );
    }
  }
  return resumen
    .map((r) => {
      const contenedor_id = String(r.contenedor_id ?? "").trim();
      return {
        contenedor_id,
        nombre: nombres.get(contenedor_id) ?? contenedor_id.slice(0, 8),
        entregado: Number(r.cantidad_entregada) || 0,
        saldo_anterior: Math.max(0, Number(r.saldo_anterior) || 0),
        retirado: Number(r.cantidad_retirada) || 0,
        saldo_nuevo: Math.max(0, Number(r.saldo_actualizado) || 0),
      };
    })
    .filter((l) => l.contenedor_id)
    .sort((a, b) => a.nombre.localeCompare(b.nombre, "es"));
}
