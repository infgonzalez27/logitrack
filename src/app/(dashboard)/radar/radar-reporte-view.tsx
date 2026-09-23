"use client";

import { Button } from "@/components/ui/button";
import { formatNumber } from "@/lib/format";
import type { RadarDetalleReporte } from "@/types/database";

/** Fecha dd/mm/yyyy como en Ejemplo_radar.docx */
function formatFechaDespacho(value: string | null | undefined): string {
  if (!value) return "—";
  const d = new Date(value.includes("T") ? value : `${value}T12:00:00`);
  if (Number.isNaN(d.getTime())) return value;
  const dd = String(d.getDate()).padStart(2, "0");
  const mm = String(d.getMonth() + 1).padStart(2, "0");
  const yyyy = d.getFullYear();
  return `${dd}/${mm}/${yyyy}`;
}

type OrdenReporte = RadarDetalleReporte["ordenes"][number];
type DetalleReporte = NonNullable<OrdenReporte["detalles"]>[number];

function clienteNombre(o: OrdenReporte): string {
  return (
    o.cliente?.razon_social ??
    (o.cliente as { nombre?: string } | undefined)?.nombre ??
    "Cliente"
  );
}

function detallesOrden(o: OrdenReporte): DetalleReporte[] {
  const raw = Array.isArray(o.detalles) ? o.detalles : [];
  return [...raw].sort((a, b) =>
    String(a.nombre_producto ?? "").localeCompare(
      String(b.nombre_producto ?? ""),
      "es",
    ),
  );
}

/**
 * Reporte de carga del radar — layout alineado a Ejemplo_radar.docx:
 * Radar # · Fecha · bloques Cliente (Producto / Cantidad solicitada) · Resumen.
 */
export function RadarReporteView({ reporte }: { reporte: RadarDetalleReporte }) {
  const { radar, despachador, resumen_productos, ordenes } = reporte;

  const ordenesOrdenadas = [...(ordenes ?? [])].sort((a, b) =>
    clienteNombre(a).localeCompare(clienteNombre(b), "es"),
  );

  const resumen = [...(resumen_productos ?? [])].sort(
    (a, b) =>
      Number(b.cantidad_solicitada) - Number(a.cantidad_solicitada) ||
      String(a.nombre_producto).localeCompare(String(b.nombre_producto), "es"),
  );

  return (
    <div className="lt-print-document space-y-6 print:space-y-4">
      <div className="flex flex-wrap items-start justify-between gap-3 print:hidden">
        <div>
          <p className="text-sm text-lt-text-muted">
            Formato de carga / picking del radar
          </p>
          {despachador?.nombre_completo ? (
            <p className="text-sm text-lt-text-muted">
              Despachador: {despachador.nombre_completo}
            </p>
          ) : null}
        </div>
        <Button
          type="button"
          variant="secondary"
          onClick={() => window.print()}
        >
          Imprimir reporte
        </Button>
      </div>

      <article className="radar-carga-report rounded-xl border border-lt-border bg-lt-surface p-5 text-lt-text print:rounded-none print:border-0 print:bg-transparent print:p-0">
        <header className="lt-print-keep-together space-y-1 border-b border-lt-border pb-4 print:border-black">
          <h2 className="font-display text-2xl font-bold tracking-tight">
            Radar # {radar.correlativo}
          </h2>
          <p className="text-base">
            Fecha de despacho {formatFechaDespacho(radar.fecha_despacho)}
          </p>
          {despachador?.nombre_completo ? (
            <p className="text-sm text-lt-text-muted print:text-black">
              Despachador: {despachador.nombre_completo}
            </p>
          ) : null}
        </header>

        <div className="mt-6 space-y-8 print:mt-4 print:space-y-6">
          {ordenesOrdenadas.map((o) => {
            const id = String(o.orden_id ?? o.id ?? o.correlativo ?? "");
            const lineas = detallesOrden(o);
            return (
              <section
                key={id}
                className="lt-print-keep-together space-y-2 break-inside-avoid"
              >
                <h3 className="text-base font-semibold">
                  Cliente: {clienteNombre(o)}
                </h3>
                <table className="w-full border-collapse text-sm">
                  <thead>
                    <tr className="border-b border-lt-border print:border-black">
                      <th className="py-2 pr-3 text-left font-semibold">
                        Producto
                      </th>
                      <th className="w-36 py-2 text-right font-semibold">
                        Cantidad solicitada
                      </th>
                    </tr>
                  </thead>
                  <tbody>
                    {lineas.map((d, idx) => (
                      <tr
                        key={String(d.detalle_id ?? `${id}-${idx}`)}
                        className="border-b border-lt-border/60 print:border-black/40"
                      >
                        <td className="py-2 pr-3 align-top">
                          {d.nombre_producto ?? "Producto"}
                        </td>
                        <td className="py-2 text-right align-top tabular-nums">
                          {formatNumber(Number(d.cantidad_solicitada ?? 0))}
                        </td>
                      </tr>
                    ))}
                    {!lineas.length ? (
                      <tr>
                        <td
                          colSpan={2}
                          className="py-3 text-lt-text-muted print:text-black"
                        >
                          Sin líneas de producto.
                        </td>
                      </tr>
                    ) : null}
                  </tbody>
                </table>
              </section>
            );
          })}

          {!ordenesOrdenadas.length ? (
            <p className="text-sm text-lt-text-muted">
              No hay órdenes vinculadas a este radar.
            </p>
          ) : null}
        </div>

        <section className="lt-print-keep-together mt-10 space-y-2 border-t border-lt-border pt-6 print:mt-8 print:border-black print:pt-4">
          <h3 className="text-lg font-bold">Resumen</h3>
          <table className="w-full border-collapse text-sm">
            <thead>
              <tr className="border-b border-lt-border print:border-black">
                <th className="py-2 pr-3 text-left font-semibold">Producto</th>
                <th className="w-36 py-2 text-right font-semibold">
                  Cantidad solicitada
                </th>
              </tr>
            </thead>
            <tbody>
              {resumen.map((p) => (
                <tr
                  key={p.producto_id}
                  className="border-b border-lt-border/60 print:border-black/40"
                >
                  <td className="py-2 pr-3 align-top">{p.nombre_producto}</td>
                  <td className="py-2 text-right align-top tabular-nums font-medium">
                    {formatNumber(Number(p.cantidad_solicitada ?? 0))}
                  </td>
                </tr>
              ))}
              {!resumen.length ? (
                <tr>
                  <td
                    colSpan={2}
                    className="py-3 text-lt-text-muted print:text-black"
                  >
                    Sin productos consolidados.
                  </td>
                </tr>
              ) : null}
            </tbody>
          </table>
        </section>
      </article>
    </div>
  );
}
