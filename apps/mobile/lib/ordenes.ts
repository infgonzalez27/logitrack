import { supabase } from "./supabase";
import type { AppProfile } from "./auth";

export type OrdenListaItem = {
  id: string;
  correlativo: number;
  cliente_razon_social: string | null;
  estado: string;
  fecha_despacho: string | null;
  factura_origen_numero: string | null;
  total_recaudar_usd: number | null;
  creado_por: string | null;
  vendedor_id?: string | null;
  created_at: string;
};

export type OrdenDetalle = {
  id: string;
  correlativo: number;
  estado: string;
  factura_origen_numero: string | null;
  fecha_despacho: string | null;
  created_at: string;
  total_recaudar_usd: number | null;
  peso_total_calculado: number | null;
  despachador_id: string | null;
  cliente_id: string | null;
  radar_id: string | null;
  clientes: {
    razon_social: string;
    rif_nit: string;
    direccion_fiscal: string | null;
  } | null;
  camiones: { placa: string; modelo: string | null } | null;
  detalle_distribucion: Array<{
    id: string;
    secuencia_entrega: number | null;
    cantidad_solicitada: number;
    valor_unitario_usd: number | null;
    subtotal_recaudar_usd: number | null;
    precio_lista_usd: number | null;
    porcentaje_descuento: number | null;
    monto_descuento_usd: number | null;
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
  message?: string;
  orden_id?: string;
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
    if (error) break;
    const rows = unwrapRpc<OrdenListaItem[]>(data) ?? [];
    for (const row of rows) {
      byId.set(row.id, {
        ...row,
        cliente_razon_social: row.cliente_razon_social ?? null,
        total_recaudar_usd: row.total_recaudar_usd ?? null,
      });
    }
  }

  if (byId.size === 0) {
    let query = supabase
      .from("ordenes_distribucion")
      .select(
        "id, correlativo, estado, fecha_despacho, factura_origen_numero, total_recaudar_usd, creado_por, vendedor_id, created_at, clientes(razon_social)",
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
      peso_total_calculado, total_recaudar_usd, despachador_id, cliente_id, radar_id,
      clientes(razon_social, rif_nit, direccion_fiscal),
      camiones(placa, modelo),
      detalle_distribucion(
        id, secuencia_entrega, cantidad_solicitada,
        valor_unitario_usd, subtotal_recaudar_usd,
        precio_lista_usd, porcentaje_descuento, monto_descuento_usd,
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
      id: data.id,
      correlativo: data.correlativo,
      estado: data.estado,
      factura_origen_numero: data.factura_origen_numero,
      fecha_despacho: data.fecha_despacho,
      created_at: data.created_at,
      total_recaudar_usd: data.total_recaudar_usd,
      peso_total_calculado: data.peso_total_calculado ?? null,
      despachador_id: data.despachador_id ?? null,
      cliente_id: data.cliente_id,
      radar_id: data.radar_id ?? null,
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

/** Lee asientos de vacíos de esta orden (DB-036). */
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
    const cid = String(m.contenedor_id ?? "").trim();
    if (!cid) continue;
    const prev = byId.get(cid) ?? { entregado: 0, retirado: 0 };
    prev.entregado += Number(m.cantidad_entregada) || 0;
    prev.retirado += Number(m.cantidad_retirada) || 0;
    byId.set(cid, prev);
  }

  const ids = [...byId.keys()];
  const { data: saldos } = await supabase
    .from("saldo_contenedores_clientes")
    .select("contenedor_id, saldo_pendiente")
    .eq("cliente_id", clienteId)
    .in("contenedor_id", ids);

  const saldoTabla = new Map<string, number>();
  for (const s of saldos ?? []) {
    saldoTabla.set(String(s.contenedor_id), Number(s.saldo_pendiente) || 0);
  }

  const nombres = new Map<string, string>();
  const { data: tipos } = await supabase
    .from("tipos_contenedores")
    .select("id, nombre, codigo")
    .in("id", ids);
  for (const t of tipos ?? []) {
    const tid = String(t.id);
    nombres.set(
      tid,
      t.codigo && String(t.codigo).trim()
        ? `${t.codigo} - ${t.nombre}`
        : String(t.nombre ?? tid),
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

export type LineaCrearOrden = {
  producto_id: string;
  cantidad_solicitada: number;
  valor_unitario_usd: number;
};

export async function crearOrdenDistribucion(input: {
  vendedorId: string;
  clienteId: string;
  camionId: string;
  fechaDespachoIso: string;
  lineas: LineaCrearOrden[];
  tasaCambio?: number | null;
}): Promise<{ ok: true; ordenId: string } | { ok: false; error: string }> {
  const { data: cliente, error: clienteError } = await supabase
    .from("clientes")
    .select("despachador_id, id_ruta")
    .eq("id", input.clienteId)
    .maybeSingle();

  if (clienteError) return { ok: false, error: clienteError.message };
  if (!cliente) return { ok: false, error: "Cliente no encontrado." };
  if (!cliente.despachador_id) {
    return {
      ok: false,
      error: "El cliente no tiene despachador asignado.",
    };
  }

  const productosJson = input.lineas.map((l) => ({
    producto_id: l.producto_id,
    cantidad: l.cantidad_solicitada,
    precio_unitario: l.valor_unitario_usd,
    valor_unitario_usd: l.valor_unitario_usd,
    valor_unitario_recaudar: null,
  }));

  const { data, error } = await supabase.rpc("crear_orden_distribucion", {
    p_vendedor_id: input.vendedorId,
    p_cliente_id: input.clienteId,
    p_camion_id: input.camionId,
    p_tasa_cambio: input.tasaCambio ?? null,
    p_productos_json: productosJson,
    p_despachador_id: cliente.despachador_id,
    p_id_ruta: cliente.id_ruta,
  });

  if (error) return { ok: false, error: error.message };

  const env = data as RpcEnvelope<{ orden_id?: string }> | null;
  if (env && env.success === false) {
    return {
      ok: false,
      error: env.message ?? env.error?.message ?? "No se pudo crear la orden.",
    };
  }

  const ordenId =
    env?.orden_id ??
    env?.data?.orden_id ??
    (typeof env?.data === "object" && env?.data && "orden_id" in env.data
      ? String((env.data as { orden_id: string }).orden_id)
      : null);

  if (!ordenId) {
    return { ok: false, error: "Orden creada pero sin ID de respuesta." };
  }

  const fecha = new Date(input.fechaDespachoIso);
  if (!Number.isNaN(fecha.getTime())) {
    await supabase
      .from("ordenes_distribucion")
      .update({ fecha_despacho: fecha.toISOString() })
      .eq("id", ordenId);
  }

  return { ok: true, ordenId };
}

/** Actualiza fecha de despacho (y opcionalmente factura) en órdenes editables. */
export async function actualizarFechaDespachoOrden(input: {
  ordenId: string;
  fechaDespachoIso: string;
  facturaOrigenNumero?: string | null;
}): Promise<{ ok: true } | { ok: false; error: string }> {
  const fecha = new Date(input.fechaDespachoIso);
  if (Number.isNaN(fecha.getTime())) {
    return { ok: false, error: "Fecha de despacho inválida." };
  }

  const { data: orden, error: fetchError } = await supabase
    .from("ordenes_distribucion")
    .select("id, estado")
    .eq("id", input.ordenId)
    .maybeSingle();

  if (fetchError) return { ok: false, error: fetchError.message };
  if (!orden) return { ok: false, error: "Orden no encontrada." };

  const estado = String(orden.estado ?? "");
  if (estado !== "borrador" && estado !== "aprobada") {
    return {
      ok: false,
      error: "Solo se puede editar la fecha en borrador o aprobada.",
    };
  }

  const patch: {
    fecha_despacho: string;
    factura_origen_numero?: string | null;
  } = {
    fecha_despacho: fecha.toISOString(),
  };
  if (input.facturaOrigenNumero !== undefined) {
    patch.factura_origen_numero = input.facturaOrigenNumero?.trim() || null;
  }

  const { error } = await supabase
    .from("ordenes_distribucion")
    .update(patch)
    .eq("id", input.ordenId);

  if (error) return { ok: false, error: error.message };
  return { ok: true };
}

/** Aprueba orden vía RPC `aprobar_orden_distribucion` (borrador → aprobada). */
export async function aprobarOrdenDistribucion(
  ordenId: string,
): Promise<{ ok: true; message?: string } | { ok: false; error: string }> {
  const { data, error } = await supabase.rpc("aprobar_orden_distribucion", {
    p_orden_id: ordenId,
  });
  if (error) return { ok: false, error: error.message };

  const env = data as {
    success?: boolean;
    message?: string;
    error?: { message?: string } | null;
  } | null;
  if (env && env.success === false) {
    return {
      ok: false,
      error: env.message ?? env.error?.message ?? "No se pudo aprobar la orden.",
    };
  }
  return { ok: true, message: env?.message };
}
