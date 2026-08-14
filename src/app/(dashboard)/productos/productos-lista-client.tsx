"use client";

import Link from "next/link";
import { useEffect, useMemo, useRef, useState, useTransition } from "react";
import { listarProductosAction } from "@/lib/actions/productos";
import { LogiImage } from "@/components/media/logi-image";
import { Input } from "@/components/ui/input";
import { PrintDocumentHeader } from "@/components/print/print-document-header";
import {
  PRODUCTO_MARCAS,
  detectProductoMarca,
  resolveProductoImage,
} from "@/lib/product-images";
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
  const [marca, setMarca] = useState("");
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

  const filtrados = useMemo(() => {
    if (!marca) return productos;
    return productos.filter((p) => detectProductoMarca(p.nombre) === marca);
  }, [productos, marca]);

  return (
    <div className="lt-print-document space-y-4 print:space-y-3">
      <PrintDocumentHeader
        title="Listado de productos"
        subtitle={
          query.trim()
            ? `Filtro: "${query.trim()}"`
            : "Catálogo completo"
        }
        meta={`${filtrados.length} producto${filtrados.length === 1 ? "" : "s"}`}
      />

      <div className="lt-no-print space-y-3">
        <div className="rounded-2xl border border-lt-border-light bg-lt-surface p-3 shadow-sm sm:p-4">
          <Input
            label="Buscar en el catálogo"
            name="q"
            placeholder="Buscar por nombre, código o código de barras…"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            autoComplete="off"
          />
          {pending ? (
            <p className="mt-1 text-xs text-lt-text-muted">Buscando…</p>
          ) : (
            <p className="mt-1 text-xs text-lt-text-muted">
              {filtrados.length} resultado{filtrados.length === 1 ? "" : "s"}
            </p>
          )}
        </div>

        <div className="flex flex-wrap gap-2">
          <button
            type="button"
            onClick={() => setMarca("")}
            className={`rounded-full px-3 py-1.5 text-xs font-medium transition-colors ${
              !marca
                ? "bg-lt-primary text-white"
                : "bg-lt-surface-muted text-lt-text hover:bg-lt-primary-muted"
            }`}
          >
            Todas
          </button>
          {PRODUCTO_MARCAS.map((m) => (
            <button
              key={m}
              type="button"
              onClick={() => setMarca(m === marca ? "" : m)}
              className={`rounded-full px-3 py-1.5 text-xs font-medium transition-colors ${
                marca === m
                  ? "bg-lt-primary text-white"
                  : "bg-lt-surface-muted text-lt-text hover:bg-lt-primary-muted"
              }`}
            >
              {m}
            </button>
          ))}
        </div>
      </div>

      {error ? <p className="text-sm text-lt-danger-text">{error}</p> : null}

      {!filtrados.length ? (
        <p className="rounded-2xl border border-dashed border-lt-border px-4 py-12 text-center text-sm text-lt-text-muted">
          {query.trim()
            ? "No se encontraron productos con ese criterio."
            : "No hay productos registrados."}
        </p>
      ) : (
        <div className="grid grid-cols-2 gap-2 min-[400px]:grid-cols-3 sm:gap-3 md:grid-cols-4 lg:grid-cols-4 xl:grid-cols-5">
          {filtrados.map((p) => {
            const precio = p.precio_lista1 ?? p.precio ?? 0;
            const fallback = resolveProductoImage(p.nombre);
            return (
              <Link
                key={p.id}
                href={`/productos/${p.id}`}
                className="group flex flex-col overflow-hidden rounded-xl border border-lt-border-light bg-lt-surface shadow-sm transition hover:-translate-y-0.5 hover:border-lt-primary/40 hover:shadow-md sm:rounded-2xl"
              >
                <div className="flex aspect-square items-center justify-center bg-white p-2.5 sm:p-4">
                  <LogiImage
                    path={p.imagen_path}
                    type="producto"
                    alt={p.nombre}
                    fallbackSrc={fallback}
                    className="max-h-full max-w-full object-contain transition group-hover:scale-[1.03]"
                  />
                </div>
                <div className="flex flex-1 flex-col gap-1 border-t border-lt-border-light p-2.5 sm:gap-2 sm:p-4">
                  <p className="truncate text-[10px] uppercase tracking-wide text-lt-text-subtle sm:text-[11px]">
                    {p.codigo_producto ?? "Sin código"}
                  </p>
                  <h3 className="line-clamp-2 min-h-[2.25rem] text-xs font-medium text-lt-text sm:min-h-[2.5rem] sm:text-sm">
                    {p.nombre}
                  </h3>
                  <p className="mt-auto font-display text-lg text-lt-text sm:text-2xl">
                    ${formatNumber(Number(precio))}
                  </p>
                  <div className="flex flex-col gap-0.5 text-[10px] sm:flex-row sm:items-center sm:justify-between sm:gap-2 sm:text-xs">
                    <span
                      className={
                        p.stock_disponible > 0
                          ? "font-medium text-lt-success-text"
                          : "font-medium text-lt-danger-text"
                      }
                    >
                      {p.stock_disponible > 0
                        ? `Stock ${formatNumber(p.stock_disponible)}`
                        : "Sin stock"}
                    </span>
                    <span className="font-medium text-lt-primary group-hover:underline">
                      Ver
                    </span>
                  </div>
                </div>
              </Link>
            );
          })}
        </div>
      )}

      {/* Impresión: tabla compacta */}
      <div className="hidden print:block">
        <table className="w-full border-collapse text-sm">
          <thead>
            <tr>
              <th className="border-b border-lt-border py-2 text-left">Código</th>
              <th className="border-b border-lt-border py-2 text-left">Nombre</th>
              <th className="border-b border-lt-border py-2 text-right">Precio</th>
              <th className="border-b border-lt-border py-2 text-right">Stock</th>
            </tr>
          </thead>
          <tbody>
            {filtrados.map((p) => (
              <tr key={p.id}>
                <td className="border-b border-lt-border-light py-1.5">
                  {p.codigo_producto ?? "—"}
                </td>
                <td className="border-b border-lt-border-light py-1.5">{p.nombre}</td>
                <td className="border-b border-lt-border-light py-1.5 text-right">
                  {formatNumber(p.precio_lista1 ?? p.precio)}
                </td>
                <td className="border-b border-lt-border-light py-1.5 text-right">
                  {p.stock_disponible}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
