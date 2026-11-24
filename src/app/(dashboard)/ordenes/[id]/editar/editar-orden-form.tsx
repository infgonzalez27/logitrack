"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { actualizaOrdenDistribucionAction } from "@/lib/actions/ordenes";
import { listarProductosAction } from "@/lib/actions/productos";
import { PageHeader } from "@/components/layout/page-header";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { ProductoCatalogo } from "@/components/productos/producto-catalogo";
import { ClienteCombobox } from "@/components/clientes/cliente-combobox";
import type { ClienteOrdenOption } from "../../nuevo/nueva-orden-form";
import { FechaDespachoField } from "@/components/ui/fecha-despacho-field";
import { LogiImage } from "@/components/media/logi-image";
import { resolveProductoImage } from "@/lib/product-images";
import { formatDateOnly, formatNumber } from "@/lib/format";
import type { ProductoListaRpc, TasaCambio } from "@/types/database";

type Linea = {
  producto_id: string;
  cantidad_solicitada: number;
  valor_unitario_usd: number;
};

export function EditarOrdenForm({
  correlativo,
  ordenId,
  initial,
  clientes,
  productos,
  productosError = null,
  tasaActual = null,
  ordenTasa = null,
}: {
  correlativo: number;
  ordenId: string;
  initial: {
    cliente_id: string;
    factura_origen_numero: string;
    fecha_despacho: string;
    lineas: Linea[];
  };
  clientes: ClienteOrdenOption[];
  productos: ProductoListaRpc[];
  productosError?: string | null;
  tasaActual?: TasaCambio | null;
  ordenTasa?: number | null;
}) {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const [clienteId, setClienteId] = useState(initial.cliente_id);
  const [factura, setFactura] = useState(initial.factura_origen_numero);
  const [fechaDespacho, setFechaDespacho] = useState(initial.fecha_despacho);
  const [catalogoProductos, setCatalogoProductos] =
    useState<ProductoListaRpc[]>(productos);
  const [catalogo, setCatalogo] = useState<Record<string, ProductoListaRpc>>(
    () => Object.fromEntries(productos.map((p) => [p.id, p])),
  );
  const [lineas, setLineas] = useState<Linea[]>(initial.lineas);

  const initialQuantities = useMemo<Record<string, number>>(() => {
    const map: Record<string, number> = {};
    for (const l of initial.lineas) {
      map[l.producto_id] = (map[l.producto_id] ?? 0) + l.cantidad_solicitada;
    }
    return map;
  }, [initial.lineas]);

  function maxPermitido(productoId: string): number | null {
    const producto = catalogo[productoId];
    if (!producto) return null;
    const disp = Math.max(0, Math.floor(producto.stock_disponible));
    const previo = Math.max(0, Math.floor(initialQuantities[productoId] ?? 0));
    return disp + previo;
  }

  const clienteSeleccionado = useMemo(
    () => clientes.find((c) => c.value === clienteId) ?? null,
    [clientes, clienteId],
  );

  useEffect(() => {
    setCatalogoProductos(productos);
    setCatalogo((prev) => ({
      ...prev,
      ...Object.fromEntries(productos.map((p) => [p.id, p])),
    }));
  }, [productos]);

  useEffect(() => {
    if (!clienteId) return;

    let active = true;
    void listarProductosAction(".F.", clienteId).then((res) => {
      if (!active) return;
      if (!res.ok) return;

      setCatalogoProductos(res.productos);
      setCatalogo((prev) => ({
        ...prev,
        ...Object.fromEntries(res.productos.map((p) => [p.id, p])),
      }));
    });

    return () => {
      active = false;
    };
  }, [clienteId]);

  function agregarProducto(producto: ProductoListaRpc, cantidad: number) {
    const disp = Math.max(0, Math.floor(producto.stock_disponible));
    const previo = Math.max(0, Math.floor(initialQuantities[producto.id] ?? 0));
    const maxStock = disp + previo;
    if (maxStock <= 0) {
      setError(`Sin existencia en almacén para ${producto.nombre}.`);
      return;
    }
    const qty = Math.max(1, Math.floor(cantidad) || 1);
    setCatalogo((prev) => ({ ...prev, [producto.id]: producto }));
    let excedio = false;
    setLineas((prev) => {
      const existente = prev.find((l) => l.producto_id === producto.id);
      if (existente) {
        const propuesta = existente.cantidad_solicitada + qty;
        if (propuesta > maxStock) {
          excedio = true;
        }
        return prev.map((l) =>
          l.producto_id === producto.id
            ? { ...l, cantidad_solicitada: Math.min(maxStock, propuesta) }
            : l,
        );
      }
      if (qty > maxStock) {
        excedio = true;
      }
      return [
        ...prev,
        {
          producto_id: producto.id,
          cantidad_solicitada: Math.min(maxStock, qty),
          valor_unitario_usd:
            producto.precio_final_usd ??
            producto.precio ??
            producto.precio_lista1 ??
            0,
        },
      ];
    });
    if (excedio) {
      setError(
        `Stock insuficiente en almacén para ${producto.nombre}: máximo permitido ${maxStock}.`,
      );
    } else {
      setError(null);
    }
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

    for (const linea of lineas) {
      const maxStock = maxPermitido(linea.producto_id);
      if (maxStock !== null && linea.cantidad_solicitada > maxStock) {
        const producto = catalogo[linea.producto_id];
        setError(
          `Stock insuficiente en almacén para ${producto?.nombre ?? "el producto"} (Máximo permitido: ${maxStock}, Solicitado: ${linea.cantidad_solicitada}).`,
        );
        setPending(false);
        return;
      }
    }

    const result = await actualizaOrdenDistribucionAction({
      correlativo,
      cliente_id: clienteId,
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
        description="Se puede editar mientras esté aprobada y aún no se haya cargado al camión."
      />

      <Card title="Cabecera">
        <div className="grid gap-3 sm:grid-cols-2">
          <ClienteCombobox
            required
            options={clientes}
            value={clienteId}
            onChange={setClienteId}
          />
          <Input
            label="Factura origen"
            value={factura}
            onChange={(e) => setFactura(e.target.value)}
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
        {productosError ? (
          <p className="lt-alert-error mb-4">{productosError}</p>
        ) : null}
        <ProductoCatalogo
          productos={catalogoProductos}
          onAdd={agregarProducto}
          selectedIds={lineas.map((l) => l.producto_id)}
          selectedQuantities={Object.fromEntries(
            lineas.map((l) => [
              l.producto_id,
              Math.max(
                0,
                l.cantidad_solicitada - (initialQuantities[l.producto_id] ?? 0),
              ),
            ]),
          )}
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
                        label={`Cantidad${maxPermitido(linea.producto_id) !== null ? ` (Máx: ${maxPermitido(linea.producto_id)})` : ""}`}
                        type="number"
                        min={1}
                        max={maxPermitido(linea.producto_id) ?? undefined}
                        required
                        value={linea.cantidad_solicitada}
                        onChange={(e) => {
                          const maxStock = maxPermitido(linea.producto_id);
                          const raw = Math.floor(Number(e.target.value));
                          let nextQty = Number.isFinite(raw)
                            ? Math.max(1, raw)
                            : 1;
                          if (maxStock !== null && nextQty > maxStock) {
                            nextQty = Math.max(1, maxStock);
                            setError(
                              `Stock insuficiente en almacén para ${producto?.nombre ?? "el producto"}: máximo permitido ${maxStock}.`,
                            );
                          } else {
                            setError(null);
                          }
                          setLineas((prev) =>
                            prev.map((l) =>
                              l.producto_id === linea.producto_id
                                ? {
                                    ...l,
                                    cantidad_solicitada: nextQty,
                                  }
                                : l,
                            ),
                          );
                        }}
                      />
                      <Input
                        label="Precio unitario (USD)"
                        type="number"
                        min={0}
                        step="0.01"
                        required
                        value={linea.valor_unitario_usd}
                        onChange={(e) =>
                          setLineas((prev) =>
                            prev.map((l) =>
                              l.producto_id === linea.producto_id
                                ? {
                                    ...l,
                                    valor_unitario_usd: Number(
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
