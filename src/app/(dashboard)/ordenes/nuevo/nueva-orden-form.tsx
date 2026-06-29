"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createOrdenAction } from "@/lib/actions/ordenes";
import { PageHeader } from "@/components/layout/page-header";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { Button } from "@/components/ui/button";

type Option = { value: string; label: string };
type ProductoOption = Option & { peso: number };

type Linea = {
  producto_id: string;
  cantidad_solicitada: number;
  valor_unitario_recaudar: number;
  secuencia_entrega: number;
};

export function NuevaOrdenForm({
  clientes,
  camiones,
  choferes,
  productos,
}: {
  clientes: Option[];
  camiones: Option[];
  choferes: Option[];
  productos: ProductoOption[];
}) {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const [lineas, setLineas] = useState<Linea[]>([
    {
      producto_id: "",
      cantidad_solicitada: 1,
      valor_unitario_recaudar: 0,
      secuencia_entrega: 1,
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
        secuencia_entrega: prev.length + 1,
      },
    ]);
  }

  function removeLinea(index: number) {
    setLineas((prev) => prev.filter((_, i) => i !== index));
  }

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setPending(true);
    setError(null);

    const form = new FormData(e.currentTarget);
    const result = await createOrdenAction({
      cliente_id: String(form.get("cliente_id")),
      camion_id: String(form.get("camion_id")),
      chofer_id: String(form.get("chofer_id")),
      factura_origen_numero: String(form.get("factura_origen_numero")).trim(),
      lineas: lineas.filter((l) => l.producto_id),
    });

    if (result?.error) {
      setError(result.error);
      setPending(false);
    }
  }

  const pesoEstimado = lineas.reduce((total, linea) => {
    const producto = productos.find((p) => p.value === linea.producto_id);
    return total + (producto?.peso ?? 0) * linea.cantidad_solicitada;
  }, 0);

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
            />
            <Input
              label="Nº factura origen"
              name="factura_origen_numero"
              required
            />
            <Select
              label="Camión"
              name="camion_id"
              required
              placeholder="Selecciona camión"
              options={camiones}
            />
            <Select
              label="Chofer"
              name="chofer_id"
              required
              placeholder="Selecciona chofer"
              options={choferes}
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
            {lineas.map((linea, index) => (
              <div
                key={index}
                className="grid gap-3 rounded-lg border border-zinc-100 p-4 sm:grid-cols-5"
              >
                <Select
                  label="Producto"
                  name={`producto_${index}`}
                  required
                  placeholder="Producto"
                  options={productos}
                  value={linea.producto_id}
                  onChange={(e) =>
                    updateLinea(index, { producto_id: e.target.value })
                  }
                />
                <Input
                  label="Cantidad"
                  type="number"
                  min="1"
                  value={linea.cantidad_solicitada}
                  onChange={(e) =>
                    updateLinea(index, {
                      cantidad_solicitada: Number(e.target.value),
                    })
                  }
                />
                <Input
                  label="Valor unit. recaudar"
                  type="number"
                  min="0"
                  step="0.01"
                  value={linea.valor_unitario_recaudar}
                  onChange={(e) =>
                    updateLinea(index, {
                      valor_unitario_recaudar: Number(e.target.value),
                    })
                  }
                />
                <Input
                  label="Secuencia"
                  type="number"
                  min="1"
                  value={linea.secuencia_entrega}
                  onChange={(e) =>
                    updateLinea(index, {
                      secuencia_entrega: Number(e.target.value),
                    })
                  }
                />
                <div className="flex items-end">
                  <Button
                    type="button"
                    variant="ghost"
                    onClick={() => removeLinea(index)}
                    disabled={lineas.length === 1}
                  >
                    Quitar
                  </Button>
                </div>
              </div>
            ))}
          </div>

          <div className="mt-4 flex flex-wrap gap-6 text-sm text-zinc-600">
            <p>
              Peso estimado:{" "}
              <span className="font-medium text-zinc-900">
                {pesoEstimado.toFixed(2)} kg
              </span>
            </p>
            <p>
              Total a recaudar:{" "}
              <span className="font-medium text-zinc-900">
                ${totalRecaudar.toFixed(2)}
              </span>
            </p>
          </div>
        </Card>

        {error && (
          <p className="rounded-lg bg-red-50 px-3 py-2 text-sm text-red-700">
            {error}
          </p>
        )}

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
