"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import { formatCurrency, formatNumber } from "@/lib/format";
import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import type { OrdenPorLiquidarCliente } from "@/types/database";

function normalizar(texto: string): string {
  return texto
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .trim();
}

export function PorLiquidarLista({
  items,
}: {
  items: OrdenPorLiquidarCliente[];
}) {
  const [busqueda, setBusqueda] = useState("");

  const filtrados = useMemo(() => {
    const q = normalizar(busqueda);
    if (!q) return items;
    return items.filter(
      (i) =>
        normalizar(i.razon_social).includes(q) ||
        normalizar(i.rif_nit ?? "").includes(q),
    );
  }, [items, busqueda]);

  const totalMonto = filtrados.reduce((s, i) => s + i.monto_por_liquidar, 0);
  const totalOrdenes = filtrados.reduce((s, i) => s + i.cant_ordenes, 0);

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
          Buscar cliente
        </label>
        <div className="relative">
          <input
            id="buscar-por-liquidar"
            type="text"
            autoComplete="off"
            placeholder="Nombre o RIF del cliente…"
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
          Clientes ({formatNumber(filtrados.length)} de{" "}
          {formatNumber(items.length)})
        </p>
      </div>

      {!filtrados.length ? (
        <Card className="px-4 py-8 text-center text-sm text-lt-text-muted">
          Ningún cliente coincide con «{busqueda.trim()}».
        </Card>
      ) : (
        <div className="grid gap-4 sm:grid-cols-2">
          {filtrados.map((row) => (
            <article
              key={row.cliente_id}
              className="flex flex-col rounded-2xl border border-lt-border bg-lt-surface p-4 shadow-sm"
            >
              <h3 className="text-lg font-bold text-lt-text">
                {row.razon_social}
              </h3>
              <p className="text-sm text-lt-text-muted">{row.rif_nit}</p>
              <dl className="mt-3 flex-1 space-y-2 text-sm">
                <div className="flex items-start justify-between gap-3">
                  <dt className="text-lt-text-muted">Días vencidos:</dt>
                  <dd className="text-right font-medium tabular-nums text-lt-text">
                    {formatNumber(row.dias_vencidos)}
                  </dd>
                </div>
                <div className="flex items-start justify-between gap-3">
                  <dt className="text-lt-text-muted">Cant. órdenes:</dt>
                  <dd className="text-right tabular-nums text-lt-text">
                    {formatNumber(row.cant_ordenes)}
                  </dd>
                </div>
                <div className="flex items-start justify-between gap-3">
                  <dt className="text-lt-text-muted">Monto por liquidar:</dt>
                  <dd className="text-right">
                    <Badge tone="warning">
                      {formatCurrency(row.monto_por_liquidar)}
                    </Badge>
                  </dd>
                </div>
              </dl>
              <div className="mt-4 flex justify-end">
                <Link
                  href={`/clientes/${row.cliente_id}/visita`}
                  className="lt-no-print inline-flex items-center justify-center rounded-xl bg-lt-primary px-4 py-2 text-sm font-medium text-white hover:opacity-90"
                >
                  Ver detalle
                </Link>
              </div>
            </article>
          ))}
        </div>
      )}

      {filtrados.length ? (
        <p className="text-sm text-lt-text-muted">
          {formatNumber(filtrados.length)} cliente
          {filtrados.length === 1 ? "" : "s"} · {formatNumber(totalOrdenes)}{" "}
          orden
          {totalOrdenes === 1 ? "" : "es"} · Total{" "}
          <span className="font-semibold text-lt-text">
            {formatCurrency(totalMonto)}
          </span>
        </p>
      ) : null}
    </>
  );
}
