"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { actualizarProductoAction } from "@/lib/actions/productos";
import { LogiImage } from "@/components/media/logi-image";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { Button } from "@/components/ui/button";
import { resolveProductoImage } from "@/lib/product-images";
import type { ActualizarProductoRpcInput } from "@/types/database";

type ContenedorOption = { id: string; nombre: string };

export function ProductoEditarForm({
  producto,
  contenedores,
}: {
  producto: ActualizarProductoRpcInput & { stock_disponible?: number };
  contenedores: ContenedorOption[];
}) {
  const router = useRouter();
  const [codigoProducto, setCodigoProducto] = useState(producto.codigo_producto);
  const [nombre, setNombre] = useState(producto.nombre);
  const [codigoBarras, setCodigoBarras] = useState(producto.codigo_barras);
  const [precioLista1, setPrecioLista1] = useState(producto.precio_lista1);
  const [precioLista2, setPrecioLista2] = useState(producto.precio_lista2);
  const [precioLista3, setPrecioLista3] = useState(producto.precio_lista3);
  const [contenedorId, setContenedorId] = useState(
    producto.contenedor_id ?? "",
  );
  const [unidadesPorContenedor, setUnidadesPorContenedor] = useState(
    producto.unidades_por_contenedor ?? 1,
  );
  const [imagenPath, setImagenPath] = useState(producto.imagen_path ?? "");
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
      contenedor_id: contenedorId || null,
      unidades_por_contenedor: contenedorId ? unidadesPorContenedor : null,
      imagen_path: imagenPath.trim() || null,
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
        <div className="flex flex-col gap-4 sm:flex-row sm:items-start">
          <div className="mx-auto flex h-36 w-36 shrink-0 items-center justify-center overflow-hidden rounded-xl border border-lt-border-light bg-white p-3 sm:mx-0">
            <LogiImage
              path={imagenPath.trim() || null}
              type="producto"
              alt={nombre || "Producto"}
              fallbackSrc={resolveProductoImage(nombre)}
              className="max-h-full max-w-full object-contain"
            />
          </div>
          <div className="min-w-0 flex-1 space-y-2">
            <Input
              label="URL / ruta de imagen"
              name="imagen_path"
              placeholder="/productos/zulia.webp"
              value={imagenPath}
              onChange={(e) => setImagenPath(e.target.value)}
            />
            <p className="text-xs text-lt-text-muted">
              Guarda la ruta relativa en Storage (ej.{" "}
              <code className="rounded bg-lt-surface-muted px-1">
                /productos/nombre.webp
              </code>
              ) o la URL pública completa. Preferir fotos de caja/empaque.
            </p>
          </div>
        </div>

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

        <div className="grid gap-4 sm:grid-cols-2">
          <Select
            label="Empaque / contenedor (opcional)"
            name="contenedor_id"
            placeholder="Sin empaque retornable"
            options={contenedores.map((c) => ({
              value: c.id,
              label: c.nombre,
            }))}
            value={contenedorId}
            onChange={(e) => setContenedorId(e.target.value)}
          />
          <Input
            label="Unidades por contenedor"
            name="unidades_por_contenedor"
            type="number"
            min="1"
            step="1"
            disabled={!contenedorId}
            value={unidadesPorContenedor}
            onChange={(e) => setUnidadesPorContenedor(Number(e.target.value))}
          />
        </div>
        <p className="text-xs text-lt-text-muted">
          Si el producto usa envase retornable, al despachar se acreditarán
          vacíos al cliente según cantidad ÷ unidades por contenedor.
        </p>

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
