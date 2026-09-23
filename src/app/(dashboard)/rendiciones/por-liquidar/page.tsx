import { redirect } from "next/navigation";
import Link from "next/link";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { retornaOrdenesPorLiquidarAction } from "@/lib/actions/rendiciones";
import { formatCurrency, formatNumber } from "@/lib/format";
import { PageHeader } from "@/components/layout/page-header";
import { PrintButton } from "@/components/print/print-button";
import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";

export default async function OrdenesPorLiquidarPage() {
  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);

  if (
    rol !== "admin" &&
    rol !== "gerente" &&
    rol !== "vendedor" &&
    rol !== "cobrador"
  ) {
    redirect("/");
  }

  const result = await retornaOrdenesPorLiquidarAction();
  const items = result.ok ? result.items : [];
  const totalMonto = items.reduce((s, i) => s + i.monto_por_liquidar, 0);
  const totalOrdenes = items.reduce((s, i) => s + i.cant_ordenes, 0);

  return (
    <div className="lt-print-document mx-auto max-w-5xl space-y-6">
      <PageHeader
        title="Órdenes por liquidar"
        description="Cartera por cliente (días vencidos y montos desde el SP)."
        action={
          <div className="flex flex-wrap gap-2">
            <PrintButton label="Imprimir" />
            <Link
              href="/rendiciones/nuevo"
              className="lt-no-print inline-flex items-center justify-center rounded-xl bg-lt-primary px-4 py-2 text-sm font-medium text-white hover:opacity-90"
            >
              Nueva cobranza
            </Link>
          </div>
        }
      />

      {!result.ok ? (
        <p className="lt-alert-error">{result.error}</p>
      ) : null}

      {!items.length ? (
        <Card className="px-4 py-8 text-center text-sm text-lt-text-muted">
          No hay órdenes en estado por liquidar.
        </Card>
      ) : (
        <div className="grid gap-4 sm:grid-cols-2">
          {items.map((row) => (
            <article
              key={row.cliente_id}
              className="flex flex-col rounded-2xl border border-lt-border bg-lt-surface p-4 shadow-sm"
            >
              <h3 className="text-lg font-bold text-lt-text">
                {row.razon_social}
              </h3>
              <p className="text-sm text-lt-text-muted">{row.rif_nit}</p>
              <dl className="mt-3 flex-1 space-y-2 text-sm">
                <div className="flex items-start justify-between gap-3">
                  <dt className="text-lt-text-muted">Días vencidos:</dt>
                  <dd className="text-right font-medium tabular-nums text-lt-text">
                    {formatNumber(row.dias_vencidos)}
                  </dd>
                </div>
                <div className="flex items-start justify-between gap-3">
                  <dt className="text-lt-text-muted">Cant. órdenes:</dt>
                  <dd className="text-right tabular-nums text-lt-text">
                    {formatNumber(row.cant_ordenes)}
                  </dd>
                </div>
                <div className="flex items-start justify-between gap-3">
                  <dt className="text-lt-text-muted">Monto por liquidar:</dt>
                  <dd className="text-right">
                    <Badge tone="warning">
                      {formatCurrency(row.monto_por_liquidar)}
                    </Badge>
                  </dd>
                </div>
              </dl>
              <div className="mt-4 flex justify-end">
                <Link
                  href={`/clientes/${row.cliente_id}/visita`}
                  className="lt-no-print inline-flex items-center justify-center rounded-xl bg-lt-primary px-4 py-2 text-sm font-medium text-white hover:opacity-90"
                >
                  Ver detalle
                </Link>
              </div>
            </article>
          ))}
        </div>
      )}

      {items.length ? (
        <p className="text-sm text-lt-text-muted">
          {formatNumber(items.length)} cliente
          {items.length === 1 ? "" : "s"} · {formatNumber(totalOrdenes)}{" "}
          orden
          {totalOrdenes === 1 ? "" : "es"} · Total{" "}
          <span className="font-semibold text-lt-text">
            {formatCurrency(totalMonto)}
          </span>
        </p>
      ) : null}
    </div>
  );
}
