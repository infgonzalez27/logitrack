"use client";

import { useMemo, useState } from "react";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { LogiImage } from "@/components/media/logi-image";
import {
  PRODUCTO_MARCAS,
  detectProductoMarca,
  resolveProductoImage,
} from "@/lib/product-images";
import { formatNumber } from "@/lib/format";
import type { ProductoListaRpc } from "@/types/database";

export function ProductoCatalogo({
  productos,
  onAdd,
  selectedIds = [],
}: {
  productos: ProductoListaRpc[];
  onAdd: (producto: ProductoListaRpc) => void;
  selectedIds?: string[];
}) {
  const [q, setQ] = useState("");
  const [marca, setMarca] = useState<string>("");

  const filtrados = useMemo(() => {
    const term = q.trim().toLowerCase();
    return productos.filter((p) => {
      const nombre = p.nombre.toLowerCase();
      const codigo = (p.codigo_producto ?? "").toLowerCase();
      const barras = (p.codigo_barras ?? "").toLowerCase();
      const matchTerm =
        !term ||
        nombre.includes(term) ||
        codigo.includes(term) ||
        barras.includes(term);
      if (!matchTerm) return false;
      if (!marca) return true;
      return detectProductoMarca(p.nombre) === marca;
    });
  }, [productos, q, marca]);

  const selected = new Set(selectedIds);

  return (
    <div className="space-y-4">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-end">
        <div className="min-w-0 flex-1">
          <Input
            label="Buscar producto"
            placeholder="Nombre, código o código de barras…"
            value={q}
            onChange={(e) => setQ(e.target.value)}
            autoComplete="off"
          />
        </div>
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

      <p className="text-sm text-lt-text-muted">
        Mostrando {filtrados.length} de {productos.length} productos
      </p>

      {!productos.length ? (
        <p className="rounded-xl border border-dashed border-lt-border px-4 py-10 text-center text-sm text-lt-text-muted">
          No hay productos en catálogo. Regístralos en Inventario / Productos.
        </p>
      ) : filtrados.length === 0 ? (
        <p className="rounded-xl border border-dashed border-lt-border px-4 py-10 text-center text-sm text-lt-text-muted">
          Sin coincidencias para la búsqueda.
        </p>
      ) : (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
          {filtrados.map((p) => {
            const fallback = resolveProductoImage(p.nombre);
            const precio = p.precio_lista1 ?? p.precio ?? 0;
            const ya = selected.has(p.id);
            return (
              <article
                key={p.id}
                className="flex flex-col overflow-hidden rounded-xl border border-lt-border-light bg-lt-surface shadow-sm"
              >
                <div className="flex aspect-square items-center justify-center bg-white p-4">
                  <LogiImage
                    path={p.imagen_path}
                    type="producto"
                    alt={p.nombre}
                    fallbackSrc={fallback}
                    className="max-h-full max-w-full object-contain"
                  />
                </div>
                <div className="flex flex-1 flex-col gap-2 p-3">
                  <h3 className="line-clamp-2 text-sm font-semibold text-lt-text">
                    {p.nombre}
                  </h3>
                  <p className="text-xs text-lt-text-muted">
                    {p.codigo_producto ? `${p.codigo_producto} · ` : ""}
                    Stock {p.stock_disponible}
                  </p>
                  <p className="text-lg font-bold text-lt-text">
                    ${formatNumber(Number(precio))}
                  </p>
                  <Button
                    type="button"
                    className="mt-auto w-full"
                    variant={ya ? "secondary" : "primary"}
                    disabled={p.stock_disponible <= 0}
                    onClick={() => onAdd(p)}
                  >
                    {p.stock_disponible <= 0
                      ? "Sin stock"
                      : ya
                        ? "Agregar otra unidad"
                        : "Agregar a la orden"}
                  </Button>
                </div>
              </article>
            );
          })}
        </div>
      )}

      <p className="text-[11px] text-lt-text-subtle">
        Imágenes de producto: centro de descargas de Cervecería Regional (uso
        comercial para clientes/distribuidores).
      </p>
    </div>
  );
}
