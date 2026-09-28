import { supabase } from "./supabase";
import { isRpcSuccess, rpcFailMessage, unwrapRpcData } from "./rpc";

export type ResumenAutoVentaItem = {
  producto_id: string;
  codigo: string;
  nombre: string;
  cantidad_cargada: number;
  cantidad_entregada: number;
  cantidad_disponible: number;
};

export type ResumenAutoVentaVenta = {
  orden_id: string;
  correlativo: number;
  factura_origen_numero: string;
  cliente_nombre: string;
  estado: string;
  total_recaudar_usd: number;
  total_recaudar_bs: number;
  created_at: string;
};

export type ResumenAutoVentaData = {
  camion_id: string;
  fecha: string;
  total_ordenes_autoventa: number;
  total_facturado_usd: number;
  total_facturado_bs: number;
  inventario_movil: ResumenAutoVentaItem[];
  ventas: ResumenAutoVentaVenta[];
};

export type InventarioMovilRow = {
  id: string;
  camion_id: string;
  producto_id: string;
  cantidad_cargada: number;
  cantidad_entregada: number;
  productos: {
    codigo_producto: string | null;
    nombre: string;
    precio_lista1: number | null;
  } | null;
};

function joinOne<T>(value: T | T[] | null | undefined): T | null {
  if (value == null) return null;
  return Array.isArray(value) ? (value[0] ?? null) : value;
}

export async function obtenerResumenAutoventas(
  camionId: string,
  fecha?: string,
): Promise<
  { ok: true; resumen: ResumenAutoVentaData } | { ok: false; error: string }
> {
  const { data, error } = await supabase.rpc(
    "retorna_resumen_autoventas_jornada",
    {
      p_camion_id: camionId,
      p_fecha: fecha || null,
    },
  );
  if (error) return { ok: false, error: error.message };
  if (!isRpcSuccess(data)) {
    return {
      ok: false,
      error: rpcFailMessage(data, "No se pudo obtener el resumen."),
    };
  }
  const raw = unwrapRpcData<Record<string, unknown>>(data);
  if (!raw) return { ok: false, error: "Resumen vacío." };

  const inv = Array.isArray(raw.inventario_movil) ? raw.inventario_movil : [];
  const ventas = Array.isArray(raw.ventas) ? raw.ventas : [];

  return {
    ok: true,
    resumen: {
      camion_id: String(raw.camion_id ?? camionId),
      fecha: String(raw.fecha ?? ""),
      total_ordenes_autoventa: Number(raw.total_ordenes_autoventa) || 0,
      total_facturado_usd: Number(raw.total_facturado_usd) || 0,
      total_facturado_bs: Number(raw.total_facturado_bs) || 0,
      inventario_movil: inv.map((i) => {
        const row = i as Record<string, unknown>;
        return {
          producto_id: String(row.producto_id ?? ""),
          codigo: String(row.codigo ?? ""),
          nombre: String(row.nombre ?? ""),
          cantidad_cargada: Number(row.cantidad_cargada) || 0,
          cantidad_entregada: Number(row.cantidad_entregada) || 0,
          cantidad_disponible: Number(row.cantidad_disponible) || 0,
        };
      }),
      ventas: ventas.map((v) => {
        const row = v as Record<string, unknown>;
        return {
          orden_id: String(row.orden_id ?? ""),
          correlativo: Number(row.correlativo) || 0,
          factura_origen_numero: String(row.factura_origen_numero ?? ""),
          cliente_nombre: String(row.cliente_nombre ?? ""),
          estado: String(row.estado ?? ""),
          total_recaudar_usd: Number(row.total_recaudar_usd) || 0,
          total_recaudar_bs: Number(row.total_recaudar_bs) || 0,
          created_at: String(row.created_at ?? ""),
        };
      }),
    },
  };
}

export async function listarInventarioMovil(
  camionId?: string,
): Promise<
  { ok: true; rows: InventarioMovilRow[] } | { ok: false; error: string }
> {
  let q = supabase
    .from("inventario_movil")
    .select(
      "id, camion_id, producto_id, cantidad_cargada, cantidad_entregada, productos(codigo_producto, nombre, precio_lista1)",
    )
    .order("producto_id");

  if (camionId) q = q.eq("camion_id", camionId);

  const { data, error } = await q;
  if (error) return { ok: false, error: error.message };

  const rows: InventarioMovilRow[] = (data ?? []).map((r) => ({
    id: r.id,
    camion_id: r.camion_id,
    producto_id: r.producto_id,
    cantidad_cargada: Number(r.cantidad_cargada) || 0,
    cantidad_entregada: Number(r.cantidad_entregada) || 0,
    productos: joinOne(
      r.productos as
        | InventarioMovilRow["productos"]
        | InventarioMovilRow["productos"][],
    ),
  }));

  return { ok: true, rows };
}

export async function registrarVentaEnRuta(input: {
  vendedorId: string;
  clienteId: string;
  camionId: string;
  productos: Array<{
    producto_id: string;
    cantidad: number;
    precio_unitario: number;
  }>;
  contenedores?: Array<{
    contenedor_id: string;
    cantidad_entregada?: number;
    cantidad_retirada?: number;
  }>;
  observaciones?: string;
  tasaCambio?: number | null;
}): Promise<
  | { ok: true; ordenId: string; correlativo?: number; total?: number }
  | { ok: false; error: string }
> {
  if (!input.productos.length) {
    return { ok: false, error: "Agrega al menos un producto." };
  }

  const { data, error } = await supabase.rpc(
    "registrar_venta_en_ruta_autoventa",
    {
      p_vendedor_id: input.vendedorId,
      p_cliente_id: input.clienteId,
      p_camion_id: input.camionId,
      p_productos_json: input.productos.map((p) => ({
        producto_id: p.producto_id,
        cantidad: p.cantidad,
        precio_unitario: p.precio_unitario,
        valor_unitario_usd: p.precio_unitario,
      })),
      p_contenedores_json: input.contenedores ?? [],
      p_observaciones: input.observaciones ?? null,
      p_tasa_cambio: input.tasaCambio ?? null,
    },
  );

  if (error) return { ok: false, error: error.message };
  if (!isRpcSuccess(data)) {
    return {
      ok: false,
      error: rpcFailMessage(data, "No se pudo registrar la venta en ruta."),
    };
  }

  const payload = unwrapRpcData<Record<string, unknown>>(data) ?? (data as Record<string, unknown>);
  const ordenId = String(
    payload?.orden_id ??
      (payload && typeof payload === "object" && "data" in payload
        ? (payload as { data?: { orden_id?: string } }).data?.orden_id
        : "") ??
      "",
  );

  if (!ordenId) {
    // Algunas respuestas ponen orden_id en la raíz del envelope
    const env = data as {
      orden_id?: string;
      correlativo?: number;
      total_recaudar_usd?: number;
      data?: {
        orden_id?: string;
        correlativo?: number;
        total_recaudar_usd?: number;
      };
    };
    const id = env.orden_id ?? env.data?.orden_id;
    if (!id) return { ok: false, error: "Venta registrada sin ID de orden." };
    return {
      ok: true,
      ordenId: id,
      correlativo: Number(env.correlativo ?? env.data?.correlativo) || undefined,
      total:
        Number(env.total_recaudar_usd ?? env.data?.total_recaudar_usd) ||
        undefined,
    };
  }

  return {
    ok: true,
    ordenId,
    correlativo: Number((payload as { correlativo?: number })?.correlativo) || undefined,
    total: Number((payload as { total_recaudar_usd?: number })?.total_recaudar_usd) || undefined,
  };
}

export async function cargarInventarioMovil(input: {
  camionId: string;
  productos: Array<{ producto_id: string; cantidad_solicitada: number }>;
}): Promise<{ ok: true; message?: string } | { ok: false; error: string }> {
  if (!input.productos.length) {
    return { ok: false, error: "Indica al menos un producto a cargar." };
  }
  const { data, error } = await supabase.rpc(
    "solicita_cargar_inventario_movil_desde_almacen",
    {
      p_camion_id: input.camionId,
      p_resumen_productos: input.productos,
      p_radar_id: null,
    },
  );
  if (error) return { ok: false, error: error.message };
  if (!isRpcSuccess(data)) {
    return {
      ok: false,
      error: rpcFailMessage(data, "No se pudo cargar el inventario móvil."),
    };
  }
  const env = data as { message?: string };
  return { ok: true, message: env.message };
}

export async function reversarInventarioMovil(input: {
  camionId: string;
  productos?: Array<{ producto_id: string; cantidad_solicitada: number }>;
}): Promise<{ ok: true; message?: string } | { ok: false; error: string }> {
  if (!input.camionId?.trim()) {
    return { ok: false, error: "Camión requerido." };
  }
  const { data, error } = await supabase.rpc(
    "solicita_reversar_carga_inventario_movil_a_almacen",
    {
      p_camion_id: input.camionId,
      p_resumen_productos: input.productos?.length ? input.productos : null,
      p_radar_id: null,
    },
  );
  if (error) return { ok: false, error: error.message };
  if (!isRpcSuccess(data)) {
    return {
      ok: false,
      error: rpcFailMessage(data, "No se pudo devolver el inventario al almacén."),
    };
  }
  const env = data as { message?: string };
  return {
    ok: true,
    message:
      env.message ||
      "Inventario móvil devuelto exitosamente al almacén central.",
  };
}
