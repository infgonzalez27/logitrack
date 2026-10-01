import { createClient } from "@/lib/supabase/server";
import { joinOne } from "@/lib/supabase/join";

export type VacioTipo = { id: string; nombre: string; codigo: string | null };

export type VaciosOrdenFila = {
  orden_id: string;
  correlativo: number;
  cliente: string;
  retirados: Record<string, number>;
  total: number;
};

export type VaciosPorOrdenData = {
  tipos: VacioTipo[];
  ordenes: VaciosOrdenFila[];
};

/** Día calendario de Venezuela (UTC-4, sin horario de verano). */
function rangoDiaCaracas(fechaIso: string): { desde: string; hasta: string } {
  const fecha = fechaIso ? new Date(fechaIso) : new Date();
  const base = Number.isNaN(fecha.getTime()) ? new Date() : fecha;
  const ymd = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Caracas",
  }).format(base);
  const desde = new Date(`${ymd}T00:00:00-04:00`);
  const hasta = new Date(desde.getTime() + 24 * 60 * 60 * 1000);
  return { desde: desde.toISOString(), hasta: hasta.toISOString() };
}

/** Órdenes AutoVenta del camión en el día y vacíos retirados en cada una. */
export async function getVaciosRetiradosPorOrden(
  camionId: string,
  fechaIso: string,
): Promise<VaciosPorOrdenData> {
  const supabase = await createClient();
  const { desde, hasta } = rangoDiaCaracas(fechaIso);

  const { data: ordenesData } = await supabase
    .from("ordenes_distribucion")
    .select("id, correlativo, clientes(razon_social)")
    .eq("camion_id", camionId)
    .eq("es_autoventa", true)
    .neq("estado", "anulada")
    .gte("created_at", desde)
    .lt("created_at", hasta)
    .order("created_at", { ascending: true });

  const ordenes = ordenesData ?? [];
  if (!ordenes.length) return { tipos: [], ordenes: [] };

  const { data: movimientos } = await supabase
    .from("movimientos_contenedores")
    .select("orden_id, contenedor_id, cantidad_retirada, tipos_contenedores(nombre, codigo)")
    .in(
      "orden_id",
      ordenes.map((o) => o.id),
    );

  const tiposById = new Map<string, VacioTipo>();
  const retiradosByOrden = new Map<string, Record<string, number>>();

  for (const m of movimientos ?? []) {
    const cantidad = Number(m.cantidad_retirada) || 0;
    if (cantidad <= 0 || !m.orden_id || !m.contenedor_id) continue;
    const tipoId = String(m.contenedor_id);
    if (!tiposById.has(tipoId)) {
      const tipo = joinOne(m.tipos_contenedores);
      tiposById.set(tipoId, {
        id: tipoId,
        nombre: String(tipo?.nombre ?? "Envase"),
        codigo: tipo?.codigo ? String(tipo.codigo) : null,
      });
    }
    const ordenId = String(m.orden_id);
    const fila = retiradosByOrden.get(ordenId) ?? {};
    fila[tipoId] = (fila[tipoId] ?? 0) + cantidad;
    retiradosByOrden.set(ordenId, fila);
  }

  return {
    tipos: [...tiposById.values()].sort((a, b) =>
      a.nombre.localeCompare(b.nombre, "es"),
    ),
    ordenes: ordenes.map((o) => {
      const retirados = retiradosByOrden.get(String(o.id)) ?? {};
      return {
        orden_id: String(o.id),
        correlativo: Number(o.correlativo),
        cliente: String(joinOne(o.clientes)?.razon_social ?? "—"),
        retirados,
        total: Object.values(retirados).reduce((s, n) => s + n, 0),
      };
    }),
  };
}
