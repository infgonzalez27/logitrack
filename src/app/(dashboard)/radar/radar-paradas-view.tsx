import Link from "next/link";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { formatDateOnly, formatNumber } from "@/lib/format";
import type { RadarDetalle, RadarDetalleReporte } from "@/types/database";

type ParadaOrden = RadarDetalleReporte["ordenes"][number];

function ordenId(o: ParadaOrden): string {
  return String(o.orden_id ?? o.id ?? "");
}

function clienteNombre(o: ParadaOrden): string {
  return o.cliente?.razon_social ?? "Cliente";
}

function paradaEstado(o: ParadaOrden): {
  label: string;
  tone: "success" | "warning" | "neutral" | "danger";
} {
  const detalles = (o.detalles ?? []) as RadarDetalle[];
  if (!detalles.length) {
    return { label: "Sin líneas", tone: "neutral" };
  }
  const pendientes = detalles.filter(
    (d) => (d.estado_entrega ?? "pendiente") === "pendiente",
  );
  if (pendientes.length === 0) {
    return { label: "Completado", tone: "success" };
  }
  const parciales = detalles.some(
    (d) =>
      d.estado_entrega === "entregado_parcial" ||
      d.estado_entrega === "entregado",
  );
  if (parciales) {
    return { label: "En proceso", tone: "warning" };
  }
  return { label: "Pendiente", tone: "warning" };
}

function resumenCarga(o: ParadaOrden): string {
  const detalles = (o.detalles ?? []) as RadarDetalle[];
  const items = detalles.reduce(
    (s, d) => s + Number(d.cantidad_solicitada ?? 0),
    0,
  );
  const skus = detalles.length;
  if (!skus) return "Sin productos";
  return `${formatNumber(items)} items · ${skus} SKU`;
}

export function RadarParadasView({
  reporte,
  radarId,
  modoDespachador = false,
}: {
  reporte: RadarDetalleReporte;
  radarId: string;
  modoDespachador?: boolean;
}) {
  const { radar, despachador, ordenes } = reporte;

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 className="text-lg font-semibold text-lt-text">
            Radar de despacho · {formatDateOnly(radar.fecha_despacho)}
          </h2>
          <p className="text-sm text-lt-text-muted">
            {despachador.nombre_completo} · #{radar.correlativo}
          </p>
        </div>
        {!modoDespachador ? (
          <Button variant="secondary" href="/radar">
            Volver al listado
          </Button>
        ) : null}
      </div>

      <Card className="p-4">
        <h3 className="font-medium text-lt-text">
          Paradas del día ({ordenes?.length ?? 0})
        </h3>
        <p className="mt-1 text-sm text-lt-text-muted">
          Cada parada es un cliente a visitar en la ruta.
        </p>
      </Card>

      <ul className="space-y-3">
        {(ordenes ?? []).map((o) => {
          const id = ordenId(o);
          const estado = paradaEstado(o);
          const mapsUrl = o.cliente?.direccion_fiscal
            ? `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(o.cliente.direccion_fiscal)}`
            : null;

          return (
            <li key={id || String(o.correlativo)}>
              <Card className="p-4">
                <div className="flex flex-wrap items-start justify-between gap-2">
                  <div className="min-w-0 flex-1">
                    <p className="font-semibold text-lt-text">
                      {clienteNombre(o)}
                    </p>
                    <p className="mt-1 text-sm text-lt-text-muted">
                      Orden #{o.correlativo ?? "—"}
                      {o.cliente?.nombre_ruta
                        ? ` · ${o.cliente.nombre_ruta}`
                        : ""}
                    </p>
                    {o.cliente?.direccion_fiscal ? (
                      <p className="mt-1 text-sm text-lt-text-muted">
                        {o.cliente.direccion_fiscal}
                      </p>
                    ) : null}
                    <p className="mt-2 text-sm font-medium text-lt-text">
                      {resumenCarga(o)}
                    </p>
                  </div>
                  <Badge tone={estado.tone}>{estado.label}</Badge>
                </div>

                <div className="mt-4 flex flex-wrap gap-2">
                  {modoDespachador && id ? (
                    <Button href={`/radar/${radarId}/entrega/${id}`}>
                      Iniciar entrega
                    </Button>
                  ) : null}
                  {mapsUrl ? (
                    <a
                      href={mapsUrl}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="lt-btn inline-flex items-center rounded-xl border border-lt-border px-4 py-2.5 text-sm font-medium text-lt-text hover:bg-lt-surface-muted"
                    >
                      Navegar
                    </a>
                  ) : null}
                  {id && !modoDespachador ? (
                    <Link
                      href={`/ordenes/${id}`}
                      className="text-sm font-medium text-lt-primary"
                    >
                      Ver orden
                    </Link>
                  ) : null}
                </div>
              </Card>
            </li>
          );
        })}
        {!ordenes?.length ? (
          <li>
            <Card className="p-6 text-center text-sm text-lt-text-muted">
              No hay clientes en este radar. Verifica que existan órdenes con la
              misma fecha de entrega y despachador del cliente.
            </Card>
          </li>
        ) : null}
      </ul>
    </div>
  );
}
