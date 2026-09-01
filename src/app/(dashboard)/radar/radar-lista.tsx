import Link from "next/link";
import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { formatDateOnly, formatNumber } from "@/lib/format";
import type { RadarListaItem } from "@/types/database";

export function RadarLista({ radares }: { radares: RadarListaItem[] }) {
  if (!radares.length) {
    return (
      <Card className="p-6 text-center text-sm text-lt-text-muted">
        No hay radares registrados. Crea uno con fecha y despachador.
      </Card>
    );
  }

  return (
    <div className="space-y-3">
      {radares.map((r) => (
        <Link
          key={r.id}
          href={`/radar/${r.id}`}
          className="block rounded-2xl border border-lt-border bg-lt-surface p-4 transition-colors hover:border-lt-primary-pastel hover:bg-lt-surface-muted"
        >
          <div className="flex flex-wrap items-start justify-between gap-2">
            <div>
              <p className="font-semibold text-lt-text">
                Radar #{r.correlativo}
              </p>
              <p className="mt-1 text-sm text-lt-text-muted">
                {formatDateOnly(r.fecha_despacho)} · {r.despachador_nombre}
              </p>
            </div>
            <Badge tone={r.status_radar ? "success" : "warning"}>
              {r.status_radar ? "Despachado" : "Pendiente"}
            </Badge>
          </div>
          <div className="mt-3 flex flex-wrap gap-4 text-sm text-lt-text-muted">
            <span>{r.total_ordenes} clientes</span>
            <span>
              Solicitado: {formatNumber(r.total_cantidad_solicitada)}
            </span>
            <span>
              Despachado: {formatNumber(r.total_cantidad_despachada)}
            </span>
          </div>
        </Link>
      ))}
    </div>
  );
}
