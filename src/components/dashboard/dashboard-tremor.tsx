"use client";

import type { ReactNode } from "react";
import Link from "next/link";
import { Card, Grid, Metric, Text, Title } from "@tremor/react";
import type { RolNombre } from "@/lib/auth/roles";
import { ventaScopeLabel } from "@/lib/dashboard/sales";
import {
  ChartEmptyState,
  LtMoneyHorizontalChart,
  LtVentasMesChart,
} from "@/components/dashboard/lt-charts";
import type { DashboardKpi } from "@/lib/dashboard/kpis";
import type { DashboardChartsData } from "@/lib/dashboard/charts";

const KPI_ACCENT: Record<
  NonNullable<DashboardKpi["tone"]>,
  string
> = {
  default: "text-lt-text",
  success: "text-lt-success-text",
  warning: "text-lt-warning-text",
  danger: "text-lt-danger-text",
  info: "text-lt-info-text",
};

const CARD_CLASS =
  "rounded-2xl border border-lt-border-light bg-lt-surface shadow-[var(--lt-shadow-card)] ring-0";

const CXC_COLOR = "#f59e0b";

function KpiCard({ kpi }: { kpi: DashboardKpi }) {
  const accent = KPI_ACCENT[kpi.tone ?? "default"];

  const body = (
    <Card className={CARD_CLASS}>
      <Text className="!text-lt-text-muted">{kpi.label}</Text>
      <Metric className={`mt-2 font-display !text-inherit ${accent}`}>
        {kpi.value}
      </Metric>
      {kpi.hint ? (
        <Text className="mt-1 text-xs !text-lt-text-subtle">{kpi.hint}</Text>
      ) : null}
    </Card>
  );

  if (kpi.href) {
    return (
      <Link href={kpi.href} className="block transition-transform hover:scale-[1.01]">
        {body}
      </Link>
    );
  }

  return body;
}

function ChartCard({
  title,
  subtitle,
  children,
}: {
  title: string;
  subtitle?: string;
  children: ReactNode;
}) {
  return (
    <Card className={`${CARD_CLASS} p-4 sm:p-6`}>
      <Title className="font-display !text-lt-text">{title}</Title>
      {subtitle ? (
        <Text className="mt-1 !text-lt-text-muted">{subtitle}</Text>
      ) : null}
      <div className="mt-4">{children}</div>
    </Card>
  );
}

function showsSalesCharts(rol: RolNombre | null): boolean {
  return rol === "admin" || rol === "gerente" || rol === "vendedor";
}

export function DashboardTremor({
  kpis,
  charts,
  rol,
}: {
  kpis: DashboardKpi[];
  charts: DashboardChartsData;
  rol: RolNombre | null;
}) {
  const scopeText = ventaScopeLabel(rol);
  const hasVentasMes = charts.ventasPorMes.some((d) => d.Ventas > 0);
  const salesCharts = showsSalesCharts(rol);

  return (
    <div className="lt-dashboard space-y-6">
      <Grid numItemsSm={2} numItemsLg={4} className="gap-4">
        {kpis.map((kpi) => (
          <KpiCard key={kpi.id} kpi={kpi} />
        ))}
      </Grid>

      {salesCharts ? (
        <>
          <ChartCard
            title="Ventas por mes"
            subtitle={`Últimos 6 meses · ${scopeText}`}
          >
            {hasVentasMes ? (
              <LtVentasMesChart data={charts.ventasPorMes} />
            ) : (
              <ChartEmptyState message="Aún no hay ventas registradas en órdenes liquidadas o en tránsito." />
            )}
          </ChartCard>

          <Grid numItemsMd={1} numItemsLg={2} className="gap-4">
            <ChartCard
              title="Ventas por cliente"
              subtitle={`Top clientes · ${scopeText}`}
            >
              {charts.ventasPorCliente.length > 0 ? (
                <LtMoneyHorizontalChart
                  data={charts.ventasPorCliente}
                  valueLabel="Ventas"
                  multiColor
                />
              ) : (
                <ChartEmptyState message="Sin ventas por cliente en el período." />
              )}
            </ChartCard>

            <ChartCard
              title="Cuentas por cobrar"
              subtitle={`Saldo pendiente · ${scopeText}`}
            >
              {charts.cuentasPorCobrar.length > 0 ? (
                <LtMoneyHorizontalChart
                  data={charts.cuentasPorCobrar}
                  valueLabel="Por cobrar"
                  barColor={CXC_COLOR}
                />
              ) : (
                <ChartEmptyState message="No hay saldos pendientes de cobro." />
              )}
            </ChartCard>
          </Grid>
        </>
      ) : null}
    </div>
  );
}
