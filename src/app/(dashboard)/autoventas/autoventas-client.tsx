"use client";

import { useEffect, useMemo, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { LogiImage } from "@/components/media/logi-image";
import { ProductoCatalogo } from "@/components/productos/producto-catalogo";
import { resolveProductoImage } from "@/lib/product-images";
import { formatCurrency, formatNumber } from "@/lib/format";
import {
  cargarInventarioMovilAutoVentasAction,
  obtenerResumenAutoVentasJornada,
  registrarVentaEnRutaAction,
  reversarInventarioMovilAutoVentasAction,
} from "@/lib/actions/autoventas";
import type {
  ProductoListaRpc,
  ResumenAutoVentaData,
} from "@/types/database";

type CamionItem = {
  id: string;
  placa: string;
  modelo: string | null;
  estado: string;
};

type ClienteItem = {
  id: string;
  razon_social: string;
  rif_nit: string;
  direccion_fiscal: string | null;
};

type ContenedorItem = {
  id: string;
  codigo: string | null;
  nombre: string;
};

type InventarioMovilRow = {
  id: string;
  camion_id: string;
  producto_id: string;
  cantidad_cargada: number;
  cantidad_entregada: number;
  productos?: {
    codigo_producto: string;
    nombre: string;
    precio_lista1: number;
    imagen_path?: string | null;
  } | null;
};

type OrdenAutoVentaRow = {
  id: string;
  correlativo: number;
  factura_origen_numero: string;
  estado: string;
  total_recaudar_usd: number;
  total_recaudar_bs: number;
  created_at: string;
  camion_id: string;
  clientes?: { razon_social: string } | null;
};

type LineaCarga = {
  producto_id: string;
  cantidad: number;
};

type LineaVenta = {
  producto_id: string;
  cantidad: number;
  precio_unitario: number;
};

type LineaContenedor = {
  contenedor_id: string;
  cantidad_entregada: number;
  cantidad_retirada: number;
};

type Props = {
  camiones: CamionItem[];
  clientes: ClienteItem[];
  productos: ProductoListaRpc[];
  contenedores: ContenedorItem[];
  inventarioMovil: InventarioMovilRow[];
  ordenesJornada: OrdenAutoVentaRow[];
  vendedorId: string;
  tasaOficial: number;
};

const inputClass =
  "w-full rounded-xl border border-lt-border bg-lt-surface px-3 py-2 text-sm text-lt-text outline-none focus:border-lt-primary focus:ring-2 focus:ring-lt-primary/25";

export function AutoVentasClient({
  camiones,
  clientes,
  productos,
  contenedores,
  inventarioMovil,
  ordenesJornada,
  vendedorId,
  tasaOficial,
}: Props) {
  const router = useRouter();
  const [isPending, startTransition] = useTransition();
  const [camionId, setCamionId] = useState(camiones[0]?.id ?? "");
  const [tab, setTab] = useState<"resumen" | "venta" | "carga">("carga");
  const [mensaje, setMensaje] = useState<{
    tipo: "success" | "error";
    texto: string;
  } | null>(null);
  const [resumenRpc, setResumenRpc] = useState<ResumenAutoVentaData | null>(
    null,
  );
  const [cargandoResumen, setCargandoResumen] = useState(false);

  const [clienteId, setClienteId] = useState("");
  const [buscarCliente, setBuscarCliente] = useState("");
  const [observaciones, setObservaciones] = useState("");
  const [lineasVenta, setLineasVenta] = useState<LineaVenta[]>([]);
  const [lineasContenedor, setLineasContenedor] = useState<LineaContenedor[]>(
    [],
  );
  const [lineasCarga, setLineasCarga] = useState<LineaCarga[]>([]);
  const [catalogo, setCatalogo] = useState<Record<string, ProductoListaRpc>>(
    () => Object.fromEntries(productos.map((p) => [p.id, p])),
  );

  const inventarioCamion = useMemo(
    () => inventarioMovil.filter((i) => i.camion_id === camionId),
    [inventarioMovil, camionId],
  );

  const ordenesCamion = useMemo(
    () => ordenesJornada.filter((o) => o.camion_id === camionId),
    [ordenesJornada, camionId],
  );

  const clientesFiltrados = useMemo(() => {
    const q = buscarCliente.trim().toLowerCase();
    if (!q) return clientes;
    return clientes.filter(
      (c) =>
        c.razon_social.toLowerCase().includes(q) ||
        c.rif_nit.toLowerCase().includes(q),
    );
  }, [clientes, buscarCliente]);

  /** Catálogo para venta: stock = disponible en el camión seleccionado. */
  const productosParaVenta = useMemo((): ProductoListaRpc[] => {
    return productos
      .map((p) => {
        const inv = inventarioCamion.find((i) => i.producto_id === p.id);
        const disponible = Math.max(
          0,
          (inv?.cantidad_cargada ?? 0) - (inv?.cantidad_entregada ?? 0),
        );
        return { ...p, stock_disponible: disponible };
      })
      .filter((p) => p.stock_disponible > 0);
  }, [productos, inventarioCamion]);

  useEffect(() => {
    if (!camionId) {
      setResumenRpc(null);
      return;
    }
    let cancelled = false;
    setCargandoResumen(true);
    void obtenerResumenAutoVentasJornada(camionId).then((res) => {
      if (cancelled) return;
      setCargandoResumen(false);
      if (res.success && res.data) setResumenRpc(res.data);
      else setResumenRpc(null);
    });
    return () => {
      cancelled = true;
    };
  }, [camionId]);

  const ventasHoyCount =
    resumenRpc?.total_ordenes_autoventa ?? ordenesCamion.length;
  const totalFacturadoUsd =
    resumenRpc?.total_facturado_usd ??
    ordenesCamion.reduce((s, o) => s + o.total_recaudar_usd, 0);
  const totalFacturadoBs =
    resumenRpc?.total_facturado_bs ??
    ordenesCamion.reduce((s, o) => s + o.total_recaudar_bs, 0);
  const inventarioResumen =
    resumenRpc?.inventario_movil?.length
      ? resumenRpc.inventario_movil
      : inventarioCamion.map((item) => ({
          producto_id: item.producto_id,
          codigo: item.productos?.codigo_producto ?? "",
          nombre: item.productos?.nombre ?? "—",
          cantidad_cargada: item.cantidad_cargada,
          cantidad_entregada: item.cantidad_entregada,
          cantidad_disponible: Math.max(
            0,
            item.cantidad_cargada - item.cantidad_entregada,
          ),
        }));
  const ventasResumen =
    resumenRpc?.ventas?.length
      ? resumenRpc.ventas
      : ordenesCamion.map((o) => ({
          orden_id: o.id,
          correlativo: o.correlativo,
          factura_origen_numero: o.factura_origen_numero,
          cliente_nombre: o.clientes?.razon_social ?? "—",
          estado: o.estado,
          total_recaudar_usd: o.total_recaudar_usd,
          total_recaudar_bs: o.total_recaudar_bs,
          created_at: o.created_at,
        }));

  const totalVentaUsd = lineasVenta.reduce(
    (s, l) => s + l.cantidad * l.precio_unitario,
    0,
  );
  const totalCargaUnidades = lineasCarga.reduce((s, l) => s + l.cantidad, 0);

  function registrarEnCatalogo(producto: ProductoListaRpc) {
    setCatalogo((prev) => ({ ...prev, [producto.id]: producto }));
  }

  function agregarCarga(producto: ProductoListaRpc, cantidad: number) {
    const qty = Math.max(1, Math.floor(cantidad) || 1);
    registrarEnCatalogo(producto);
    setLineasCarga((prev) => {
      const idx = prev.findIndex((l) => l.producto_id === producto.id);
      if (idx >= 0) {
        const next = [...prev];
        next[idx] = {
          ...next[idx],
          cantidad: next[idx].cantidad + qty,
        };
        return next;
      }
      return [...prev, { producto_id: producto.id, cantidad: qty }];
    });
  }

  function agregarVenta(producto: ProductoListaRpc, cantidad: number) {
    const qty = Math.max(1, Math.floor(cantidad) || 1);
    registrarEnCatalogo(producto);
    const precio = Number(producto.precio_lista1 ?? producto.precio ?? 0);
    setLineasVenta((prev) => {
      const idx = prev.findIndex((l) => l.producto_id === producto.id);
      if (idx >= 0) {
        const next = [...prev];
        next[idx] = {
          ...next[idx],
          cantidad: next[idx].cantidad + qty,
        };
        return next;
      }
      return [
        ...prev,
        {
          producto_id: producto.id,
          cantidad: qty,
          precio_unitario: precio,
        },
      ];
    });
  }

  const handleGuardarVenta = () => {
    setMensaje(null);
    if (!camionId) {
      setMensaje({ tipo: "error", texto: "Selecciona un camión." });
      return;
    }
    if (!clienteId) {
      setMensaje({ tipo: "error", texto: "Selecciona un cliente." });
      return;
    }
    if (!lineasVenta.length) {
      setMensaje({ tipo: "error", texto: "Agrega al menos un producto." });
      return;
    }

    startTransition(async () => {
      const res = await registrarVentaEnRutaAction({
        vendedor_id: vendedorId,
        cliente_id: clienteId,
        camion_id: camionId,
        productos_json: lineasVenta.map((l) => ({
          producto_id: l.producto_id,
          cantidad: l.cantidad,
          precio_unitario: l.precio_unitario,
        })),
        contenedores_json: lineasContenedor
          .filter(
            (c) =>
              (c.cantidad_entregada || 0) > 0 || (c.cantidad_retirada || 0) > 0,
          )
          .map((c) => ({
            contenedor_id: c.contenedor_id,
            cantidad_entregada: c.cantidad_entregada,
            cantidad_retirada: c.cantidad_retirada,
          })),
        observaciones: observaciones || undefined,
        tasa_cambio: tasaOficial > 0 ? tasaOficial : undefined,
      });

      if (res.success) {
        setMensaje({
          tipo: "success",
          texto: res.message || "Venta registrada.",
        });
        setLineasVenta([]);
        setLineasContenedor([]);
        setObservaciones("");
        setTab("resumen");
        router.refresh();
      } else {
        setMensaje({
          tipo: "error",
          texto: res.message || "Error al registrar la venta.",
        });
      }
    });
  };

  const handleCargar = () => {
    setMensaje(null);
    if (!camionId || !lineasCarga.length) {
      setMensaje({
        tipo: "error",
        texto: "Selecciona camión y al menos un producto a cargar.",
      });
      return;
    }
    startTransition(async () => {
      const res = await cargarInventarioMovilAutoVentasAction(
        camionId,
        lineasCarga.map((l) => ({
          producto_id: l.producto_id,
          cantidad_solicitada: l.cantidad,
        })),
      );
      if (res.success) {
        setMensaje({
          tipo: "success",
          texto: res.message || "Inventario cargado.",
        });
        setLineasCarga([]);
        setTab("resumen");
        router.refresh();
      } else {
        setMensaje({
          tipo: "error",
          texto: res.message || "Error al cargar inventario.",
        });
      }
    });
  };

  const handleReversar = () => {
    if (!camionId) return;
    if (
      !confirm(
        "¿Devolver el stock sobrante de este camión al almacén central?",
      )
    ) {
      return;
    }
    setMensaje(null);
    startTransition(async () => {
      const res = await reversarInventarioMovilAutoVentasAction(camionId);
      if (res.success) {
        setMensaje({
          tipo: "success",
          texto: res.message || "Inventario devuelto.",
        });
        router.refresh();
      } else {
        setMensaje({
          tipo: "error",
          texto: res.message || "Error al devolver inventario.",
        });
      }
    });
  };

  const tabs: Array<{ id: typeof tab; label: string }> = [
    { id: "resumen", label: "Resumen de jornada" },
    { id: "venta", label: "Registrar venta" },
    { id: "carga", label: "Cargar almacén móvil" },
  ];

  return (
    <div className="space-y-6">
      {mensaje ? (
        <p
          className={
            mensaje.tipo === "success" ? "lt-alert-success" : "lt-alert-error"
          }
        >
          {mensaje.texto}
        </p>
      ) : null}

      <Card className="space-y-4 p-4">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
          <div className="min-w-[14rem] flex-1 space-y-1.5">
            <label className="block text-sm font-medium text-lt-text">
              Camión
            </label>
            <select
              value={camionId}
              onChange={(e) => setCamionId(e.target.value)}
              className={inputClass}
            >
              {camiones.length === 0 ? (
                <option value="">Sin camiones</option>
              ) : (
                camiones.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.placa}
                    {c.modelo ? ` — ${c.modelo}` : ""} ({c.estado})
                  </option>
                ))
              )}
            </select>
          </div>
          <p className="text-sm text-lt-text-muted">
            Tasa BCV:{" "}
            <span className="font-semibold text-lt-text">
              {formatNumber(tasaOficial)} Bs / USD
            </span>
          </p>
        </div>

        <div className="flex flex-wrap gap-2">
          {tabs.map((t) => (
            <button
              key={t.id}
              type="button"
              onClick={() => setTab(t.id)}
              className={`rounded-xl px-3 py-2 text-sm font-medium transition ${
                tab === t.id
                  ? "bg-lt-primary text-white"
                  : "bg-lt-surface-muted text-lt-text hover:bg-lt-primary-muted"
              }`}
            >
              {t.label}
            </button>
          ))}
        </div>
      </Card>

      {tab === "resumen" ? (
        <div className="space-y-4">
          {cargandoResumen ? (
            <p className="text-sm text-lt-text-muted">
              Consultando resumen de jornada…
            </p>
          ) : null}
          <div className="grid gap-4 sm:grid-cols-3">
            <Card className="p-4">
              <p className="text-xs font-medium uppercase tracking-wide text-lt-text-subtle">
                Ventas hoy
              </p>
              <p className="mt-1 text-2xl font-bold text-lt-text">
                {ventasHoyCount}
              </p>
            </Card>
            <Card className="p-4">
              <p className="text-xs font-medium uppercase tracking-wide text-lt-text-subtle">
                Facturado USD
              </p>
              <p className="mt-1 text-2xl font-bold text-lt-success-text">
                {formatCurrency(totalFacturadoUsd)}
              </p>
            </Card>
            <Card className="p-4">
              <p className="text-xs font-medium uppercase tracking-wide text-lt-text-subtle">
                Facturado Bs
              </p>
              <p className="mt-1 text-2xl font-bold text-lt-text">
                {formatNumber(totalFacturadoBs)}
              </p>
            </Card>
          </div>

          <Card className="space-y-3 p-4">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <div>
                <h2 className="text-base font-semibold text-lt-text">
                  Stock en camión
                </h2>
                <p className="text-sm text-lt-text-muted">
                  Disponible = cargado − entregado
                </p>
              </div>
              <Button
                type="button"
                variant="secondary"
                disabled={isPending || inventarioResumen.length === 0}
                onClick={handleReversar}
              >
                Devolver sobrante a almacén
              </Button>
            </div>
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-lt-border text-left text-lt-text-muted">
                    <th className="px-2 py-2 font-medium">Código</th>
                    <th className="px-2 py-2 font-medium">Producto</th>
                    <th className="px-2 py-2 text-right font-medium">Cargado</th>
                    <th className="px-2 py-2 text-right font-medium">
                      Entregado
                    </th>
                    <th className="px-2 py-2 text-right font-medium">
                      Disponible
                    </th>
                  </tr>
                </thead>
                <tbody>
                  {inventarioResumen.length === 0 ? (
                    <tr>
                      <td
                        colSpan={5}
                        className="px-2 py-6 text-center text-lt-text-muted"
                      >
                        Sin stock. Usa «Cargar almacén móvil».
                      </td>
                    </tr>
                  ) : (
                    inventarioResumen.map((item) => (
                      <tr
                        key={item.producto_id}
                        className="border-b border-lt-border-light"
                      >
                        <td className="px-2 py-2 font-mono text-xs text-lt-text-muted">
                          {item.codigo || "—"}
                        </td>
                        <td className="px-2 py-2 font-medium text-lt-text">
                          {item.nombre || "—"}
                        </td>
                        <td className="px-2 py-2 text-right tabular-nums">
                          {formatNumber(item.cantidad_cargada)}
                        </td>
                        <td className="px-2 py-2 text-right tabular-nums">
                          {formatNumber(item.cantidad_entregada)}
                        </td>
                        <td className="px-2 py-2 text-right font-semibold tabular-nums text-lt-success-text">
                          {formatNumber(item.cantidad_disponible)}
                        </td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          </Card>

          <Card className="space-y-3 p-4">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <div>
                <h2 className="text-base font-semibold text-lt-text">
                  Ventas AutoVenta de hoy
                </h2>
                <p className="text-sm text-lt-text-muted">
                  Órdenes por liquidar listas para rendición
                </p>
              </div>
              <Button href="/rendiciones/nuevo" variant="secondary">
                Ir a rendición
              </Button>
            </div>
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-lt-border text-left text-lt-text-muted">
                    <th className="px-2 py-2 font-medium">Orden</th>
                    <th className="px-2 py-2 font-medium">Cliente</th>
                    <th className="px-2 py-2 font-medium">Estado</th>
                    <th className="px-2 py-2 text-right font-medium">USD</th>
                    <th className="px-2 py-2 text-right font-medium">Hora</th>
                  </tr>
                </thead>
                <tbody>
                  {ventasResumen.length === 0 ? (
                    <tr>
                      <td
                        colSpan={5}
                        className="px-2 py-6 text-center text-lt-text-muted"
                      >
                        Aún no hay ventas en ruta para este camión hoy.
                      </td>
                    </tr>
                  ) : (
                    ventasResumen.map((o) => (
                      <tr
                        key={o.orden_id}
                        className="border-b border-lt-border-light"
                      >
                        <td className="px-2 py-2 font-semibold text-lt-text">
                          #{o.correlativo}
                          {o.factura_origen_numero
                            ? ` · ${o.factura_origen_numero}`
                            : ""}
                        </td>
                        <td className="px-2 py-2">{o.cliente_nombre || "—"}</td>
                        <td className="px-2 py-2">
                          <span className="rounded-lg bg-lt-surface-muted px-2 py-0.5 text-xs font-medium">
                            {o.estado}
                          </span>
                        </td>
                        <td className="px-2 py-2 text-right tabular-nums">
                          {formatCurrency(o.total_recaudar_usd)}
                        </td>
                        <td className="px-2 py-2 text-right text-xs text-lt-text-muted">
                          {new Date(o.created_at).toLocaleTimeString("es-VE", {
                            hour: "2-digit",
                            minute: "2-digit",
                          })}
                        </td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          </Card>
        </div>
      ) : null}

      {tab === "carga" ? (
        <div className="space-y-4">
          <Card className="space-y-2 p-4">
            <h2 className="text-base font-semibold text-lt-text">
              Cargar almacén móvil
            </h2>
            <p className="text-sm text-lt-text-muted">
              Elige productos con imagen y filtros (igual que una orden) y
              transfiere stock del almacén central al camión.
            </p>
          </Card>

          <Card title="Catálogo de productos">
            <ProductoCatalogo
              productos={productos}
              onAdd={agregarCarga}
              selectedIds={lineasCarga.map((l) => l.producto_id)}
              addLabel="Añadir a la carga"
              stockLabel="Almacén"
            />
          </Card>

          <Card title="Productos a cargar en el camión">
            {!lineasCarga.length ? (
              <p className="text-sm text-lt-text-muted">
                Agrega productos desde el catálogo.
              </p>
            ) : (
              <ul className="space-y-3">
                {lineasCarga.map((linea) => {
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
                        <p className="text-xs text-lt-text-muted">
                          {producto?.codigo_producto ?? "—"}
                        </p>
                        <Input
                          label="Cantidad a cargar"
                          type="number"
                          min={1}
                          max={producto?.stock_disponible}
                          value={linea.cantidad}
                          onChange={(e) =>
                            setLineasCarga((prev) =>
                              prev.map((l) =>
                                l.producto_id === linea.producto_id
                                  ? {
                                      ...l,
                                      cantidad: Math.max(
                                        1,
                                        Number(e.target.value) || 1,
                                      ),
                                    }
                                  : l,
                              ),
                            )
                          }
                        />
                      </div>
                      <div className="flex items-start justify-end">
                        <Button
                          type="button"
                          variant="ghost"
                          onClick={() =>
                            setLineasCarga((prev) =>
                              prev.filter(
                                (l) => l.producto_id !== linea.producto_id,
                              ),
                            )
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
              Unidades a cargar:{" "}
              <span className="font-medium text-lt-text">
                {formatNumber(totalCargaUnidades)}
              </span>
            </p>
            <div className="mt-4 flex flex-wrap justify-end gap-2">
              <Button
                type="button"
                variant="secondary"
                onClick={() => setTab("resumen")}
              >
                Cancelar
              </Button>
              <Button
                type="button"
                disabled={isPending || !lineasCarga.length}
                onClick={handleCargar}
              >
                {isPending ? "Cargando…" : "Cargar al camión"}
              </Button>
            </div>
          </Card>
        </div>
      ) : null}

      {tab === "venta" ? (
        <div className="space-y-4">
          <Card className="space-y-4 p-4">
            <div>
              <h2 className="text-base font-semibold text-lt-text">
                Registrar venta en ruta
              </h2>
              <p className="text-sm text-lt-text-muted">
                Solo productos con stock en el camión seleccionado.
              </p>
            </div>
            <div className="space-y-1.5">
              <label className="block text-sm font-medium text-lt-text">
                Cliente *
              </label>
              <input
                type="search"
                placeholder="Buscar razón social o RIF…"
                value={buscarCliente}
                onChange={(e) => setBuscarCliente(e.target.value)}
                className={`${inputClass} mb-2`}
              />
              <select
                value={clienteId}
                onChange={(e) => setClienteId(e.target.value)}
                className={inputClass}
              >
                <option value="">Selecciona cliente</option>
                {clientesFiltrados.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.razon_social} ({c.rif_nit})
                  </option>
                ))}
              </select>
            </div>
            <Input
              label="Observaciones"
              value={observaciones}
              onChange={(e) => setObservaciones(e.target.value)}
              placeholder="Opcional"
            />
          </Card>

          <Card title="Catálogo en camión">
            {!productosParaVenta.length ? (
              <p className="rounded-xl border border-dashed border-lt-border px-4 py-8 text-center text-sm text-lt-text-muted">
                No hay stock en este camión. Carga el almacén móvil primero.
              </p>
            ) : (
              <ProductoCatalogo
                productos={productosParaVenta}
                onAdd={agregarVenta}
                selectedIds={lineasVenta.map((l) => l.producto_id)}
                addLabel="Añadir a la venta"
                stockLabel="En camión"
              />
            )}
          </Card>

          <Card title="Productos de la venta">
            {!lineasVenta.length ? (
              <p className="text-sm text-lt-text-muted">
                Agrega productos desde el catálogo del camión.
              </p>
            ) : (
              <ul className="space-y-3">
                {lineasVenta.map((linea) => {
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
                            value={linea.cantidad}
                            onChange={(e) =>
                              setLineasVenta((prev) =>
                                prev.map((l) =>
                                  l.producto_id === linea.producto_id
                                    ? {
                                        ...l,
                                        cantidad: Math.max(
                                          1,
                                          Number(e.target.value) || 1,
                                        ),
                                      }
                                    : l,
                                ),
                              )
                            }
                          />
                          <Input
                            label="Precio USD"
                            type="number"
                            min={0}
                            step="0.01"
                            value={linea.precio_unitario}
                            onChange={(e) =>
                              setLineasVenta((prev) =>
                                prev.map((l) =>
                                  l.producto_id === linea.producto_id
                                    ? {
                                        ...l,
                                        precio_unitario: Number(
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
                      <div className="flex items-start justify-end">
                        <Button
                          type="button"
                          variant="ghost"
                          onClick={() =>
                            setLineasVenta((prev) =>
                              prev.filter(
                                (l) => l.producto_id !== linea.producto_id,
                              ),
                            )
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
            <p className="mt-4 text-sm font-semibold text-lt-text">
              Total: {formatCurrency(totalVentaUsd)} ·{" "}
              {formatNumber(totalVentaUsd * tasaOficial)} Bs
            </p>

            <div className="mt-4 space-y-3 border-t border-lt-border-light pt-4">
              <div className="flex items-center justify-between gap-2">
                <h3 className="text-sm font-semibold text-lt-text">
                  Envases (opcional)
                </h3>
                <Button
                  type="button"
                  variant="secondary"
                  disabled={!contenedores.length}
                  onClick={() => {
                    if (!contenedores[0]) return;
                    setLineasContenedor((prev) => [
                      ...prev,
                      {
                        contenedor_id: contenedores[0].id,
                        cantidad_entregada: 0,
                        cantidad_retirada: 0,
                      },
                    ]);
                  }}
                >
                  + Envase
                </Button>
              </div>
              {lineasContenedor.map((linea, idx) => (
                <div
                  key={idx}
                  className="grid gap-2 rounded-xl border border-lt-border p-3 sm:grid-cols-12 sm:items-end"
                >
                  <div className="sm:col-span-5">
                    <select
                      value={linea.contenedor_id}
                      onChange={(e) =>
                        setLineasContenedor((prev) => {
                          const next = [...prev];
                          next[idx] = {
                            ...next[idx],
                            contenedor_id: e.target.value,
                          };
                          return next;
                        })
                      }
                      className={inputClass}
                    >
                      {contenedores.map((c) => (
                        <option key={c.id} value={c.id}>
                          {c.codigo ? `${c.codigo} — ` : ""}
                          {c.nombre}
                        </option>
                      ))}
                    </select>
                  </div>
                  <div className="sm:col-span-3">
                    <Input
                      label="Entregados"
                      type="number"
                      min={0}
                      value={linea.cantidad_entregada}
                      onChange={(e) =>
                        setLineasContenedor((prev) => {
                          const next = [...prev];
                          next[idx] = {
                            ...next[idx],
                            cantidad_entregada: Number(e.target.value),
                          };
                          return next;
                        })
                      }
                    />
                  </div>
                  <div className="sm:col-span-3">
                    <Input
                      label="Retirados"
                      type="number"
                      min={0}
                      value={linea.cantidad_retirada}
                      onChange={(e) =>
                        setLineasContenedor((prev) => {
                          const next = [...prev];
                          next[idx] = {
                            ...next[idx],
                            cantidad_retirada: Number(e.target.value),
                          };
                          return next;
                        })
                      }
                    />
                  </div>
                  <div className="sm:col-span-1">
                    <Button
                      type="button"
                      variant="secondary"
                      className="w-full"
                      onClick={() =>
                        setLineasContenedor((prev) =>
                          prev.filter((_, i) => i !== idx),
                        )
                      }
                    >
                      ×
                    </Button>
                  </div>
                </div>
              ))}
            </div>

            <div className="mt-4 flex flex-wrap justify-end gap-2">
              <Button
                type="button"
                variant="secondary"
                onClick={() => setTab("resumen")}
              >
                Cancelar
              </Button>
              <Button
                type="button"
                disabled={isPending || !lineasVenta.length}
                onClick={handleGuardarVenta}
              >
                {isPending ? "Guardando…" : "Registrar venta"}
              </Button>
            </div>
          </Card>
        </div>
      ) : null}
    </div>
  );
}
