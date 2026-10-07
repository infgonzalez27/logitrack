"use server";

import { createClient } from "@/lib/supabase/server";

export type ReporteEntregasResponse = {
  camion_id: string;
  fecha: string;
  total_general_usd: number;
  entregas: Array<{
    cliente_id: string;
    razon_social: string;
    rif_nit: string;
    orden_id: string;
    correlativo: number;
    total_orden_usd: number;
    productos: Array<{
      producto_id: string;
      codigo: string;
      nombre: string;
      cantidad_cargada: number;
      cantidad_entregada: number;
      devolucion: number;
      precio_unitario_usd: number;
      subtotal_usd: number;
    }>;
  }>;
};

export async function obtenerReporteEntregasAction(
  camionId: string,
  fecha?: string,
) {
  const supabase = await createClient();
  const args = fecha
    ? { p_camion_id: camionId, p_fecha: fecha }
    : { p_camion_id: camionId };

  const { data, error } = await supabase.rpc(
    "retorna_reporte_autoventas_entregas_cliente",
    args,
  );

  if (error || !data?.success) {
    return null;
  }

  return data.data as ReporteEntregasResponse;
}
