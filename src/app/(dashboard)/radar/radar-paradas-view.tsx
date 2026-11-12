"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { quitarOrdenDeRadarAction } from "@/lib/actions/radar";
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
    const todosRechazados = detalles.every(
      (d) => d.estado_entrega === "rechazado",
    );
    if (todosRechazados) {
      return { label: "Devuelta", tone: "danger" };
    }
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
  return `${formatNumber(items)} Cant. Despachada · ${skus} SKU`;
}

export function RadarParadasView({
  reporte,
  radarId,
  modoDespachador = false,
  puedeEditarRadar = false,
  yaAprobado = false,
  cargaInventarioMovil = false,
}: {
  reporte: RadarDetalleReporte;
  radarId: string;
  modoDespachador?: boolean;
  puedeEditarRadar?: boolean;
  yaAprobado?: boolean;
  cargaInventarioMovil?: boolean;
}) {
  const { radar, despachador, ordenes } = reporte;
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [quitandoId, setQuitandoId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  const radarFechaIso = String(radar.fecha_despacho ?? "").slice(0, 10);

  function onQuitarOrden(o: ParadaOrden) {
    const id = ordenId(o);
    if (!id || yaAprobado || cargaInventarioMovil) return;

    const ok = window.confirm(
      `¿Quitar la Orden #${o.correlativo ?? ""} de este radar?\nLa orden seguirá en estado Aprobada y se incluirá automáticamente cuando se cree un nuevo radar.`,
    );
    if (!ok) return;

    setError(null);
    setSuccess(null);
    setQuitandoId(id);
    startTransition(async () => {
      const result = await quitarOrdenDeRadarAction({
        radar_id: radarId,
        orden_id: id,
      });
      setQuitandoId(null);
      if (!result.ok) {
        setError(result.error);
        return;
      }
      setSuccess(
        result.message ??
          `Orden #${o.correlativo ?? ""} retirada del radar y mantenida como aprobada.`,
      );
      router.refresh();
    });
  }

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

      {error ? <p className="lt-alert-error text-sm">{error}</p> : null}
      {success ? <p className="lt-alert-success text-sm">{success}</p> : null}

      <ul className="space-y-3">
        {(ordenes ?? []).map((o) => {
          const id = ordenId(o);
          const estado = paradaEstado(o);
          const mapsUrl = o.cliente?.direccion_fiscal
            ? `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(o.cliente.direccion_fiscal)}`
            : null;
          const pendientes = ((o.detalles ?? []) as RadarDetalle[]).some(
            (d) => (d.estado_entrega ?? "pendiente") === "pendiente",
          );
          const ordenFechaIso = String(o.fecha_despacho ?? "").slice(0, 10);
          const esFechaAnterior =
            Boolean(ordenFechaIso && radarFechaIso) &&
            ordenFechaIso < radarFechaIso;
          const esOrdenAprobada =
            String(o.estado ?? "aprobada").toLowerCase() === "aprobada";
          const mostrarQuitar =
            puedeEditarRadar && !modoDespachador && !yaAprobado && esOrdenAprobada && Boolean(id);

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
                      {o.fecha_despacho
                        ? ` · Fecha: ${formatDateOnly(o.fecha_despacho)}`
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
                  <div className="flex flex-wrap items-center gap-1.5">
                    {esFechaAnterior ? (
                      <Badge tone="warning">
                        Fecha anterior ({formatDateOnly(o.fecha_despacho)})
                      </Badge>
                    ) : null}
                    <Badge tone={estado.tone}>{estado.label}</Badge>
                  </div>
                </div>

                <div className="mt-4 flex flex-wrap items-center gap-2">
                  {modoDespachador && id && pendientes ? (
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
                  {mostrarQuitar ? (
                    <Button
                      type="button"
                      variant="secondary"
                      className="border-amber-600/40 text-amber-700 hover:bg-amber-50 dark:border-amber-500/40 dark:text-amber-400 dark:hover:bg-amber-950/20"
                      disabled={pending || cargaInventarioMovil}
                      onClick={() => onQuitarOrden(o)}
                      title={
                        cargaInventarioMovil
                          ? "Primero reversa el inventario móvil al almacén para quitar órdenes del radar"
                          : "Quitar orden de este radar y mantenerla aprobada"
                      }
                    >
                      {quitandoId === id ? "Quitando…" : "Quitar del radar"}
                    </Button>
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
