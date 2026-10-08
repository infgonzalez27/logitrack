"use client";

import { useMemo, useRef, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import {
  crearVentaDirectaAlmacenAction,
  type VentaDirectaResultado,
} from "@/lib/actions/venta-directa";
import { listarProductosAction } from "@/lib/actions/productos";
import { obtenerSaldosEnvasesClienteAction } from "@/lib/actions/autoventas";
import {
  EnvasesResumenTabla,
  EnvasesVentaFields,
} from "@/components/contenedores/envases-venta";
import {
  calcularEnvasesEntregados,
  type TipoEnvase,
} from "@/lib/contenedores/envases-venta";
import { PageHeader } from "@/components/layout/page-header";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { ProductoCatalogo } from "@/components/productos/producto-catalogo";
import {
  ClienteCombobox,
  type ClienteComboboxOption,
} from "@/components/clientes/cliente-combobox";
import { formatDateOnly, formatNumber } from "@/lib/format";
import type { ProductoListaRpc, TasaCambio } from "@/types/database";

type Linea = {
  producto_id: string;
  cantidad: number;
  valor_unitario_usd: number;
};

function precioNetoProducto(producto: ProductoListaRpc): number {
  return producto.precio_final_usd ?? producto.precio ?? producto.precio_lista1 ?? 0;
}

export function VentaDirectaForm({
  clientes,
  productos,
  productosError = null,
  tasaActual = null,
  tiposEnvase = [],
}: {
  clientes: ClienteComboboxOption[];
  productos: ProductoListaRpc[];
  productosError?: string | null;
  tasaActual?: TasaCambio | null;
  tiposEnvase?: TipoEnvase[];
}) {
  const router = useRouter();
  const [clienteId, setClienteId] = useState("");
  const [catalogoProductos, setCatalogoProductos] = useState<ProductoListaRpc[]>(productos);
  const [catalogo, setCatalogo] = useState<Record<string, ProductoListaRpc>>(() =>
    Object.fromEntries(productos.map((p) => [p.id, p])),
  );
  const [lineas, setLineas] = useState<Linea[]>([]);
  const [cargandoPrecios, setCargandoPrecios] = useState(false);
  const [confirmando, setConfirmando] = useState(false);
  const [pending, setPending] = useState(false);
  const [esCortesia, setEsCortesia] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [venta, setVenta] = useState<VentaDirectaResultado | null>(null);
  const peticionPrecios = useRef(0);
  const [saldosEnvases, setSaldosEnvases] = useState<Record<string, number> | null>(null);
  const [cargandoSaldos, setCargandoSaldos] = useState(false);
  const [retiradosEnvases, setRetiradosEnvases] = useState<Record<string, string>>({});

  const envasesEntregados = useMemo(
    () =>
      calcularEnvasesEntregados(
        lineas.map((l) => ({
          cantidad: l.cantidad,
          contenedor_id: catalogo[l.producto_id]?.contenedor_id,
          unidades_por_contenedor: catalogo[l.producto_id]?.unidades_por_contenedor,
        })),
      ),
    [lineas, catalogo],
  );

  async function seleccionarCliente(id: string) {
    setClienteId(id);
    setRetiradosEnvases({});
    setSaldosEnvases(null);
    const peticion = ++peticionPrecios.current;
    if (!id) {
      setCargandoPrecios(false);
      setCargandoSaldos(false);
      return;
    }
    setCargandoSaldos(true);
    void obtenerSaldosEnvasesClienteAction(id).then((res) => {
      if (peticion !== peticionPrecios.current) return;
      setCargandoSaldos(false);
      setSaldosEnvases(res.success && res.data ? res.data : {});
    });
    setCargandoPrecios(true);
    const res = await listarProductosAction(".F.", id);
    if (peticion !== peticionPrecios.current) return;
    setCargandoPrecios(false);
    if (!res.ok) return;
    setCatalogoProductos(res.productos);
    setCatalogo(Object.fromEntries(res.productos.map((p) => [p.id, p])));
    setLineas((prev) =>
      prev.map((linea) => {
        const p = res.productos.find((prod) => prod.id === linea.producto_id);
        return p ? { ...linea, valor_unitario_usd: precioNetoProducto(p) } : linea;
      }),
    );
  }

  const clienteLabel = useMemo(
    () => clientes.find((c) => c.value === clienteId)?.label ?? "",
    [clientes, clienteId],
  );

  const total = esCortesia ? 0 : lineas.reduce((acc, l) => acc + l.cantidad * l.valor_unitario_usd, 0);

  function agregarProducto(producto: ProductoListaRpc, cantidad: number) {
    const qty = Math.max(1, Math.floor(cantidad) || 1);
    setCatalogo((prev) => ({ ...prev, [producto.id]: producto }));
    setLineas((prev) => {
      const existente = prev.find((l) => l.producto_id === producto.id);
      if (existente) {
        return prev.map((l) =>
          l.producto_id === producto.id ? { ...l, cantidad: l.cantidad + qty } : l,
        );
      }
      return [
        ...prev,
        { producto_id: producto.id, cantidad: qty, valor_unitario_usd: precioNetoProducto(producto) },
      ];
    });
  }

  function updateLinea(productoId: string, patch: Partial<Linea>) {
    setLineas((prev) => prev.map((l) => (l.producto_id === productoId ? { ...l, ...patch } : l)));
  }

  function validar(): string | null {
    if (!clienteId) return "Selecciona un cliente.";
    if (!lineas.length) return "Agrega al menos un producto.";
    for (const l of lineas) {
      const p = catalogo[l.producto_id];
      const nombre = p?.nombre ?? "Producto";
      if (!Number.isInteger(l.cantidad) || l.cantidad <= 0) {
        return `«${nombre}»: la cantidad debe ser un entero mayor a 0.`;
      }
      if (p && l.cantidad > p.stock_disponible) {
        return `«${nombre}»: solo hay ${p.stock_disponible} en almacén.`;
      }
      if (!Number.isFinite(l.valor_unitario_usd) || l.valor_unitario_usd < 0) {
        return `«${nombre}»: el precio no puede ser negativo.`;
      }
    }
    return null;
  }

  function pedirConfirmacion(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const msg = validar();
    setError(msg);
    if (!msg) setConfirmando(true);
  }

  async function registrar() {
    setPending(true);
    setError(null);
    const res = await crearVentaDirectaAlmacenAction({
      cliente_id: clienteId,
      lineas,
      tasa_cambio: tasaActual?.tasa_cambio ?? null,
      retirados: Object.entries(retiradosEnvases)
        .map(([contenedor_id, v]) => ({ contenedor_id, cantidad_retirada: Number(v) || 0 }))
        .filter((r) => r.cantidad_retirada > 0),
      es_cortesia: esCortesia,
    });
    setPending(false);
    setConfirmando(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    setVenta(res.venta);
    router.refresh();
  }

  function nuevaVenta() {
    setVenta(null);
    setLineas([]);
    setClienteId("");
    setRetiradosEnvases({});
    setSaldosEnvases(null);
    setCatalogoProductos(productos);
    setCatalogo(Object.fromEntries(productos.map((p) => [p.id, p])));
  }

  if (venta) {
    return (
      <div className="mx-auto max-w-2xl space-y-6">
        <PageHeader title="Venta directa registrada" />
        <Card>
          <div className="space-y-2 text-sm">
            <p>
              Orden <span className="font-semibold">#{venta.correlativo ?? "—"}</span> para{" "}
              <span className="font-semibold">{clienteLabel || "el cliente"}</span> por{" "}
              <span className="font-semibold">${formatNumber(venta.total_recaudar_usd)}</span>.
            </p>
            <p className="text-lt-text-muted">
              La mercancía ya se descontó del almacén. La orden queda por liquidar hasta registrar
              el cobro en Cobranzas.
            </p>
          </div>
          {venta.contenedores.length ? (
            <div className="mt-4 space-y-1">
              <h3 className="text-sm font-semibold text-lt-text">Resumen de envases</h3>
              <EnvasesResumenTabla filas={venta.contenedores} />
            </div>
          ) : null}
          <div className="mt-4 flex flex-wrap gap-3">
            <Link href={`/ordenes/${venta.orden_id}/imprimir`}>
              <Button type="button">Imprimir</Button>
            </Link>
            <Link href={`/rendiciones/nuevo?cliente_id=${clienteId}`}>
              <Button type="button" variant="secondary">
                Registrar cobro
              </Button>
            </Link>
            <Link href={`/ordenes/${venta.orden_id}`}>
              <Button type="button" variant="ghost">
                Ver orden
              </Button>
            </Link>
            <Button type="button" variant="ghost" onClick={nuevaVenta}>
              Nueva venta
            </Button>
          </div>
        </Card>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <PageHeader
        title="Venta directa en almacén"
        description="Venta en mostrador: descuenta del almacén, sin camión ni radar."
      />

      <form onSubmit={pedirConfirmacion} className="space-y-6">
        <Card title="Cliente">
          <div className="grid gap-4 sm:grid-cols-2">
            <ClienteCombobox
              required
              minChars={2}
              options={clientes}
              value={clienteId}
              onChange={(id) => void seleccionarCliente(id)}
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
          {!tasaActual ? (
            <p className="mt-2 text-sm text-amber-700">
              No hay tasa registrada. Regístrala en Tasas de cambio.
            </p>
          ) : null}
          <div className="mt-4 flex items-center gap-2">
            <input
              type="checkbox"
              id="cortesia-check"
              className="h-4 w-4 rounded border-gray-300 text-blue-600 focus:ring-blue-500"
              checked={esCortesia}
              onChange={(e) => setEsCortesia(e.target.checked)}
            />
            <label htmlFor="cortesia-check" className="text-sm font-medium text-lt-text">
              Marcar como orden de cortesía (Precio final $0.00)
            </label>
          </div>
        </Card>

        <Card title="Catálogo de productos">
          {productosError ? (
            <p className="mb-4 text-sm text-lt-danger-text">{productosError}</p>
          ) : null}
          {!clienteId ? (
            <p className="mb-4 text-sm text-amber-700">
              Selecciona un cliente para ver sus precios con descuento.
            </p>
          ) : cargandoPrecios ? (
            <p className="mb-4 text-sm text-lt-text-muted">Actualizando precios del cliente…</p>
          ) : null}
          <ProductoCatalogo
            productos={catalogoProductos}
            onAdd={agregarProducto}
            selectedIds={lineas.map((l) => l.producto_id)}
          />
        </Card>

        <Card title="Productos de la venta">
          {!lineas.length ? (
            <p className="text-sm text-lt-text-muted">Agrega productos desde el catálogo.</p>
          ) : (
            <ul className="space-y-3">
              {lineas.map((linea) => {
                const producto = catalogo[linea.producto_id];
                return (
                  <li
                    key={linea.producto_id}
                    className="grid gap-3 rounded-xl border border-lt-border-light bg-lt-surface-muted/40 p-3 sm:grid-cols-[1fr_auto]"
                  >
                    <div className="min-w-0 space-y-2">
                      <p className="text-sm font-medium text-lt-text">
                        {producto?.nombre ?? "Producto"}
                        <span className="ml-2 text-xs font-normal text-lt-text-muted">
                          Disponible: {producto?.stock_disponible ?? "—"}
                        </span>
                      </p>
                      <div className="grid grid-cols-3 gap-2">
                        <Input
                          label="Cantidad"
                          type="number"
                          min={1}
                          step={1}
                          required
                          value={linea.cantidad}
                          onChange={(e) =>
                            updateLinea(linea.producto_id, { cantidad: Number(e.target.value) })
                          }
                        />
                        <Input
                          label="Precio unitario (USD)"
                          type="number"
                          min={0}
                          step="0.01"
                          required
                          readOnly={esCortesia}
                          value={esCortesia ? 0 : linea.valor_unitario_usd}
                          onChange={(e) =>
                            !esCortesia && updateLinea(linea.producto_id, {
                              valor_unitario_usd: Number(e.target.value),
                            })
                          }
                        />
                        <Input
                          label="Subtotal (USD)"
                          readOnly
                          value={formatNumber(esCortesia ? 0 : linea.cantidad * linea.valor_unitario_usd)}
                        />
                      </div>
                    </div>
                    <div className="flex items-start justify-end">
                      <Button
                        type="button"
                        variant="ghost"
                        onClick={() =>
                          setLineas((prev) => prev.filter((l) => l.producto_id !== linea.producto_id))
                        }
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
            Total (USD): <span className="font-medium text-lt-text">${formatNumber(total)}</span>
          </p>
        </Card>

        <Card>
          <EnvasesVentaFields
            tipos={tiposEnvase}
            clienteSeleccionado={Boolean(clienteId)}
            cargandoSaldos={cargandoSaldos}
            saldos={saldosEnvases}
            entregados={envasesEntregados}
            retirados={retiradosEnvases}
            onRetiradosChange={(id, valor) =>
              setRetiradosEnvases((prev) => ({ ...prev, [id]: valor }))
            }
          />
        </Card>

        {error && <p className="lt-alert-error">{error}</p>}

        {confirmando ? (
          <Card>
            <p className="text-sm">
              ¿Registrar la venta a <span className="font-semibold">{clienteLabel}</span> por{" "}
              <span className="font-semibold">${formatNumber(total)}</span>? Se descontará del
              almacén de inmediato.
            </p>
            <div className="mt-4 flex gap-3">
              <Button type="button" disabled={pending} onClick={registrar}>
                {pending ? "Registrando…" : "Sí, registrar venta"}
              </Button>
              <Button
                type="button"
                variant="secondary"
                disabled={pending}
                onClick={() => setConfirmando(false)}
              >
                Revisar
              </Button>
            </div>
          </Card>
        ) : (
          <div className="flex gap-3">
            <Button type="submit">Registrar venta</Button>
            <Button type="button" variant="secondary" onClick={() => router.push("/ordenes")}>
              Cancelar
            </Button>
          </div>
        )}
      </form>
    </div>
  );
}
