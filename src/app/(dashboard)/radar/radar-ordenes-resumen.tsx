import Link from "next/link";
import { Card } from "@/components/ui/card";
import { formatNumber } from "@/lib/format";
import type { RadarOrdenResumen } from "@/types/database";

export function RadarOrdenesResumen({
  ordenes,
  radarId,
  modoDespachador,
}: {
  ordenes: RadarOrdenResumen[];
  radarId?: string;
  modoDespachador?: boolean;
}) {
  if (!ordenes.length) {
    return (
      <Card className="p-6 text-center text-sm text-lt-text-muted">
        Este radar no tiene órdenes de distribución.
      </Card>
    );
  }

  return (
    <div className="overflow-x-auto rounded-2xl border border-lt-border bg-lt-surface">
      <table className="w-full min-w-[44rem] text-left text-sm">
        <thead className="border-b border-lt-border bg-lt-surface-muted text-lt-text-muted">
          <tr>
            <th className="px-4 py-3 font-medium">Orden</th>
            <th className="px-4 py-3 font-medium">Ruta</th>
            <th className="px-4 py-3 font-medium">Cliente</th>
            <th className="px-4 py-3 font-medium">Dirección</th>
            <th className="px-4 py-3 font-medium text-right">Cant. Despachada</th>
            <th className="px-4 py-3 font-medium text-right">SKU</th>
            <th className="px-4 py-3 font-medium text-right">Cont.</th>
          </tr>
        </thead>
        <tbody>
          {ordenes.map((o) => {
            const href =
              modoDespachador && radarId
                ? `/radar/${radarId}/entrega/${o.id_orden_distribucion}`
                : `/ordenes/${o.id_orden_distribucion}`;
            return (
              <tr
                key={o.id_orden_distribucion}
                className="border-b border-lt-border-light last:border-0"
              >
                <td className="px-4 py-3">
                  <Link
                    href={href}
                    className="font-semibold text-lt-primary hover:underline"
                  >
                    #{o.correlativo}
                  </Link>
                </td>
                <td className="px-4 py-3 text-lt-text">{o.ruta || "—"}</td>
                <td className="px-4 py-3 font-medium text-lt-text">
                  {o.razon_social || "—"}
                </td>
                <td className="max-w-[14rem] truncate px-4 py-3 text-lt-text-muted">
                  {o.direccion_fiscal || "—"}
                </td>
                <td className="px-4 py-3 text-right tabular-nums">
                  {formatNumber(o.items)}
                </td>
                <td className="px-4 py-3 text-right tabular-nums">
                  {formatNumber(o.sku)}
                </td>
                <td className="px-4 py-3 text-right tabular-nums">
                  {formatNumber(o.contenedores_retirados)}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
