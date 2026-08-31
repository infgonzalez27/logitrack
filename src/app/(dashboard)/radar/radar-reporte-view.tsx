"use client";

import Link from "next/link";
import { Badge, ordenEstadoTone } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { labelOrdenEstado } from "@/lib/constants";
import { formatDateOnly, formatNumber } from "@/lib/format";
import type { OrdenEstado, RadarDetalleReporte } from "@/types/database";

export function RadarReporteView({ reporte }: { reporte: RadarDetalleReporte }) {
  const { radar, despachador, resumen_productos, ordenes } = reporte;
  const ordenId = (o: (typeof ordenes)[number]) =>
    String(o.orden_id ?? o.id ?? "");
  const clienteNombre = (o: (typeof ordenes)[number]) =>
    o.cliente?.razon_social ??
    (o.cliente as { nombre?: string } | undefined)?.nombre ??
    "Cliente";

  return (
    <div className="space-y-4 print:space-y-3">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 className="text-lg font-semibold text-lt-text">
            Radar #{radar.correlativo}
          </h2>
          <p className="text-sm text-lt-text-muted">
            {formatDateOnly(radar.fecha_despacho)} ·{" "}
            {despachador.nombre_completo}
            {radar.status_radar ? " · Despacho registrado" : " · Pendiente de ruta"}
          </p>
        </div>
        <Button
          type="button"
          variant="secondary"
          className="print:hidden"
          onClick={() => window.print()}
        >
          Imprimir reporte
        </Button>
      </div>

      <div className="grid gap-3 sm:grid-cols-3">
        <Card className="p-3">
          <p className="text-xs text-lt-text-muted">Solicitado</p>
          <p className="text-xl font-semibold">
            {formatNumber(Number(radar.total_cantidad_solicitada ?? 0))}
          </p>
        </Card>
        <Card className="p-3">
          <p className="text-xs text-lt-text-muted">Despachado</p>
          <p className="text-xl font-semibold">
            {formatNumber(Number(radar.total_cantidad_despachada ?? 0))}
          </p>
        </Card>
        <Card className="p-3">
          <p className="text-xs text-lt-text-muted">Contenedores retirados</p>
          <p className="text-xl font-semibold">
            {formatNumber(Number(radar.total_contenedores_retirados ?? 0))}
          </p>
        </Card>
      </div>

      <Card className="overflow-hidden p-0">
        <div className="border-b border-lt-border px-4 py-3">
          <h3 className="font-medium text-lt-text">Resumen de productos</h3>
        </div>
        <div className="overflow-x-auto">
          <table className="min-w-full text-sm">
            <thead className="bg-lt-surface-muted text-left text-lt-text-muted">
              <tr>
                <th className="px-4 py-2 font-medium">Producto</th>
                <th className="px-4 py-2 font-medium">Solicitado</th>
                <th className="px-4 py-2 font-medium">Despachado</th>
              </tr>
            </thead>
            <tbody>
              {(resumen_productos ?? []).map((p) => (
                <tr key={p.producto_id} className="border-t border-lt-border">
                  <td className="px-4 py-2">
                    <span className="font-medium">{p.nombre_producto}</span>
                    {p.codigo_producto ? (
                      <span className="ml-2 text-lt-text-muted">
                        {p.codigo_producto}
                      </span>
                    ) : null}
                  </td>
                  <td className="px-4 py-2">
                    {formatNumber(Number(p.cantidad_solicitada))}
                  </td>
                  <td className="px-4 py-2">
                    {formatNumber(Number(p.cantidad_despachada))}
                  </td>
                </tr>
              ))}
              {!resumen_productos?.length ? (
                <tr>
                  <td
                    colSpan={3}
                    className="px-4 py-6 text-center text-lt-text-muted"
                  >
                    Sin productos vinculados a este radar.
                  </td>
                </tr>
              ) : null}
            </tbody>
          </table>
        </div>
      </Card>

      <Card className="space-y-3 p-4">
        <h3 className="font-medium text-lt-text">Órdenes del radar</h3>
        <ul className="divide-y divide-lt-border">
          {(ordenes ?? []).map((o) => {
            const id = ordenId(o);
            const estado = String(o.estado ?? "");
            return (
              <li
                key={id || String(o.correlativo)}
                className="flex flex-wrap items-center justify-between gap-2 py-3"
              >
                <div>
                  <p className="font-medium text-lt-text">
                    #{o.correlativo ?? "—"} · {clienteNombre(o)}
                  </p>
                  {o.cliente?.rif_nit ? (
                    <p className="text-xs text-lt-text-muted">
                      {o.cliente.rif_nit}
                    </p>
                  ) : null}
                </div>
                <div className="flex items-center gap-2">
                  {estado ? (
                    <Badge tone={ordenEstadoTone(estado as OrdenEstado)}>
                      {labelOrdenEstado(estado as OrdenEstado)}
                    </Badge>
                  ) : null}
                  {id ? (
                    <Link
                      href={`/ordenes/${id}`}
                      className="text-sm font-medium text-lt-primary print:hidden"
                    >
                      Ver orden
                    </Link>
                  ) : null}
                </div>
              </li>
            );
          })}
          {!ordenes?.length ? (
            <li className="py-4 text-center text-sm text-lt-text-muted">
              No hay órdenes para esta fecha y despachador. Revisa que las
              órdenes tengan la misma fecha de entrega y cliente con ese
              despachador.
            </li>
          ) : null}
        </ul>
      </Card>
    </div>
  );
}
