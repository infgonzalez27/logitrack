import { PageHeader } from "@/components/layout/page-header";
import { obtenerReporteFormasPagoAction } from "@/lib/actions/reportes";
import { ReportePagosClient } from "./reporte-pagos-client";

export default async function ReporteFormasPagoPage() {
  const hoy = new Date();
  const primerDiaMes = new Date(hoy.getFullYear(), hoy.getMonth(), 1);

  const fechaDesdeInicial = primerDiaMes.toISOString().split("T")[0];
  const fechaHastaInicial = hoy.toISOString().split("T")[0];

  const res = await obtenerReporteFormasPagoAction(fechaDesdeInicial, fechaHastaInicial, false);

  return (
    <div className="space-y-6">
      <PageHeader
        title="Reporte de Formas de Pago"
        description="Consulta e impresión gerencial de recaudaciones por rango de fechas"
      />

      <ReportePagosClient
        initialData={res.data ?? null}
        fechaDesdeInicial={fechaDesdeInicial}
        fechaHastaInicial={fechaHastaInicial}
      />
    </div>
  );
}
