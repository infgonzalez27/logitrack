"use server";

import { revalidatePath } from "next/cache";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile, type RolNombre } from "@/lib/auth/roles";
import { callDbProcedure, rpcErrorMessage } from "@/lib/actions/db-rpc";
import { createClient } from "@/lib/supabase/server";
import type {
  ResumenAutoVentaData,
  VentaAutoVentaParams,
} from "@/types/database";

export type ActionResult<T = unknown> = {
  success: boolean;
  message?: string;
  data?: T;
};

const ROLES_AUTOVENTA: RolNombre[] = [
  "admin",
  "gerente",
  "vendedor",
  "despachador",
];

async function requireAutoVentaAccess(): Promise<
  | { ok: true; profileId: string }
  | { ok: false; message: string }
> {
  const profile = await getCurrentProfile();
  if (!profile) {
    return { ok: false, message: "No autenticado." };
  }
  const rol = getRoleNameFromProfile(profile);
  if (!rol || !ROLES_AUTOVENTA.includes(rol)) {
    return {
      ok: false,
      message: "No tienes permiso para operar AutoVentas.",
    };
  }
  return { ok: true, profileId: profile.id };
}

/** Registra venta en caliente (`registrar_venta_en_ruta_autoventa`). */
export async function registrarVentaEnRutaAction(
  params: VentaAutoVentaParams,
): Promise<
  ActionResult<{ orden_id?: string; correlativo?: number; contenedores?: unknown }>
> {
  const access = await requireAutoVentaAccess();
  if (!access.ok) return { success: false, message: access.message };

  if (!params.cliente_id?.trim() || !params.camion_id?.trim()) {
    return {
      success: false,
      message: "Cliente y camión son obligatorios.",
    };
  }
  if (!params.productos_json?.length) {
    return {
      success: false,
      message: "Debe incluir al menos un producto.",
    };
  }

  const response = await callDbProcedure<{
    orden_id?: string;
    correlativo?: number;
    es_autoventa?: boolean;
    total_recaudar_usd?: number;
    contenedores?: unknown;
  }>("registrar_venta_en_ruta_autoventa", {
    p_vendedor_id: params.vendedor_id || access.profileId,
    p_cliente_id: params.cliente_id,
    p_camion_id: params.camion_id,
    p_productos_json: params.productos_json,
    p_contenedores_json: params.contenedores_json ?? [],
    p_observaciones: params.observaciones ?? null,
    p_tasa_cambio: params.tasa_cambio ?? null,
  });

  if (!response.success) {
    return {
      success: false,
      message: rpcErrorMessage(
        response,
        "No se pudo registrar la venta en ruta.",
      ),
    };
  }

  revalidatePath("/autoventas");
  revalidatePath("/ordenes");
  revalidatePath("/rendiciones");
  revalidatePath("/inventario-movil");

  return {
    success: true,
    message: response.message || "Venta en ruta registrada exitosamente.",
    data: response.data ?? undefined,
  };
}

/** Saldo actual de envases del cliente por tipo de contenedor. */
export async function obtenerSaldosEnvasesClienteAction(
  clienteId: string,
): Promise<ActionResult<Record<string, number>>> {
  const access = await requireAutoVentaAccess();
  if (!access.ok) return { success: false, message: access.message };
  if (!clienteId?.trim()) return { success: false, message: "Cliente requerido." };

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("saldo_contenedores_clientes")
    .select("contenedor_id, saldo_pendiente")
    .eq("cliente_id", clienteId);
  if (error) return { success: false, message: error.message };

  const saldos: Record<string, number> = {};
  for (const row of data ?? []) {
    saldos[String(row.contenedor_id)] = Number(row.saldo_pendiente) || 0;
  }
  return { success: true, data: saldos };
}

/** Resumen de jornada (`retorna_resumen_autoventas_jornada`). */
export async function obtenerResumenAutoVentasJornada(
  camionId: string,
  fecha?: string,
): Promise<ActionResult<ResumenAutoVentaData>> {
  const access = await requireAutoVentaAccess();
  if (!access.ok) return { success: false, message: access.message };

  if (!camionId?.trim()) {
    return { success: false, message: "Camión requerido." };
  }

  const response = await callDbProcedure<ResumenAutoVentaData>(
    "retorna_resumen_autoventas_jornada",
    {
      p_camion_id: camionId,
      p_fecha: fecha || null,
    },
  );

  if (!response.success || !response.data) {
    return {
      success: false,
      message: rpcErrorMessage(
        response,
        "No se pudo obtener el resumen de AutoVentas.",
      ),
    };
  }

  return { success: true, data: response.data };
}

/** Carga almacén → móvil sin radar (`solicita_cargar_inventario_movil_desde_almacen`). */
export async function cargarInventarioMovilAutoVentasAction(
  camionId: string,
  productos: Array<{ producto_id: string; cantidad_solicitada: number }>,
): Promise<ActionResult> {
  const access = await requireAutoVentaAccess();
  if (!access.ok) return { success: false, message: access.message };

  if (!camionId?.trim()) {
    return { success: false, message: "Camión requerido." };
  }
  if (!productos.length) {
    return {
      success: false,
      message: "Debe indicar al menos un producto a cargar.",
    };
  }

  const response = await callDbProcedure(
    "solicita_cargar_inventario_movil_desde_almacen",
    {
      p_camion_id: camionId,
      p_resumen_productos: productos,
      p_radar_id: null,
    },
  );

  if (!response.success) {
    return {
      success: false,
      message: rpcErrorMessage(
        response,
        "No se pudo cargar el inventario móvil.",
      ),
    };
  }

  revalidatePath("/autoventas");
  revalidatePath("/inventario-movil");
  revalidatePath("/inventario-almacen");

  return {
    success: true,
    message:
      response.message ||
      "Inventario móvil cargado exitosamente en el camión.",
  };
}

export type DescargaCamionLinea = {
  producto_id: string;
  codigo: string | null;
  nombre: string;
  cantidad: number;
};

/**
 * Descarga el camión (`descargar_camion_autoventa`): devuelve al almacén solo
 * el sobrante (cargado − entregado). Sin `productos` vacía el inventario móvil.
 */
export async function reversarInventarioMovilAutoVentasAction(
  camionId: string,
  productos?: Array<{ producto_id: string; cantidad: number }>,
): Promise<ActionResult<{ detalle: DescargaCamionLinea[] }>> {
  const access = await requireAutoVentaAccess();
  if (!access.ok) return { success: false, message: access.message };

  if (!camionId?.trim()) {
    return { success: false, message: "Camión requerido." };
  }

  const response = await callDbProcedure<{ detalle?: DescargaCamionLinea[] }>(
    "descargar_camion_autoventa",
    {
      p_camion_id: camionId,
      p_productos: productos?.length ? productos : null,
    },
  );

  if (!response.success) {
    return {
      success: false,
      message: rpcErrorMessage(response, "No se pudo descargar el camión."),
    };
  }

  revalidatePath("/autoventas");
  revalidatePath("/inventario-movil");
  revalidatePath("/inventario-almacen");

  return {
    success: true,
    message: response.message || "Sobrante devuelto al almacén.",
    data: { detalle: response.data?.detalle ?? [] },
  };
}
