import Link from "next/link";
import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { formatDateOnly, formatNumber } from "@/lib/format";
import type { RadarListaRangoItem } from "@/types/database";

export function RadarLista({ items }: { items: RadarListaRangoItem[] }) {
  if (!items.length) {
    return (
      <Card className="p-6 text-center text-sm text-lt-text-muted">
        No hay radares en el rango de fechas seleccionado.
      </Card>
    );
  }

  return (
    <div className="overflow-x-auto rounded-2xl border border-lt-border bg-lt-surface">
      <table className="w-full min-w-[40rem] text-left text-sm">
        <thead className="border-b border-lt-border bg-lt-surface-muted text-lt-text-muted">
          <tr>
            <th className="px-4 py-3 font-medium">Fecha</th>
            <th className="px-4 py-3 font-medium">ID Radar</th>
            <th className="px-4 py-3 font-medium text-right">Paradas</th>
            <th className="px-4 py-3 font-medium text-right">Cant. Despachada</th>
            <th className="px-4 py-3 font-medium text-right">SKU</th>
            <th className="px-4 py-3 font-medium">Estado</th>
          </tr>
        </thead>
        <tbody>
          {items.map((r) => (
            <tr
              key={r.id_radar}
              className="border-b border-lt-border-light last:border-0"
            >
              <td className="px-4 py-3 text-lt-text">
                {formatDateOnly(r.fecha_despacho)}
              </td>
              <td className="px-4 py-3">
                <Link
                  href={`/radar/${r.id_radar}`}
                  className="font-semibold text-lt-primary hover:underline"
                >
                  #{r.correlativo}
                </Link>
              </td>
              <td className="px-4 py-3 text-right tabular-nums text-lt-text">
                {formatNumber(r.total_paradas)}
              </td>
              <td className="px-4 py-3 text-right tabular-nums text-lt-text">
                {formatNumber(r.items)}
              </td>
              <td className="px-4 py-3 text-right tabular-nums text-lt-text">
                {formatNumber(r.sku)}
              </td>
              <td className="px-4 py-3">
                <div className="flex flex-wrap gap-1">
                  <Badge tone={r.status_radar ? "success" : "warning"}>
                    {r.status_radar ? "Despachado" : "Pendiente"}
                  </Badge>
                  {r.aprobado ? (
                    <Badge tone="success">Aprobado</Badge>
                  ) : null}
                </div>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
