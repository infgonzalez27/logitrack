"use server";

import { revalidatePath } from "next/cache";
import { getCurrentProfile } from "@/lib/auth";
import { callDbProcedure, rpcErrorMessage } from "@/lib/actions/db-rpc";
import { getRoleNameFromProfile, type RolNombre } from "@/lib/auth/roles";
import type {
  RadarCabecera,
  RadarDetalleReporte,
  RadarOrden,
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

/** INTEGRACION-RPC §2.17 — `registrar_despacho_cliente_radar` */
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
    nuevo_estado_orden: string;
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

  revalidatePath("/radar");
  revalidatePath("/radar/entrega");
  revalidatePath("/ordenes");
  revalidatePath(`/ordenes/${ordenId}`);
  return { ok: true, estado: response.data?.nuevo_estado_orden };
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
