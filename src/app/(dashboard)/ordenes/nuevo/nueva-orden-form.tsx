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
};

export function NuevaOrdenForm({
  choferes,
  productos,
}: {
  choferes: Option[];
  productos: ProductoOption[];
}) {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const [choferId, setChoferId] = useState("");
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

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setPending(true);
    setError(null);

    const result = await createOrdenAction({
      chofer_id: choferId,
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
        description="Solicitud al despacho — estado inicial: borrador"
      />

      <form onSubmit={handleSubmit} className="space-y-6">
        <Card title="Asignación">
          <Select
            label="Chofer"
            name="chofer_id"
            required
            placeholder="Selecciona chofer"
            options={choferes}
            value={choferId}
            onChange={(e) => setChoferId(e.target.value)}
          />
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
                className="grid gap-3 rounded-xl border border-lt-border-light bg-lt-surface-muted/50 p-4 sm:grid-cols-4"
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
                  label="Precio unitario"
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

          <div className="mt-4 flex flex-wrap gap-6 text-sm text-lt-text-muted">
            <p>
              Peso estimado:{" "}
              <span className="font-medium text-lt-text">
                {pesoEstimado.toFixed(2)} kg
              </span>
            </p>
            <p>
              Total a recaudar:{" "}
              <span className="font-medium text-lt-text">
                ${totalRecaudar.toFixed(2)}
              </span>
            </p>
          </div>
        </Card>

        {error && <p className="lt-alert-error">{error}</p>}

        <div className="flex gap-3">
          <Button type="submit" disabled={pending}>
            {pending ? "Guardando…" : "Solicitar orden"}
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
