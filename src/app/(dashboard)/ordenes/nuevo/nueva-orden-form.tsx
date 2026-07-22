"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createOrdenAction } from "@/lib/actions/ordenes";
import { PageHeader } from "@/components/layout/page-header";
import { Card } from "@/components/ui/card";
import { Select } from "@/components/ui/select";
import { Button } from "@/components/ui/button";
import { LineaProductoRow } from "./linea-producto-row";
import type { ProductoListaRpc } from "@/types/database";

type Option = { value: string; label: string };

type Linea = {
  producto_id: string;
  cantidad_solicitada: number;
  valor_unitario_recaudar: number;
};

export function NuevaOrdenForm({
  clientes,
  camiones,
  choferes,
  choferesError = null,
  choferesAviso = null,
  productos,
  productosError = null,
}: {
  clientes: Option[];
  camiones: Option[];
  choferes: Option[];
  choferesError?: string | null;
  choferesAviso?: string | null;
  productos: ProductoListaRpc[];
  productosError?: string | null;
}) {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const [clienteId, setClienteId] = useState("");
  const [camionId, setCamionId] = useState("");
  const [choferId, setChoferId] = useState("");
  const [catalogo, setCatalogo] = useState<Record<string, ProductoListaRpc>>(() =>
    Object.fromEntries(productos.map((p) => [p.id, p])),
  );
  const [lineas, setLineas] = useState<Linea[]>([
    {
      producto_id: "",
      cantidad_solicitada: 1,
      valor_unitario_recaudar: 0,
    },
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
  }

  function removeLinea(index: number) {
    setLineas((prev) => prev.filter((_, i) => i !== index));
  }

  function registrarProducto(producto: ProductoListaRpc) {
    setCatalogo((prev) => ({ ...prev, [producto.id]: producto }));
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
          {choferesError ? (
            <p className="mt-2 text-sm text-lt-danger-text">{choferesError}</p>
          ) : null}
          {choferesAviso ? (
            <p className="mt-2 text-sm text-amber-700">{choferesAviso}</p>
          ) : null}
        </Card>

        <Card
          title="Detalle de productos"
          action={
            <Button type="button" variant="secondary" onClick={addLinea}>
              Agregar línea
            </Button>
          }
        >
          {productosError ? (
            <p className="mb-4 text-sm text-lt-danger-text">{productosError}</p>
          ) : null}
          <div className="space-y-4">
            {lineas.map((linea, index) => (
              <LineaProductoRow
                key={index}
                linea={linea}
                catalogo={productos}
                producto={
                  linea.producto_id
                    ? catalogo[linea.producto_id]
                    : undefined
                }
                onLineaChange={(patch) => updateLinea(index, patch)}
                onProductoCatalogo={registrarProducto}
                onRemove={() => removeLinea(index)}
                canRemove={lineas.length > 1}
              />
            ))}
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
