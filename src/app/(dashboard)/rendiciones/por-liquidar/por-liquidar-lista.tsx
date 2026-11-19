"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import { formatCurrency, formatNumber } from "@/lib/format";
import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { agruparPorTramoAntiguedad } from "@/lib/rendiciones/antiguedad";
import type { OrdenPorLiquidarDetalle } from "@/types/database";

function normalizar(texto: string): string {
  return texto
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .trim();
}

function formatFecha(iso: string | null): string {
  if (!iso) return "—";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso.slice(0, 10);
  return d.toLocaleDateString("es-VE", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
  });
}

export function PorLiquidarLista({
  items,
}: {
  items: OrdenPorLiquidarDetalle[];
}) {
  const [busqueda, setBusqueda] = useState("");

  const filtrados = useMemo(() => {
    const q = normalizar(busqueda);
    if (!q) return items;
    return items.filter(
      (i) =>
        normalizar(i.razon_social).includes(q) ||
        normalizar(i.rif_nit ?? "").includes(q) ||
        normalizar(i.factura_origen_numero ?? "").includes(q) ||
        String(i.correlativo).includes(q),
    );
  }, [items, busqueda]);

  const grupos = useMemo(
    () => agruparPorTramoAntiguedad(filtrados),
    [filtrados],
  );

  const totalMonto = filtrados.reduce(
    (s, i) => s + (Number(i.monto_por_liquidar) || 0),
    0,
  );
  const totalOrdenes = filtrados.length;

  if (!items.length) {
    return (
      <Card className="px-4 py-8 text-center text-sm text-lt-text-muted">
        No hay órdenes en estado por liquidar.
      </Card>
    );
  }

  return (
    <>
      <div className="lt-no-print space-y-1.5">
        <label
          htmlFor="buscar-por-liquidar"
          className="block text-sm font-medium text-lt-text"
        >
          Buscar orden o cliente
        </label>
        <div className="relative">
          <input
            id="buscar-por-liquidar"
            type="text"
            autoComplete="off"
            placeholder="Cliente, RIF, # de orden o factura…"
            value={busqueda}
            onChange={(e) => setBusqueda(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Escape") setBusqueda("");
            }}
            className="lt-input w-full rounded-xl border border-lt-border bg-lt-surface px-3.5 py-2.5 pr-10 text-sm text-lt-text placeholder:text-lt-text-subtle outline-none focus:border-lt-primary focus:ring-2 focus:ring-lt-primary/25"
          />
          {busqueda ? (
            <button
              type="button"
              aria-label="Limpiar búsqueda"
              onClick={() => setBusqueda("")}
              className="absolute right-2 top-1/2 flex h-7 w-7 -translate-y-1/2 items-center justify-center rounded-full text-lg leading-none text-lt-text-muted hover:bg-lt-surface-muted hover:text-lt-text"
            >
              ×
            </button>
          ) : null}
        </div>
        <p className="text-xs text-lt-text-muted">
          Órdenes ({formatNumber(totalOrdenes)} de {formatNumber(items.length)})
          {" · "}Total{" "}
          <span className="font-semibold text-lt-text">
            {formatCurrency(totalMonto)}
          </span>
        </p>
      </div>

      {!filtrados.length ? (
        <Card className="px-4 py-8 text-center text-sm text-lt-text-muted">
          Ninguna orden coincide con «{busqueda.trim()}».
        </Card>
      ) : (
        <div className="space-y-6">
          {/* Resumen rápido por tramo */}
          <div className="grid gap-2 sm:grid-cols-3 lg:grid-cols-6">
            {grupos.map((g) => (
              <a
                key={g.key}
                href={`#tramo-${g.key}`}
                className="rounded-xl border border-lt-border bg-lt-surface p-3 shadow-sm transition hover:border-lt-primary/50"
              >
                <p className="text-xs font-medium text-lt-text-muted">
                  {g.label}
                </p>
                <p className="mt-1 text-base font-bold tabular-nums text-lt-text">
                  {formatCurrency(g.totalMonto)}
                </p>
                <p className="text-xs tabular-nums text-lt-text-muted">
                  {formatNumber(g.totalOrdenes)}{" "}
                  {g.totalOrdenes === 1 ? "orden" : "órdenes"}
                </p>
              </a>
            ))}
          </div>

          {/* 6 secciones ordenadas */}
          {grupos.map((grupo) => (
            <section
              key={grupo.key}
              id={`tramo-${grupo.key}`}
              className="space-y-3"
            >
              <div className="flex flex-wrap items-center justify-between gap-2 border-b border-lt-border pb-2">
                <div className="flex items-center gap-2">
                  <h2 className="text-base font-bold text-lt-text">
                    {grupo.label}
                  </h2>
                  <span className="text-xs text-lt-text-muted">
                    ({grupo.rangoTexto})
                  </span>
                </div>
                <div className="flex items-center gap-2 text-sm">
                  <span className="tabular-nums text-lt-text-muted">
                    {formatNumber(grupo.totalOrdenes)}{" "}
                    {grupo.totalOrdenes === 1 ? "orden" : "órdenes"}
                  </span>
                  <Badge tone={grupo.badgeTone}>
                    {formatCurrency(grupo.totalMonto)}
                  </Badge>
                </div>
              </div>

              {grupo.ordenes.length === 0 ? (
                <Card className="px-4 py-4 text-sm text-lt-text-muted">
                  Sin órdenes en este tramo.
                </Card>
              ) : (
                <div className="grid gap-3 sm:grid-cols-2">
                  {grupo.ordenes.map((ord) => (
                    <article
                      key={ord.orden_id}
                      className="flex flex-col rounded-2xl border border-lt-border bg-lt-surface p-4 shadow-sm"
                    >
                      <div className="flex items-start justify-between gap-2">
                        <div>
                          <h3 className="text-base font-bold text-lt-text">
                            {ord.razon_social}
                          </h3>
                          <p className="text-xs text-lt-text-muted">
                            {ord.rif_nit}
                          </p>
                        </div>
                        <Badge tone={grupo.badgeTone}>
                          {formatNumber(ord.dias_vencidos)}{" "}
                          {ord.dias_vencidos === 1 ? "día" : "días"}
                        </Badge>
                      </div>

                      <dl className="mt-3 flex-1 space-y-1.5 text-sm">
                        <div className="flex items-start justify-between gap-3">
                          <dt className="text-lt-text-muted">Orden:</dt>
                          <dd className="text-right font-medium tabular-nums text-lt-text">
                            #{formatNumber(ord.correlativo)}
                            {ord.factura_origen_numero
                              ? ` · Fac. ${ord.factura_origen_numero}`
                              : ""}
                          </dd>
                        </div>
                        <div className="flex items-start justify-between gap-3">
                          <dt className="text-lt-text-muted">Despacho:</dt>
                          <dd className="text-right tabular-nums text-lt-text">
                            {formatFecha(ord.fecha_despacho)}
                          </dd>
                        </div>
                        {ord.abonado_usd > 0 ? (
                          <div className="flex items-start justify-between gap-3">
                            <dt className="text-lt-text-muted">
                              Abonado / Total:
                            </dt>
                            <dd className="text-right text-xs tabular-nums text-lt-text-muted">
                              {formatCurrency(ord.abonado_usd)} /{" "}
                              {formatCurrency(ord.total_orden_usd)}
                            </dd>
                          </div>
                        ) : null}
                        <div className="flex items-start justify-between gap-3">
                          <dt className="text-lt-text-muted">
                            Monto por liquidar:
                          </dt>
                          <dd className="text-right font-semibold tabular-nums text-lt-text">
                            {formatCurrency(ord.monto_por_liquidar)}
                          </dd>
                        </div>
                      </dl>

                      <div className="lt-no-print mt-4 flex flex-wrap justify-end gap-2">
                        <Link
                          href={`/ordenes/${ord.orden_id}`}
                          className="inline-flex items-center justify-center rounded-xl border border-lt-border bg-lt-surface px-3 py-1.5 text-xs font-medium text-lt-text hover:bg-lt-surface-muted"
                        >
                          Ver orden
                        </Link>
                        <Link
                          href={`/clientes/${ord.cliente_id}/visita`}
                          className="inline-flex items-center justify-center rounded-xl bg-lt-primary px-3 py-1.5 text-xs font-medium text-white hover:opacity-90"
                        >
                          Gestionar cobro
                        </Link>
                      </div>
                    </article>
                  ))}
                </div>
              )}
            </section>
          ))}
        </div>
      )}
    </>
  );
}
