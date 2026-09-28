import { supabase } from "./supabase";
import { isRpcSuccess, rpcFailMessage, unwrapRpcData } from "./rpc";

export type RadarCliente = {
  id: string;
  razon_social: string;
  rif_nit: string;
  direccion_fiscal: string | null;
  telefono: string | null;
  movil1: string | null;
  nombre_ruta: string | null;
};

export type RadarDetalle = {
  detalle_id: string;
  producto_id: string;
  codigo_producto: string | null;
  nombre_producto: string;
  cantidad_solicitada: number;
  cantidad_despachada: number;
  valor_unitario_usd: number | null;
  subtotal_recaudar_usd: number | null;
  precio_lista_usd: number | null;
  porcentaje_descuento: number;
  monto_descuento_usd: number;
  estado_entrega: string;
  motivo_rechazo: string | null;
  contenedores_retirados: number;
  contenedor_id: string | null;
};

export type RadarSaldoContenedor = {
  contenedor_id: string;
  nombre_contenedor: string;
  saldo_pendiente: number;
};

export type RadarOrden = {
  orden_id: string;
  correlativo: number;
  estado: string;
  fecha_despacho: string | null;
  tasa_cambio: number | null;
  total_recaudar_bs: number | null;
  total_recaudar_usd: number | null;
  despacho_permitido?: boolean;
  motivo_bloqueo?: string | null;
  cliente: RadarCliente;
  detalles: RadarDetalle[];
  saldo_contenedores: RadarSaldoContenedor[];
};

export type RadarListaItem = {
  fecha_despacho: string;
  id_radar: string;
  correlativo: number;
  total_paradas: number;
  items: number;
  sku: number;
  status_radar: boolean;
};

export type RadarParadaResumen = {
  id_orden_distribucion: string;
  correlativo: number;
  ruta: string;
  razon_social: string;
  direccion_fiscal: string | null;
  items: number;
  sku: number;
  contenedores_retirados: number;
};

export type ContenedorOption = {
  id: string;
  codigo: string | null;
  nombre: string;
};

type DetalleInput = {
  detalle_id: string;
  cantidad_despachada: number;
  estado_entrega: string;
  motivo_rechazo: string | null;
  contenedores_retirados: number;
  contenedor_id: string | null;
};

function normalizeOrden(raw: Record<string, unknown>): RadarOrden | null {
  const ordenId = String(raw.orden_id ?? raw.id ?? "");
  if (!ordenId) return null;
  const clienteRaw = (raw.cliente ?? {}) as Record<string, unknown>;
  const detallesRaw = Array.isArray(raw.detalles) ? raw.detalles : [];
  const saldosRaw = Array.isArray(raw.saldo_contenedores)
    ? raw.saldo_contenedores
    : [];

  return {
    orden_id: ordenId,
    correlativo: Number(raw.correlativo) || 0,
    estado: String(raw.estado ?? ""),
    fecha_despacho: (raw.fecha_despacho as string) ?? null,
    tasa_cambio:
      raw.tasa_cambio != null ? Number(raw.tasa_cambio) : null,
    total_recaudar_bs:
      raw.total_recaudar_bs != null ? Number(raw.total_recaudar_bs) : null,
    total_recaudar_usd:
      raw.total_recaudar_usd != null ? Number(raw.total_recaudar_usd) : null,
    despacho_permitido:
      raw.despacho_permitido != null
        ? Boolean(raw.despacho_permitido)
        : clienteRaw.despacho_permitido != null
          ? Boolean(clienteRaw.despacho_permitido)
          : true,
    motivo_bloqueo:
      (raw.motivo_bloqueo as string) ??
      (clienteRaw.motivo_bloqueo as string) ??
      null,
    cliente: {
      id: String(clienteRaw.id ?? ""),
      razon_social: String(clienteRaw.razon_social ?? "Cliente"),
      rif_nit: String(clienteRaw.rif_nit ?? ""),
      direccion_fiscal: (clienteRaw.direccion_fiscal as string) ?? null,
      telefono: (clienteRaw.telefono as string) ?? null,
      movil1: (clienteRaw.movil1 as string) ?? null,
      nombre_ruta: (clienteRaw.nombre_ruta as string) ?? null,
    },
    detalles: detallesRaw.map((d) => {
      const row = d as Record<string, unknown>;
      return {
        detalle_id: String(row.detalle_id ?? row.id ?? ""),
        producto_id: String(row.producto_id ?? ""),
        codigo_producto: (row.codigo_producto as string) ?? null,
        nombre_producto: String(row.nombre_producto ?? "Producto"),
        cantidad_solicitada: Number(row.cantidad_solicitada) || 0,
        cantidad_despachada: Number(row.cantidad_despachada) || 0,
        valor_unitario_usd:
          row.valor_unitario_usd != null ? Number(row.valor_unitario_usd) : null,
        subtotal_recaudar_usd:
          row.subtotal_recaudar_usd != null
            ? Number(row.subtotal_recaudar_usd)
            : null,
        precio_lista_usd:
          row.precio_lista_usd != null ? Number(row.precio_lista_usd) : null,
        porcentaje_descuento: Number(row.porcentaje_descuento ?? 0),
        monto_descuento_usd: Number(row.monto_descuento_usd ?? 0),
        estado_entrega: String(row.estado_entrega ?? "pendiente"),
        motivo_rechazo: (row.motivo_rechazo as string) ?? null,
        contenedores_retirados: Number(row.contenedores_retirados) || 0,
        contenedor_id: (row.contenedor_id as string) ?? null,
      };
    }),
    saldo_contenedores: saldosRaw.map((s) => {
      const row = s as Record<string, unknown>;
      return {
        contenedor_id: String(row.contenedor_id ?? ""),
        nombre_contenedor: String(row.nombre_contenedor ?? "Contenedor"),
        saldo_pendiente: Number(row.saldo_pendiente) || 0,
      };
    }),
  };
}

export async function retornaRadarDespachador(): Promise<
  { ok: true; ordenes: RadarOrden[] } | { ok: false; error: string }
> {
  const { data, error } = await supabase.rpc("retorna_radar_despachador");
  if (error) return { ok: false, error: error.message };
  if (!isRpcSuccess(data)) {
    return { ok: false, error: rpcFailMessage(data, "No se pudo cargar el radar.") };
  }
  const rows = unwrapRpcData<Record<string, unknown>[]>(data) ?? [];
  const ordenes = (Array.isArray(rows) ? rows : [])
    .map((r) => normalizeOrden(r))
    .filter((o): o is RadarOrden => o != null);
  return { ok: true, ordenes };
}

export async function listarRadarsHoy(): Promise<
  { ok: true; radars: RadarListaItem[] } | { ok: false; error: string }
> {
  const hoy = new Date();
  const y = hoy.getFullYear();
  const m = String(hoy.getMonth() + 1).padStart(2, "0");
  const d = String(hoy.getDate()).padStart(2, "0");
  const fecha = `${y}-${m}-${d}`;

  const { data, error } = await supabase.rpc(
    "retorna_lista_radars_segun_rango_fechas",
    { p_fecha_inicial: fecha, p_fecha_limite: fecha },
  );
  if (error) return { ok: false, error: error.message };
  if (!isRpcSuccess(data)) {
    return {
      ok: false,
      error: rpcFailMessage(data, "No se pudieron listar radares."),
    };
  }
  const rows = unwrapRpcData<Record<string, unknown>[]>(data) ?? [];
  const radars: RadarListaItem[] = (Array.isArray(rows) ? rows : []).map(
    (r) => ({
      fecha_despacho: String(r.fecha_despacho ?? fecha),
      id_radar: String(r.id_radar ?? r.id ?? ""),
      correlativo: Number(r.correlativo) || 0,
      total_paradas: Number(r.total_paradas) || 0,
      items: Number(r.items) || 0,
      sku: Number(r.sku) || 0,
      status_radar: Boolean(r.status_radar),
    }),
  );
  return { ok: true, radars: radars.filter((r) => r.id_radar) };
}

export async function listarParadasRadar(
  radarId: string,
): Promise<
  { ok: true; paradas: RadarParadaResumen[] } | { ok: false; error: string }
> {
  const { data, error } = await supabase.rpc(
    "retorna_ordenes_distribucion_segun_idradar",
    { p_radar_id: radarId },
  );
  if (error) return { ok: false, error: error.message };
  if (!isRpcSuccess(data)) {
    return {
      ok: false,
      error: rpcFailMessage(data, "No se pudieron cargar las paradas."),
    };
  }
  const rows = unwrapRpcData<Record<string, unknown>[]>(data) ?? [];
  const paradas: RadarParadaResumen[] = (Array.isArray(rows) ? rows : []).map(
    (r) => ({
      id_orden_distribucion: String(
        r.id_orden_distribucion ?? r.orden_id ?? r.id ?? "",
      ),
      correlativo: Number(r.correlativo) || 0,
      ruta: String(r.ruta ?? ""),
      razon_social: String(r.razon_social ?? "Cliente"),
      direccion_fiscal: (r.direccion_fiscal as string) ?? null,
      items: Number(r.items) || 0,
      sku: Number(r.sku) || 0,
      contenedores_retirados: Number(r.contenedores_retirados) || 0,
    }),
  );
  return {
    ok: true,
    paradas: paradas.filter((p) => p.id_orden_distribucion),
  };
}

export async function getOrdenRadarFromList(
  ordenId: string,
): Promise<{ ok: true; orden: RadarOrden } | { ok: false; error: string }> {
  const list = await retornaRadarDespachador();
  if (!list.ok) return list;
  const orden = list.ordenes.find((o) => o.orden_id === ordenId);
  if (!orden) return { ok: false, error: "Parada no encontrada en tu radar." };
  return { ok: true, orden };
}

export async function listarContenedores(): Promise<
  { ok: true; contenedores: ContenedorOption[] } | { ok: false; error: string }
> {
  const { data, error } = await supabase.rpc("retorna_lista_contenedores");
  if (error) {
    const fallback = await supabase
      .from("contenedores")
      .select("id, codigo, nombre")
      .order("nombre");
    if (fallback.error) return { ok: false, error: fallback.error.message };
    return {
      ok: true,
      contenedores: (fallback.data ?? []).map((c) => ({
        id: c.id,
        codigo: c.codigo,
        nombre: c.nombre,
      })),
    };
  }
  const rows = unwrapRpcData<Record<string, unknown>[]>(data) ?? [];
  return {
    ok: true,
    contenedores: (Array.isArray(rows) ? rows : []).map((c) => ({
      id: String(c.id ?? ""),
      codigo: (c.codigo as string) ?? null,
      nombre: String(c.nombre ?? ""),
    })).filter((c) => c.id),
  };
}

async function registrarDespacho(
  ordenId: string,
  detalles: DetalleInput[],
): Promise<{ ok: true; estado?: string } | { ok: false; error: string }> {
  const { data, error } = await supabase.rpc("registrar_despacho_cliente_radar", {
    p_orden_id: ordenId,
    p_detalles_json: detalles,
  });
  if (error) return { ok: false, error: error.message };
  if (!isRpcSuccess(data)) {
    return {
      ok: false,
      error: rpcFailMessage(data, "No se pudo registrar el despacho."),
    };
  }
  const payload = unwrapRpcData<Record<string, unknown>>(data);
  const estado =
    payload &&
    String(payload.nuevo_estado ?? payload.nuevo_estado_orden ?? "");
  return { ok: true, estado: estado || undefined };
}

async function registrarRetiroExtra(input: {
  clienteId: string;
  ordenId: string;
  contenedorId: string;
  cantidad: number;
  creadoPor: string;
}): Promise<{ ok: true } | { ok: false; error: string }> {
  const { data, error } = await supabase.rpc("registrar_movimiento_contenedores", {
    p_cliente_id: input.clienteId,
    p_orden_id: input.ordenId,
    p_contenedor_id: input.contenedorId,
    p_cantidad_entregada: 0,
    p_cantidad_retirada: input.cantidad,
    p_creado_por: input.creadoPor,
  });
  if (error) return { ok: false, error: error.message };
  if (!isRpcSuccess(data)) {
    return {
      ok: false,
      error: rpcFailMessage(data, "No se pudo registrar el retiro de vacíos."),
    };
  }
  return { ok: true };
}

/**
 * Cierre de parada: all-or-nothing (si alguna línea queda corta → toda la
 * parada a devolución), igual que la web.
 */
export async function finalizarEntregaRadar(input: {
  ordenId: string;
  clienteId: string;
  userId: string;
  entregas: Array<{
    detalle_id: string;
    cantidad_asignada: number;
    cantidad_entregada: number;
  }>;
  retiros: Array<{ contenedor_id: string; cantidad: number }>;
}): Promise<{ ok: true; estado?: string; deVuelta?: boolean } | { ok: false; error: string }> {
  if (!input.entregas.length) {
    return { ok: false, error: "No hay productos pendientes para registrar." };
  }

  const forzarDeVuelta = input.entregas.some((l) => {
    const asignada = Number(l.cantidad_asignada);
    const entregada = Number(l.cantidad_entregada);
    return !Number.isFinite(entregada) || entregada < asignada;
  });

  const detalleIds = input.entregas.map((e) => e.detalle_id);
  const { data: detalleRows, error: detalleError } = await supabase
    .from("detalle_distribucion")
    .select("id, productos(contenedor_id)")
    .eq("orden_id", input.ordenId)
    .in("id", detalleIds);

  if (detalleError) return { ok: false, error: detalleError.message };

  const contenedorProductoPorDetalle = new Map<string, string | null>();
  for (const row of detalleRows ?? []) {
    const prod = Array.isArray(row.productos) ? row.productos[0] : row.productos;
    const raw =
      prod &&
      typeof (prod as { contenedor_id?: string | null }).contenedor_id ===
        "string"
        ? String((prod as { contenedor_id?: string | null }).contenedor_id).trim()
        : "";
    contenedorProductoPorDetalle.set(String(row.id), raw || null);
  }

  const retiroRestante = new Map<string, number>();
  for (const r of input.retiros) {
    if (!r.contenedor_id || !(r.cantidad > 0)) continue;
    retiroRestante.set(
      r.contenedor_id,
      (retiroRestante.get(r.contenedor_id) ?? 0) + r.cantidad,
    );
  }

  const detalles: DetalleInput[] = input.entregas.map((linea) => {
    const asignada = Number(linea.cantidad_asignada);
    let entregada = Math.min(Number(linea.cantidad_entregada), asignada);
    if (forzarDeVuelta) entregada = 0;
    const estado = forzarDeVuelta
      ? "rechazado"
      : entregada <= 0
        ? "rechazado"
        : entregada >= asignada
          ? "entregado"
          : "entregado_parcial";
    const motivo =
      estado === "rechazado"
        ? "Devolución"
        : estado === "entregado_parcial"
          ? "Entrega parcial"
          : null;

    const productoContenedorId =
      contenedorProductoPorDetalle.get(linea.detalle_id) ?? null;
    let contenedoresRetirados = 0;
    if (
      productoContenedorId &&
      (retiroRestante.get(productoContenedorId) ?? 0) > 0
    ) {
      contenedoresRetirados = retiroRestante.get(productoContenedorId) ?? 0;
      retiroRestante.set(productoContenedorId, 0);
    }

    return {
      detalle_id: linea.detalle_id,
      cantidad_despachada: estado === "rechazado" ? 0 : entregada,
      estado_entrega: estado,
      motivo_rechazo: motivo,
      contenedores_retirados: contenedoresRetirados,
      contenedor_id: null,
    };
  });

  const registered = await registrarDespacho(input.ordenId, detalles);
  if (!registered.ok) return registered;

  for (const [contenedorId, cantidad] of retiroRestante.entries()) {
    if (cantidad <= 0) continue;
    const extra = await registrarRetiroExtra({
      clienteId: input.clienteId,
      ordenId: input.ordenId,
      contenedorId,
      cantidad,
      creadoPor: input.userId,
    });
    if (!extra.ok) return extra;
  }

  return { ok: true, estado: registered.estado, deVuelta: forzarDeVuelta };
}

export async function reportarIncidenciaRadar(input: {
  ordenId: string;
  detalleIds: string[];
  motivo: string;
}): Promise<{ ok: true; estado?: string } | { ok: false; error: string }> {
  if (!input.motivo.trim()) {
    return { ok: false, error: "Indica el motivo de la incidencia." };
  }
  if (!input.detalleIds.length) {
    return { ok: false, error: "No hay líneas pendientes para marcar." };
  }
  const detalles: DetalleInput[] = input.detalleIds.map((detalle_id) => ({
    detalle_id,
    cantidad_despachada: 0,
    estado_entrega: "rechazado",
    motivo_rechazo: `Incidencia: ${input.motivo.trim()}`,
    contenedores_retirados: 0,
    contenedor_id: null,
  }));
  return registrarDespacho(input.ordenId, detalles);
}

export async function aprobarRadar(
  radarId: string,
): Promise<{ ok: true; message?: string } | { ok: false; error: string }> {
  const { data, error } = await supabase.rpc("solicita_aprobar_radar", {
    p_radar_id: radarId,
  });
  if (error) return { ok: false, error: error.message };
  if (!isRpcSuccess(data)) {
    return {
      ok: false,
      error: rpcFailMessage(data, "No se pudo aprobar el radar."),
    };
  }
  const env = data as { message?: string };
  return { ok: true, message: env.message };
}

export function paradaEstadoLabel(detalles: RadarDetalle[]): {
  label: string;
  tone: "ok" | "warn" | "danger" | "muted";
} {
  if (!detalles.length) return { label: "Sin líneas", tone: "muted" };
  const pendientes = detalles.filter(
    (d) => (d.estado_entrega ?? "pendiente") === "pendiente",
  );
  if (pendientes.length === 0) {
    const todosRechazados = detalles.every(
      (d) => d.estado_entrega === "rechazado",
    );
    if (todosRechazados) return { label: "Devuelta", tone: "danger" };
    return { label: "Completado", tone: "ok" };
  }
  if (pendientes.length < detalles.length) {
    return { label: "En proceso", tone: "warn" };
  }
  return { label: "Pendiente", tone: "warn" };
}
