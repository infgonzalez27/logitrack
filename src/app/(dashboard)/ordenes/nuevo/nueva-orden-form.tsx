"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { buscarProductosOrdenAction } from "@/lib/actions/productos";
import { createOrdenAction } from "@/lib/actions/ordenes";
import { PageHeader } from "@/components/layout/page-header";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { Button } from "@/components/ui/button";
import type { ProductoListaRpc } from "@/types/database";

type Option = { value: string; label: string };

type Linea = {
  producto_id: string;
  cantidad_solicitada: number;
  valor_unitario_recaudar: number;
};

function labelProducto(p: ProductoListaRpc): string {
  const codigo = p.codigo_barras ? ` · ${p.codigo_barras}` : "";
  return `${p.nombre}${codigo} (stock: ${p.stock_disponible})`;
}

export function NuevaOrdenForm({
  clientes,
  camiones,
  choferes,
}: {
  clientes: Option[];
  camiones: Option[];
  choferes: Option[];
}) {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const [clienteId, setClienteId] = useState("");
  const [camionId, setCamionId] = useState("");
  const [choferId, setChoferId] = useState("");
  const [catalogo, setCatalogo] = useState<Record<string, ProductoListaRpc>>({});
  const [lineas, setLineas] = useState<Linea[]>([
    {
      producto_id: "",
      cantidad_solicitada: 1,
      valor_unitario_recaudar: 0,
    },
  ]);
  const [busquedas, setBusquedas] = useState<string[]>([""]);
  const [opcionesLinea, setOpcionesLinea] = useState<ProductoListaRpc[][]>([[]]);
  const [buscandoLinea, setBuscandoLinea] = useState<number | null>(null);
  const [busquedaErrores, setBusquedaErrores] = useState<(string | null)[]>([
    null,
  ]);

  function updateLinea(index: number, patch: Partial<Linea>) {
    setLineas((prev) =>
      prev.map((linea, i) => (i === index ? { ...linea, ...patch } : linea)),
    );
  }

  function addLinea() {
    setLineas((prev) => [
      ...prev,
      {
        producto_id: "",
        cantidad_solicitada: 1,
        valor_unitario_recaudar: 0,
      },
    ]);
    setBusquedas((prev) => [...prev, ""]);
    setOpcionesLinea((prev) => [...prev, []]);
    setBusquedaErrores((prev) => [...prev, null]);
  }

  function removeLinea(index: number) {
    setLineas((prev) => prev.filter((_, i) => i !== index));
    setBusquedas((prev) => prev.filter((_, i) => i !== index));
    setOpcionesLinea((prev) => prev.filter((_, i) => i !== index));
    setBusquedaErrores((prev) => prev.filter((_, i) => i !== index));
  }

  async function buscarProductos(index: number) {
    const termino = busquedas[index] ?? "";
    setBuscandoLinea(index);
    setBusquedaErrores((prev) =>
      prev.map((e, i) => (i === index ? null : e)),
    );

    const result = await buscarProductosOrdenAction(termino);

    setBuscandoLinea(null);

    if (!result.ok) {
      setBusquedaErrores((prev) =>
        prev.map((e, i) => (i === index ? result.error : e)),
      );
      setOpcionesLinea((prev) =>
        prev.map((opts, i) => (i === index ? [] : opts)),
      );
      return;
    }

    setOpcionesLinea((prev) =>
      prev.map((opts, i) => (i === index ? result.productos : opts)),
    );
    setCatalogo((prev) => {
      const next = { ...prev };
      for (const p of result.productos) {
        next[p.id] = p;
      }
      return next;
    });
  }

  function seleccionarProducto(index: number, productoId: string) {
    const producto =
      opcionesLinea[index]?.find((p) => p.id === productoId) ??
      catalogo[productoId];

    updateLinea(index, {
      producto_id: productoId,
      valor_unitario_recaudar: producto?.precio ?? 0,
    });

    if (producto) {
      setCatalogo((prev) => ({ ...prev, [producto.id]: producto }));
    }
  }

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setPending(true);
    setError(null);

    const result = await createOrdenAction({
      cliente_id: clienteId,
      camion_id: camionId,
      chofer_id: choferId,
      lineas: lineas.filter((l) => l.producto_id),
    });

    if (result?.error) {
      setError(result.error);
      setPending(false);
    }
  }

  const totalRecaudar = lineas.reduce(
    (total, linea) =>
      total + linea.cantidad_solicitada * linea.valor_unitario_recaudar,
    0,
  );

  return (
    <div className="mx-auto max-w-4xl space-y-6">
      <PageHeader
        title="Nueva orden de distribución"
        description="Estado inicial: borrador"
      />

      <form onSubmit={handleSubmit} className="space-y-6">
        <Card title="Cabecera">
          <div className="grid gap-4 sm:grid-cols-2">
            <Select
              label="Cliente"
              name="cliente_id"
              required
              placeholder="Selecciona cliente"
              options={clientes}
              value={clienteId}
              onChange={(e) => setClienteId(e.target.value)}
            />
            <Select
              label="Camión"
              name="camion_id"
              required
              placeholder="Selecciona camión"
              options={camiones}
              value={camionId}
              onChange={(e) => setCamionId(e.target.value)}
            />
            <Select
              label="Chofer"
              name="chofer_id"
              required
              placeholder="Selecciona chofer"
              options={choferes}
              value={choferId}
              onChange={(e) => setChoferId(e.target.value)}
            />
          </div>
        </Card>

        <Card
          title="Detalle de productos"
          action={
            <Button type="button" variant="secondary" onClick={addLinea}>
              Agregar línea
            </Button>
          }
        >
          <div className="space-y-4">
            {lineas.map((linea, index) => {
              const opciones = opcionesLinea[index] ?? [];
              const selectOptions = opciones.map((p) => ({
                value: p.id,
                label: labelProducto(p),
              }));

              return (
                <div
                  key={index}
                  className="space-y-3 rounded-xl border border-lt-border-light bg-lt-surface-muted/50 p-4"
                >
                  <div className="flex flex-wrap items-end gap-2">
                    <div className="min-w-[200px] flex-1">
                      <Input
                        label="Buscar producto"
                        placeholder="Nombre o código de barras"
                        value={busquedas[index] ?? ""}
                        onChange={(e) =>
                          setBusquedas((prev) =>
                            prev.map((b, i) =>
                              i === index ? e.target.value : b,
                            ),
                          )
                        }
                      />
                    </div>
                    <Button
                      type="button"
                      variant="secondary"
                      disabled={buscandoLinea === index}
                      onClick={() => buscarProductos(index)}
                    >
                      {buscandoLinea === index ? "Buscando…" : "Buscar"}
                    </Button>
                  </div>

                  {busquedaErrores[index] ? (
                    <p className="text-xs text-lt-danger-text">
                      {busquedaErrores[index]}
                    </p>
                  ) : null}

                  <div className="grid gap-3 sm:grid-cols-3">
                    <Select
                      label="Producto"
                      name={`producto_${index}`}
                      required
                      placeholder={
                        selectOptions.length
                          ? "Selecciona producto"
                          : "Busca primero un producto"
                      }
                      options={selectOptions}
                      value={linea.producto_id}
                      onChange={(e) =>
                        seleccionarProducto(index, e.target.value)
                      }
                    />
                    <Input
                      label="Cantidad"
                      type="number"
                      min="1"
                      required
                      value={linea.cantidad_solicitada}
                      onChange={(e) =>
                        updateLinea(index, {
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
                      value={linea.valor_unitario_recaudar}
                      onChange={(e) =>
                        updateLinea(index, {
                          valor_unitario_recaudar: Number(e.target.value),
                        })
                      }
                    />
                  </div>

                  {linea.producto_id && catalogo[linea.producto_id] ? (
                    <p className="text-xs text-lt-text-muted">
                      Stock disponible:{" "}
                      {catalogo[linea.producto_id].stock_disponible} · Precio
                      lista: ${Number(catalogo[linea.producto_id].precio).toFixed(2)}
                    </p>
                  ) : null}

                  <div className="flex justify-end">
                    <Button
                      type="button"
                      variant="ghost"
                      onClick={() => removeLinea(index)}
                      disabled={lineas.length === 1}
                    >
                      Quitar línea
                    </Button>
                  </div>
                </div>
              );
            })}
          </div>

          <p className="mt-4 text-sm text-lt-text-muted">
            Total a recaudar:{" "}
            <span className="font-medium text-lt-text">
              ${totalRecaudar.toFixed(2)}
            </span>
          </p>
        </Card>

        {error && <p className="lt-alert-error">{error}</p>}

        <div className="flex gap-3">
          <Button type="submit" disabled={pending}>
            {pending ? "Guardando…" : "Crear orden"}
          </Button>
          <Button
            type="button"
            variant="secondary"
            onClick={() => router.push("/ordenes")}
          >
            Cancelar
          </Button>
        </div>
      </form>
    </div>
  );
}
