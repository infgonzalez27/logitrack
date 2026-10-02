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
 * Radar # | Fecha | bloques Cliente (Producto / Cantidad solicitada) | Resumen.
 */
export function RadarReporteView({ reporte }: { reporte: RadarDetalleReporte }) {
  const { radar, despachador, resumen_productos, resumen_vacios, ordenes } = reporte;

  const ordenesOrdenadas = [...(ordenes ?? [])].sort((a, b) =>
    clienteNombre(a).localeCompare(clienteNombre(b), "es"),
  );

  const resumen = [...(resumen_productos ?? [])].sort(
    (a, b) =>
      Number(b.cargado) - Number(a.cargado) ||
      String(a.nombre_producto).localeCompare(String(b.nombre_producto), "es"),
  );

  const vacios = [...(resumen_vacios ?? [])];

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
            Fecha de despacho: {formatFechaDespacho(radar.fecha_despacho)}
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

        {/* Resumen de Productos */}
        <section className="lt-print-keep-together mt-10 space-y-2 border-t border-lt-border pt-6 print:mt-8 print:border-black print:pt-4">
          <h3 className="text-lg font-bold">Resumen de Carga y Despacho</h3>
          <table className="w-full border-collapse text-sm">
            <thead>
              <tr className="border-b border-lt-border print:border-black bg-lt-background/50">
                <th className="py-2 pr-3 text-left font-semibold">Producto</th>
                <th className="w-24 py-2 text-right font-semibold">Cargado</th>
                <th className="w-24 py-2 text-right font-semibold">Despachado</th>
                <th className="w-24 py-2 text-right font-semibold">Sobrante</th>
              </tr>
            </thead>
            <tbody>
              {resumen.map((p) => (
                <tr
                  key={p.producto_id}
                  className="border-b border-lt-border/60 print:border-black/40"
                >
                  <td className="py-2 pr-3 align-top font-medium">{p.nombre_producto}</td>
                  <td className="py-2 text-right align-top tabular-nums">
                    {formatNumber(Number(p.cargado ?? 0))}
                  </td>
                  <td className="py-2 text-right align-top tabular-nums">
                    {formatNumber(Number(p.despachado ?? 0))}
                  </td>
                  <td className="py-2 text-right align-top tabular-nums font-bold">
                    {formatNumber(Number(p.sobrante ?? 0))}
                  </td>
                </tr>
              ))}
              {!resumen.length ? (
                <tr>
                  <td
                    colSpan={4}
                    className="py-3 text-lt-text-muted print:text-black"
                  >
                    Sin productos consolidados.
                  </td>
                </tr>
              ) : null}
            </tbody>
          </table>
        </section>

        {/* Resumen de Vacíos */}
        {vacios.length > 0 && (
          <section className="lt-print-keep-together mt-8 space-y-2 border-t border-lt-border pt-6 print:mt-6 print:border-black print:pt-4 break-inside-avoid">
            <h3 className="text-lg font-bold">Resumen de Contenedores (Vacíos)</h3>
            <table className="w-full border-collapse text-sm">
              <thead>
                <tr className="border-b border-lt-border print:border-black bg-lt-background/50">
                  <th className="py-2 pr-3 text-left font-semibold">Cliente</th>
                  <th className="py-2 pr-3 text-left font-semibold">Envase</th>
                  <th className="w-24 py-2 text-right font-semibold">Entregado</th>
                  <th className="w-24 py-2 text-right font-semibold">Retirado</th>
                </tr>
              </thead>
              <tbody>
                {vacios.map((v) =>
                  v.detalles.map((d, i) => (
                    <tr
                      key={`${v.cliente_id}-${d.contenedor_id}`}
                      className="border-b border-lt-border/60 print:border-black/40"
                    >
                      {i === 0 && (
                        <td
                          rowSpan={v.detalles.length}
                          className="py-2 pr-3 align-top border-r border-lt-border/60 print:border-black/40"
                        >
                          <span className="font-semibold block">{v.razon_social}</span>
                          <span className="text-xs text-lt-text-muted block">{v.rif_nit}</span>
                        </td>
                      )}
                      <td className="py-2 pl-3 pr-3 align-top">{d.nombre_producto}</td>
                      <td className="py-2 text-right align-top tabular-nums">
                        {formatNumber(Number(d.entregado ?? 0))}
                      </td>
                      <td className="py-2 text-right align-top tabular-nums font-medium text-lt-primary">
                        {formatNumber(Number(d.retirado ?? 0))}
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </section>
        )}

      </article>
    </div>
  );
}
