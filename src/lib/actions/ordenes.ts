"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { getCurrentProfile, getSessionUser } from "@/lib/auth";
import {
  canCreateOrden,
  esEstadoOrdenValido,
  puedeCambiarEstadoOrden,
} from "@/lib/auth/orden-permissions";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { createClient } from "@/lib/supabase/server";
import type { OrdenEstado, ProductoOrdenRpc } from "@/types/database";

export type LineaOrdenInput = {
  producto_id: string;
  cantidad_solicitada: number;
  valor_unitario_recaudar: number;
};

type CrearOrdenRpcResult = {
  success: boolean;
  message?: string;
  orden_id?: string;
};

type ActualizarEstadoRpcResult = {
  success: boolean;
  message?: string;
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

  const record = data as Record<string, unknown>;
  if (typeof record.id === "string") return record.id;

  return null;
}

function parseRpcError(data: unknown, fallback: string): string {
  if (data && typeof data === "object") {
    const result = data as CrearOrdenRpcResult;
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
        "Estado inválido. Valores permitidos: borrador, lista_para_carga, en_transito, liquidada, anulada.",
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

  const { data, error } = await supabase.rpc("actualizar_estado_orden_distribucion", {
    p_orden_id: ordenIdTrim,
    p_estado: estado,
  });

  if (error) return { error: error.message };

  const rpcResult = data as ActualizarEstadoRpcResult | null;
  if (rpcResult && rpcResult.success === false) {
    return { error: rpcResult.message ?? "No se pudo actualizar el estado." };
  }

  revalidatePath("/ordenes");
  revalidatePath(`/ordenes/${ordenIdTrim}`);
  return { success: true };
}
