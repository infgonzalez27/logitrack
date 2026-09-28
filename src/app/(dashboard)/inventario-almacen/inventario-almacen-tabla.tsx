"use client";

import { useMemo, useState } from "react";
import { DataTable } from "@/components/ui/data-table";
import { Input } from "@/components/ui/input";
import { formatNumber } from "@/lib/format";

export type InventarioAlmacenFila = {
  id: string;
  producto: string;
  codigo: string | null;
  codigo_barras: string | null;
  disponible: number;
  comprometido: number;
  ubicacion: string | null;
};

function normalizar(texto: string): string {
  return texto
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .trim();
}

export function InventarioAlmacenTabla({
  filas,
}: {
  filas: InventarioAlmacenFila[];
}) {
  const [query, setQuery] = useState("");

  const filtradas = useMemo(() => {
    const term = normalizar(query);
    if (!term) return filas;
    return filas.filter((f) =>
      [f.producto, f.codigo, f.codigo_barras].some(
        (campo) => campo && normalizar(campo).includes(term),
      ),
    );
  }, [filas, query]);

  return (
    <div className="space-y-4">
      <div>
        <Input
          label="Buscar producto"
          name="q"
          placeholder="Buscar por nombre, código o código de barras…"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          autoComplete="off"
        />
        <p className="mt-1 text-xs text-lt-text-muted">
          {filtradas.length} resultado{filtradas.length === 1 ? "" : "s"}
        </p>
      </div>
      <DataTable
        columns={[
          { key: "codigo", label: "Código" },
          { key: "producto", label: "Producto" },
          { key: "disponible", label: "Disponible" },
          { key: "comprometido", label: "Comprometido" },
          { key: "ubicacion", label: "Ubicación" },
        ]}
        emptyMessage={
          query.trim()
            ? "No se encontraron productos con ese criterio."
            : "No hay registros."
        }
        rows={filtradas.map((f) => ({
          id: f.id,
          cells: {
            codigo: (
              <span className="font-mono text-xs text-lt-text-muted">
                {f.codigo ?? "—"}
              </span>
            ),
            producto: f.producto,
            disponible: formatNumber(f.disponible),
            comprometido: formatNumber(f.comprometido),
            ubicacion: f.ubicacion ?? "—",
          },
        }))}
      />
    </div>
  );
}
