"use client";

import { useMemo, useState } from "react";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { Button } from "@/components/ui/button";
import type { ProductoListaRpc } from "@/types/database";

type Linea = {
  producto_id: string;
  cantidad_solicitada: number;
  valor_unitario_recaudar: number;
};

function formatoPrecio(value: number) {
  return Number(value).toFixed(2);
}

function etiquetaProducto(p: ProductoListaRpc) {
  const codigo = p.codigo_producto ? `${p.codigo_producto} — ` : "";
  return `${codigo}${p.nombre} (stock ${p.stock_disponible})`;
}

export function LineaProductoRow({
  linea,
  producto,
  catalogo,
  onLineaChange,
  onProductoCatalogo,
  onRemove,
  canRemove,
}: {
  linea: Linea;
  producto?: ProductoListaRpc;
  catalogo: ProductoListaRpc[];
  onLineaChange: (patch: Partial<Linea>) => void;
  onProductoCatalogo: (producto: ProductoListaRpc) => void;
  onRemove: () => void;
  canRemove: boolean;
}) {
  const [filtro, setFiltro] = useState("");

  const opciones = useMemo(() => {
    const q = filtro.trim().toLowerCase();
    const lista = q
      ? catalogo.filter(
          (p) =>
            p.nombre.toLowerCase().includes(q) ||
            (p.codigo_producto ?? "").toLowerCase().includes(q) ||
            (p.codigo_barras ?? "").toLowerCase().includes(q),
        )
      : catalogo;

    return lista.map((p) => ({
      value: p.id,
      label: etiquetaProducto(p),
    }));
  }, [catalogo, filtro]);

  function elegirProducto(p: ProductoListaRpc) {
    onProductoCatalogo(p);
    onLineaChange({
      producto_id: p.id,
      valor_unitario_recaudar: p.precio_lista1 ?? p.precio ?? 0,
    });
    setFiltro("");
  }

  function cambiarProducto() {
    onLineaChange({
      producto_id: "",
      valor_unitario_recaudar: 0,
    });
    setFiltro("");
  }

  return (
    <div className="space-y-3 rounded-xl border border-lt-border-light bg-lt-surface-muted/50 p-4">
      {!linea.producto_id ? (
        <div className="space-y-2">
          <Input
            label="Filtrar producto"
            placeholder="Nombre o código…"
            value={filtro}
            onChange={(e) => setFiltro(e.target.value)}
            autoComplete="off"
          />
          <Select
            label="Producto"
            name="producto_id"
            required
            placeholder={
              catalogo.length
                ? "Selecciona un producto"
                : "No hay productos en catálogo"
            }
            options={opciones}
            value=""
            onChange={(e) => {
              const p = catalogo.find((item) => item.id === e.target.value);
              if (p) elegirProducto(p);
            }}
          />
          {!catalogo.length ? (
            <p className="text-xs text-lt-text-muted">
              Registra productos en el módulo de inventario para poder agregarlos.
            </p>
          ) : opciones.length === 0 ? (
            <p className="text-xs text-lt-text-muted">
              Sin coincidencias para &quot;{filtro.trim()}&quot;.
            </p>
          ) : null}
        </div>
      ) : (
        <div className="flex items-start justify-between gap-3 rounded-xl border border-lt-border-light bg-lt-surface px-3 py-2.5">
          <div className="min-w-0">
            <p className="truncate text-sm font-medium text-lt-text">
              {producto?.nombre ?? "Producto seleccionado"}
            </p>
            <p className="text-xs text-lt-text-muted">
              Código: {producto?.codigo_producto ?? "—"} · Stock:{" "}
              {producto?.stock_disponible ?? 0} · Precio lista: $
              {formatoPrecio(
                producto?.precio_lista1 ?? producto?.precio ?? 0,
              )}
            </p>
          </div>
          <Button type="button" variant="ghost" onClick={cambiarProducto}>
            Cambiar
          </Button>
        </div>
      )}

      <div className="grid grid-cols-2 gap-3">
        <Input
          label="Cantidad"
          type="number"
          min="1"
          required
          disabled={!linea.producto_id}
          value={linea.cantidad_solicitada}
          onChange={(e) =>
            onLineaChange({
              cantidad_solicitada: Number(e.target.value),
            })
          }
        />
        <Input
          label="Precio unitario"
          type="number"
          min="0"
          step="0.01"
          required
          disabled={!linea.producto_id}
          value={linea.valor_unitario_recaudar}
          onChange={(e) =>
            onLineaChange({
              valor_unitario_recaudar: Number(e.target.value),
            })
          }
        />
      </div>

      <div className="flex justify-end">
        <Button
          type="button"
          variant="ghost"
          onClick={onRemove}
          disabled={!canRemove}
        >
          Quitar línea
        </Button>
      </div>
    </div>
  );
}
