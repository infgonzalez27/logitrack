import { redirect } from "next/navigation";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { reporteFormasPagoRendicionAction } from "@/lib/actions/rendiciones";
import { formatCurrency, formatDate, formatNumber } from "@/lib/format";
import { PageHeader } from "@/components/layout/page-header";
import { Card } from "@/components/ui/card";
import { DataTable } from "@/components/ui/data-table";
import { ReporteFormasPagoFiltros } from "./reporte-formas-pago-filtros";
import { ExportFormasPagoExcelButton } from "./export-formas-pago-excel-button";

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
    <div className="mx-auto max-w-6xl space-y-4">
      <PageHeader
        title="Reporte de formas de pago"
        description="Movimientos de pago en rendiciones aprobadas (§2.42 reporte_formas_pago_rendicion)."
        action={
          result.ok ? (
            <ExportFormasPagoExcelButton data={result.data} />
          ) : undefined
        }
      />

      <Card className="lt-no-print space-y-3 p-3">
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
          <div className="flex items-center justify-between text-xs text-lt-text-muted">
            <span>
              Período {result.data.fecha_desde} → {result.data.fecha_hasta}
              {result.data.solo_bancarios
                ? " · Solo bancarios"
                : " · Todas las formas de pago"}
            </span>
            <span>{formatNumber(result.data.total_registros)} registros</span>
          </div>

          <Card className="overflow-hidden">
            <DataTable
              emptyMessage="No hay movimientos de pago en el rango seleccionado."
              columns={[
                { key: "fecha", label: "Fecha" },
                { key: "cliente", label: "Cliente" },
                { key: "forma", label: "Forma de pago" },
                { key: "ref", label: "Referencia / Cuenta" },
                { key: "usd", label: "USD" },
                { key: "bs", label: "Bs" },
              ]}
              rows={result.data.movimientos.map((m, i) => ({
                id: `${m.rendicion_id}-${m.fpago_id}-${i}`,
                cells: {
                  fecha: (
                    <span className="text-xs">{formatDate(m.fecha_rendicion)}</span>
                  ),
                  cliente: (
                    <span className="text-xs">
                      <span className="font-medium text-lt-text">{m.cliente_nombre}</span>
                      <span className="block text-[11px] text-lt-text-muted">
                        {m.cliente_rif}
                      </span>
                    </span>
                  ),
                  forma: (
                    <span className="inline-flex flex-wrap items-center gap-1 text-xs">
                      {m.fpago_concepto}
                      {m.es_bancario ? (
                        <span className="rounded bg-lt-primary-muted px-1.5 py-0.5 text-[10px] font-medium text-lt-primary">
                          Bancario
                        </span>
                      ) : null}
                    </span>
                  ),
                  ref: (
                    <span className="text-xs text-lt-text-muted">
                      {m.referencia_bancaria
                        ? `${m.codigo_banco ? `${m.codigo_banco}-` : ""}${m.referencia_bancaria}${m.nombre_banco ? ` (${m.nombre_banco})` : ""}`
                        : m.cuenta_bancaria || "—"}
                    </span>
                  ),
                  usd: (
                    <span className="text-xs font-semibold tabular-nums text-lt-success-text">
                      {formatCurrency(Number(m.monto_usd ?? 0))}
                    </span>
                  ),
                  bs: (
                    <span className="text-xs tabular-nums text-lt-text">
                      {formatNumber(Number(m.monto_bs ?? 0))}
                    </span>
                  ),
                },
              }))}
            />
          </Card>

          {/* Resumen al final con puros montos totales */}
          <div className="flex flex-wrap items-center justify-end gap-3 pt-2">
            <div className="flex items-center gap-4 rounded-xl border border-lt-border bg-lt-surface px-4 py-2.5 shadow-xs">
              <span className="text-xs font-semibold uppercase tracking-wider text-lt-text-muted">
                Totales Generales:
              </span>
              <div className="flex items-baseline gap-1.5 border-l border-lt-border pl-4">
                <span className="text-xs text-lt-text-muted">Total USD:</span>
                <span className="text-base font-bold tabular-nums text-lt-success-text">
                  {formatCurrency(result.data.monto_total_usd)}
                </span>
              </div>
              <div className="flex items-baseline gap-1.5 border-l border-lt-border pl-4">
                <span className="text-xs text-lt-text-muted">Total Bs:</span>
                <span className="text-base font-bold tabular-nums text-lt-text">
                  Bs. {formatNumber(result.data.monto_total_bs)}
                </span>
              </div>
            </div>
          </div>
        </>
      )}
    </div>
  );
}
