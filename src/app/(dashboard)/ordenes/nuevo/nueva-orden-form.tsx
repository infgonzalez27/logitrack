"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createOrdenAction } from "@/lib/actions/ordenes";
import { PageHeader } from "@/components/layout/page-header";
import { Card } from "@/components/ui/card";
import { Select } from "@/components/ui/select";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { ProductoCatalogo } from "./producto-catalogo";
import { FechaDespachoField } from "@/components/ui/fecha-despacho-field";
import { LogiImage } from "@/components/media/logi-image";
import { resolveProductoImage } from "@/lib/product-images";
import { fechaHoyCaracas } from "@/lib/dates";
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

function defaultFechaDespachoLocal(): string {
  return `${fechaHoyCaracas()}T08:00`;
}

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
  const [fechaDespacho, setFechaDespacho] = useState(defaultFechaDespachoLocal);
  const [catalogo, setCatalogo] = useState<Record<string, ProductoListaRpc>>(
    () => Object.fromEntries(productos.map((p) => [p.id, p])),
  );
  const [lineas, setLineas] = useState<Linea[]>([]);

  const clienteSeleccionado = useMemo(
    () => clientes.find((c) => c.value === clienteId) ?? null,
    [clientes, clienteId],
  );

  function registrarProducto(producto: ProductoListaRpc) {
    setCatalogo((prev) => ({ ...prev, [producto.id]: producto }));
  }

  function agregarProducto(producto: ProductoListaRpc, cantidad: number) {
    const qty = Math.max(1, Math.floor(cantidad) || 1);
    registrarProducto(producto);
    setLineas((prev) => {
      const existente = prev.find((l) => l.producto_id === producto.id);
      if (existente) {
        return prev.map((l) =>
          l.producto_id === producto.id
            ? { ...l, cantidad_solicitada: l.cantidad_solicitada + qty }
            : l,
        );
      }
      return [
        ...prev,
        {
          producto_id: producto.id,
          cantidad_solicitada: qty,
          valor_unitario_recaudar: producto.precio_lista1 ?? producto.precio ?? 0,
        },
      ];
    });
  }

  function updateLinea(productoId: string, patch: Partial<Linea>) {
    setLineas((prev) =>
      prev.map((l) => (l.producto_id === productoId ? { ...l, ...patch } : l)),
    );
  }

  function removeLinea(productoId: string) {
    setLineas((prev) => prev.filter((l) => l.producto_id !== productoId));
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
    if (!lineas.length) {
      setError("Agrega al menos un producto a la orden.");
      setPending(false);
      return;
    }
    if (!fechaDespacho.trim()) {
      setError("La fecha de despacho es obligatoria para el Radar.");
      setPending(false);
      return;
    }

    const result = await createOrdenAction({
      cliente_id: clienteId,
      camion_id: camionId,
      fecha_despacho: fechaDespacho,
      lineas,
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
    <div className="mx-auto max-w-6xl space-y-6">
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
            <FechaDespachoField
              name="fecha_despacho"
              required
              value={fechaDespacho}
              onChange={setFechaDespacho}
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
          <p className="mt-2 text-xs text-lt-text-muted">
            La fecha de despacho define cuándo aparece la orden en el Radar del
            despachador.
          </p>
          {clienteId && !clienteSeleccionado?.despachador_id ? (
            <p className="mt-2 text-sm text-amber-700">
              Este cliente no tiene despachador. Asígnalo en Clientes antes de
              crear la orden.
            </p>
          ) : null}
          {!tasaActual ? (
            <p className="mt-2 text-sm text-amber-700">
              No hay tasa del día. Regístrala en Tasas de cambio.
            </p>
          ) : null}
          {camionesError ? (
            <p className="mt-2 text-sm text-lt-danger-text">{camionesError}</p>
          ) : null}
        </Card>

        <Card title="Catálogo de productos">
          {productosError ? (
            <p className="mb-4 text-sm text-lt-danger-text">{productosError}</p>
          ) : null}
          <ProductoCatalogo
            productos={productos}
            onAdd={agregarProducto}
            selectedIds={lineas.map((l) => l.producto_id)}
          />
        </Card>

        <Card title="Productos en la orden">
          {!lineas.length ? (
            <p className="text-sm text-lt-text-muted">
              Agrega productos desde el catálogo.
            </p>
          ) : (
            <ul className="space-y-3">
              {lineas.map((linea) => {
                const producto = catalogo[linea.producto_id];
                const fallback = producto
                  ? resolveProductoImage(producto.nombre)
                  : null;
                return (
                  <li
                    key={linea.producto_id}
                    className="grid gap-3 rounded-xl border border-lt-border-light bg-lt-surface-muted/40 p-3 sm:grid-cols-[72px_1fr_auto]"
                  >
                    <div className="flex h-16 w-16 items-center justify-center overflow-hidden rounded-lg bg-white">
                      <LogiImage
                        path={producto?.imagen_path}
                        type="producto"
                        alt={producto?.nombre ?? "Producto"}
                        fallbackSrc={fallback}
                        className="max-h-full max-w-full object-contain"
                      />
                    </div>
                    <div className="min-w-0 space-y-2">
                      <p className="truncate text-sm font-medium text-lt-text">
                        {producto?.nombre ?? "Producto"}
                      </p>
                      <div className="grid grid-cols-2 gap-2">
                        <Input
                          label="Cantidad"
                          type="number"
                          min={1}
                          required
                          value={linea.cantidad_solicitada}
                          onChange={(e) =>
                            updateLinea(linea.producto_id, {
                              cantidad_solicitada: Number(e.target.value),
                            })
                          }
                        />
                        <Input
                          label="Precio unitario"
                          type="number"
                          min={0}
                          step="0.01"
                          required
                          value={linea.valor_unitario_recaudar}
                          onChange={(e) =>
                            updateLinea(linea.producto_id, {
                              valor_unitario_recaudar: Number(e.target.value),
                            })
                          }
                        />
                      </div>
                    </div>
                    <div className="flex items-start justify-end">
                      <Button
                        type="button"
                        variant="ghost"
                        onClick={() => removeLinea(linea.producto_id)}
                      >
                        Quitar
                      </Button>
                    </div>
                  </li>
                );
              })}
            </ul>
          )}
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
