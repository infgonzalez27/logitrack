import type { createClient } from "@/lib/supabase/server";
import type { RolNombre } from "@/lib/auth/roles";
import {
  aggregateCuentasPorCobrar,
  aggregateVentasPorCliente,
  aggregateVentasPorMes,
  isDashboardVendedorScope,
  type MoneyBarPoint,
  type OrdenFinanciera,
  type VentasMesPoint,
} from "@/lib/dashboard/sales";

type ServerSupabase = Awaited<ReturnType<typeof createClient>>;

async function fetchOrdenesFinancieras(
  supabase: ServerSupabase,
  rol: RolNombre | null,
  userId: string,
): Promise<OrdenFinanciera[]> {
  let query = supabase.from("ordenes_distribucion").select(`
      id,
      cliente_id,
      chofer_id,
      estado,
      created_at,
      fecha_despacho,
      clientes(razon_social),
      detalle_distribucion(subtotal_recaudar),
      detalle_rendicion_ordenes(recaudado)
    `);

  if (isDashboardVendedorScope(rol)) {
    query = query.eq("creado_por", userId);
  }

  const { data, error } = await query;

  if (error) {
    console.warn("[LogiTrack Charts] ordenes financieras:", error.message);
    return [];
  }

  return (data ?? []) as OrdenFinanciera[];
}

export { fetchOrdenesFinancieras };

export type { MoneyBarPoint, VentasMesPoint };

export type DashboardChartsData = {
  scope: "general" | "vendedor";
  ventasPorMes: VentasMesPoint[];
  ventasPorCliente: MoneyBarPoint[];
  cuentasPorCobrar: MoneyBarPoint[];
};

export async function fetchDashboardCharts(
  supabase: ServerSupabase,
  rol: RolNombre | null,
  userId: string,
): Promise<DashboardChartsData> {
  const ordenes = await fetchOrdenesFinancieras(supabase, rol, userId);
  const scope = isDashboardVendedorScope(rol) ? "vendedor" : "general";

  return {
    scope,
    ventasPorMes: aggregateVentasPorMes(ordenes),
    ventasPorCliente: aggregateVentasPorCliente(ordenes),
    cuentasPorCobrar: aggregateCuentasPorCobrar(ordenes),
  };
}
