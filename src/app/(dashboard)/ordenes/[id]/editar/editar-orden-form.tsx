"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { actualizaOrdenDistribucionAction } from "@/lib/actions/ordenes";
import { PageHeader } from "@/components/layout/page-header";
import { Card } from "@/components/ui/card";
import { Select } from "@/components/ui/select";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { LineaProductoRow } from "../../nuevo/linea-producto-row";
import { formatDateOnly, formatNumber } from "@/lib/format";
import type { ProductoListaRpc, TasaCambio } from "@/types/database";

type Option = { value: string; label: string };

type Linea = {
  producto_id: string;
  cantidad_solicitada: number;
  valor_unitario_recaudar: number;
};

export function EditarOrdenForm({
  correlativo,
  ordenId,
  initial,
  clientes,
  camiones,
  choferes,
  productos,
  tasaActual = null,
  ordenTasa = null,
}: {
  correlativo: number;
  ordenId: string;
  initial: {
    cliente_id: string;
    camion_id: string;
    chofer_id: string;
    factura_origen_numero: string;
    fecha_despacho: string;
    lineas: Linea[];
  };
  clientes: Option[];
  camiones: Option[];
  choferes: Option[];
  productos: ProductoListaRpc[];
  tasaActual?: TasaCambio | null;
  ordenTasa?: number | null;
}) {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const [clienteId, setClienteId] = useState(initial.cliente_id);
  const [camionId, setCamionId] = useState(initial.camion_id);
  const [choferId, setChoferId] = useState(initial.chofer_id);
  const [factura, setFactura] = useState(initial.factura_origen_numero);
  const [fechaDespacho, setFechaDespacho] = useState(initial.fecha_despacho);
  const [catalogo, setCatalogo] = useState<Record<string, ProductoListaRpc>>(
    () => Object.fromEntries(productos.map((p) => [p.id, p])),
  );
  const [lineas, setLineas] = useState<Linea[]>(
    initial.lineas.length
      ? initial.lineas
      : [{ producto_id: "", cantidad_solicitada: 1, valor_unitario_recaudar: 0 }],
  );

  function updateLinea(index: number, patch: Partial<Linea>) {
    setLineas((prev) =>
      prev.map((linea, i) => (i === index ? { ...linea, ...patch } : linea)),
    );
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setPending(true);
    setError(null);

    const result = await actualizaOrdenDistribucionAction({
      correlativo,
      cliente_id: clienteId,
      camion_id: camionId,
      chofer_id: choferId,
      factura_origen_numero: factura,
      fecha_despacho: fechaDespacho || null,
      lineas: lineas.filter((l) => l.producto_id),
    });

    if (result?.error) {
      setError(
        result.code === "EXCEPCION_TASA_NO_ENCONTRADA"
          ? `${result.error} Regístrala en Tasas de cambio.`
          : result.error,
      );
      setPending(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-6">
      <PageHeader
        title={`Editar orden #${correlativo}`}
        description="Solo se puede editar en borrador. Debe existir tasa del día."
      />

      <Card title="Cabecera">
        <div className="grid gap-3 sm:grid-cols-2">
          <Select
            label="Cliente"
            required
            options={clientes}
            value={clienteId}
            onChange={(e) => setClienteId(e.target.value)}
          />
          <Input
            label="Factura origen"
            value={factura}
            onChange={(e) => setFactura(e.target.value)}
          />
          <Select
            label="Camión"
            required
            options={camiones}
            value={camionId}
            onChange={(e) => setCamionId(e.target.value)}
          />
          <Select
            label="Chofer"
            required
            options={choferes}
            value={choferId}
            onChange={(e) => setChoferId(e.target.value)}
          />
          <Input
            label="Fecha despacho"
            type="datetime-local"
            value={fechaDespacho}
            onChange={(e) => setFechaDespacho(e.target.value)}
          />
          <Input
            label="Tasa de cambio"
            readOnly
            value={
              tasaActual
                ? `${formatNumber(Number(tasaActual.tasa_cambio))} (${formatDateOnly(tasaActual.fecha_tasa)})`
                : ordenTasa != null
                  ? formatNumber(Number(ordenTasa))
                  : "Sin tasa registrada"
            }
          />
        </div>
      </Card>

      <Card title="Detalle de productos">
        <div className="space-y-4">
          {lineas.map((linea, index) => (
            <LineaProductoRow
              key={index}
              linea={linea}
              catalogo={productos}
              producto={
                linea.producto_id ? catalogo[linea.producto_id] : undefined
              }
              onLineaChange={(patch) => updateLinea(index, patch)}
              onProductoCatalogo={(p) =>
                setCatalogo((prev) => ({ ...prev, [p.id]: p }))
              }
              onRemove={() =>
                setLineas((prev) => prev.filter((_, i) => i !== index))
              }
              canRemove={lineas.length > 1}
            />
          ))}
        </div>
        <div className="mt-4 flex justify-center">
          <Button
            type="button"
            variant="secondary"
            onClick={() =>
              setLineas((prev) => [
                ...prev,
                {
                  producto_id: "",
                  cantidad_solicitada: 1,
                  valor_unitario_recaudar: 0,
                },
              ])
            }
          >
            Agrega otro producto
          </Button>
        </div>
      </Card>

      {error ? <p className="lt-alert-error">{error}</p> : null}

      <div className="flex gap-3">
        <Button type="submit" disabled={pending}>
          {pending ? "Guardando…" : "Guardar cambios"}
        </Button>
        <Button
          type="button"
          variant="secondary"
          onClick={() => router.push(`/ordenes/${ordenId}`)}
        >
          Cancelar
        </Button>
      </div>
    </form>
  );
}
