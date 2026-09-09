import { redirect } from "next/navigation";
import Link from "next/link";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { retornaOrdenesPorLiquidarAction } from "@/lib/actions/rendiciones";
import { formatCurrency, formatNumber } from "@/lib/format";
import { PageHeader } from "@/components/layout/page-header";
import { PrintButton } from "@/components/print/print-button";
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

  return (
    <div className="lt-print-document mx-auto max-w-5xl space-y-6">
      <PageHeader
        title="Órdenes por liquidar"
        description="Órdenes pendientes de liquidación."
        action={
          <div className="flex flex-wrap gap-2">
            <PrintButton label="Imprimir" />
            <Link
              href="/rendiciones/nuevo"
              className="lt-no-print inline-flex items-center justify-center rounded-xl bg-lt-primary px-4 py-2 text-sm font-medium text-white hover:opacity-90"
            >
              Nueva rendición
            </Link>
          </div>
        }
      />

      {!result.ok ? (
        <p className="lt-alert-error">{result.error}</p>
      ) : null}

      <Card className="overflow-hidden p-0">
        <div className="overflow-x-auto">
          <table className="w-full min-w-[36rem] text-left text-sm">
            <thead className="border-b border-lt-border bg-lt-surface-muted text-lt-text-muted">
              <tr>
                <th className="px-4 py-3 font-medium">Id</th>
                <th className="px-4 py-3 font-medium">Cliente</th>
                <th className="px-4 py-3 font-medium text-right">
                  Días vencidos
                </th>
                <th className="px-4 py-3 font-medium text-right">
                  Monto por liquidar
                </th>
              </tr>
            </thead>
            <tbody>
              {!items.length ? (
                <tr>
                  <td
                    colSpan={4}
                    className="px-4 py-8 text-center text-lt-text-muted"
                  >
                    No hay órdenes en estado por liquidar.
                  </td>
                </tr>
              ) : (
                items.map((row) => (
                  <tr
                    key={row.orden_id}
                    className="border-b border-lt-border-light last:border-0"
                  >
                    <td className="px-4 py-3 font-medium text-lt-text">
                      <Link
                        href={`/ordenes/${row.orden_id}`}
                        className="text-lt-primary hover:underline print:text-lt-text print:no-underline"
                      >
                        #{row.correlativo}
                      </Link>
                    </td>
                    <td className="px-4 py-3 text-lt-text">{row.razon_social}</td>
                    <td className="px-4 py-3 text-right tabular-nums text-lt-text">
                      {formatNumber(row.dias_vencidos)}
                    </td>
                    <td className="px-4 py-3 text-right tabular-nums font-medium text-lt-text">
                      {formatCurrency(row.monto_por_liquidar)}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
            {items.length ? (
              <tfoot className="border-t border-lt-border bg-lt-surface-muted font-semibold">
                <tr>
                  <td className="px-4 py-3" colSpan={3}>
                    Totales ({formatNumber(items.length)} órdenes)
                  </td>
                  <td className="px-4 py-3 text-right tabular-nums">
                    {formatCurrency(totalMonto)}
                  </td>
                </tr>
              </tfoot>
            ) : null}
          </table>
        </div>
      </Card>
    </div>
  );
}
