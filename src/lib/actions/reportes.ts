"use server";

import { getCurrentProfile } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import type { ReporteFormasPagoData } from "@/types/database";

export type ActionResult<T = unknown> = {
  success: boolean;
  message?: string;
  data?: T;
};

/**
 * Consulta el reporte de formas de pago en rendiciones de cuentas por rango de fecha
 */
export async function obtenerReporteFormasPagoAction(
  fechaDesde?: string,
  fechaHasta?: string,
  soloBancarios: boolean = false
): Promise<ActionResult<ReporteFormasPagoData>> {
  try {
    const profile = await getCurrentProfile();
    if (!profile) {
      return { success: false, message: "No autenticado." };
    }

    const supabase = await createClient();

    const { data, error } = await supabase.rpc(
      "reporte_formas_pago_rendicion" as never,
      {
        p_fecha_desde: fechaDesde || null,
        p_fecha_hasta: fechaHasta || null,
        p_solo_bancarios: soloBancarios,
      } as never
    );

    if (error) {
      return { success: false, message: error.message };
    }

    const res = data as { success?: boolean; message?: string; data?: ReporteFormasPagoData };

    if (res && res.success === false) {
      return { success: false, message: res.message || "Error al obtener reporte de formas de pago." };
    }

    return {
      success: true,
      data: res?.data,
    };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : "Error inesperado al generar reporte.";
    return { success: false, message: msg };
  }
}
