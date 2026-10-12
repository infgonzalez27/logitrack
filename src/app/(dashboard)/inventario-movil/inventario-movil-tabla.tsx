"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import { DataTable } from "@/components/ui/data-table";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { formatNumber } from "@/lib/format";

export type InventarioMovilFila = {
  id: string;
  camion_id: string;
  camion_placa: string;
  camion_modelo: string | null;
  producto_id: string;
  producto_nombre: string;
  codigo_producto: string | null;
  codigo_barras: string | null;
  cantidad_cargada: number;
  cantidad_entregada: number;
  cantidad_devolucion: number;
  disponible: number;
};

export type CamionFiltro = {
  id: string;
  placa: string;
  modelo: string | null;
  estado: string | null;
};

function normalizar(texto: string): string {
  return texto
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .trim();
}

export function InventarioMovilTabla({
  filas,
  camiones,
  initialCamionId = "",
}: {
  filas: InventarioMovilFila[];
  camiones: CamionFiltro[];
  initialCamionId?: string;
}) {
  const [camionId, setCamionId] = useState<string>(initialCamionId);
  const [query, setQuery] = useState("");
  const [soloDisponibles, setSoloDisponibles] = useState(false);

  // Filtrado reactivo por camión, búsqueda de texto y stock disponible
  const filtradas = useMemo(() => {
    let result = filas;

    // Filtro por camión
    if (camionId.trim()) {
      result = result.filter((f) => f.camion_id === camionId.trim());
    }

    // Filtro solo con stock disponible
    if (soloDisponibles) {
      result = result.filter((f) => f.disponible > 0);
    }

    // Búsqueda por texto (nombre, código o código de barras)
    const term = normalizar(query);
    if (term) {
      result = result.filter((f) =>
        [
          f.producto_nombre,
          f.codigo_producto,
          f.codigo_barras,
          f.camion_placa,
          f.camion_modelo,
        ].some((campo) => campo && normalizar(campo).includes(term)),
      );
    }

    return result;
  }, [filas, camionId, soloDisponibles, query]);

  // Resumen / Métricas del camión o flota seleccionada
  const metricas = useMemo(() => {
    let totalCargada = 0;
    let totalEntregada = 0;
    let totalDevolucion = 0;
    let totalDisponible = 0;

    for (const f of filtradas) {
      totalCargada += f.cantidad_cargada;
      totalEntregada += f.cantidad_entregada;
      totalDevolucion += f.cantidad_devolucion;
      totalDisponible += f.disponible;
    }

    return {
      totalProductos: filtradas.length,
      totalCargada,
      totalEntregada,
      totalDevolucion,
      totalDisponible,
    };
  }, [filtradas]);

  const camionActual = camiones.find((c) => c.id === camionId);

  return (
    <div className="space-y-6">
      {/* Barra de selección de camión y filtros */}
      <div className="rounded-2xl border border-lt-border-light bg-lt-surface p-4 shadow-sm md:p-5">
        <div className="grid grid-cols-1 gap-4 md:grid-cols-12 md:items-end">
          {/* Selector de camión */}
          <div className="md:col-span-5">
            <Select
              label="Elegir camión"
              name="camion_filtro"
              value={camionId}
              onChange={(e) => setCamionId(e.target.value)}
              placeholder="Todos los camiones"
              options={camiones.map((c) => ({
                value: c.id,
                label: `${c.placa}${c.modelo ? ` — ${c.modelo}` : ""}${
                  c.estado === "en_ruta" ? " (En ruta)" : ""
                }`,
              }))}
            />
          </div>

          {/* Buscador de producto */}
          <div className="md:col-span-4">
            <Input
              label="Buscar en inventario"
              name="q"
              placeholder="Producto, código o barras..."
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              autoComplete="off"
            />
          </div>

          {/* Toggle de solo disponibles */}
          <div className="flex items-center gap-2 pb-2 md:col-span-3">
            <label className="flex cursor-pointer items-center gap-2 text-sm text-lt-text select-none">
              <input
                type="checkbox"
                checked={soloDisponibles}
                onChange={(e) => setSoloDisponibles(e.target.checked)}
                className="h-4 w-4 rounded border-lt-border text-lt-primary focus:ring-lt-primary/25"
              />
              <span className="font-medium">Solo con disponible &gt; 0</span>
            </label>
          </div>
        </div>

        {/* Tarjetas de métricas resumidas */}
        <div className="mt-5 grid grid-cols-2 gap-3 border-t border-lt-border-light pt-4 sm:grid-cols-4">
          <div className="rounded-xl bg-lt-surface-muted/60 p-3">
            <span className="text-xs font-medium uppercase tracking-wider text-lt-text-subtle">
              {camionActual ? `Camión: ${camionActual.placa}` : "Camiones"}
            </span>
            <p className="mt-1 text-lg font-bold text-lt-text">
              {metricas.totalProductos}{" "}
              <span className="text-xs font-normal text-lt-text-muted">
                productos
              </span>
            </p>
          </div>

          <div className="rounded-xl bg-lt-surface-muted/60 p-3">
            <span className="text-xs font-medium uppercase tracking-wider text-lt-text-subtle">
              Cargada total
            </span>
            <p className="mt-1 text-lg font-bold text-lt-text">
              {formatNumber(metricas.totalCargada)}
            </p>
          </div>

          <div className="rounded-xl bg-lt-surface-muted/60 p-3">
            <span className="text-xs font-medium uppercase tracking-wider text-lt-text-subtle">
              Entregada
            </span>
            <p className="mt-1 text-lg font-bold text-lt-text">
              {formatNumber(metricas.totalEntregada)}
            </p>
          </div>

          <div className="rounded-xl border border-emerald-500/20 bg-emerald-500/10 p-3">
            <span className="text-xs font-medium uppercase tracking-wider text-emerald-700 dark:text-emerald-300">
              Disponible en ruta
            </span>
            <p className="mt-1 text-lg font-bold text-emerald-700 dark:text-emerald-300">
              {formatNumber(metricas.totalDisponible)}
            </p>
          </div>
        </div>

        {/* Botón de acción contextual para el camión */}
        {camionActual && (
          <div className="mt-4 flex flex-wrap items-center justify-between gap-3 border-t border-lt-border-light pt-3">
            <div className="text-xs text-lt-text-muted">
              Mostrando inventario exclusivo del camión{" "}
              <strong className="text-lt-text font-semibold">
                {camionActual.placa}
              </strong>
              {camionActual.modelo ? ` (${camionActual.modelo})` : ""}
            </div>
            <Link
              href={`/inventario-movil/nuevo?camion_id=${camionActual.id}`}
              className="text-xs font-medium text-lt-primary hover:underline"
            >
              + Cargar producto a {camionActual.placa}
            </Link>
          </div>
        )}
      </div>

      {/* Tabla con los datos */}
      <div className="rounded-2xl border border-lt-border-light bg-lt-surface shadow-sm overflow-hidden">
        <DataTable
          emptyMessage={
            camionActual
              ? `No hay inventario registrado para el camión ${camionActual.placa}.`
              : "No se encontraron productos en inventario móvil con los filtros actuales."
          }
          columns={[
            { key: "camion", label: "Camión" },
            { key: "codigo", label: "Código" },
            { key: "producto", label: "Producto" },
            { key: "cargada", label: "Cargada" },
            { key: "entregada", label: "Entregada" },
            { key: "devolucion", label: "Devolución" },
            { key: "disponible", label: "Disponible en Camión" },
          ]}
          rows={filtradas.map((row) => ({
            id: row.id,
            cells: {
              camion: (
                <div className="flex flex-col">
                  <span className="font-semibold text-lt-text">
                    {row.camion_placa}
                  </span>
                  {row.camion_modelo ? (
                    <span className="text-xs text-lt-text-subtle">
                      {row.camion_modelo}
                    </span>
                  ) : null}
                </div>
              ),
              codigo: (
                <span className="font-mono text-xs text-lt-text-muted">
                  {row.codigo_producto || row.codigo_barras || "—"}
                </span>
              ),
              producto: (
                <span className="font-medium text-lt-text">
                  {row.producto_nombre}
                </span>
              ),
              cargada: (
                <span className="font-medium text-lt-text">
                  {formatNumber(row.cantidad_cargada)}
                </span>
              ),
              entregada: (
                <span className="text-lt-text-muted">
                  {formatNumber(row.cantidad_entregada)}
                </span>
              ),
              devolucion: (
                <span className="text-lt-text-muted">
                  {formatNumber(row.cantidad_devolucion)}
                </span>
              ),
              disponible: (
                <Badge tone={row.disponible > 0 ? "success" : "default"}>
                  {formatNumber(row.disponible)}
                </Badge>
              ),
            },
          }))}
        />
      </div>
    </div>
  );
}
