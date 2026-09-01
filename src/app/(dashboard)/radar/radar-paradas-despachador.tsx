import Link from "next/link";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { formatDateOnly, formatNumber } from "@/lib/format";
import type { RadarDetalle, RadarOrden } from "@/types/database";

function paradaEstado(orden: RadarOrden): {
  label: string;
  tone: "success" | "warning" | "neutral";
} {
  const detalles = orden.detalles ?? [];
  if (!detalles.length) return { label: "Sin líneas", tone: "neutral" };
  const pendientes = detalles.filter(
    (d) => (d.estado_entrega ?? "pendiente") === "pendiente",
  );
  if (pendientes.length === 0) return { label: "Completado", tone: "success" };
  const enProceso = detalles.some(
    (d) =>
      d.estado_entrega === "entregado" ||
      d.estado_entrega === "entregado_parcial",
  );
  if (enProceso) return { label: "En proceso", tone: "warning" };
  return { label: "Pendiente", tone: "warning" };
}

function resumenCarga(detalles: RadarDetalle[]): string {
  const items = detalles.reduce(
    (s, d) => s + Number(d.cantidad_solicitada ?? 0),
    0,
  );
  if (!detalles.length) return "Sin productos";
  return `${formatNumber(items)} items · ${detalles.length} SKU`;
}

export function RadarParadasDespachador({ ordenes }: { ordenes: RadarOrden[] }) {
  const fecha =
    ordenes[0]?.fecha_despacho != null
      ? formatDateOnly(ordenes[0].fecha_despacho)
      : "Hoy";

  if (!ordenes.length) {
    return (
      <Card className="p-6 text-center text-sm text-lt-text-muted">
        No hay despachos en tránsito para tus clientes.
      </Card>
    );
  }

  return (
    <div className="space-y-4">
      <Card className="p-4">
        <h2 className="text-lg font-semibold text-lt-text">
          Resumen de ruta · {fecha}
        </h2>
        <p className="mt-1 text-sm text-lt-text-muted">
          {ordenes.length} paradas en tu ruta de hoy.
        </p>
      </Card>

      <ul className="space-y-3">
        {ordenes.map((orden) => {
          const estado = paradaEstado(orden);
          const mapsUrl = orden.cliente.direccion_fiscal
            ? `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(orden.cliente.direccion_fiscal)}`
            : null;

          return (
            <li key={orden.orden_id}>
              <Card className="p-4">
                <div className="flex flex-wrap items-start justify-between gap-2">
                  <div className="min-w-0 flex-1">
                    <p className="font-semibold text-lt-text">
                      {orden.cliente.razon_social}
                    </p>
                    <p className="mt-1 text-sm text-lt-text-muted">
                      Orden #{orden.correlativo}
                      {orden.cliente.nombre_ruta
                        ? ` · ${orden.cliente.nombre_ruta}`
                        : ""}
                    </p>
                    {orden.cliente.direccion_fiscal ? (
                      <p className="mt-1 text-sm text-lt-text-muted">
                        {orden.cliente.direccion_fiscal}
                      </p>
                    ) : null}
                    <p className="mt-2 text-sm font-medium text-lt-text">
                      {resumenCarga(orden.detalles ?? [])}
                    </p>
                  </div>
                  <Badge tone={estado.tone}>{estado.label}</Badge>
                </div>

                <div className="mt-4 flex flex-wrap gap-2">
                  <Button href={`/radar/entrega/${orden.orden_id}`}>
                    Iniciar entrega
                  </Button>
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
                  <Link
                    href={`/ordenes/${orden.orden_id}`}
                    className="inline-flex items-center px-2 py-2.5 text-sm font-medium text-lt-primary"
                  >
                    Ver orden
                  </Link>
                </div>
              </Card>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
