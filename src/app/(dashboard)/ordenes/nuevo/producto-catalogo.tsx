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

const QTY_DEFAULT = 2;

export function ProductoCatalogo({
  productos,
  onAdd,
  selectedIds = [],
}: {
  productos: ProductoListaRpc[];
  onAdd: (producto: ProductoListaRpc, cantidad: number) => void;
  selectedIds?: string[];
}) {
  const [q, setQ] = useState("");
  const [marca, setMarca] = useState<string>("");
  const [activoId, setActivoId] = useState<string | null>(null);
  const [cantidades, setCantidades] = useState<Record<string, number>>({});

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

  function qtyOf(id: string) {
    return cantidades[id] ?? QTY_DEFAULT;
  }

  function setQty(id: string, value: number) {
    const next = Math.max(1, Math.floor(value) || 1);
    setCantidades((prev) => ({ ...prev, [id]: next }));
  }

  function añadir(producto: ProductoListaRpc) {
    const cantidad = qtyOf(producto.id);
    onAdd(producto, cantidad);
    setCantidades((prev) => ({ ...prev, [producto.id]: QTY_DEFAULT }));
  }

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
        Mostrando {filtrados.length} de {productos.length} productos. Selecciona
        uno y elige la cantidad antes de añadir.
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
        <div className="grid grid-cols-2 gap-2 min-[400px]:grid-cols-3 sm:gap-3 md:grid-cols-3 lg:grid-cols-4 xl:grid-cols-4">
          {filtrados.map((p) => {
            const fallback = resolveProductoImage(p.nombre);
            const precio = p.precio_lista1 ?? p.precio ?? 0;
            const ya = selected.has(p.id);
            const activo = activoId === p.id;
            const qty = qtyOf(p.id);
            const sinStock = p.stock_disponible <= 0;

            return (
              <article
                key={p.id}
                className={`flex flex-col overflow-hidden rounded-xl border bg-lt-surface shadow-sm transition ${
                  activo
                    ? "border-lt-primary ring-2 ring-lt-primary/25"
                    : "border-lt-border-light"
                }`}
              >
                <button
                  type="button"
                  disabled={sinStock}
                  onClick={() => setActivoId(activo ? null : p.id)}
                  className="flex aspect-square items-center justify-center bg-white p-2.5 text-left sm:p-4 disabled:cursor-not-allowed disabled:opacity-50"
                >
                  <LogiImage
                    path={p.imagen_path}
                    type="producto"
                    alt={p.nombre}
                    fallbackSrc={fallback}
                    className="max-h-full max-w-full object-contain"
                  />
                </button>
                <div className="flex flex-1 flex-col gap-1.5 p-2.5 sm:gap-2 sm:p-3">
                  <h3 className="line-clamp-2 text-xs font-semibold text-lt-text sm:text-sm">
                    {p.nombre}
                  </h3>
                  <p className="text-[10px] text-lt-text-muted sm:text-xs">
                    {p.codigo_producto ? `${p.codigo_producto} · ` : ""}
                    Stock {p.stock_disponible}
                  </p>
                  <p className="text-base font-bold text-lt-text sm:text-lg">
                    ${formatNumber(Number(precio))}
                  </p>

                  {sinStock ? (
                    <Button
                      type="button"
                      className="mt-auto w-full px-2 text-xs sm:text-sm"
                      variant="secondary"
                      disabled
                    >
                      Sin stock
                    </Button>
                  ) : !activo ? (
                    <Button
                      type="button"
                      className="mt-auto w-full px-2 text-xs sm:text-sm"
                      variant={ya ? "secondary" : "primary"}
                      onClick={() => setActivoId(p.id)}
                    >
                      {ya ? "Añadir más" : "Seleccionar"}
                    </Button>
                  ) : (
                    <div className="mt-auto space-y-2">
                      <div className="flex items-center justify-between gap-2">
                        <button
                          type="button"
                          aria-label="Disminuir cantidad"
                          className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-lt-surface-muted text-lg font-medium text-lt-text hover:bg-lt-primary-muted"
                          onClick={() => setQty(p.id, qty - 1)}
                        >
                          −
                        </button>
                        <input
                          type="number"
                          min={1}
                          max={p.stock_disponible}
                          value={qty}
                          onChange={(e) =>
                            setQty(p.id, Number(e.target.value))
                          }
                          className="w-14 rounded-lg border border-lt-border bg-lt-surface px-1 py-1.5 text-center text-sm font-semibold tabular-nums outline-none focus:border-lt-primary focus:ring-2 focus:ring-lt-primary/25"
                        />
                        <button
                          type="button"
                          aria-label="Aumentar cantidad"
                          className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-lt-surface-muted text-lg font-medium text-lt-text hover:bg-lt-primary-muted"
                          onClick={() =>
                            setQty(
                              p.id,
                              Math.min(p.stock_disponible, qty + 1),
                            )
                          }
                        >
                          +
                        </button>
                      </div>
                      <Button
                        type="button"
                        className="w-full px-2 text-xs sm:text-sm"
                        onClick={() => añadir(p)}
                      >
                        Añadir al carrito
                      </Button>
                    </div>
                  )}
                </div>
              </article>
            );
          })}
        </div>
      )}
    </div>
  );
}
