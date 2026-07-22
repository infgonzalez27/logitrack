"use client";

import Link from "next/link";
import { useEffect, useRef, useState, useTransition } from "react";
import { listarProductosAction } from "@/lib/actions/productos";
import { Input } from "@/components/ui/input";
import { DataTable } from "@/components/ui/data-table";
import { Card } from "@/components/ui/card";
import { PrintDocumentHeader } from "@/components/print/print-document-header";
import { formatNumber } from "@/lib/format";
import type { ProductoListaRpc } from "@/types/database";

export function ProductosListaClient({
  initialProductos,
  initialQuery = "",
  initialError = null,
}: {
  initialProductos: ProductoListaRpc[];
  initialQuery?: string;
  initialError?: string | null;
}) {
  const [query, setQuery] = useState(initialQuery);
  const [productos, setProductos] = useState(initialProductos);
  const [error, setError] = useState<string | null>(initialError);
  const [pending, startTransition] = useTransition();
  const omitirPrimeraBusqueda = useRef(true);

  useEffect(() => {
    if (omitirPrimeraBusqueda.current) {
      omitirPrimeraBusqueda.current = false;
      if (query === initialQuery) return;
    }

    const timeout = setTimeout(() => {
      startTransition(async () => {
        const result = await listarProductosAction(query);
        if (!result.ok) {
          setError(result.error);
          return;
        }

        setError(null);
        setProductos(result.productos);

        const q = query.trim();
        const url = q
          ? `/productos?q=${encodeURIComponent(q)}`
          : "/productos";
        window.history.replaceState(null, "", url);
      });
    }, 300);

    return () => clearTimeout(timeout);
  }, [query, initialQuery]);

  return (
    <div className="lt-print-document space-y-4 print:space-y-3">
      <PrintDocumentHeader
        title="Listado de productos"
        subtitle={
          query.trim()
            ? `Filtro: "${query.trim()}"`
            : "Catálogo completo"
        }
        meta={`${productos.length} producto${productos.length === 1 ? "" : "s"}`}
      />

      <div className="lt-no-print relative">
        <Input
          label="Buscar producto"
          name="q"
          placeholder="Nombre, código de producto o código de barras…"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
        />
        {pending ? (
          <p className="mt-1 text-xs text-lt-text-muted">Buscando…</p>
        ) : null}
      </div>

      {error ? <p className="text-sm text-lt-danger-text">{error}</p> : null}

      <Card className="lt-print-allow-break">
        <DataTable
          columns={[
            { key: "codigo", label: "Código" },
            { key: "nombre", label: "Nombre" },
            { key: "barras", label: "Cód. barras" },
            { key: "precio", label: "Precio lista 1" },
            { key: "stock", label: "Stock" },
            { key: "acciones", label: "", className: "lt-no-print" },
          ]}
          rows={productos.map((p) => ({
            id: p.id,
            cells: {
              codigo: p.codigo_producto ?? "—",
              nombre: p.nombre,
              barras: p.codigo_barras ?? "—",
              precio: formatNumber(p.precio_lista1 ?? p.precio),
              stock: p.stock_disponible,
              acciones: (
                <Link
                  href={`/productos/${p.id}`}
                  className="lt-no-print text-sm font-medium text-lt-primary hover:underline"
                >
                  Editar
                </Link>
              ),
            },
          }))}
          emptyMessage={
            query.trim()
              ? "No se encontraron productos con ese criterio."
              : "No hay productos registrados."
          }
        />
      </Card>
    </div>
  );
}
