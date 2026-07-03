import { PageHeader } from "@/components/layout/page-header";
import { DashboardTremor } from "@/components/dashboard/dashboard-tremor";
import type { DashboardChartsData } from "@/lib/dashboard/charts";
import type { DashboardKpi } from "@/lib/dashboard/kpis";
import type { RolNombre } from "@/lib/auth/roles";

export function RoleDashboard({
  title,
  description,
  kpis,
  charts,
  rol,
}: {
  title: string;
  description?: string;
  kpis: DashboardKpi[];
  charts: DashboardChartsData;
  rol: RolNombre | null;
}) {
  return (
    <div className="space-y-6">
      <PageHeader title={title} description={description} />
      <DashboardTremor kpis={kpis} charts={charts} rol={rol} />
    </div>
  );
}
