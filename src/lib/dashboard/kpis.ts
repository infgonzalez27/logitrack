import type { createClient } from "@/lib/supabase/server";
import type { RolNombre } from "@/lib/auth/roles";
import {
  countClientesConSaldo,
  isDashboardVendedorScope,
  sumCuentasPorCobrar,
  sumVentasMesActual,
  type OrdenFinanciera,
} from "@/lib/dashboard/sales";
import { fetchOrdenesFinancieras } from "@/lib/dashboard/charts";
import { formatCurrency } from "@/lib/format";

export type KpiTone = "default" | "success" | "warning" | "danger" | "info";

export type DashboardKpi = {
  id: string;
  label: string;
  value: number | string;
  hint?: string;
  href?: string;
  tone?: KpiTone;
};

type ServerSupabase = Awaited<ReturnType<typeof createClient>>;

async function countOrdenes(
  supabase: ServerSupabase,
  filters: Record<string, string>,
  vendedorId?: string,
): Promise<number> {
  let query = supabase
    .from("ordenes_distribucion")
    .select("*", { count: "exact", head: true });
  for (const [k, v] of Object.entries(filters)) {
    query = query.eq(k, v);
  }
  if (vendedorId) query = query.eq("creado_por", vendedorId);
  const { count } = await query;
  return count ?? 0;
}

function kpisGerencia(
  ordenes: OrdenFinanciera[],
  extras: { rendicionesRevision: number; facturasPendientes: number },
): DashboardKpi[] {
  const ventasMes = sumVentasMesActual(ordenes);
  const cxc = sumCuentasPorCobrar(ordenes);
  const clientesSaldo = countClientesConSaldo(ordenes);

  return [
    {
      id: "ventas-mes",
      label: "Ventas del mes",
      value: formatCurrency(ventasMes),
      hint: "Órdenes en tránsito y liquidadas",
      href: "/ordenes",
      tone: "success",
    },
    {
      id: "cxc",
      label: "Cuentas por cobrar",
      value: formatCurrency(cxc),
      hint: `${clientesSaldo} cliente(s) con saldo`,
      href: "/clientes",
      tone: cxc > 0 ? "warning" : "success",
    },
    {
      id: "rendiciones",
      label: "Rendiciones en revisión",
      value: extras.rendicionesRevision,
      href: "/rendiciones",
      tone: "info",
    },
    {
      id: "facturas",
      label: "Facturas pendientes",
      value: extras.facturasPendientes,
      href: "/facturas-compras",
      tone: "danger",
    },
  ];
}

function kpisVendedor(
  ordenes: OrdenFinanciera[],
  userId: string,
  supabase: ServerSupabase,
): Promise<DashboardKpi[]> {
  const ventasMes = sumVentasMesActual(ordenes);
  const cxc = sumCuentasPorCobrar(ordenes);

  return Promise.all([
    countOrdenes(supabase, { estado: "en_transito" }, userId),
    countOrdenes(supabase, { estado: "lista_para_carga" }, userId),
    countOrdenes(supabase, { estado: "liquidada" }, userId),
  ]).then(([transito, carga, liquidadas]) => [
    {
      id: "ventas-mes",
      label: "Mis ventas del mes",
      value: formatCurrency(ventasMes),
      href: "/ordenes",
      tone: "success",
    },
    {
      id: "cxc",
      label: "Mi cartera por cobrar",
      value: formatCurrency(cxc),
      href: "/ordenes",
      tone: cxc > 0 ? "warning" : "success",
    },
    {
      id: "transito",
      label: "Órdenes en tránsito",
      value: transito,
      href: "/ordenes",
      tone: "info",
    },
    {
      id: "carga",
      label: "Listas para carga",
      value: carga,
      href: "/ordenes",
      tone: "default",
    },
    {
      id: "liquidadas",
      label: "Órdenes liquidadas",
      value: liquidadas,
      href: "/ordenes",
      tone: "success",
    },
  ]);
}

export async function fetchDashboardKpis(
  supabase: ServerSupabase,
  rol: RolNombre | null,
  userId: string,
): Promise<DashboardKpi[]> {
  const ordenes = await fetchOrdenesFinancieras(supabase, rol, userId);

  if (isDashboardVendedorScope(rol)) {
    return kpisVendedor(ordenes, userId, supabase);
  }

  if (rol === "admin" || rol === "gerente") {
    const [rendicionesRevision, facturasPendientes] = await Promise.all([
      supabase
        .from("rendiciones_cuentas")
        .select("*", { count: "exact", head: true })
        .eq("estado", "revision")
        .then((r) => r.count ?? 0),
      supabase
        .from("facturas_compras")
        .select("*", { count: "exact", head: true })
        .eq("estado_pago", "pendiente")
        .then((r) => r.count ?? 0),
    ]);
    return kpisGerencia(ordenes, {
      rendicionesRevision,
      facturasPendientes,
    });
  }

  // Despachador — operativo
  const [borrador, transito, camiones] = await Promise.all([
    countOrdenes(supabase, { estado: "borrador" }),
    countOrdenes(supabase, { estado: "en_transito" }),
    supabase
      .from("camiones")
      .select("*", { count: "exact", head: true })
      .eq("estado", "disponible")
      .then((r) => r.count ?? 0),
  ]);

  return [
    {
      id: "borrador",
      label: "Borradores",
      value: borrador,
      href: "/ordenes",
      tone: "warning",
    },
    {
      id: "transito",
      label: "En tránsito",
      value: transito,
      href: "/ordenes",
      tone: "info",
    },
    {
      id: "camiones",
      label: "Camiones disponibles",
      value: camiones,
      href: "/camiones",
      tone: "success",
    },
    {
      id: "ventas-mes",
      label: "Ventas del mes (empresa)",
      value: formatCurrency(sumVentasMesActual(ordenes)),
      href: "/ordenes",
      tone: "default",
    },
  ];
}
