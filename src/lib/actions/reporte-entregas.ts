"use server";

import { createClient } from "@/lib/supabase/server";

export type ContenedorEntrega = {
  contenedor_id: string;
  codigo?: string | null;
  nombre: string;
  cantidad_entregada?: number;
  cantidad_retirada?: number;
};

export type ResumenVacioDetalle = {
  contenedor_id: string;
  codigo_producto?: string | null;
  nombre_producto: string;
  entregado: number;
  retirado: number;
};

export type ResumenVacioCliente = {
  cliente_id: string;
  razon_social: string;
  rif_nit: string | null;
  detalles: ResumenVacioDetalle[];
};

export type ResumenContenedorJornada = {
  contenedor_id: string;
  codigo: string | null;
  nombre: string;
  total_entregado: number;
  total_retirado: number;
};

export type ReporteEntregasResponse = {
  camion_id: string;
  fecha: string;
  total_general_usd: number;
  total_contenedores_entregados?: number;
  total_contenedores_retirados?: number;
  resumen_vacios?: ResumenVacioCliente[];
  resumen_contenedores?: ResumenContenedorJornada[];
  entregas: Array<{
    cliente_id: string;
    razon_social: string;
    rif_nit: string;
    orden_id: string;
    correlativo: number;
    total_orden_usd: number;
    total_contenedores_entregados?: number;
    total_contenedores_retirados?: number;
    contenedores?: ContenedorEntrega[];
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
    console.error("Error en reporte de entregas:", error || data?.message);
    return null;
  }

  return data.data as ReporteEntregasResponse;
}
