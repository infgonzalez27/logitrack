import { redirect } from "next/navigation";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { reporteFormasPagoRendicionAction } from "@/lib/actions/rendiciones";
import { formatCurrency, formatDate, formatNumber } from "@/lib/format";
import { PageHeader } from "@/components/layout/page-header";
import { PrintButton } from "@/components/print/print-button";
import { Card } from "@/components/ui/card";
import { DataTable } from "@/components/ui/data-table";
import { ReporteFormasPagoFiltros } from "./reporte-formas-pago-filtros";

function defaultDesde(): string {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-01`;
}

function defaultHasta(): string {
  return new Date().toISOString().slice(0, 10);
}

export default async function ReporteFormasPagoPage({
  searchParams,
}: {
  searchParams: Promise<{
    desde?: string;
    hasta?: string;
    bancarios?: string;
  }>;
}) {
  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);
  if (rol !== "admin" && rol !== "gerente") {
    redirect("/rendiciones");
  }

  const sp = await searchParams;
  const desde = (sp.desde?.trim() || defaultDesde()).slice(0, 10);
  const hasta = (sp.hasta?.trim() || defaultHasta()).slice(0, 10);
  const soloBancarios = sp.bancarios === "1";

  const result = await reporteFormasPagoRendicionAction({
    fecha_desde: desde,
    fecha_hasta: hasta,
    solo_bancarios: soloBancarios,
  });

  return (
    <div className="lt-print-document mx-auto max-w-6xl space-y-6">
      <PageHeader
        title="Reporte de formas de pago"
        description="Movimientos de pago en rendiciones aprobadas (§2.42 reporte_formas_pago_rendicion)."
        action={<PrintButton label="Imprimir" />}
      />

      <Card className="lt-no-print space-y-3 p-4">
        <ReporteFormasPagoFiltros
          defaultDesde={desde}
          defaultHasta={hasta}
          defaultSoloBancarios={soloBancarios}
        />
      </Card>

      {!result.ok ? (
        <p className="lt-alert-error">{result.error}</p>
      ) : (
        <>
          <div className="grid gap-3 sm:grid-cols-3">
            <Card className="p-4">
              <p className="text-xs font-medium uppercase tracking-wide text-lt-text-subtle">
                Registros
              </p>
              <p className="mt-1 text-2xl font-bold tabular-nums text-lt-text">
                {formatNumber(result.data.total_registros)}
              </p>
            </Card>
            <Card className="p-4">
              <p className="text-xs font-medium uppercase tracking-wide text-lt-text-subtle">
                Total USD
              </p>
              <p className="mt-1 text-2xl font-bold tabular-nums text-lt-success-text">
                {formatCurrency(result.data.monto_total_usd)}
              </p>
            </Card>
            <Card className="p-4">
              <p className="text-xs font-medium uppercase tracking-wide text-lt-text-subtle">
                Total Bs
              </p>
              <p className="mt-1 text-2xl font-bold tabular-nums text-lt-text">
                {formatNumber(result.data.monto_total_bs)}
              </p>
            </Card>
          </div>

          <p className="text-sm text-lt-text-muted">
            Período {result.data.fecha_desde} → {result.data.fecha_hasta}
            {result.data.solo_bancarios
              ? " · Solo bancarios (Pago móvil, Transferencia, Zelle, Binance)"
              : " · Todas las formas de pago"}
          </p>

          <Card>
            <DataTable
              emptyMessage="No hay movimientos de pago en el rango seleccionado."
              columns={[
                { key: "fecha", label: "Fecha" },
                { key: "cliente", label: "Cliente" },
                { key: "forma", label: "Forma de pago" },
                { key: "ref", label: "Referencia" },
                { key: "usd", label: "USD" },
                { key: "bs", label: "Bs" },
              ]}
              rows={result.data.movimientos.map((m, i) => ({
                id: `${m.rendicion_id}-${m.fpago_id}-${i}`,
                cells: {
                  fecha: formatDate(m.fecha_rendicion),
                  cliente: (
                    <span>
                      <span className="font-medium">{m.cliente_nombre}</span>
                      <span className="block text-xs text-lt-text-muted">
                        {m.cliente_rif}
                      </span>
                    </span>
                  ),
                  forma: (
                    <span className="inline-flex flex-wrap items-center gap-1">
                      {m.fpago_concepto}
                      {m.es_bancario ? (
                        <span className="rounded-md bg-lt-primary-muted px-1.5 py-0.5 text-[10px] font-medium text-lt-primary">
                          Bancario
                        </span>
                      ) : null}
                    </span>
                  ),
                  ref: m.referencia_bancaria || m.cuenta_bancaria || "—",
                  usd: (
                    <span className="tabular-nums">
                      {formatCurrency(Number(m.monto_usd ?? 0))}
                    </span>
                  ),
                  bs: (
                    <span className="tabular-nums">
                      {formatNumber(Number(m.monto_bs ?? 0))}
                    </span>
                  ),
                },
              }))}
            />
          </Card>
        </>
      )}
    </div>
  );
}
