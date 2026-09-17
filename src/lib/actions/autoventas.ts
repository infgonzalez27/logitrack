"use server";

import { revalidatePath } from "next/cache";
import { getCurrentProfile } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import type {
  VentaAutoVentaParams,
  ResumenAutoVentaData,
} from "@/types/database";

export type ActionResult<T = unknown> = {
  success: boolean;
  message?: string;
  data?: T;
};

/**
 * Registra una venta en caliente en la ruta (AutoVenta sin radar)
 */
export async function registrarVentaEnRutaAction(
  params: VentaAutoVentaParams
): Promise<ActionResult> {
  try {
    const profile = await getCurrentProfile();
    if (!profile) {
      return { success: false, message: "No autenticado." };
    }

    const supabase = await createClient();

    const { data, error } = await supabase.rpc(
      "registrar_venta_en_ruta_autoventa" as never,
      {
        p_vendedor_id: params.vendedor_id || profile.id,
        p_cliente_id: params.cliente_id,
        p_camion_id: params.camion_id,
        p_productos_json: params.productos_json,
        p_contenedores_json: params.contenedores_json || [],
        p_observaciones: params.observaciones || null,
        p_tasa_cambio: params.tasa_cambio || null,
      } as never
    );

    if (error) {
      return { success: false, message: error.message };
    }

    const res = data as { success?: boolean; message?: string; data?: unknown; error?: { message?: string } };

    if (res && res.success === false) {
      return {
        success: false,
        message: res.error?.message || res.message || "Error al registrar la venta en ruta.",
      };
    }

    revalidatePath("/autoventas");
    revalidatePath("/ordenes");

    return {
      success: true,
      message: res?.message || "Venta en ruta registrada exitosamente.",
      data: res?.data,
    };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : "Error inesperado al procesar AutoVenta.";
    return { success: false, message: msg };
  }
}

/**
 * Obtiene el resumen consolidado de la jornada de AutoVentas para un camión
 */
export async function obtenerResumenAutoVentasJornada(
  camionId: string,
  fecha?: string
): Promise<ActionResult<ResumenAutoVentaData>> {
  try {
    const profile = await getCurrentProfile();
    if (!profile) {
      return { success: false, message: "No autenticado." };
    }

    const supabase = await createClient();

    const { data, error } = await supabase.rpc(
      "retorna_resumen_autoventas_jornada" as never,
      {
        p_camion_id: camionId,
        p_fecha: fecha || null,
      } as never
    );

    if (error) {
      return { success: false, message: error.message };
    }

    const res = data as { success?: boolean; message?: string; data?: ResumenAutoVentaData };

    if (res && res.success === false) {
      return { success: false, message: res.message || "Error al obtener resumen de AutoVentas." };
    }

    return {
      success: true,
      data: res?.data,
    };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : "Error inesperado al consultar resumen.";
    return { success: false, message: msg };
  }
}

/**
 * Carga inventario móvil desde el almacén central hacia el camión (sin radar)
 */
export async function cargarInventarioMovilAutoVentasAction(
  camionId: string,
  productos: Array<{ producto_id: string; cantidad_solicitada: number }>
): Promise<ActionResult> {
  try {
    const profile = await getCurrentProfile();
    if (!profile) {
      return { success: false, message: "No autenticado." };
    }

    const supabase = await createClient();

    const { data, error } = await supabase.rpc(
      "solicita_cargar_inventario_movil_desde_almacen" as never,
      {
        p_camion_id: camionId,
        p_resumen_productos: productos,
        p_radar_id: null,
      } as never
    );

    if (error) {
      return { success: false, message: error.message };
    }

    const res = data as { success?: boolean; message?: string };
    if (res && res.success === false) {
      return { success: false, message: res.message || "Error al cargar inventario móvil." };
    }

    revalidatePath("/autoventas");

    return {
      success: true,
      message: res?.message || "Inventario móvil cargado exitosamente en el camión.",
    };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : "Error al cargar inventario móvil.";
    return { success: false, message: msg };
  }
}

/**
 * Reversa / devuelce el inventario sobrante del camión al almacén central
 */
export async function reversarInventarioMovilAutoVentasAction(
  camionId: string,
  productos?: Array<{ producto_id: string; cantidad_solicitada: number }>
): Promise<ActionResult> {
  try {
    const profile = await getCurrentProfile();
    if (!profile) {
      return { success: false, message: "No autenticado." };
    }

    const supabase = await createClient();

    const { data, error } = await supabase.rpc(
      "solicita_reversar_carga_inventario_movil_a_almacen" as never,
      {
        p_camion_id: camionId,
        p_resumen_productos: productos || null,
        p_radar_id: null,
      } as never
    );

    if (error) {
      return { success: false, message: error.message };
    }

    const res = data as { success?: boolean; message?: string };
    if (res && res.success === false) {
      return { success: false, message: res.message || "Error al reversar inventario móvil." };
    }

    revalidatePath("/autoventas");

    return {
      success: true,
      message: res?.message || "Inventario móvil devuelto exitosamente al almacén central.",
    };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : "Error al reversar inventario móvil.";
    return { success: false, message: msg };
  }
}
