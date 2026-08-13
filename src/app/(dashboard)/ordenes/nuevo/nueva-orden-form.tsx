"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createOrdenAction } from "@/lib/actions/ordenes";
import { PageHeader } from "@/components/layout/page-header";
import { Card } from "@/components/ui/card";
import { Select } from "@/components/ui/select";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { LineaProductoRow } from "./linea-producto-row";
import { formatDateOnly, formatNumber } from "@/lib/format";
import type { ProductoListaRpc, TasaCambio } from "@/types/database";

type Option = { value: string; label: string };

export type ClienteOrdenOption = Option & {
  despachador_id: string | null;
  despachador_nombre: string | null;
};

type Linea = {
  producto_id: string;
  cantidad_solicitada: number;
  valor_unitario_recaudar: number;
};

export function NuevaOrdenForm({
  clientes,
  camiones,
  camionesError = null,
  productos,
  productosError = null,
  tasaActual = null,
}: {
  clientes: ClienteOrdenOption[];
  camiones: Option[];
  camionesError?: string | null;
  productos: ProductoListaRpc[];
  productosError?: string | null;
  tasaActual?: TasaCambio | null;
}) {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const [clienteId, setClienteId] = useState("");
  const [camionId, setCamionId] = useState("");
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

  const clienteSeleccionado = useMemo(
    () => clientes.find((c) => c.value === clienteId) ?? null,
    [clientes, clienteId],
  );

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

    if (!clienteSeleccionado?.despachador_id) {
      setError(
        "El cliente no tiene despachador asignado. Asígnalo en la ficha del cliente.",
      );
      setPending(false);
      return;
    }

    const result = await createOrdenAction({
      cliente_id: clienteId,
      camion_id: camionId,
      lineas: lineas.filter((l) => l.producto_id),
      tasa_cambio: tasaActual?.tasa_cambio ?? null,
    });

    if (result?.error) {
      const msg = String(result.error);
      setError(
        msg.toLowerCase().includes("tasa")
          ? `${msg} Regístrala en Tasas de cambio.`
          : msg,
      );
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
              options={clientes.map((c) => ({
                value: c.value,
                label: c.label,
              }))}
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
            <Input
              label="Despachador del cliente"
              readOnly
              value={
                !clienteId
                  ? "Selecciona un cliente"
                  : clienteSeleccionado?.despachador_nombre ||
                    "Sin despachador asignado"
              }
            />
            <Input
              label="Tasa de cambio"
              readOnly
              value={
                tasaActual
                  ? `${formatNumber(Number(tasaActual.tasa_cambio))} (${formatDateOnly(tasaActual.fecha_tasa)})`
                  : "Sin tasa registrada"
              }
            />
          </div>
          {clienteId && !clienteSeleccionado?.despachador_id ? (
            <p className="mt-2 text-sm text-amber-700">
              Este cliente no tiene despachador. Asígnalo en{" "}
              <a href="/clientes/nuevo" className="underline">
                Clientes
              </a>{" "}
              antes de crear la orden.
            </p>
          ) : null}
          {!tasaActual ? (
            <p className="mt-2 text-sm text-amber-700">
              No hay tasa del día. Regístrala en{" "}
              <a href="/tasas-cambio" className="underline">
                Tasas de cambio
              </a>{" "}
              antes de crear la orden.
            </p>
          ) : null}
          {camionesError ? (
            <p className="mt-2 text-sm text-lt-danger-text">{camionesError}</p>
          ) : null}
        </Card>

        <Card title="Detalle de productos">
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

          <div className="mt-4 flex justify-center">
            <Button type="button" variant="secondary" onClick={addLinea}>
              Agrega otro producto
            </Button>
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
