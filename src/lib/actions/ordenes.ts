"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { getCurrentProfile, getSessionUser } from "@/lib/auth";
import {
  canCreateOrden,
  canRegistrarContenedores,
  canRegistrarEntrega,
  esEstadoOrdenValido,
  puedeCambiarEstadoOrden,
} from "@/lib/auth/orden-permissions";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { callDbProcedure, rpcErrorMessage } from "@/lib/actions/db-rpc";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import type { EstadoEntrega, OrdenEstado, ProductoOrdenRpc } from "@/types/database";

export type LineaOrdenInput = {
  producto_id: string;
  cantidad_solicitada: number;
  valor_unitario_recaudar: number;
};

type CrearOrdenRpcResult = {
  success: boolean;
  message?: string;
  orden_id?: string;
  data?: { orden_id?: string };
};

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function isUuid(value: string): boolean {
  return UUID_RE.test(value.trim());
}

function parseOrdenIdFromRpc(data: unknown): string | null {
  if (typeof data === "string") return data;
  if (!data || typeof data !== "object") return null;

  const result = data as CrearOrdenRpcResult;
  if (result.orden_id) return result.orden_id;
  if (result.data?.orden_id) return result.data.orden_id;

  const record = data as Record<string, unknown>;
  if (typeof record.id === "string") return record.id;

  return null;
}

function parseRpcError(data: unknown, fallback: string): string {
  if (data && typeof data === "object") {
    const result = data as CrearOrdenRpcResult & {
      error?: { message?: string };
    };
    if (result.error?.message) return result.error.message;
    if (result.message) return result.message;
  }
  return fallback;
}

function mapProductosJson(lineas: LineaOrdenInput[]): ProductoOrdenRpc[] {
  return lineas.map((linea) => ({
    producto_id: linea.producto_id.trim(),
    cantidad: linea.cantidad_solicitada,
    precio_unitario: linea.valor_unitario_recaudar,
  }));
}

function validateCreateOrdenInput(
  input: {
    chofer_id: string;
    cliente_id: string;
    camion_id: string;
    lineas: LineaOrdenInput[];
  },
  vendedorId: string | undefined,
): string | null {
  if (!vendedorId?.trim()) {
    return "No autenticado.";
  }
  if (!isUuid(vendedorId)) {
    return "Sesión de vendedor inválida.";
  }
  if (!input.cliente_id?.trim()) {
    return "Selecciona un cliente.";
  }
  if (!isUuid(input.cliente_id)) {
    return "Cliente inválido.";
  }
  if (!input.camion_id?.trim()) {
    return "Selecciona un camión.";
  }
  if (!isUuid(input.camion_id)) {
    return "Camión inválido.";
  }
  if (!input.chofer_id?.trim()) {
    return "Selecciona un chofer.";
  }
  if (!isUuid(input.chofer_id)) {
    return "Chofer inválido.";
  }
  if (!input.lineas.length) {
    return "Agrega al menos una línea de producto.";
  }

  for (let i = 0; i < input.lineas.length; i++) {
    const linea = input.lineas[i];
    if (!linea.producto_id?.trim()) {
      return `Línea ${i + 1}: selecciona un producto.`;
    }
    if (!isUuid(linea.producto_id)) {
      return `Línea ${i + 1}: producto inválido.`;
    }
    if (!Number.isFinite(linea.cantidad_solicitada) || linea.cantidad_solicitada <= 0) {
      return `Línea ${i + 1}: la cantidad debe ser mayor a 0.`;
    }
    if (
      !Number.isFinite(linea.valor_unitario_recaudar) ||
      linea.valor_unitario_recaudar < 0
    ) {
      return `Línea ${i + 1}: el precio unitario no puede ser negativo.`;
    }
  }

  return null;
}

export async function createOrdenAction(input: {
  cliente_id: string;
  camion_id: string;
  chofer_id: string;
  lineas: LineaOrdenInput[];
}) {
  const supabase = await createClient();
  const user = await getSessionUser();

  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);
  if (!canCreateOrden(rol)) {
    return { error: "No tienes permiso para crear órdenes de distribución." };
  }

  const validationError = validateCreateOrdenInput(input, user?.id);
  if (validationError) {
    return { error: validationError };
  }

  const productosJson = mapProductosJson(input.lineas);
  if (!productosJson.length) {
    return { error: "Agrega al menos una línea de producto." };
  }

  // Firma actual del SP en BD (db/functions/crear_orden_distribucion.sql)
  const { data, error } = await supabase.rpc("crear_orden_distribucion", {
    p_vendedor_id: user!.id,
    p_chofer_id: input.chofer_id.trim(),
    p_cliente_id: input.cliente_id.trim(),
    p_camion_id: input.camion_id.trim(),
    p_productos_json: productosJson,
  });

  if (error) {
    return { error: error.message };
  }

  const ordenId = parseOrdenIdFromRpc(data);
  const rpcResult = data as CrearOrdenRpcResult | null;

  if (rpcResult && rpcResult.success === false) {
    return { error: parseRpcError(data, "No se pudo crear la orden.") };
  }

  if (!ordenId) {
    return { error: parseRpcError(data, "No se pudo crear la orden.") };
  }

  revalidatePath("/ordenes");
  redirect(`/ordenes/${ordenId}`);
}

export async function updateOrdenEstadoAction(
  ordenId: string,
  estado: OrdenEstado,
) {
  const ordenIdTrim = ordenId?.trim();
  if (!ordenIdTrim) {
    return { error: "ID de orden requerido." };
  }
  if (!isUuid(ordenIdTrim)) {
    return { error: "ID de orden inválido." };
  }
  if (!estado?.trim()) {
    return { error: "Estado de destino requerido." };
  }
  if (!esEstadoOrdenValido(estado)) {
    return {
      error:
        "Estado inválido. Valores permitidos: borrador, aprobada, en_transito, por_liquidar, liquidada, anulada.",
    };
  }

  const supabase = await createClient();
  const user = await getSessionUser();
  if (!user) {
    return { error: "No autenticado." };
  }

  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);

  const { data: orden, error: fetchError } = await supabase
    .from("ordenes_distribucion")
    .select("estado, creado_por")
    .eq("id", ordenIdTrim)
    .single();

  if (fetchError || !orden) {
    return { error: "Orden no encontrada." };
  }

  const estadoActual = orden.estado as OrdenEstado;
  const esCreador = orden.creado_por === user.id;

  if (
    !puedeCambiarEstadoOrden(rol, estadoActual, estado, { esCreador })
  ) {
    return { error: "Transición de estado no permitida para tu rol." };
  }

  // DB-002 / DB-003: RPCs dedicados (INTEGRACION-RPC.md)
  if (estado === "aprobada") {
    const response = await callDbProcedure<{
      orden_id: string;
      nuevo_estado: string;
    }>("aprobar_orden_distribucion", { p_orden_id: ordenIdTrim });

    if (!response.success) {
      return {
        error: rpcErrorMessage(response, "No se pudo aprobar la orden."),
        code: response.error?.code,
      };
    }
  } else if (estado === "en_transito") {
    const response = await callDbProcedure<{
      orden_id: string;
      nuevo_estado: string;
    }>("cargar_inventario_movil", { p_orden_id: ordenIdTrim });

    if (!response.success) {
      return {
        error: rpcErrorMessage(
          response,
          "No se pudo cargar el inventario móvil / despachar.",
        ),
        code: response.error?.code,
      };
    }
  } else if (estado === "liquidada") {
    // DB-005: requiere rendición aprobada vinculada a la orden
    const response = await callDbProcedure<{
      orden_id: string;
      nuevo_estado: string;
    }>("liquidar_orden_distribucion", { p_orden_id: ordenIdTrim });

    if (!response.success) {
      return {
        error: rpcErrorMessage(
          response,
          "No se pudo liquidar la orden. Verifica que exista una rendición aprobada.",
        ),
        code: response.error?.code,
      };
    }
  } else if (estado === "anulada") {
    // DB-006
    const response = await callDbProcedure<{
      orden_id: string;
      nuevo_estado: string;
    }>("anular_orden_distribucion", { p_orden_id: ordenIdTrim });

    if (!response.success) {
      return {
        error: rpcErrorMessage(response, "No se pudo anular la orden."),
        code: response.error?.code,
      };
    }
  } else {
    return {
      error: "Esta transición no está disponible.",
    };
  }

  revalidatePath("/ordenes");
  revalidatePath(`/ordenes/${ordenIdTrim}`);
  return { success: true };
}

export async function registrarEntregaDetalleAction(input: {
  detalle_id: string;
  cantidad_despachada: number;
  estado_entrega: EstadoEntrega;
  motivo_rechazo?: string;
}) {
  const detalleId = input.detalle_id?.trim();
  if (!detalleId || !isUuid(detalleId)) {
    return { error: "ID de línea inválido." };
  }

  const estadosValidos: EstadoEntrega[] = [
    "entregado",
    "entregado_parcial",
    "rechazado",
  ];
  if (!estadosValidos.includes(input.estado_entrega)) {
    return {
      error:
        "Estado de entrega inválido. Usa entregado, entregado_parcial o rechazado.",
    };
  }

  if (
    !Number.isFinite(input.cantidad_despachada) ||
    input.cantidad_despachada < 0
  ) {
    return { error: "La cantidad despachada no puede ser negativa." };
  }

  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);
  if (!canRegistrarEntrega(rol)) {
    return { error: "No tienes permiso para registrar entregas." };
  }

  const motivo =
    input.estado_entrega === "entregado"
      ? null
      : (input.motivo_rechazo?.trim() || null);

  if (
    (input.estado_entrega === "rechazado" ||
      input.estado_entrega === "entregado_parcial") &&
    !motivo
  ) {
    return {
      error: "Indica el motivo para entregas parciales o rechazadas.",
    };
  }

  // DB-004
  const response = await callDbProcedure<{
    detalle_id: string;
    estado_entrega: string;
    orden_estado: string;
  }>("registrar_entrega_detalle", {
    p_detalle_id: detalleId,
    p_cantidad_despachada: input.cantidad_despachada,
    p_estado_entrega: input.estado_entrega,
    p_motivo_rechazo: motivo,
  });

  if (!response.success) {
    return {
      error: rpcErrorMessage(response, "No se pudo registrar la entrega."),
      code: response.error?.code,
    };
  }

  revalidatePath("/ordenes");
  return {
    success: true,
    orden_estado: response.data?.orden_estado ?? null,
  };
}

export type TipoContenedorOption = {
  id: string;
  codigo: string;
  nombre: string;
};

export async function listarTiposContenedoresAction(): Promise<
  | { ok: true; contenedores: TipoContenedorOption[] }
  | { ok: false; error: string }
> {
  try {
    const { data, error } = await createAdminClient()
      .from("tipos_contenedores")
      .select("id, codigo, nombre")
      .order("nombre");

    if (error) {
      return { ok: false, error: error.message };
    }

    return {
      ok: true,
      contenedores: (data ?? []).map((row) => ({
        id: row.id,
        codigo: row.codigo,
        nombre: row.nombre,
      })),
    };
  } catch (err) {
    return {
      ok: false,
      error:
        err instanceof Error
          ? err.message
          : "No se pudieron cargar los tipos de contenedores.",
    };
  }
}

export async function registrarMovimientoContenedoresAction(input: {
  cliente_id: string;
  orden_id: string;
  contenedor_id: string;
  cantidad_entregada: number;
  cantidad_retirada: number;
}) {
  const clienteId = input.cliente_id?.trim();
  const ordenId = input.orden_id?.trim();
  const contenedorId = input.contenedor_id?.trim();

  if (!clienteId || !isUuid(clienteId)) {
    return { error: "Cliente inválido." };
  }
  if (!ordenId || !isUuid(ordenId)) {
    return { error: "Orden inválida." };
  }
  if (!contenedorId || !isUuid(contenedorId)) {
    return { error: "Selecciona un tipo de contenedor." };
  }
  if (
    !Number.isFinite(input.cantidad_entregada) ||
    input.cantidad_entregada < 0 ||
    !Number.isFinite(input.cantidad_retirada) ||
    input.cantidad_retirada < 0
  ) {
    return { error: "Las cantidades deben ser mayores o iguales a 0." };
  }
  if (input.cantidad_entregada === 0 && input.cantidad_retirada === 0) {
    return { error: "Indica al menos una cantidad entregada o retirada." };
  }

  const user = await getSessionUser();
  if (!user) {
    return { error: "No autenticado." };
  }

  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);
  if (!canRegistrarContenedores(rol)) {
    return {
      error: "No tienes permiso para registrar movimientos de contenedores.",
    };
  }

  // DB-004b
  const response = await callDbProcedure<{ movimiento_id: string }>(
    "registrar_movimiento_contenedores",
    {
      p_cliente_id: clienteId,
      p_orden_id: ordenId,
      p_contenedor_id: contenedorId,
      p_cantidad_entregada: input.cantidad_entregada,
      p_cantidad_retirada: input.cantidad_retirada,
      p_creado_por: user.id,
    },
  );

  if (!response.success) {
    return {
      error: rpcErrorMessage(
        response,
        "No se pudo registrar el movimiento de contenedores.",
      ),
      code: response.error?.code,
    };
  }

  revalidatePath("/ordenes");
  revalidatePath(`/ordenes/${ordenId}`);
  return { success: true, movimiento_id: response.data?.movimiento_id ?? null };
}

export type ActualizaOrdenDetalleInput = {
  producto_id: string;
  cantidad_solicitada: number;
  valor_unitario_recaudar: number;
  valor_unitario_usd?: number | null;
};

/** DB-017 — solo órdenes en borrador. */
export async function actualizaOrdenDistribucionAction(input: {
  correlativo: number;
  cliente_id: string;
  camion_id: string;
  chofer_id: string;
  fecha_despacho?: string | null;
  factura_origen_numero?: string | null;
  lineas: ActualizaOrdenDetalleInput[];
}) {
  const user = await getSessionUser();
  if (!user) {
    return { error: "No autenticado." };
  }

  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);
  if (!canCreateOrden(rol)) {
    return { error: "No tienes permiso para actualizar órdenes." };
  }

  if (!Number.isFinite(input.correlativo) || input.correlativo <= 0) {
    return { error: "Correlativo inválido." };
  }

  const lineas = input.lineas.filter((l) => l.producto_id?.trim());
  if (!lineas.length) {
    return { error: "Agrega al menos una línea de producto." };
  }

  const response = await callDbProcedure<{
    correlativo: number;
    orden_id: string;
    tasa_cambio: number;
    total_recaudar_bs: number;
    total_recaudar_usd: number;
  }>("actualiza_orden_distribucion_segun_correlativo", {
    p_correlativo: input.correlativo,
    p_header: {
      cliente_id: input.cliente_id.trim(),
      camion_id: input.camion_id.trim(),
      chofer_id: input.chofer_id.trim(),
      fecha_despacho: input.fecha_despacho?.trim() || null,
      factura_origen_numero: input.factura_origen_numero?.trim() || null,
    },
    p_detalle: lineas.map((l) => ({
      producto_id: l.producto_id.trim(),
      cantidad_solicitada: l.cantidad_solicitada,
      valor_unitario_recaudar: l.valor_unitario_recaudar,
      valor_unitario_usd: l.valor_unitario_usd ?? null,
    })),
  });

  if (!response.success) {
    return {
      error: rpcErrorMessage(response, "No se pudo actualizar la orden."),
      code: response.error?.code,
    };
  }

  const ordenId = response.data?.orden_id;
  revalidatePath("/ordenes");
  if (ordenId) {
    revalidatePath(`/ordenes/${ordenId}`);
    redirect(`/ordenes/${ordenId}`);
  }

  return { success: true, data: response.data };
}

