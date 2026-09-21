import { supabase } from "./supabase";
import type { AppProfile } from "./auth";

export type OrdenListaItem = {
  id: string;
  correlativo: number;
  cliente_razon_social: string | null;
  estado: string;
  fecha_despacho: string | null;
  factura_origen_numero: string | null;
  total_recaudar_bs: number | null;
  total_recaudar_usd: number | null;
  creado_por: string | null;
  vendedor_id?: string | null;
  created_at: string;
};

export type OrdenDetalle = {
  id: string;
  correlativo: number;
  estado: string;
  factura_origen_numero: string;
  fecha_despacho: string | null;
  created_at: string;
  peso_total_calculado: number | null;
  total_recaudar_bs: number | null;
  total_recaudar_usd: number | null;
  cliente_id: string | null;
  radar_id: string | null;
  clientes: {
    razon_social: string;
    rif_nit: string;
    direccion_fiscal: string;
  } | null;
  camiones: { placa: string; modelo: string | null } | null;
  despachador_id: string | null;
  detalle_distribucion: Array<{
    id: string;
    secuencia_entrega: number | null;
    cantidad_solicitada: number;
    cantidad_despachada: number | null;
    valor_unitario_recaudar: number | null;
    subtotal_recaudar: number | null;
    valor_unitario_usd: number | null;
    subtotal_recaudar_usd: number | null;
    contenedores_retirados: number | null;
    contenedor_id: string | null;
    productos: {
      nombre: string;
      codigo_producto: string | null;
      contenedor_id: string | null;
      unidades_por_contenedor: number | null;
    } | null;
  }>;
};

type RpcEnvelope<T> = {
  success?: boolean;
  data?: T | null;
  error?: { message?: string } | null;
};

const ESTADOS = [
  "borrador",
  "aprobada",
  "en_transito",
  "despachada",
  "por_liquidar",
  "liquidada",
  "anulada",
] as const;

function unwrapRpc<T>(payload: unknown): T | null {
  if (!payload || typeof payload !== "object") return null;
  const env = payload as RpcEnvelope<T>;
  if (env.success === false) return null;
  if (Array.isArray(env.data)) return env.data as T;
  if (env.data != null) return env.data;
  if (Array.isArray(payload)) return payload as T;
  return null;
}

function joinOne<T>(value: T | T[] | null | undefined): T | null {
  if (value == null) return null;
  return Array.isArray(value) ? (value[0] ?? null) : value;
}

export async function listOrdenesForProfile(
  profile: AppProfile,
): Promise<{ ok: true; ordenes: OrdenListaItem[] } | { ok: false; error: string }> {
  const byId = new Map<string, OrdenListaItem>();

  for (const estado of ESTADOS) {
    const { data, error } = await supabase.rpc(
      "retorna_ordenes_distribucion_segun_estado",
      { p_estado: estado },
    );
    if (error) {
      // Fallback tabla si el RPC falla
      break;
    }
    const rows = unwrapRpc<OrdenListaItem[]>(data) ?? [];
    for (const row of rows) {
      byId.set(row.id, row);
    }
  }

  if (byId.size === 0) {
    let query = supabase
      .from("ordenes_distribucion")
      .select(
        "id, correlativo, estado, fecha_despacho, factura_origen_numero, total_recaudar_bs, total_recaudar_usd, creado_por, vendedor_id, created_at, clientes(razon_social)",
      )
      .order("correlativo", { ascending: false })
      .limit(100);

    if (profile.rol === "vendedor") {
      query = query.or(
        `creado_por.eq.${profile.id},vendedor_id.eq.${profile.id}`,
      );
    }

    const { data, error } = await query;
    if (error) return { ok: false, error: error.message };

    const mapped: OrdenListaItem[] = (data ?? []).map((row) => {
      const cliente = joinOne(
        row.clientes as
          | { razon_social: string }
          | { razon_social: string }[]
          | null,
      );
      return {
        id: row.id,
        correlativo: row.correlativo,
        cliente_razon_social: cliente?.razon_social ?? null,
        estado: row.estado,
        fecha_despacho: row.fecha_despacho,
        factura_origen_numero: row.factura_origen_numero,
        total_recaudar_bs: row.total_recaudar_bs,
        total_recaudar_usd: row.total_recaudar_usd ?? null,
        creado_por: row.creado_por,
        vendedor_id: row.vendedor_id,
        created_at: row.created_at,
      };
    });
    return { ok: true, ordenes: mapped };
  }

  let ordenes = [...byId.values()].sort(
    (a, b) => b.correlativo - a.correlativo,
  );

  if (profile.rol === "vendedor") {
    ordenes = ordenes.filter(
      (o) => o.creado_por === profile.id || o.vendedor_id === profile.id,
    );
  }

  return { ok: true, ordenes };
}

export async function getOrdenDetalle(
  id: string,
): Promise<{ ok: true; orden: OrdenDetalle } | { ok: false; error: string }> {
  const { data, error } = await supabase
    .from("ordenes_distribucion")
    .select(
      `
      id, correlativo, estado, factura_origen_numero, fecha_despacho, created_at,
      peso_total_calculado, total_recaudar_bs, total_recaudar_usd, despachador_id,
      cliente_id, radar_id,
      clientes(razon_social, rif_nit, direccion_fiscal),
      camiones(placa, modelo),
      detalle_distribucion(
        id, secuencia_entrega, cantidad_solicitada, cantidad_despachada,
        valor_unitario_recaudar, subtotal_recaudar,
        valor_unitario_usd, subtotal_recaudar_usd,
        contenedores_retirados, contenedor_id,
        productos(nombre, codigo_producto, contenedor_id, unidades_por_contenedor)
      )
    `,
    )
    .eq("id", id)
    .maybeSingle();

  if (error) return { ok: false, error: error.message };
  if (!data) return { ok: false, error: "Orden no encontrada." };

  const clientes = joinOne(
    data.clientes as OrdenDetalle["clientes"] | OrdenDetalle["clientes"][],
  );
  const camiones = joinOne(
    data.camiones as OrdenDetalle["camiones"] | OrdenDetalle["camiones"][],
  );
  const detalle = (data.detalle_distribucion ?? []).map((linea) => ({
    ...linea,
    productos: joinOne(
      linea.productos as
        | {
            nombre: string;
            codigo_producto: string | null;
            contenedor_id: string | null;
            unidades_por_contenedor: number | null;
          }
        | {
            nombre: string;
            codigo_producto: string | null;
            contenedor_id: string | null;
            unidades_por_contenedor: number | null;
          }[]
        | null,
    ),
  }));

  return {
    ok: true,
    orden: {
      ...(data as Omit<
        OrdenDetalle,
        "clientes" | "camiones" | "detalle_distribucion"
      >),
      cliente_id: (data as { cliente_id?: string | null }).cliente_id ?? null,
      radar_id: (data as { radar_id?: string | null }).radar_id ?? null,
      clientes,
      camiones,
      detalle_distribucion: detalle,
    },
  };
}

export async function resolveDespachadorNombre(
  despachadorId: string | null,
): Promise<string> {
  if (!despachadorId) return "-";
  const { data } = await supabase
    .from("perfiles_usuario")
    .select("nombre_completo")
    .eq("id", despachadorId)
    .maybeSingle();
  return data?.nombre_completo ?? "-";
}

export type LineaVaciosTicket = {
  contenedor_id: string;
  nombre: string;
  entregado: number;
  retirado: number;
  saldo_nuevo: number;
};

/**
 * DB-036: lee solo el asiento del SP en movimientos de ESTA orden.
 * No proyecta CEIL desde productos en el dispositivo.
 */
export async function fetchEstadoCuentaVacios(orden: OrdenDetalle): Promise<{
  lineas: LineaVaciosTicket[];
  provisional: boolean;
}> {
  const clienteId = orden.cliente_id?.trim();
  const ordenId = orden.id?.trim();
  if (!clienteId || !ordenId) return { lineas: [], provisional: false };

  const { data: movs } = await supabase
    .from("movimientos_contenedores")
    .select("contenedor_id, cantidad_entregada, cantidad_retirada")
    .eq("cliente_id", clienteId)
    .eq("orden_id", ordenId);

  if (!movs?.length) return { lineas: [], provisional: false };

  const byId = new Map<string, { entregado: number; retirado: number }>();
  for (const m of movs) {
    const id = String(m.contenedor_id ?? "").trim();
    if (!id) continue;
    const prev = byId.get(id) ?? { entregado: 0, retirado: 0 };
    prev.entregado += Number(m.cantidad_entregada) || 0;
    prev.retirado += Number(m.cantidad_retirada) || 0;
    byId.set(id, prev);
  }

  const ids = [...byId.keys()];
  const { data: saldos } = await supabase
    .from("saldo_contenedores_clientes")
    .select("contenedor_id, saldo_pendiente")
    .eq("cliente_id", clienteId)
    .in("contenedor_id", ids);

  const saldoTabla = new Map<string, number>();
  for (const s of saldos ?? []) {
    saldoTabla.set(
      String(s.contenedor_id),
      Number(s.saldo_pendiente) || 0,
    );
  }

  const nombres = new Map<string, string>();
  const { data: tipos } = await supabase
    .from("tipos_contenedores")
    .select("id, nombre, codigo")
    .in("id", ids);
  for (const t of tipos ?? []) {
    const id = String(t.id);
    nombres.set(
      id,
      t.codigo && String(t.codigo).trim()
        ? `${t.codigo} - ${t.nombre}`
        : String(t.nombre ?? id),
    );
  }

  const lineas = [...byId.entries()]
    .map(([contenedor_id, v]) => ({
      contenedor_id,
      nombre: nombres.get(contenedor_id) ?? contenedor_id.slice(0, 8),
      entregado: v.entregado,
      retirado: v.retirado,
      saldo_nuevo: Math.max(
        0,
        saldoTabla.get(contenedor_id) ??
          Math.max(0, v.entregado - v.retirado),
      ),
    }))
    .filter((l) => l.entregado > 0 || l.retirado > 0 || l.saldo_nuevo > 0)
    .sort((a, b) => a.nombre.localeCompare(b.nombre, "es"));

  return { lineas, provisional: false };
}
