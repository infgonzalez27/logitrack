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
    valor_unitario_recaudar: number;
    subtotal_recaudar: number;
    productos: {
      nombre: string;
      codigo_producto: string | null;
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
        "id, correlativo, estado, fecha_despacho, factura_origen_numero, total_recaudar_bs, creado_por, vendedor_id, created_at, clientes(razon_social)",
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
      clientes(razon_social, rif_nit, direccion_fiscal),
      camiones(placa, modelo),
      detalle_distribucion(
        id, secuencia_entrega, cantidad_solicitada, valor_unitario_recaudar, subtotal_recaudar,
        productos(nombre, codigo_producto)
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
        | { nombre: string; codigo_producto: string | null }
        | { nombre: string; codigo_producto: string | null }[]
        | null,
    ),
  }));

  return {
    ok: true,
    orden: {
      ...(data as Omit<OrdenDetalle, "clientes" | "camiones" | "detalle_distribucion">),
      clientes,
      camiones,
      detalle_distribucion: detalle,
    },
  };
}

export async function resolveDespachadorNombre(
  despachadorId: string | null,
): Promise<string> {
  if (!despachadorId) return "—";
  const { data } = await supabase
    .from("perfiles_usuario")
    .select("nombre_completo")
    .eq("id", despachadorId)
    .maybeSingle();
  return data?.nombre_completo ?? "—";
}
