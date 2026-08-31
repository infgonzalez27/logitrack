"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { actualizaOrdenDistribucionAction } from "@/lib/actions/ordenes";
import { PageHeader } from "@/components/layout/page-header";
import { Card } from "@/components/ui/card";
import { Select } from "@/components/ui/select";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { ProductoCatalogo } from "../../nuevo/producto-catalogo";
import type { ClienteOrdenOption } from "../../nuevo/nueva-orden-form";
import { FechaDespachoField } from "@/components/ui/fecha-despacho-field";
import { LogiImage } from "@/components/media/logi-image";
import { resolveProductoImage } from "@/lib/product-images";
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
  productos,
  tasaActual = null,
  ordenTasa = null,
}: {
  correlativo: number;
  ordenId: string;
  initial: {
    cliente_id: string;
    camion_id: string;
    factura_origen_numero: string;
    fecha_despacho: string;
    lineas: Linea[];
  };
  clientes: ClienteOrdenOption[];
  camiones: Option[];
  productos: ProductoListaRpc[];
  tasaActual?: TasaCambio | null;
  ordenTasa?: number | null;
}) {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const [clienteId, setClienteId] = useState(initial.cliente_id);
  const [camionId, setCamionId] = useState(initial.camion_id);
  const [factura, setFactura] = useState(initial.factura_origen_numero);
  const [fechaDespacho, setFechaDespacho] = useState(initial.fecha_despacho);
  const [catalogo, setCatalogo] = useState<Record<string, ProductoListaRpc>>(
    () => Object.fromEntries(productos.map((p) => [p.id, p])),
  );
  const [lineas, setLineas] = useState<Linea[]>(initial.lineas);

  const clienteSeleccionado = useMemo(
    () => clientes.find((c) => c.value === clienteId) ?? null,
    [clientes, clienteId],
  );

  function agregarProducto(producto: ProductoListaRpc, cantidad: number) {
    const qty = Math.max(1, Math.floor(cantidad) || 1);
    setCatalogo((prev) => ({ ...prev, [producto.id]: producto }));
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
          valor_unitario_recaudar:
            producto.precio_lista1 ?? producto.precio ?? 0,
        },
      ];
    });
  }

  async function handleSubmit(e: React.FormEvent) {
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
      setError("Agrega al menos un producto.");
      setPending(false);
      return;
    }
    if (!fechaDespacho.trim()) {
      setError("La fecha de despacho es obligatoria para el Radar.");
      setPending(false);
      return;
    }

    const result = await actualizaOrdenDistribucionAction({
      correlativo,
      cliente_id: clienteId,
      camion_id: camionId,
      factura_origen_numero: factura,
      fecha_despacho: fechaDespacho,
      lineas,
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
    <form onSubmit={handleSubmit} className="mx-auto max-w-6xl space-y-6">
      <PageHeader
        title={`Editar orden #${correlativo}`}
        description="Solo se puede editar en borrador. Debe existir tasa del día."
      />

      <Card title="Cabecera">
        <div className="grid gap-3 sm:grid-cols-2">
          <Select
            label="Cliente"
            required
            options={clientes.map((c) => ({
              value: c.value,
              label: c.label,
            }))}
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
          <Input
            label="Despachador del cliente"
            readOnly
            value={
              clienteSeleccionado?.despachador_nombre ||
              "Sin despachador asignado"
            }
          />
          <FechaDespachoField
            required
            value={fechaDespacho}
            onChange={setFechaDespacho}
          />
          <p className="text-xs text-lt-text-muted sm:col-span-2">
            La fecha de entrega, junto con el despachador del cliente, es la
            clave para agrupar la orden en el Radar.
          </p>
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

      <Card title="Catálogo de productos">
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
                          setLineas((prev) =>
                            prev.map((l) =>
                              l.producto_id === linea.producto_id
                                ? {
                                    ...l,
                                    cantidad_solicitada: Number(e.target.value),
                                  }
                                : l,
                            ),
                          )
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
                          setLineas((prev) =>
                            prev.map((l) =>
                              l.producto_id === linea.producto_id
                                ? {
                                    ...l,
                                    valor_unitario_recaudar: Number(
                                      e.target.value,
                                    ),
                                  }
                                : l,
                            ),
                          )
                        }
                      />
                    </div>
                  </div>
                  <Button
                    type="button"
                    variant="ghost"
                    onClick={() =>
                      setLineas((prev) =>
                        prev.filter((l) => l.producto_id !== linea.producto_id),
                      )
                    }
                  >
                    Quitar
                  </Button>
                </li>
              );
            })}
          </ul>
        )}
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
