"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { actualizarProductoAction } from "@/lib/actions/productos";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import type { ActualizarProductoRpcInput } from "@/types/database";

export function ProductoEditarForm({
  producto,
}: {
  producto: ActualizarProductoRpcInput & { stock_disponible?: number };
}) {
  const router = useRouter();
  const [codigoProducto, setCodigoProducto] = useState(producto.codigo_producto);
  const [nombre, setNombre] = useState(producto.nombre);
  const [codigoBarras, setCodigoBarras] = useState(producto.codigo_barras);
  const [precioLista1, setPrecioLista1] = useState(producto.precio_lista1);
  const [precioLista2, setPrecioLista2] = useState(producto.precio_lista2);
  const [precioLista3, setPrecioLista3] = useState(producto.precio_lista3);
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setPending(true);
    setError(null);

    const result = await actualizarProductoAction({
      id: producto.id,
      codigo_producto: codigoProducto,
      nombre,
      codigo_barras: codigoBarras,
      precio_lista1: precioLista1,
      precio_lista2: precioLista2,
      precio_lista3: precioLista3,
    });

    if (!result.ok) {
      setError(result.error);
      setPending(false);
      return;
    }

    router.push("/productos");
    router.refresh();
  }

  return (
    <Card title="Ficha del producto">
      <form onSubmit={handleSubmit} className="space-y-4">
        <Input
          label="Código de producto"
          name="codigo_producto"
          required
          value={codigoProducto}
          onChange={(e) => setCodigoProducto(e.target.value)}
        />
        <Input
          label="Nombre"
          name="nombre"
          required
          value={nombre}
          onChange={(e) => setNombre(e.target.value)}
        />
        <Input
          label="Código de barras"
          name="codigo_barras"
          value={codigoBarras}
          onChange={(e) => setCodigoBarras(e.target.value)}
        />
        <div className="grid gap-4 sm:grid-cols-3">
          <Input
            label="Precio lista 1"
            name="precio_lista1"
            type="number"
            min="0"
            step="0.01"
            required
            value={precioLista1}
            onChange={(e) => setPrecioLista1(Number(e.target.value))}
          />
          <Input
            label="Precio lista 2"
            name="precio_lista2"
            type="number"
            min="0"
            step="0.01"
            required
            value={precioLista2}
            onChange={(e) => setPrecioLista2(Number(e.target.value))}
          />
          <Input
            label="Precio lista 3"
            name="precio_lista3"
            type="number"
            min="0"
            step="0.01"
            required
            value={precioLista3}
            onChange={(e) => setPrecioLista3(Number(e.target.value))}
          />
        </div>

        {producto.stock_disponible !== undefined ? (
          <p className="text-sm text-lt-text-muted">
            Stock disponible: {producto.stock_disponible}
          </p>
        ) : null}

        {error ? <p className="lt-alert-error">{error}</p> : null}

        <div className="flex gap-3">
          <Button type="submit" disabled={pending}>
            {pending ? "Guardando…" : "Guardar cambios"}
          </Button>
          <Button
            type="button"
            variant="secondary"
            onClick={() => router.push("/productos")}
          >
            Cancelar
          </Button>
        </div>
      </form>
    </Card>
  );
}
