"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { formatNumber } from "@/lib/format";
import type { RadarDetalleReporte } from "@/types/database";
import {
  exportRadarDespachosToExcel,
  exportRadarResumenToExcel,
} from "@/lib/export/radar-excel";

/** Fecha dd/mm/yyyy */
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

export function RadarReporteView({ reporte }: { reporte: RadarDetalleReporte }) {
  const [tabActivo, setTabActivo] = useState<"despachos" | "resumen">("despachos");

  const { radar, despachador, resumen_productos, resumen_vacios, ordenes } =
    reporte;

  const ordenesOrdenadas = [...(ordenes ?? [])].sort((a, b) =>
    clienteNombre(a).localeCompare(clienteNombre(b), "es"),
  );

  const resumen = [...(resumen_productos ?? [])].sort(
    (a, b) =>
      Number(b.cargado) - Number(a.cargado) ||
      String(a.nombre_producto).localeCompare(String(b.nombre_producto), "es"),
  );

  const vacios = [...(resumen_vacios ?? [])];

  const handleExportExcel = () => {
    if (tabActivo === "despachos") {
      exportRadarDespachosToExcel(reporte);
    } else {
      exportRadarResumenToExcel(reporte);
    }
  };

  return (
    <div className="lt-print-document space-y-4">
      {/* Barra superior de control: Tabs de reporte y botones de exportación */}
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-lt-border pb-3 print:hidden">
        <div className="flex items-center gap-2">
          <span className="text-xs font-semibold uppercase tracking-wider text-lt-text-muted">
            Reporte:
          </span>
          <div className="inline-flex rounded-lg border border-lt-border bg-lt-surface p-1 shadow-xs">
            <button
              type="button"
              onClick={() => setTabActivo("despachos")}
              className={`cursor-pointer rounded-md px-3 py-1.5 text-xs font-semibold transition-colors ${
                tabActivo === "despachos"
                  ? "bg-lt-primary text-white shadow-xs"
                  : "text-lt-text-muted hover:text-lt-text"
              }`}
            >
              Despachos
            </button>
            <button
              type="button"
              onClick={() => setTabActivo("resumen")}
              className={`cursor-pointer rounded-md px-3 py-1.5 text-xs font-semibold transition-colors ${
                tabActivo === "resumen"
                  ? "bg-lt-primary text-white shadow-xs"
                  : "text-lt-text-muted hover:text-lt-text"
              }`}
            >
              Resumen
            </button>
          </div>
        </div>

        <div className="flex items-center gap-2">
          <Button
            type="button"
            variant="secondary"
            onClick={handleExportExcel}
            className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium border-emerald-700/30 text-emerald-700 hover:bg-emerald-50 dark:border-emerald-500/30 dark:text-emerald-400 dark:hover:bg-emerald-950/20"
          >
            <svg
              className="size-4 text-emerald-600 dark:text-emerald-400"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
            >
              <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
              <polyline points="14 2 14 8 20 8" />
              <line x1="8" y1="13" x2="16" y2="13" />
              <line x1="8" y1="17" x2="16" y2="17" />
              <polyline points="10 9 9 9 8 9" />
            </svg>
            Exportar a Excel
          </Button>

          <Button
            type="button"
            variant="secondary"
            onClick={() => window.print()}
            className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium"
          >
            <svg
              className="size-4"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
            >
              <polyline points="6 9 6 2 18 2 18 9" />
              <path d="M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2" />
              <rect x="6" y="14" width="12" height="8" />
            </svg>
            Imprimir reporte
          </Button>
        </div>
      </div>

      {/* Contenedor del Reporte Activo (impresión con tamaño 10pt y line-height compacto) */}
      <article className="radar-report-container rounded-xl border border-lt-border bg-lt-surface p-5 text-lt-text text-[13px] leading-snug print:rounded-none print:border-0 print:bg-transparent print:p-0 print:text-[10pt] print:leading-[1.15]">
        {/* Cabecera del Reporte */}
        <header className="lt-print-keep-together space-y-1 border-b border-lt-border pb-3 print:border-black">
          <div className="flex flex-wrap items-baseline justify-between gap-2">
            <h2 className="font-display text-xl font-bold tracking-tight print:text-lg">
              Radar # {radar.correlativo}
            </h2>
            <span className="text-xs font-semibold uppercase tracking-wide text-lt-primary print:text-black">
              {tabActivo === "despachos"
                ? "Reporte de Despachos"
                : "Reporte de Resumen"}
            </span>
          </div>
          <p className="text-xs text-lt-text-muted print:text-black">
            Fecha de despacho:{" "}
            <strong className="text-lt-text print:text-black">
              {formatFechaDespacho(radar.fecha_despacho)}
            </strong>
          </p>
          {despachador?.nombre_completo ? (
            <p className="text-xs text-lt-text-muted print:text-black">
              Despachador:{" "}
              <strong className="text-lt-text print:text-black">
                {despachador.nombre_completo}
              </strong>
            </p>
          ) : null}
        </header>

        {/* ------------------------------------------------------------- */}
        {/* REPORTE 1: DESPACHOS                                          */}
        {/* ------------------------------------------------------------- */}
        {tabActivo === "despachos" && (
          <div className="mt-4 space-y-6 print:mt-3 print:space-y-4">
            {ordenesOrdenadas.map((o) => {
              const id = String(o.orden_id ?? o.id ?? o.correlativo ?? "");
              const lineas = detallesOrden(o);
              const rif = o.cliente?.rif_nit ? ` (${o.cliente.rif_nit})` : "";
              const correlativoOrden = o.correlativo
                ? ` · Orden #${o.correlativo}`
                : "";
              return (
                <section
                  key={id}
                  className="lt-print-keep-together space-y-1.5 break-inside-avoid"
                >
                  <div className="rounded-md bg-lt-background/60 px-2.5 py-1 text-xs font-semibold text-lt-primary print:bg-transparent print:p-0 print:text-black">
                    Cliente: {clienteNombre(o)}
                    {rif}
                    {correlativoOrden}
                  </div>
                  <table className="w-full border-collapse text-xs print:text-[10pt]">
                    <thead>
                      <tr className="border-b border-lt-border print:border-black">
                        <th className="py-1.5 pr-3 text-left font-semibold">
                          Producto
                        </th>
                        <th className="w-28 py-1.5 pr-2 text-left font-semibold text-lt-text-muted print:text-black">
                          Código
                        </th>
                        <th className="w-32 py-1.5 text-right font-semibold">
                          Cant. solicitada
                        </th>
                      </tr>
                    </thead>
                    <tbody>
                      {lineas.map((d, idx) => (
                        <tr
                          key={String(d.detalle_id ?? `${id}-${idx}`)}
                          className="border-b border-lt-border/50 print:border-black/30"
                        >
                          <td className="py-1 pr-3 align-middle font-medium">
                            {d.nombre_producto ?? "Producto"}
                          </td>
                          <td className="py-1 pr-2 align-middle text-lt-text-muted print:text-black">
                            {d.codigo_producto ?? "—"}
                          </td>
                          <td className="py-1 text-right align-middle tabular-nums">
                            {formatNumber(Number(d.cantidad_solicitada ?? 0))}
                          </td>
                        </tr>
                      ))}
                      {!lineas.length ? (
                        <tr>
                          <td
                            colSpan={3}
                            className="py-2 text-lt-text-muted print:text-black"
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
              <p className="text-xs text-lt-text-muted">
                No hay órdenes vinculadas a este radar.
              </p>
            ) : null}
          </div>
        )}

        {/* ------------------------------------------------------------- */}
        {/* REPORTE 2: RESUMEN                                            */}
        {/* ------------------------------------------------------------- */}
        {tabActivo === "resumen" && (
          <div className="mt-4 space-y-6 print:mt-3 print:space-y-4">
            {/* Resumen de Productos */}
            <section className="lt-print-keep-together space-y-2 break-inside-avoid">
              <h3 className="text-sm font-bold uppercase tracking-wide text-lt-text print:text-black">
                Resumen de Carga y Despacho
              </h3>
              <table className="w-full border-collapse text-xs print:text-[10pt]">
                <thead>
                  <tr className="border-b border-lt-border bg-lt-background/50 print:border-black print:bg-transparent">
                    <th className="py-1.5 pr-3 text-left font-semibold">
                      Producto
                    </th>
                    <th className="w-24 py-1.5 text-right font-semibold">
                      Cargado
                    </th>
                    <th className="w-24 py-1.5 text-right font-semibold">
                      Despachado
                    </th>
                    <th className="w-24 py-1.5 text-right font-semibold">
                      Sobrante
                    </th>
                  </tr>
                </thead>
                <tbody>
                  {resumen.map((p) => (
                    <tr
                      key={p.producto_id}
                      className="border-b border-lt-border/50 print:border-black/30"
                    >
                      <td className="py-1 pr-3 align-middle font-medium">
                        {p.nombre_producto}
                      </td>
                      <td className="py-1 text-right align-middle tabular-nums">
                        {formatNumber(Number(p.cargado ?? 0))}
                      </td>
                      <td className="py-1 text-right align-middle tabular-nums">
                        {formatNumber(Number(p.despachado ?? 0))}
                      </td>
                      <td className="py-1 text-right align-middle font-bold tabular-nums">
                        {formatNumber(Number(p.sobrante ?? 0))}
                      </td>
                    </tr>
                  ))}
                  {!resumen.length ? (
                    <tr>
                      <td
                        colSpan={4}
                        className="py-2 text-lt-text-muted print:text-black"
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
              <section className="lt-print-keep-together space-y-2 border-t border-lt-border pt-4 print:border-black print:pt-3 break-inside-avoid">
                <h3 className="text-sm font-bold uppercase tracking-wide text-lt-text print:text-black">
                  Resumen de Contenedores (Vacíos)
                </h3>
                <table className="w-full border-collapse text-xs print:text-[10pt]">
                  <thead>
                    <tr className="border-b border-lt-border bg-lt-background/50 print:border-black print:bg-transparent">
                      <th className="py-1.5 pr-3 text-left font-semibold">
                        Cliente
                      </th>
                      <th className="py-1.5 pr-3 text-left font-semibold">
                        Envase
                      </th>
                      <th className="w-24 py-1.5 text-right font-semibold">
                        Entregado
                      </th>
                      <th className="w-24 py-1.5 text-right font-semibold">
                        Retirado
                      </th>
                    </tr>
                  </thead>
                  <tbody>
                    {vacios.map((v) =>
                      v.detalles.map((d, i) => (
                        <tr
                          key={`${v.cliente_id}-${d.contenedor_id}`}
                          className="border-b border-lt-border/50 print:border-black/30"
                        >
                          {i === 0 && (
                            <td
                              rowSpan={v.detalles.length}
                              className="py-1 pr-3 align-top border-r border-lt-border/50 print:border-black/30"
                            >
                              <span className="font-semibold block">
                                {v.razon_social}
                              </span>
                              <span className="text-[11px] text-lt-text-muted block print:text-black">
                                {v.rif_nit}
                              </span>
                            </td>
                          )}
                          <td className="py-1 pl-3 pr-3 align-middle">
                            {d.nombre_producto}
                          </td>
                          <td className="py-1 text-right align-middle tabular-nums">
                            {formatNumber(Number(d.entregado ?? 0))}
                          </td>
                          <td className="py-1 text-right align-middle font-medium text-lt-primary print:text-black tabular-nums">
                            {formatNumber(Number(d.retirado ?? 0))}
                          </td>
                        </tr>
                      )),
                    )}
                  </tbody>
                </table>
              </section>
            )}
          </div>
        )}
      </article>
    </div>
  );
}
