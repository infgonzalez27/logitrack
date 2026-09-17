"use client";

import { useMemo, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { formatCurrency, formatNumber } from "@/lib/format";
import {
  cargarInventarioMovilAutoVentasAction,
  registrarVentaEnRutaAction,
  reversarInventarioMovilAutoVentasAction,
} from "@/lib/actions/autoventas";

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

type ProductoItem = {
  id: string;
  codigo_producto: string;
  nombre: string;
  precio_lista1: number;
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
  productos: ProductoItem[];
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
  const [tab, setTab] = useState<"resumen" | "venta" | "carga">("resumen");
  const [mensaje, setMensaje] = useState<{
    tipo: "success" | "error";
    texto: string;
  } | null>(null);

  const [clienteId, setClienteId] = useState("");
  const [observaciones, setObservaciones] = useState("");
  const [lineasVenta, setLineasVenta] = useState<LineaVenta[]>([]);
  const [lineasContenedor, setLineasContenedor] = useState<LineaContenedor[]>(
    [],
  );
  const [lineasCarga, setLineasCarga] = useState<
    { producto_id: string; cantidad: number }[]
  >([]);
  const [buscarCliente, setBuscarCliente] = useState("");

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

  const totalVentaUsd = lineasVenta.reduce(
    (s, l) => s + l.cantidad * l.precio_unitario,
    0,
  );

  const disponibleProducto = (productoId: string) => {
    const item = inventarioCamion.find((i) => i.producto_id === productoId);
    return Math.max(
      0,
      (item?.cantidad_cargada ?? 0) - (item?.cantidad_entregada ?? 0),
    );
  };

  const agregarLineaVenta = () => {
    const desdeStock = inventarioCamion.find(
      (i) =>
        (i.cantidad_cargada || 0) - (i.cantidad_entregada || 0) > 0 &&
        productos.some((p) => p.id === i.producto_id),
    );
    const prod =
      productos.find((p) => p.id === desdeStock?.producto_id) ?? productos[0];
    if (!prod) return;
    setLineasVenta((prev) => [
      ...prev,
      {
        producto_id: prod.id,
        cantidad: 1,
        precio_unitario: Number(prod.precio_lista1 || 0),
      },
    ]);
  };

  const actualizarLineaVenta = (
    index: number,
    campo: keyof LineaVenta,
    valor: string | number,
  ) => {
    setLineasVenta((prev) => {
      const next = [...prev];
      if (campo === "producto_id") {
        const prod = productos.find((p) => p.id === valor);
        next[index] = {
          ...next[index],
          producto_id: String(valor),
          precio_unitario: Number(prod?.precio_lista1 || 0),
        };
      } else {
        next[index] = { ...next[index], [campo]: Number(valor) };
      }
      return next;
    });
  };

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
          <div className="grid gap-4 sm:grid-cols-3">
            <Card className="p-4">
              <p className="text-xs font-medium uppercase tracking-wide text-lt-text-subtle">
                Ventas hoy
              </p>
              <p className="mt-1 text-2xl font-bold text-lt-text">
                {ordenesCamion.length}
              </p>
            </Card>
            <Card className="p-4">
              <p className="text-xs font-medium uppercase tracking-wide text-lt-text-subtle">
                Facturado USD
              </p>
              <p className="mt-1 text-2xl font-bold text-lt-success-text">
                {formatCurrency(
                  ordenesCamion.reduce((s, o) => s + o.total_recaudar_usd, 0),
                )}
              </p>
            </Card>
            <Card className="p-4">
              <p className="text-xs font-medium uppercase tracking-wide text-lt-text-subtle">
                Facturado Bs
              </p>
              <p className="mt-1 text-2xl font-bold text-lt-text">
                {formatNumber(
                  ordenesCamion.reduce((s, o) => s + o.total_recaudar_bs, 0),
                )}
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
                disabled={isPending || inventarioCamion.length === 0}
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
                  {inventarioCamion.length === 0 ? (
                    <tr>
                      <td
                        colSpan={5}
                        className="px-2 py-6 text-center text-lt-text-muted"
                      >
                        Sin stock. Usa «Cargar almacén móvil».
                      </td>
                    </tr>
                  ) : (
                    inventarioCamion.map((item) => {
                      const disponible = Math.max(
                        0,
                        item.cantidad_cargada - item.cantidad_entregada,
                      );
                      return (
                        <tr
                          key={item.id}
                          className="border-b border-lt-border-light"
                        >
                          <td className="px-2 py-2 font-mono text-xs text-lt-text-muted">
                            {item.productos?.codigo_producto || "—"}
                          </td>
                          <td className="px-2 py-2 font-medium text-lt-text">
                            {item.productos?.nombre || "—"}
                          </td>
                          <td className="px-2 py-2 text-right tabular-nums">
                            {formatNumber(item.cantidad_cargada)}
                          </td>
                          <td className="px-2 py-2 text-right tabular-nums">
                            {formatNumber(item.cantidad_entregada)}
                          </td>
                          <td className="px-2 py-2 text-right font-semibold tabular-nums text-lt-success-text">
                            {formatNumber(disponible)}
                          </td>
                        </tr>
                      );
                    })
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
                  Órdenes `por_liquidar` listas para rendición
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
                  {ordenesCamion.length === 0 ? (
                    <tr>
                      <td
                        colSpan={5}
                        className="px-2 py-6 text-center text-lt-text-muted"
                      >
                        Aún no hay ventas en ruta para este camión hoy.
                      </td>
                    </tr>
                  ) : (
                    ordenesCamion.map((o) => (
                      <tr
                        key={o.id}
                        className="border-b border-lt-border-light"
                      >
                        <td className="px-2 py-2 font-semibold text-lt-text">
                          #{o.correlativo}
                          {o.factura_origen_numero
                            ? ` · ${o.factura_origen_numero}`
                            : ""}
                        </td>
                        <td className="px-2 py-2">
                          {o.clientes?.razon_social || "—"}
                        </td>
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

      {tab === "venta" ? (
        <Card className="space-y-5 p-4">
          <div>
            <h2 className="text-base font-semibold text-lt-text">
              Registrar venta en ruta
            </h2>
            <p className="text-sm text-lt-text-muted">
              Descuenta del inventario móvil y crea orden por liquidar
              (es_autoventa).
            </p>
          </div>

          <div className="grid gap-4 sm:grid-cols-2">
            <div className="space-y-1.5 sm:col-span-2">
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
            <div className="space-y-1.5 sm:col-span-2">
              <label className="block text-sm font-medium text-lt-text">
                Observaciones
              </label>
              <input
                value={observaciones}
                onChange={(e) => setObservaciones(e.target.value)}
                className={inputClass}
                placeholder="Opcional"
              />
            </div>
          </div>

          <div className="space-y-3">
            <div className="flex items-center justify-between gap-2">
              <h3 className="text-sm font-semibold text-lt-text">Productos</h3>
              <Button
                type="button"
                variant="secondary"
                onClick={agregarLineaVenta}
                disabled={!productos.length}
              >
                + Producto
              </Button>
            </div>
            {lineasVenta.length === 0 ? (
              <p className="rounded-xl border border-dashed border-lt-border px-3 py-4 text-center text-sm text-lt-text-muted">
                Agrega productos disponibles en el camión.
              </p>
            ) : (
              <div className="space-y-2">
                {lineasVenta.map((linea, idx) => (
                  <div
                    key={idx}
                    className="grid gap-2 rounded-xl border border-lt-border bg-lt-surface-muted p-3 sm:grid-cols-12 sm:items-end"
                  >
                    <div className="sm:col-span-5">
                      <label className="mb-1 block text-xs text-lt-text-muted">
                        Producto
                      </label>
                      <select
                        value={linea.producto_id}
                        onChange={(e) =>
                          actualizarLineaVenta(idx, "producto_id", e.target.value)
                        }
                        className={inputClass}
                      >
                        {productos.map((p) => (
                          <option key={p.id} value={p.id}>
                            {p.codigo_producto} — {p.nombre}
                          </option>
                        ))}
                      </select>
                      <p className="mt-1 text-xs text-lt-text-muted">
                        Disponible:{" "}
                        <strong>{disponibleProducto(linea.producto_id)}</strong>
                      </p>
                    </div>
                    <div className="sm:col-span-2">
                      <label className="mb-1 block text-xs text-lt-text-muted">
                        Cantidad
                      </label>
                      <input
                        type="number"
                        min={1}
                        value={linea.cantidad}
                        onChange={(e) =>
                          actualizarLineaVenta(idx, "cantidad", e.target.value)
                        }
                        className={inputClass}
                      />
                    </div>
                    <div className="sm:col-span-2">
                      <label className="mb-1 block text-xs text-lt-text-muted">
                        Precio USD
                      </label>
                      <input
                        type="number"
                        min={0}
                        step="0.01"
                        value={linea.precio_unitario}
                        onChange={(e) =>
                          actualizarLineaVenta(
                            idx,
                            "precio_unitario",
                            e.target.value,
                          )
                        }
                        className={inputClass}
                      />
                    </div>
                    <div className="sm:col-span-2">
                      <p className="mb-1 text-xs text-lt-text-muted">Subtotal</p>
                      <p className="py-2 font-semibold tabular-nums">
                        {formatCurrency(
                          linea.cantidad * linea.precio_unitario,
                        )}
                      </p>
                    </div>
                    <div className="sm:col-span-1">
                      <Button
                        type="button"
                        variant="secondary"
                        className="w-full"
                        onClick={() =>
                          setLineasVenta((prev) =>
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
            )}
            <p className="text-right text-sm font-semibold text-lt-text">
              Total: {formatCurrency(totalVentaUsd)} ·{" "}
              {formatNumber(totalVentaUsd * tasaOficial)} Bs
            </p>
          </div>

          <div className="space-y-3">
            <div className="flex items-center justify-between gap-2">
              <h3 className="text-sm font-semibold text-lt-text">
                Envases / contenedores (opcional)
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
                  <label className="mb-1 block text-xs text-lt-text-muted">
                    Entregados
                  </label>
                  <input
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
                    className={inputClass}
                  />
                </div>
                <div className="sm:col-span-3">
                  <label className="mb-1 block text-xs text-lt-text-muted">
                    Retirados
                  </label>
                  <input
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
                    className={inputClass}
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

          <div className="flex justify-end gap-2">
            <Button
              type="button"
              variant="secondary"
              onClick={() => setTab("resumen")}
            >
              Cancelar
            </Button>
            <Button
              type="button"
              disabled={isPending}
              onClick={handleGuardarVenta}
            >
              {isPending ? "Guardando…" : "Registrar venta"}
            </Button>
          </div>
        </Card>
      ) : null}

      {tab === "carga" ? (
        <Card className="space-y-5 p-4">
          <div>
            <h2 className="text-base font-semibold text-lt-text">
              Cargar almacén móvil
            </h2>
            <p className="text-sm text-lt-text-muted">
              Transfiere stock del almacén central al camión (sin radar).
            </p>
          </div>

          <div className="flex justify-end">
            <Button
              type="button"
              variant="secondary"
              disabled={!productos.length}
              onClick={() =>
                setLineasCarga((prev) => [
                  ...prev,
                  {
                    producto_id: productos[0]?.id ?? "",
                    cantidad: 1,
                  },
                ])
              }
            >
              + Producto a cargar
            </Button>
          </div>

          {lineasCarga.length === 0 ? (
            <p className="rounded-xl border border-dashed border-lt-border px-3 py-4 text-center text-sm text-lt-text-muted">
              Agrega los productos a bajar del almacén.
            </p>
          ) : (
            <div className="space-y-2">
              {lineasCarga.map((linea, idx) => (
                <div
                  key={idx}
                  className="grid gap-2 rounded-xl border border-lt-border p-3 sm:grid-cols-12 sm:items-end"
                >
                  <div className="sm:col-span-8">
                    <select
                      value={linea.producto_id}
                      onChange={(e) =>
                        setLineasCarga((prev) => {
                          const next = [...prev];
                          next[idx] = {
                            ...next[idx],
                            producto_id: e.target.value,
                          };
                          return next;
                        })
                      }
                      className={inputClass}
                    >
                      {productos.map((p) => (
                        <option key={p.id} value={p.id}>
                          {p.codigo_producto} — {p.nombre}
                        </option>
                      ))}
                    </select>
                  </div>
                  <div className="sm:col-span-3">
                    <input
                      type="number"
                      min={1}
                      value={linea.cantidad}
                      onChange={(e) =>
                        setLineasCarga((prev) => {
                          const next = [...prev];
                          next[idx] = {
                            ...next[idx],
                            cantidad: Number(e.target.value),
                          };
                          return next;
                        })
                      }
                      className={inputClass}
                    />
                  </div>
                  <div className="sm:col-span-1">
                    <Button
                      type="button"
                      variant="secondary"
                      className="w-full"
                      onClick={() =>
                        setLineasCarga((prev) =>
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
          )}

          <div className="flex justify-end gap-2">
            <Button
              type="button"
              variant="secondary"
              onClick={() => setTab("resumen")}
            >
              Cancelar
            </Button>
            <Button type="button" disabled={isPending} onClick={handleCargar}>
              {isPending ? "Cargando…" : "Cargar al camión"}
            </Button>
          </div>
        </Card>
      ) : null}
    </div>
  );
}
