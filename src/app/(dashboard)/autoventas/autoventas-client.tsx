"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { formatCurrency, formatNumber } from "@/lib/format";
import {
  registrarVentaEnRutaAction,
  cargarInventarioMovilAutoVentasAction,
  reversarInventarioMovilAutoVentasAction,
} from "@/lib/actions/autoventas";

interface CamionItem {
  id: string;
  placa: string;
  modelo: string | null;
  estado: string;
}

interface ClienteItem {
  id: string;
  nombre_negocio: string;
  rif: string | null;
  direccion: string | null;
}

interface ProductoItem {
  id: string;
  codigo: string;
  nombre: string;
  precio_lista1: number;
}

interface ContenedorItem {
  id: string;
  tipo: string;
  capacidad: string | null;
}

interface InventarioMovilRow {
  id: string;
  camion_id: string;
  producto_id: string;
  cantidad_cargada: number;
  cantidad_entregada: number;
  productos?: { codigo: string; nombre: string; precio_lista1: number } | null;
}

interface OrdenAutoVentaRow {
  id: string;
  correlativo: number;
  factura_origen_numero: string;
  estado: string;
  total_recaudar_usd: number;
  total_recaudar_bs: number;
  created_at: string;
  clientes?: { nombre_negocio: string } | null;
}

interface AutoVentasClientProps {
  camiones: CamionItem[];
  clientes: ClienteItem[];
  productos: ProductoItem[];
  contenedores: ContenedorItem[];
  inventarioMovil: InventarioMovilRow[];
  ordenesJornada: OrdenAutoVentaRow[];
  vendedorId: string;
  tasaOficial: number;
}

interface LineaVenta {
  producto_id: string;
  cantidad: number;
  precio_unitario: number;
}

interface LineaContenedor {
  contenedor_id: string;
  cantidad_entregada: number;
  cantidad_retirada: number;
}

export function AutoVentasClient({
  camiones,
  clientes,
  productos,
  contenedores,
  inventarioMovil,
  ordenesJornada,
  vendedorId,
  tasaOficial,
}: AutoVentasClientProps) {
  const router = useRouter();
  const [isPending, startTransition] = useTransition();

  const [camionSeleccionadoId, setCamionSeleccionadoId] = useState<string>(
    camiones[0]?.id || ""
  );
  const [tabActiva, setTabActiva] = useState<"resumen" | "nueva_venta" | "cargar_camion">("resumen");
  const [mensaje, setMensaje] = useState<{ tipo: "success" | "error"; texto: string } | null>(null);

  // Formulario Venta en Ruta
  const [clienteId, setClienteId] = useState<string>("");
  const [observaciones, setObservaciones] = useState<string>("");
  const [lineasVenta, setLineasVenta] = useState<LineaVenta[]>([]);
  const [lineasContenedor, setLineasContenedor] = useState<LineaContenedor[]>([]);

  // Formulario Cargar Camión
  const [lineasCarga, setLineasCarga] = useState<{ producto_id: string; cantidad: number }[]>([]);

  // Inventario disponible para el camión seleccionado
  const inventarioCamion = inventarioMovil.filter(
    (item) => item.camion_id === camionSeleccionadoId
  );

  const ordenesCamion = ordenesJornada;

  // Manejo de Líneas de Venta
  const agregarLineaVenta = () => {
    if (productos.length === 0) return;
    const prodDef = productos[0];
    setLineasVenta((prev) => [
      ...prev,
      {
        producto_id: prodDef.id,
        cantidad: 1,
        precio_unitario: Number(prodDef.precio_lista1 || 0),
      },
    ]);
  };

  const actualizarLineaVenta = (index: number, campo: keyof LineaVenta, valor: string | number) => {
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
        next[index] = {
          ...next[index],
          [campo]: Number(valor),
        };
      }
      return next;
    });
  };

  const eliminarLineaVenta = (index: number) => {
    setLineasVenta((prev) => prev.filter((_, i) => i !== index));
  };

  // Manejo de Líneas de Contenedor
  const agregarLineaContenedor = () => {
    if (contenedores.length === 0) return;
    const contDef = contenedores[0];
    setLineasContenedor((prev) => [
      ...prev,
      {
        contenedor_id: contDef.id,
        cantidad_entregada: 0,
        cantidad_retirada: 0,
      },
    ]);
  };

  const actualizarLineaContenedor = (
    index: number,
    campo: keyof LineaContenedor,
    valor: string | number
  ) => {
    setLineasContenedor((prev) => {
      const next = [...prev];
      next[index] = {
        ...next[index],
        [campo]: campo === "contenedor_id" ? String(valor) : Number(valor),
      };
      return next;
    });
  };

  const eliminarLineaContenedor = (index: number) => {
    setLineasContenedor((prev) => prev.filter((_, i) => i !== index));
  };

  // Totales de la venta en edición
  const totalVentaUsd = lineasVenta.reduce(
    (sum, l) => sum + (l.cantidad || 0) * (l.precio_unitario || 0),
    0
  );
  const totalVentaBs = totalVentaUsd * tasaOficial;

  // Registrar Venta en Ruta
  const handleGuardarVenta = () => {
    setMensaje(null);
    if (!camionSeleccionadoId) {
      setMensaje({ tipo: "error", texto: "Debe seleccionar un camión." });
      return;
    }
    if (!clienteId) {
      setMensaje({ tipo: "error", texto: "Debe seleccionar un cliente." });
      return;
    }
    if (lineasVenta.length === 0) {
      setMensaje({ tipo: "error", texto: "Debe agregar al menos un producto a la venta." });
      return;
    }

    startTransition(async () => {
      const res = await registrarVentaEnRutaAction({
        vendedor_id: vendedorId,
        cliente_id: clienteId,
        camion_id: camionSeleccionadoId,
        productos_json: lineasVenta.map((l) => ({
          producto_id: l.producto_id,
          cantidad: l.cantidad,
          precio_unitario: l.precio_unitario,
        })),
        contenedores_json: lineasContenedor.map((c) => ({
          contenedor_id: c.contenedor_id,
          cantidad_entregada: c.cantidad_entregada,
          cantidad_retirada: c.cantidad_retirada,
        })),
        observaciones,
        tasa_cambio: tasaOficial,
      });

      if (res.success) {
        setMensaje({ tipo: "success", texto: res.message || "¡Venta registrada con éxito!" });
        setLineasVenta([]);
        setLineasContenedor([]);
        setObservaciones("");
        setTabActiva("resumen");
        router.refresh();
      } else {
        setMensaje({ tipo: "error", texto: res.message || "Error al guardar la venta." });
      }
    });
  };

  // Cargar Inventario Móvil
  const handleCargarInventario = () => {
    setMensaje(null);
    if (!camionSeleccionadoId) {
      setMensaje({ tipo: "error", texto: "Debe seleccionar un camión." });
      return;
    }
    if (lineasCarga.length === 0) {
      setMensaje({ tipo: "error", texto: "Debe agregar al menos un producto para cargar." });
      return;
    }

    startTransition(async () => {
      const res = await cargarInventarioMovilAutoVentasAction(
        camionSeleccionadoId,
        lineasCarga.map((l) => ({ producto_id: l.producto_id, cantidad_solicitada: l.cantidad }))
      );

      if (res.success) {
        setMensaje({ tipo: "success", texto: res.message || "Carga de inventario móvil procesada." });
        setLineasCarga([]);
        setTabActiva("resumen");
        router.refresh();
      } else {
        setMensaje({ tipo: "error", texto: res.message || "Error al cargar inventario." });
      }
    });
  };

  // Reversar / Devolver sobrante al almacén
  const handleReversarInventario = () => {
    if (!camionSeleccionadoId) return;
    if (!confirm("¿Está seguro de devolver todo el stock sobrante del camión al Almacén Central?")) return;

    setMensaje(null);
    startTransition(async () => {
      const res = await reversarInventarioMovilAutoVentasAction(camionSeleccionadoId);
      if (res.success) {
        setMensaje({ tipo: "success", texto: res.message || "Inventario devuelto al almacén." });
        router.refresh();
      } else {
        setMensaje({ tipo: "error", texto: res.message || "Error al reversar inventario." });
      }
    });
  };

  return (
    <div className="space-y-6">
      {/* Alertas */}
      {mensaje && (
        <div
          className={`p-4 rounded-lg text-sm font-medium ${
            mensaje.tipo === "success"
              ? "bg-emerald-500/10 border border-emerald-500/20 text-emerald-400"
              : "bg-red-500/10 border border-red-500/20 text-red-400"
          }`}
        >
          {mensaje.texto}
        </div>
      )}

      {/* Selector de Camión & Pestañas */}
      <Card className="p-4 bg-slate-900 border-slate-800">
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
          <div className="flex items-center space-x-3">
            <span className="text-sm text-slate-400 font-medium">Camión en Ruta:</span>
            <select
              value={camionSeleccionadoId}
              onChange={(e) => setCamionSeleccionadoId(e.target.value)}
              className="bg-slate-800 border border-slate-700 text-slate-100 rounded-md px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-emerald-500"
            >
              {camiones.length === 0 ? (
                <option value="">No hay camiones registrados</option>
              ) : (
                camiones.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.placa} — {c.modelo ?? "Sin modelo"} ({c.estado})
                  </option>
                ))
              )}
            </select>
          </div>

          <div className="flex items-center space-x-2">
            <button
              onClick={() => setTabActiva("resumen")}
              className={`px-3 py-1.5 rounded-md text-xs font-semibold transition ${
                tabActiva === "resumen"
                  ? "bg-emerald-600 text-white"
                  : "bg-slate-800 text-slate-300 hover:bg-slate-700"
              }`}
            >
              📊 Resumen de Jornada
            </button>

            <button
              onClick={() => setTabActiva("nueva_venta")}
              className={`px-3 py-1.5 rounded-md text-xs font-semibold transition ${
                tabActiva === "nueva_venta"
                  ? "bg-emerald-600 text-white"
                  : "bg-slate-800 text-slate-300 hover:bg-slate-700"
              }`}
            >
              🛒 Registrar Venta en Ruta
            </button>

            <button
              onClick={() => setTabActiva("cargar_camion")}
              className={`px-3 py-1.5 rounded-md text-xs font-semibold transition ${
                tabActiva === "cargar_camion"
                  ? "bg-emerald-600 text-white"
                  : "bg-slate-800 text-slate-300 hover:bg-slate-700"
              }`}
            >
              📦 Cargar Almacén Móvil
            </button>
          </div>
        </div>
      </Card>

      {/* Pestaña 1: Resumen de Jornada */}
      {tabActiva === "resumen" && (
        <div className="space-y-6">
          {/* Tarjetas KPI */}
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
            <Card className="p-4 bg-slate-900 border-slate-800">
              <span className="text-xs text-slate-400 uppercase font-semibold">Ventas Hoy</span>
              <p className="text-2xl font-bold text-white mt-1">{ordenesCamion.length}</p>
            </Card>
            <Card className="p-4 bg-slate-900 border-slate-800">
              <span className="text-xs text-slate-400 uppercase font-semibold">Total Facturado (USD)</span>
              <p className="text-2xl font-bold text-emerald-400 mt-1">
                {formatCurrency(
                  ordenesCamion.reduce((sum, o) => sum + Number(o.total_recaudar_usd || 0), 0)
                )}
              </p>
            </Card>
            <Card className="p-4 bg-slate-900 border-slate-800">
              <span className="text-xs text-slate-400 uppercase font-semibold">Total Facturado (Bs)</span>
              <p className="text-2xl font-bold text-blue-400 mt-1">
                Bs.{" "}
                {formatNumber(
                  ordenesCamion.reduce((sum, o) => sum + Number(o.total_recaudar_bs || 0), 0)
                )}
              </p>
            </Card>
          </div>

          {/* Tabla de Inventario Móvil en el Camión */}
          <Card className="p-5 bg-slate-900 border-slate-800 space-y-4">
            <div className="flex items-center justify-between">
              <div>
                <h3 className="text-base font-semibold text-white">Stock en Camión (Almacén Móvil)</h3>
                <p className="text-xs text-slate-400">Productos disponibles para venta inmediata</p>
              </div>
              <Button
                variant="secondary"
                onClick={handleReversarInventario}
                disabled={isPending || inventarioCamion.length === 0}
                className="text-xs border-amber-500/40 text-amber-400 hover:bg-amber-500/10 px-3 py-1.5"
              >
                🔄 Devolver Sobrante a Almacén Central
              </Button>
            </div>

            <div className="overflow-x-auto">
              <table className="w-full text-sm text-left text-slate-300">
                <thead className="bg-slate-800/80 text-xs uppercase text-slate-400 font-medium">
                  <tr>
                    <th className="px-4 py-2.5">Código</th>
                    <th className="px-4 py-2.5">Producto</th>
                    <th className="px-4 py-2.5 text-right">Cargado</th>
                    <th className="px-4 py-2.5 text-right">Vendido / Entregado</th>
                    <th className="px-4 py-2.5 text-right font-bold text-emerald-400">Disponible</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-800">
                  {inventarioCamion.length === 0 ? (
                    <tr>
                      <td colSpan={5} className="px-4 py-6 text-center text-slate-500">
                        No hay productos cargados en este camión. Utilice &quot;Cargar Almacén Móvil&quot;.
                      </td>
                    </tr>
                  ) : (
                    inventarioCamion.map((item) => {
                      const disponible = Math.max(
                        0,
                        (item.cantidad_cargada || 0) - (item.cantidad_entregada || 0)
                      );
                      return (
                        <tr key={item.id} className="hover:bg-slate-800/40">
                          <td className="px-4 py-3 font-mono text-xs text-slate-400">
                            {item.productos?.codigo ?? "—"}
                          </td>
                          <td className="px-4 py-3 font-medium text-white">
                            {item.productos?.nombre ?? "—"}
                          </td>
                          <td className="px-4 py-3 text-right">{formatNumber(item.cantidad_cargada)}</td>
                          <td className="px-4 py-3 text-right">{formatNumber(item.cantidad_entregada)}</td>
                          <td className="px-4 py-3 text-right font-bold text-emerald-400">
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

          {/* Tabla de Ventas en la Jornada */}
          <Card className="p-5 bg-slate-900 border-slate-800 space-y-4">
            <div className="flex items-center justify-between">
              <div>
                <h3 className="text-base font-semibold text-white">Ventas en Ruta Registradas Hoy</h3>
                <p className="text-xs text-slate-400">Órdenes generadas en la ruta activa</p>
              </div>
              <Button href="/rendiciones" variant="secondary" className="text-xs px-3 py-1.5 font-medium border-slate-700 hover:bg-slate-800">
                💳 Ir a Rendición de Cuentas
              </Button>
            </div>

            <div className="overflow-x-auto">
              <table className="w-full text-sm text-left text-slate-300">
                <thead className="bg-slate-800/80 text-xs uppercase text-slate-400 font-medium">
                  <tr>
                    <th className="px-4 py-2.5">Factura / Orden</th>
                    <th className="px-4 py-2.5">Cliente</th>
                    <th className="px-4 py-2.5 text-center">Estado</th>
                    <th className="px-4 py-2.5 text-right">Total USD</th>
                    <th className="px-4 py-2.5 text-right">Total Bs</th>
                    <th className="px-4 py-2.5 text-right">Hora</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-800">
                  {ordenesCamion.length === 0 ? (
                    <tr>
                      <td colSpan={6} className="px-4 py-6 text-center text-slate-500">
                        No se han registrado ventas en ruta para este camión hoy.
                      </td>
                    </tr>
                  ) : (
                    ordenesCamion.map((o) => (
                      <tr key={o.id} className="hover:bg-slate-800/40">
                        <td className="px-4 py-3 font-semibold text-emerald-400">
                          {o.factura_origen_numero}
                        </td>
                        <td className="px-4 py-3 text-white">
                          {o.clientes?.nombre_negocio ?? "—"}
                        </td>
                        <td className="px-4 py-3 text-center">
                          <span
                            className={`px-2 py-0.5 text-xs rounded-full font-medium ${
                              o.estado === "liquidada"
                                ? "bg-emerald-500/20 text-emerald-400"
                                : "bg-amber-500/20 text-amber-400"
                            }`}
                          >
                            {o.estado}
                          </span>
                        </td>
                        <td className="px-4 py-3 text-right font-medium text-slate-100">
                          {formatCurrency(Number(o.total_recaudar_usd || 0))}
                        </td>
                        <td className="px-4 py-3 text-right text-slate-400">
                          Bs. {formatNumber(Number(o.total_recaudar_bs || 0))}
                        </td>
                        <td className="px-4 py-3 text-right text-xs text-slate-500">
                          {new Date(o.created_at).toLocaleTimeString([], {
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
      )}

      {/* Pestaña 2: Nueva Venta en Ruta */}
      {tabActiva === "nueva_venta" && (
        <Card className="p-6 bg-slate-900 border-slate-800 space-y-6">
          <div>
            <h3 className="text-lg font-semibold text-white">Registrar Venta en Ruta (En Caliente)</h3>
            <p className="text-xs text-slate-400">
              Descuenta directo del camión e ingresa la orden para cobranza inmediata
            </p>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1">
                Cliente a Visitar *
              </label>
              <select
                value={clienteId}
                onChange={(e) => setClienteId(e.target.value)}
                className="w-full bg-slate-800 border border-slate-700 text-slate-100 rounded-md px-3 py-2 text-sm focus:ring-2 focus:ring-emerald-500"
              >
                <option value="">-- Seleccionar Cliente --</option>
                {clientes.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.nombre_negocio} {c.rif ? `(${c.rif})` : ""}
                  </option>
                ))}
              </select>
            </div>

            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1">
                Tasa de Cambio Oficial
              </label>
              <input
                type="text"
                disabled
                value={`Bs. ${tasaOficial.toFixed(4)} / USD`}
                className="w-full bg-slate-800/60 border border-slate-700 text-slate-400 rounded-md px-3 py-2 text-sm cursor-not-allowed"
              />
            </div>
          </div>

          {/* Sección de Productos de la Venta */}
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <h4 className="text-sm font-semibold text-slate-200">Productos Solicitados</h4>
              <Button variant="secondary" onClick={agregarLineaVenta} className="text-xs px-2.5 py-1">
                + Agregar Producto
              </Button>
            </div>

            {lineasVenta.length === 0 ? (
              <p className="text-xs text-slate-500 italic py-3 text-center border border-dashed border-slate-800 rounded-md">
                No ha agregado productos. Haga clic en &quot;+ Agregar Producto&quot;.
              </p>
            ) : (
              <div className="space-y-2">
                {lineasVenta.map((linea, idx) => {
                  const invItem = inventarioCamion.find(
                    (i) => i.producto_id === linea.producto_id
                  );
                  const disponibleMovil = Math.max(
                    0,
                    (invItem?.cantidad_cargada || 0) - (invItem?.cantidad_entregada || 0)
                  );
                  const subtotal = (linea.cantidad || 0) * (linea.precio_unitario || 0);

                  return (
                    <div
                      key={idx}
                      className="grid grid-cols-1 sm:grid-cols-12 gap-2 items-center bg-slate-800/60 p-3 rounded-lg border border-slate-700/60"
                    >
                      <div className="sm:col-span-5">
                        <select
                          value={linea.producto_id}
                          onChange={(e) => actualizarLineaVenta(idx, "producto_id", e.target.value)}
                          className="w-full bg-slate-900 border border-slate-700 text-slate-100 rounded-md px-2 py-1.5 text-xs"
                        >
                          {productos.map((p) => (
                            <option key={p.id} value={p.id}>
                              {p.codigo} — {p.nombre}
                            </option>
                          ))}
                        </select>
                        <span className="text-[10px] text-slate-400 block mt-0.5">
                          Disponible en Camión:{" "}
                          <strong className="text-emerald-400">{disponibleMovil} uds</strong>
                        </span>
                      </div>

                      <div className="sm:col-span-2">
                        <label className="text-[10px] text-slate-400 block sm:hidden">Cantidad</label>
                        <input
                          type="number"
                          min="1"
                          max={disponibleMovil}
                          value={linea.cantidad}
                          onChange={(e) => actualizarLineaVenta(idx, "cantidad", e.target.value)}
                          className="w-full bg-slate-900 border border-slate-700 text-slate-100 rounded-md px-2 py-1.5 text-xs text-right"
                        />
                      </div>

                      <div className="sm:col-span-2">
                        <label className="text-[10px] text-slate-400 block sm:hidden">Precio USD</label>
                        <input
                          type="number"
                          step="0.01"
                          value={linea.precio_unitario}
                          onChange={(e) =>
                            actualizarLineaVenta(idx, "precio_unitario", e.target.value)
                          }
                          className="w-full bg-slate-900 border border-slate-700 text-slate-100 rounded-md px-2 py-1.5 text-xs text-right"
                        />
                      </div>

                      <div className="sm:col-span-2 text-right">
                        <span className="text-xs font-semibold text-emerald-400">
                          {formatCurrency(subtotal)}
                        </span>
                      </div>

                      <div className="sm:col-span-1 text-center">
                        <button
                          type="button"
                          onClick={() => eliminarLineaVenta(idx)}
                          className="text-red-400 hover:text-red-300 text-xs font-bold"
                        >
                          ✕
                        </button>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>

          {/* Sección de Envases / Contenedores */}
          <div className="space-y-3 pt-2 border-t border-slate-800">
            <div className="flex items-center justify-between">
              <h4 className="text-sm font-semibold text-slate-200">Envases / Contenedores Prestados y Retirados</h4>
              <Button variant="secondary" onClick={agregarLineaContenedor} className="text-xs px-2.5 py-1">
                + Agregar Contenedor
              </Button>
            </div>

            {lineasContenedor.length > 0 && (
              <div className="space-y-2">
                {lineasContenedor.map((cont, idx) => (
                  <div
                    key={idx}
                    className="grid grid-cols-1 sm:grid-cols-12 gap-2 items-center bg-slate-800/60 p-3 rounded-lg border border-slate-700/60"
                  >
                    <div className="sm:col-span-5">
                      <select
                        value={cont.contenedor_id}
                        onChange={(e) =>
                          actualizarLineaContenedor(idx, "contenedor_id", e.target.value)
                        }
                        className="w-full bg-slate-900 border border-slate-700 text-slate-100 rounded-md px-2 py-1.5 text-xs"
                      >
                        {contenedores.map((c) => (
                          <option key={c.id} value={c.id}>
                            {c.tipo} {c.capacidad ? `(${c.capacidad})` : ""}
                          </option>
                        ))}
                      </select>
                    </div>

                    <div className="sm:col-span-3">
                      <label className="text-[10px] text-slate-400 block">Entregados (Prestados)</label>
                      <input
                        type="number"
                        min="0"
                        value={cont.cantidad_entregada}
                        onChange={(e) =>
                          actualizarLineaContenedor(idx, "cantidad_entregada", e.target.value)
                        }
                        className="w-full bg-slate-900 border border-slate-700 text-slate-100 rounded-md px-2 py-1 text-xs text-right"
                      />
                    </div>

                    <div className="sm:col-span-3">
                      <label className="text-[10px] text-slate-400 block">Retirados (Devueltos por cliente)</label>
                      <input
                        type="number"
                        min="0"
                        value={cont.cantidad_retirada}
                        onChange={(e) =>
                          actualizarLineaContenedor(idx, "cantidad_retirada", e.target.value)
                        }
                        className="w-full bg-slate-900 border border-slate-700 text-slate-100 rounded-md px-2 py-1 text-xs text-right"
                      />
                    </div>

                    <div className="sm:col-span-1 text-center">
                      <button
                        type="button"
                        onClick={() => eliminarLineaContenedor(idx)}
                        className="text-red-400 hover:text-red-300 text-xs font-bold"
                      >
                        ✕
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>

          {/* Observaciones y Totales */}
          <div className="pt-2 border-t border-slate-800 space-y-4">
            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1">
                Observaciones (Opcional)
              </label>
              <textarea
                rows={2}
                value={observaciones}
                onChange={(e) => setObservaciones(e.target.value)}
                placeholder="Notas de entrega o acuerdo con el cliente..."
                className="w-full bg-slate-800 border border-slate-700 text-slate-100 rounded-md px-3 py-2 text-xs focus:ring-2 focus:ring-emerald-500"
              />
            </div>

            <div className="flex flex-col sm:flex-row items-center justify-between bg-slate-800/80 p-4 rounded-lg border border-slate-700">
              <div>
                <span className="text-xs text-slate-400">Total Venta Estimado</span>
                <div className="flex items-baseline space-x-3">
                  <span className="text-xl font-bold text-emerald-400">
                    {formatCurrency(totalVentaUsd)}
                  </span>
                  <span className="text-sm font-semibold text-blue-400">
                    Bs. {formatNumber(totalVentaBs)}
                  </span>
                </div>
              </div>

              <div className="mt-3 sm:mt-0 flex items-center space-x-3">
                <Button
                  variant="ghost"
                  onClick={() => setTabActiva("resumen")}
                  disabled={isPending}
                  className="text-xs px-3 py-1.5 font-medium"
                >
                  Cancelar
                </Button>

                <Button
                  onClick={handleGuardarVenta}
                  disabled={isPending || lineasVenta.length === 0}
                  className="bg-emerald-600 hover:bg-emerald-500 text-white font-semibold text-xs px-3 py-1.5"
                >
                  {isPending ? "Guardando..." : "✅ Registrar Venta en Ruta"}
                </Button>
              </div>
            </div>
          </div>
        </Card>
      )}

      {/* Pestaña 3: Cargar Almacén Móvil */}
      {tabActiva === "cargar_camion" && (
        <Card className="p-6 bg-slate-900 border-slate-800 space-y-6">
          <div>
            <h3 className="text-lg font-semibold text-white">Cargar Productos al Camión (Almacén Móvil)</h3>
            <p className="text-xs text-slate-400">
              Transfiere stock disponible del Almacén Central al Camión de AutoVentas sin asignar a un Radar.
            </p>
          </div>

          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <h4 className="text-sm font-semibold text-slate-200">Productos a Subir al Camión</h4>
              <Button
                variant="secondary"
                onClick={() => {
                  if (productos.length === 0) return;
                  setLineasCarga((prev) => [...prev, { producto_id: productos[0].id, cantidad: 10 }]);
                }}
                className="text-xs px-2.5 py-1"
              >
                + Agregar Producto
              </Button>
            </div>

            {lineasCarga.length === 0 ? (
              <p className="text-xs text-slate-500 italic py-3 text-center border border-dashed border-slate-800 rounded-md">
                Haga clic en &quot;+ Agregar Producto&quot; para armar el lote de carga del camión.
              </p>
            ) : (
              <div className="space-y-2">
                {lineasCarga.map((item, idx) => (
                  <div
                    key={idx}
                    className="grid grid-cols-1 sm:grid-cols-12 gap-2 items-center bg-slate-800/60 p-3 rounded-lg border border-slate-700/60"
                  >
                    <div className="sm:col-span-8">
                      <select
                        value={item.producto_id}
                        onChange={(e) => {
                          const val = e.target.value;
                          setLineasCarga((prev) => {
                            const next = [...prev];
                            next[idx].producto_id = val;
                            return next;
                          });
                        }}
                        className="w-full bg-slate-900 border border-slate-700 text-slate-100 rounded-md px-2 py-1.5 text-xs"
                      >
                        {productos.map((p) => (
                          <option key={p.id} value={p.id}>
                            {p.codigo} — {p.nombre}
                          </option>
                        ))}
                      </select>
                    </div>

                    <div className="sm:col-span-3">
                      <input
                        type="number"
                        min="1"
                        value={item.cantidad}
                        onChange={(e) => {
                          const val = Number(e.target.value);
                          setLineasCarga((prev) => {
                            const next = [...prev];
                            next[idx].cantidad = val;
                            return next;
                          });
                        }}
                        className="w-full bg-slate-900 border border-slate-700 text-slate-100 rounded-md px-2 py-1.5 text-xs text-right"
                      />
                    </div>

                    <div className="sm:col-span-1 text-center">
                      <button
                        type="button"
                        onClick={() => setLineasCarga((prev) => prev.filter((_, i) => i !== idx))}
                        className="text-red-400 hover:text-red-300 text-xs font-bold"
                      >
                        ✕
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>

          <div className="flex justify-end space-x-3 pt-4 border-t border-slate-800">
            <Button variant="ghost" onClick={() => setTabActiva("resumen")} className="text-xs px-3 py-1.5 font-medium">
              Cancelar
            </Button>
            <Button
              onClick={handleCargarInventario}
              disabled={isPending || lineasCarga.length === 0}
              className="bg-emerald-600 hover:bg-emerald-500 text-white font-semibold text-xs px-3 py-1.5"
            >
              {isPending ? "Cargando..." : "📦 Procesar Carga al Camión"}
            </Button>
          </div>
        </Card>
      )}
    </div>
  );
}
