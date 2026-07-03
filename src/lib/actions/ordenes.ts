"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { getCurrentProfile, getSessionUser } from "@/lib/auth";
import { canCreateOrden } from "@/lib/auth/orden-permissions";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { createClient } from "@/lib/supabase/server";
import type { OrdenEstado } from "@/types/database";

export type LineaOrdenInput = {
  producto_id: string;
  cantidad_solicitada: number;
  valor_unitario_recaudar: number;
};

type SolicitaCrearOrdenRpcResult = {
  success: boolean;
  message?: string;
  orden_id?: string;
};

function parseOrdenIdFromRpc(data: unknown): string | null {
  if (typeof data === "string") return data;
  if (!data || typeof data !== "object") return null;

  const result = data as SolicitaCrearOrdenRpcResult;
  if (result.orden_id) return result.orden_id;

  const record = data as Record<string, unknown>;
  if (typeof record.id === "string") return record.id;

  return null;
}

function parseRpcError(data: unknown, fallback: string): string {
  if (data && typeof data === "object") {
    const result = data as SolicitaCrearOrdenRpcResult;
    if (result.message) return result.message;
  }
  return fallback;
}

export async function createOrdenAction(input: {
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

  if (!user) {
    return { error: "No autenticado." };
  }

  if (!input.lineas.length) {
    return { error: "Agrega al menos una línea de producto." };
  }

  const { data, error } = await supabase.rpc("solicita_crear_orden_distribucion", {
    p_vendedor_id: user.id,
    p_chofer_id: input.chofer_id,
    p_productos_json: input.lineas.map((linea) => ({
      producto_id: linea.producto_id,
      cantidad: linea.cantidad_solicitada,
      precio_unitario: linea.valor_unitario_recaudar,
    })),
  });

  if (error) {
    return { error: error.message };
  }

  const ordenId = parseOrdenIdFromRpc(data);
  const rpcResult = data as SolicitaCrearOrdenRpcResult | null;

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
  const supabase = await createClient();

  const { error } = await supabase.rpc("actualizar_estado_orden_distribucion", {
    p_orden_id: ordenId,
    p_estado: estado,
  });

  if (error) return { error: error.message };

  revalidatePath("/ordenes");
  revalidatePath(`/ordenes/${ordenId}`);
  return { success: true };
}
