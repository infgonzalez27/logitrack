"use server";

import { revalidatePath } from "next/cache";
import { getCurrentProfile, getSessionUser } from "@/lib/auth";
import { callDbProcedure, rpcErrorMessage } from "@/lib/actions/db-rpc";
import { getRoleNameFromProfile, type RolNombre } from "@/lib/auth/roles";
import { createClient } from "@/lib/supabase/server";
import type {
  RadarCabecera,
  RadarDetalleReporte,
  RadarListaRangoItem,
  RadarOrden,
  RadarOrdenResumen,
} from "@/types/database";

export type RadarDetalleInput = {
  detalle_id: string;
  cantidad_despachada: number;
  estado_entrega: string;
  motivo_rechazo: string | null;
  contenedores_retirados: number;
  contenedor_id: string | null;
};

const ROLES_CREAR_RADAR: RolNombre[] = ["admin", "gerente", "vendedor"];
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function canCreateRadar(rol: RolNombre | null): boolean {
  return !!rol && ROLES_CREAR_RADAR.includes(rol);
}

/** INTEGRACION-RPC §2.16 — `retorna_radar_despachador` */
export async function retornaRadarDespachadorAction(): Promise<
  { ok: true; ordenes: RadarOrden[] } | { ok: false; error: string }
> {
  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);
  if (rol !== "despachador") {
    return { ok: false, error: "El radar de ruta solo está disponible para despachadores." };
  }

  const response = await callDbProcedure<RadarOrden[]>("retorna_radar_despachador");

  if (!response.success) {
    if (response.error?.code === "SQL_ERROR" && !response.data) {
      return { ok: true, ordenes: [] };
    }
    return {
      ok: false,
      error: rpcErrorMessage(response, "No se pudo cargar el radar."),
    };
  }

  return {
    ok: true,
    ordenes: Array.isArray(response.data) ? response.data : [],
  };
}

export type RadarEntregaLineaInput = {
  detalle_id: string;
  cantidad_asignada: number;
  cantidad_entregada: number;
};

export type RadarRetiroInput = {
  contenedor_id: string;
  cantidad: number;
};

function deriveEstadoEntrega(
  asignada: number,
  entregada: number,
): "entregado" | "entregado_parcial" | "rechazado" {
  if (entregada <= 0) return "rechazado";
  if (entregada >= asignada) return "entregado";
  return "entregado_parcial";
}

function revalidateRadarPaths(ordenId: string) {
  revalidatePath("/radar");
  revalidatePath("/radar/entrega");
  revalidatePath(`/radar/entrega/${ordenId}`);
  revalidatePath("/ordenes");
  revalidatePath(`/ordenes/${ordenId}`);
}

/** INTEGRACION-RPC §2.17 — `registrar_despacho_cliente_radar` (bajo nivel). */
export async function registrarDespachoClienteRadarAction(input: {
  orden_id: string;
  detalles: RadarDetalleInput[];
}): Promise<{ ok: true; estado?: string } | { ok: false; error: string; code?: string }> {
  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);
  if (rol !== "despachador") {
    return { ok: false, error: "Solo el despachador puede registrar en radar." };
  }

  const ordenId = input.orden_id?.trim();
  if (!ordenId) {
    return { ok: false, error: "La orden es requerida.", code: "PARAMETRO_INVALIDO" };
  }
  if (!input.detalles?.length) {
    return {
      ok: false,
      error: "Debes registrar al menos una línea.",
      code: "PARAMETRO_INVALIDO",
    };
  }

  for (const linea of input.detalles) {
    if (!linea.detalle_id) {
      return { ok: false, error: "Falta el detalle de producto.", code: "PARAMETRO_INVALIDO" };
    }
    if (!Number.isFinite(linea.cantidad_despachada) || linea.cantidad_despachada < 0) {
      return {
        ok: false,
        error: "La cantidad despachada no puede ser negativa.",
        code: "PARAMETRO_INVALIDO",
      };
    }
    if (
      (linea.estado_entrega === "entregado_parcial" || linea.estado_entrega === "rechazado") &&
      !linea.motivo_rechazo?.trim()
    ) {
      return {
        ok: false,
        error: "Indica el motivo si la entrega es parcial o rechazada.",
        code: "PARAMETRO_INVALIDO",
      };
    }
  }

  const response = await callDbProcedure<{
    orden_id: string;
    nuevo_estado_orden?: string;
    nuevo_estado?: string;
    total_despachado?: number;
  }>("registrar_despacho_cliente_radar", {
    p_orden_id: ordenId,
    p_detalles_json: input.detalles.map((linea) => ({
      detalle_id: linea.detalle_id,
      cantidad_despachada: linea.cantidad_despachada,
      estado_entrega: linea.estado_entrega,
      motivo_rechazo: linea.motivo_rechazo,
      contenedores_retirados: linea.contenedores_retirados,
      contenedor_id: linea.contenedor_id,
    })),
  });

  if (!response.success) {
    return {
      ok: false,
      error: rpcErrorMessage(response, "No se pudo registrar el despacho."),
      code: response.error?.code,
    };
  }

  revalidateRadarPaths(ordenId);
  const estado =
    response.data?.nuevo_estado ?? response.data?.nuevo_estado_orden;
  return { ok: true, estado };
}

/**
 * Cierre de parada (Pantalla 2 del Radar).
 * Productos → `registrar_despacho_cliente_radar` (estado derivado de cantidades).
 * Retiros → se adjuntan a líneas cuando cabe; el excedente usa
 * `registrar_movimiento_contenedores` (§2.7) hasta que DB soporte `retiros[]` a nivel orden.
 * motivo_rechazo automático si parcial/rechazo (no hay columna de observaciones).
 */
export async function finalizarEntregaRadarAction(input: {
  orden_id: string;
  cliente_id: string;
  entregas: RadarEntregaLineaInput[];
  retiros: RadarRetiroInput[];
}): Promise<
  | { ok: true; estado?: string; deVuelta?: boolean }
  | { ok: false; error: string; code?: string }
> {
  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);
  if (rol !== "despachador") {
    return { ok: false, error: "Solo el despachador puede finalizar la entrega." };
  }

  const ordenId = input.orden_id?.trim();
  const clienteId = input.cliente_id?.trim();

  if (!ordenId || !UUID_RE.test(ordenId)) {
    return { ok: false, error: "Orden inválida.", code: "PARAMETRO_INVALIDO" };
  }
  if (!clienteId || !UUID_RE.test(clienteId)) {
    return { ok: false, error: "Cliente inválido.", code: "PARAMETRO_INVALIDO" };
  }
  if (!input.entregas?.length) {
    return {
      ok: false,
      error: "No hay productos pendientes para registrar.",
      code: "PARAMETRO_INVALIDO",
    };
  }

  const retirosValidos: RadarRetiroInput[] = [];
  for (const r of input.retiros ?? []) {
    const contenedorId = r.contenedor_id?.trim();
    const cantidad = Number(r.cantidad);
    if (!contenedorId) continue;
    if (!UUID_RE.test(contenedorId)) {
      return {
        ok: false,
        error: "Tipo de contenedor inválido en retiros.",
        code: "PARAMETRO_INVALIDO",
      };
    }
    if (!Number.isFinite(cantidad) || cantidad < 0) {
      return {
        ok: false,
        error: "Cantidad de retiro inválida.",
        code: "PARAMETRO_INVALIDO",
      };
    }
    if (cantidad === 0) continue;
    retirosValidos.push({ contenedor_id: contenedorId, cantidad });
  }

  for (const linea of input.entregas) {
    const asignada = Number(linea.cantidad_asignada);
    const entregada = Number(linea.cantidad_entregada);
    if (!linea.detalle_id || !UUID_RE.test(linea.detalle_id)) {
      return { ok: false, error: "Detalle de producto inválido.", code: "PARAMETRO_INVALIDO" };
    }
    if (!Number.isFinite(entregada) || entregada < 0) {
      return {
        ok: false,
        error: "La cantidad entregada no puede ser negativa.",
        code: "PARAMETRO_INVALIDO",
      };
    }
    if (entregada > asignada) {
      return {
        ok: false,
        error: "La cantidad entregada no puede superar la asignada.",
        code: "PARAMETRO_INVALIDO",
      };
    }
  }

  // Regla DB master: entrega completa o de vuelta (sin parcial por ítem).
  const forzarDeVuelta = input.entregas.some((linea) => {
    const asignada = Number(linea.cantidad_asignada);
    const entregada = Number(linea.cantidad_entregada);
    return !Number.isFinite(entregada) || entregada < asignada;
  });

  const detalles: RadarDetalleInput[] = input.entregas.map((linea, idx) => {
    const asignada = Number(linea.cantidad_asignada);
    let entregada = Math.min(Number(linea.cantidad_entregada), asignada);
    if (forzarDeVuelta) entregada = 0;
    const estado = forzarDeVuelta
      ? "rechazado"
      : deriveEstadoEntrega(asignada, entregada);
    const retiro = retirosValidos[idx];
    const motivo =
      estado === "rechazado"
        ? "Devolución"
        : estado === "entregado_parcial"
          ? "Entrega parcial"
          : null;
    return {
      detalle_id: linea.detalle_id,
      cantidad_despachada: estado === "rechazado" ? 0 : entregada,
      estado_entrega: estado,
      motivo_rechazo: motivo,
      contenedores_retirados: retiro?.cantidad ?? 0,
      contenedor_id: retiro?.contenedor_id ?? null,
    };
  });

  const registered = await registrarDespachoClienteRadarAction({
    orden_id: ordenId,
    detalles,
  });
  if (!registered.ok) return registered;

  const retirosExtra = retirosValidos.slice(input.entregas.length);
  if (retirosExtra.length) {
    const user = await getSessionUser();
    if (!user) {
      return {
        ok: false,
        error:
          "La entrega se registró, pero no se pudieron guardar retiros extras (sesión).",
        code: "UNAUTHORIZED",
      };
    }
    for (const retiro of retirosExtra) {
      const mov = await callDbProcedure<{ movimiento_id: string }>(
        "registrar_movimiento_contenedores",
        {
          p_cliente_id: clienteId,
          p_orden_id: ordenId,
          p_contenedor_id: retiro.contenedor_id,
          p_cantidad_entregada: 0,
          p_cantidad_retirada: retiro.cantidad,
          p_creado_por: user.id,
        },
      );
      if (!mov.success) {
        return {
          ok: false,
          error: rpcErrorMessage(
            mov,
            "La entrega se registró, pero falló un retiro de contenedor extra. Revisa movimientos.",
          ),
          code: mov.error?.code,
        };
      }
    }
  }

  revalidateRadarPaths(ordenId);
  // El SP decide el estado de la orden según cantidades (0 → `devuelta`).
  const deVuelta = registered.estado === "devuelta" || forzarDeVuelta;
  return {
    ok: true,
    estado: registered.estado,
    deVuelta,
  };
}

/**
 * Incidencia de parada: no se pudo completar la visita.
 * Interim: marca todas las líneas pendientes como `rechazado` con el motivo.
 * Pedido a DB: incidencia de parada dedicada (sin anular contablemente).
 */
export async function reportarIncidenciaRadarAction(input: {
  orden_id: string;
  detalle_ids: string[];
  motivo: string;
}): Promise<{ ok: true; estado?: string } | { ok: false; error: string; code?: string }> {
  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);
  if (rol !== "despachador") {
    return { ok: false, error: "Solo el despachador puede reportar incidencia." };
  }

  const ordenId = input.orden_id?.trim();
  const motivo = input.motivo?.trim();
  if (!ordenId || !UUID_RE.test(ordenId)) {
    return { ok: false, error: "Orden inválida.", code: "PARAMETRO_INVALIDO" };
  }
  if (!motivo) {
    return {
      ok: false,
      error: "Indica el motivo de la incidencia.",
      code: "PARAMETRO_INVALIDO",
    };
  }
  if (!input.detalle_ids?.length) {
    return {
      ok: false,
      error: "No hay líneas pendientes para marcar.",
      code: "PARAMETRO_INVALIDO",
    };
  }

  const detalles: RadarDetalleInput[] = input.detalle_ids.map((detalle_id) => ({
    detalle_id,
    cantidad_despachada: 0,
    estado_entrega: "rechazado",
    motivo_rechazo: `Incidencia: ${motivo}`,
    contenedores_retirados: 0,
    contenedor_id: null,
  }));

  return registrarDespachoClienteRadarAction({ orden_id: ordenId, detalles });
}

/**
 * INTEGRACION-RPC §2.33 / §2.38 — `solicita_aprobar_radar`.
 * Gerencia/admin cierra el radar: acredita vacíos entregados/retirados,
 * restituye inventario no despachado y anula órdenes en estado `devuelta`.
 */
export async function solicitaAprobarRadarAction(
  radarId: string,
): Promise<
  | {
      ok: true;
      message?: string;
      data?: {
        radar_id?: string;
        status_radar?: boolean;
        contenedores_entregados_procesados?: number;
        contenedores_retirados_procesados?: number;
        clientes_deshabilitados_credito?: number;
        /** @deprecated usar contenedores_retirados_procesados */
        contenedores_procesados?: number;
        ordenes_anuladas?: number;
        inventario_reintegrado?: unknown[];
      };
    }
  | { ok: false; error: string; code?: string }
> {
  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);
  if (rol !== "gerente" && rol !== "admin") {
    return {
      ok: false,
      error: "Solo gerencia o admin pueden aprobar el radar.",
      code: "ACCESO_DENEGADO",
    };
  }

  const id = radarId?.trim();
  if (!id || !UUID_RE.test(id)) {
    return {
      ok: false,
      error: "Identificador de radar inválido.",
      code: "PARAMETRO_INVALIDO",
    };
  }

  const response = await callDbProcedure<{
    radar_id?: string;
    status_radar?: boolean;
    contenedores_entregados_procesados?: number;
    contenedores_retirados_procesados?: number;
    clientes_deshabilitados_credito?: number;
    contenedores_procesados?: number;
    ordenes_anuladas?: number;
    inventario_reintegrado?: unknown[];
  }>("solicita_aprobar_radar", { p_radar_id: id });

  if (!response.success) {
    return {
      ok: false,
      error: rpcErrorMessage(response, "No se pudo aprobar el radar."),
      code: response.error?.code,
    };
  }

  revalidatePath("/radar");
  revalidatePath(`/radar/${id}`);
  revalidatePath("/ordenes");
  revalidatePath("/inventario-almacen");
  revalidatePath("/inventario-movil");

  return {
    ok: true,
    message: response.message,
    data: response.data ?? undefined,
  };
}

/** INTEGRACION-RPC §2.19 — `crear_o_obtener_radar` */
export async function crearOObtenerRadarAction(input: {
  despachador_id: string;
  fecha_despacho: string;
}): Promise<
  { ok: true; radar: RadarCabecera } | { ok: false; error: string; code?: string }
> {
  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);
  if (!canCreateRadar(rol)) {
    return {
      ok: false,
      error: "Solo gerente, vendedor o admin pueden crear el radar.",
      code: "FORBIDDEN",
    };
  }

  const despachadorId = input.despachador_id?.trim();
  const fecha = input.fecha_despacho?.trim().slice(0, 10);

  if (!despachadorId || !UUID_RE.test(despachadorId)) {
    return {
      ok: false,
      error: "Selecciona un despachador válido.",
      code: "PARAMETRO_INVALIDO",
    };
  }
  if (!fecha || !DATE_RE.test(fecha)) {
    return {
      ok: false,
      error: "Indica la fecha de entrega (AAAA-MM-DD).",
      code: "PARAMETRO_INVALIDO",
    };
  }

  const response = await callDbProcedure<RadarCabecera>("crear_o_obtener_radar", {
    p_despachador_id: despachadorId,
    p_fecha_despacho: fecha,
  });

  if (!response.success || !response.data) {
    return {
      ok: false,
      error: rpcErrorMessage(response, "No se pudo crear u obtener el radar."),
      code: response.error?.code,
    };
  }

  revalidatePath("/radar");
  return { ok: true, radar: response.data };
}

/** INTEGRACION-RPC §2.20 — `retorna_radar_detalle_reporte` */
export async function retornaRadarDetalleReporteAction(
  radarId: string,
): Promise<
  | { ok: true; reporte: RadarDetalleReporte }
  | { ok: false; error: string; code?: string }
> {
  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);
  if (
    rol !== "despachador" &&
    rol !== "gerente" &&
    rol !== "vendedor" &&
    rol !== "admin"
  ) {
    return { ok: false, error: "No tienes acceso al reporte de radar." };
  }

  const id = radarId?.trim();
  if (!id || !UUID_RE.test(id)) {
    return {
      ok: false,
      error: "Identificador de radar inválido.",
      code: "PARAMETRO_INVALIDO",
    };
  }

  const response = await callDbProcedure<RadarDetalleReporte>(
    "retorna_radar_detalle_reporte",
    { p_radar_id: id },
  );

  if (!response.success || !response.data) {
    return {
      ok: false,
      error: rpcErrorMessage(response, "No se pudo cargar el reporte del radar."),
      code: response.error?.code,
    };
  }

  return { ok: true, reporte: response.data };
}

function mapRadarListaRango(raw: unknown): RadarListaRangoItem | null {
  if (!raw || typeof raw !== "object") return null;
  const r = raw as Record<string, unknown>;
  const id =
    typeof r.id_radar === "string"
      ? r.id_radar
      : typeof r.id === "string"
        ? r.id
        : null;
  if (!id) return null;
  const fecha =
    typeof r.fecha_despacho === "string"
      ? r.fecha_despacho.slice(0, 10)
      : "";
  return {
    fecha_despacho: fecha,
    id_radar: id,
    correlativo: Number(r.correlativo ?? 0),
    total_paradas: Number(r.total_paradas ?? 0),
    items: Number(r.items ?? 0),
    sku: Number(r.sku ?? 0),
    status_radar: Boolean(r.status_radar),
  };
}

function mapRadarOrdenResumen(raw: unknown): RadarOrdenResumen | null {
  if (!raw || typeof raw !== "object") return null;
  const r = raw as Record<string, unknown>;
  const id =
    typeof r.id_orden_distribucion === "string"
      ? r.id_orden_distribucion
      : typeof r.orden_id === "string"
        ? r.orden_id
        : null;
  if (!id) return null;
  return {
    id_orden_distribucion: id,
    correlativo: Number(r.correlativo ?? 0),
    ruta: String(r.ruta ?? ""),
    razon_social: String(r.razon_social ?? ""),
    direccion_fiscal:
      typeof r.direccion_fiscal === "string" ? r.direccion_fiscal : null,
    items: Number(r.items ?? 0),
    sku: Number(r.sku ?? 0),
    contenedores_retirados: Number(r.contenedores_retirados ?? 0),
  };
}

/** INTEGRACION-RPC §2.30 — lista de radares por rango de fechas. */
export async function retornaListaRadarsSegunRangoFechasAction(input?: {
  fechaInicial?: string | null;
  fechaLimite?: string | null;
  despachadorId?: string | null;
}): Promise<
  | { ok: true; items: RadarListaRangoItem[] }
  | { ok: false; error: string; code?: string }
> {
  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);
  if (
    rol !== "despachador" &&
    rol !== "gerente" &&
    rol !== "vendedor" &&
    rol !== "admin"
  ) {
    return { ok: false, error: "No tienes acceso a la lista de radares." };
  }

  const fi = input?.fechaInicial?.trim().slice(0, 10);
  const fl = input?.fechaLimite?.trim().slice(0, 10);
  if (!fi || !fl || !DATE_RE.test(fi) || !DATE_RE.test(fl)) {
    return {
      ok: false,
      error: "Indica un rango de fechas válido (YYYY-MM-DD).",
      code: "PARAMETRO_INVALIDO",
    };
  }

  const despachadorFiltro =
    rol === "despachador" && profile?.id
      ? profile.id
      : input?.despachadorId?.trim() || null;

  // Staff ve todos los radares del rango (el RPC filtra siempre por un despachador).
  if (rol !== "despachador") {
    const { listarRadaresPorRangoLocal } = await import("@/lib/data/radares");
    const items = await listarRadaresPorRangoLocal({
      fechaInicial: fi,
      fechaLimite: fl,
      despachadorId: despachadorFiltro,
    });
    return { ok: true, items };
  }

  const params: Record<string, unknown> = {
    p_fecha_inicial: fi,
    p_fecha_limite: fl,
  };
  if (despachadorFiltro) params.p_despachador_id = despachadorFiltro;

  const response = await callDbProcedure<unknown>(
    "retorna_lista_radars_segun_rango_fechas",
    params,
  );

  if (!response.success) {
    const { listarRadaresPorRangoLocal } = await import("@/lib/data/radares");
    const items = await listarRadaresPorRangoLocal({
      fechaInicial: fi,
      fechaLimite: fl,
      despachadorId: despachadorFiltro,
    });
    if (items.length || response.error?.code === "NETWORK_OR_API_ERROR") {
      return { ok: true, items };
    }
    return {
      ok: false,
      error: rpcErrorMessage(response, "No se pudo cargar la lista de radares."),
      code: response.error?.code,
    };
  }

  const rows = Array.isArray(response.data)
    ? response.data
    : response.data
      ? [response.data]
      : [];
  const items = rows
    .map(mapRadarListaRango)
    .filter((x): x is RadarListaRangoItem => x != null);

  return { ok: true, items };
}

/** INTEGRACION-RPC §2.31 — órdenes/paradas de un radar. */
export async function retornaOrdenesDistribucionSegunIdRadarAction(
  radarId: string,
): Promise<
  | { ok: true; ordenes: RadarOrdenResumen[] }
  | { ok: false; error: string; code?: string }
> {
  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);
  if (
    rol !== "despachador" &&
    rol !== "gerente" &&
    rol !== "vendedor" &&
    rol !== "admin"
  ) {
    return { ok: false, error: "No tienes acceso al detalle del radar." };
  }

  const id = radarId?.trim();
  if (!id || !UUID_RE.test(id)) {
    return {
      ok: false,
      error: "Identificador de radar inválido.",
      code: "PARAMETRO_INVALIDO",
    };
  }

  const response = await callDbProcedure<unknown>(
    "retorna_ordenes_distribucion_segun_idradar",
    { p_radar_id: id },
  );

  if (!response.success) {
    // Fallback local si el RPC aún no está desplegado.
    const supabase = await createClient();
    const { data: ordenes, error } = await supabase
      .from("ordenes_distribucion")
      .select(
        `
        id, correlativo,
        clientes(razon_social, direccion_fiscal),
        detalle_distribucion(producto_id, cantidad_despachada, cantidad_solicitada, contenedores_retirados)
      `,
      )
      .eq("radar_id", id)
      .order("correlativo", { ascending: true });

    if (error) {
      return {
        ok: false,
        error: rpcErrorMessage(response, "No se pudo cargar las órdenes del radar."),
        code: response.error?.code,
      };
    }

    type Det = {
      producto_id: string | null;
      cantidad_despachada: number | null;
      cantidad_solicitada: number | null;
      contenedores_retirados: number | null;
    };
    type Cli = {
      razon_social: string;
      direccion_fiscal: string | null;
    };
    type Row = {
      id: string;
      correlativo: number;
      clientes: Cli | Cli[] | null;
      detalle_distribucion: Det[] | Det | null;
    };

    const mapped: RadarOrdenResumen[] = ((ordenes ?? []) as unknown as Row[]).map(
      (o) => {
        const c = Array.isArray(o.clientes) ? o.clientes[0] : o.clientes;
        const dets = Array.isArray(o.detalle_distribucion)
          ? o.detalle_distribucion
          : o.detalle_distribucion
            ? [o.detalle_distribucion]
            : [];
        const skus = new Set(
          dets.map((d) => d.producto_id).filter(Boolean) as string[],
        );
        return {
          id_orden_distribucion: o.id,
          correlativo: Number(o.correlativo ?? 0),
          ruta: "Sin Ruta",
          razon_social: c?.razon_social ?? "—",
          direccion_fiscal: c?.direccion_fiscal ?? null,
          items: dets.reduce(
            (s, d) =>
              s + Number(d.cantidad_despachada ?? d.cantidad_solicitada ?? 0),
            0,
          ),
          sku: skus.size,
          contenedores_retirados: dets.reduce(
            (s, d) => s + Number(d.contenedores_retirados ?? 0),
            0,
          ),
        };
      },
    );
    return { ok: true, ordenes: mapped };
  }

  const rows = Array.isArray(response.data)
    ? response.data
    : response.data
      ? [response.data]
      : [];
  const ordenes = rows
    .map(mapRadarOrdenResumen)
    .filter((x): x is RadarOrdenResumen => x != null);

  return { ok: true, ordenes };
}
