"use client";

import { useEffect, useMemo, useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { LogiImage } from "@/components/media/logi-image";
import { ProductoCatalogo } from "@/components/productos/producto-catalogo";
import { ClienteCombobox } from "@/components/clientes/cliente-combobox";
import {
  EnvasesResumenTabla,
  EnvasesVentaFields,
} from "@/components/contenedores/envases-venta";
import {
  calcularEnvasesEntregados,
  parseEnvasesResumen,
  type EnvaseResumenVenta,
} from "@/lib/contenedores/envases-venta";
import { resolveProductoImage } from "@/lib/product-images";
import { formatCurrency, formatNumber } from "@/lib/format";
import {
  encodeCargaTicket,
  type CargaTicketData,
} from "@/lib/autoventas/carga-ticket";
import {
  cargarInventarioMovilAutoVentasAction,
  obtenerResumenAutoVentasJornada,
  obtenerSaldosEnvasesClienteAction,
  registrarVentaEnRutaAction,
  reversarInventarioMovilAutoVentasAction,
  consultarDescuentoProductoClienteAction,
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
  precio_lista_usd?: number;
  porcentaje_descuento?: number;
  monto_descuento_usd?: number;
  aplica_descuento?: boolean;
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
  const [agregandoProducto, setAgregandoProducto] = useState(false);

  const [clienteId, setClienteId] = useState("");
  const [observaciones, setObservaciones] = useState("");
  const [lineasVenta, setLineasVenta] = useState<LineaVenta[]>([]);
  const [retiradosEnvases, setRetiradosEnvases] = useState<Record<string, string>>({});
  const [saldosEnvases, setSaldosEnvases] = useState<Record<
    string,
    number
  > | null>(null);
  const [cargandoSaldos, setCargandoSaldos] = useState(false);
  const [ultimaVentaId, setUltimaVentaId] = useState<string | null>(null);
  const [ultimaVentaEnvases, setUltimaVentaEnvases] = useState<EnvaseResumenVenta[]>([]);
  const [ultimaCarga, setUltimaCarga] = useState<CargaTicketData | null>(null);
  const [ultimaDescarga, setUltimaDescarga] = useState<CargaTicketData | null>(
    null,
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

  const clienteOptions = useMemo(
    () =>
      clientes.map((c) => ({
        value: c.id,
        label: c.razon_social,
        hint: c.rif_nit,
      })),
    [clientes],
  );

  const clienteSolicitado = useRef("");

  function seleccionarCliente(id: string) {
    setClienteId(id);
    setRetiradosEnvases({});
    setSaldosEnvases(null);
    clienteSolicitado.current = id;
    if (!id) {
      setCargandoSaldos(false);
      return;
    }
    setCargandoSaldos(true);
    void obtenerSaldosEnvasesClienteAction(id).then((res) => {
      if (clienteSolicitado.current !== id) return;
      setCargandoSaldos(false);
      setSaldosEnvases(res.success && res.data ? res.data : {});
    });
  }

  const envasesEntregados = useMemo(
    () =>
      calcularEnvasesEntregados(
        lineasVenta.map((l) => ({
          cantidad: l.cantidad,
          contenedor_id: catalogo[l.producto_id]?.contenedor_id,
          unidades_por_contenedor:
            catalogo[l.producto_id]?.unidades_por_contenedor,
        })),
      ),
    [lineasVenta, catalogo],
  );

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
  const cargaActualTicket: CargaTicketData | null = inventarioResumen.length
    ? {
        tipo: "carga",
        camion: camiones.find((c) => c.id === camionId)?.placa ?? "—",
        camionId,
        fecha: new Date().toISOString(),
        lineas: inventarioResumen.map((item) => ({
          codigo: item.codigo ?? "",
          producto: item.nombre ?? "Producto",
          cantidad: Number(item.cantidad_cargada) || 0,
          entregado: Number(item.cantidad_entregada) || 0,
          disponible: Number(item.cantidad_disponible) || 0,
        })),
      }
    : null;
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

  async function agregarVenta(producto: ProductoListaRpc, cantidad: number) {
    if (!clienteId) {
      setMensaje({ tipo: "error", texto: "Debes seleccionar un cliente primero para calcular descuentos." });
      return;
    }
    const qty = Math.max(1, Math.floor(cantidad) || 1);
    registrarEnCatalogo(producto);
    
    setAgregandoProducto(true);
    const res = await consultarDescuentoProductoClienteAction(clienteId, producto.id);
    setAgregandoProducto(false);

    let precio_lista_usd = Number(producto.precio_lista1 ?? producto.precio ?? 0);
    let precio_unitario = precio_lista_usd;
    let porcentaje_descuento = 0;
    let monto_descuento_usd = 0;
    let aplica_descuento = false;

    if (res.success && res.data) {
      precio_lista_usd = res.data.precio_lista_usd;
      precio_unitario = res.data.precio_final_usd;
      porcentaje_descuento = res.data.porcentaje_descuento;
      monto_descuento_usd = res.data.monto_descuento_usd;
      aplica_descuento = res.data.aplica_descuento;
    }

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
          precio_unitario,
          precio_lista_usd,
          porcentaje_descuento,
          monto_descuento_usd,
          aplica_descuento,
        },
      ];
    });
  }

  const handleGuardarVenta = () => {
    setMensaje(null);
    setUltimaVentaId(null);
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

    const contenedoresJson = contenedores
      .map((c) => {
        const saldo = saldosEnvases?.[c.id] ?? 0;
        const entregados = envasesEntregados[c.id] ?? 0;
        const retirados = Number(retiradosEnvases[c.id]) || 0;
        return {
          id: c.id,
          nombre: c.nombre,
          entregados,
          retirados,
          excede: retirados > saldo + entregados,
        };
      })
      .filter((c) => c.entregados > 0 || c.retirados > 0);
    const excedidos = contenedoresJson.filter((c) => c.excede);
    if (
      excedidos.length &&
      !confirm(
        `Los retirados superan el saldo del cliente en: ${excedidos
          .map((c) => c.nombre)
          .join(", ")}. El saldo final quedará en 0. ¿Continuar?`,
      )
    ) {
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
        contenedores_json: contenedoresJson.map((c) => ({
          contenedor_id: c.id,
          cantidad_entregada: c.entregados,
          cantidad_retirada: c.retirados,
        })),
        observaciones: observaciones || undefined,
        tasa_cambio: tasaOficial > 0 ? tasaOficial : undefined,
      });

      if (res.success) {
        setMensaje({
          tipo: "success",
          texto: res.message || "Venta registrada.",
        });
        setUltimaVentaId(res.data?.orden_id ?? null);
        setUltimaVentaEnvases(parseEnvasesResumen(res.data?.contenedores));
        setLineasVenta([]);
        seleccionarCliente("");
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
        setUltimaCarga({
          camion: camiones.find((c) => c.id === camionId)?.placa ?? "—",
          camionId,
          fecha: new Date().toISOString(),
          lineas: lineasCarga.map((l) => ({
            codigo: catalogo[l.producto_id]?.codigo_producto ?? "",
            producto: catalogo[l.producto_id]?.nombre ?? "Producto",
            cantidad: l.cantidad,
          })),
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
        "Descargar camión: todo el sobrante (cargado − entregado) vuelve al almacén y el inventario móvil queda en cero. ¿Continuar?",
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
          texto: res.message || "Sobrante devuelto al almacén.",
        });
        const detalle = res.data?.detalle ?? [];
        setUltimaDescarga(
          detalle.length
            ? {
                tipo: "descarga",
                camion:
                  camiones.find((c) => c.id === camionId)?.placa ?? "—",
                camionId,
                fecha: new Date().toISOString(),
                lineas: detalle.map((d) => ({
                  codigo: d.codigo ?? "",
                  producto: d.nombre,
                  cantidad: Number(d.cantidad) || 0,
                })),
              }
            : null,
        );
        router.refresh();
      } else {
        setMensaje({
          tipo: "error",
          texto: res.message || "No se pudo descargar el camión.",
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

      {ultimaVentaId ? (
        <Card className="space-y-3 p-4">
          <div className="flex flex-wrap items-center justify-between gap-3">
          <p className="text-sm text-lt-text">
            Venta registrada. Puedes imprimir el ticket con el balance de
            envases.
          </p>
          <div className="flex flex-wrap gap-2">
            <Button
              href={`/ordenes/${ultimaVentaId}/imprimir?volver=/autoventas`}
              variant="primary"
            >
              Ver / imprimir ticket
            </Button>
            <Button
              type="button"
              variant="secondary"
              onClick={() => setUltimaVentaId(null)}
            >
              Listo
            </Button>
          </div>
          </div>
          {ultimaVentaEnvases.length ? (
            <div className="space-y-1">
              <h3 className="text-sm font-semibold text-lt-text">
                Resumen de envases
              </h3>
              <EnvasesResumenTabla filas={ultimaVentaEnvases} />
            </div>
          ) : null}
        </Card>
      ) : null}

      {ultimaCarga ? (
        <Card className="space-y-3 p-4">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div>
              <h2 className="text-base font-semibold text-lt-success-text">
                Carga confirmada
              </h2>
              <p className="text-sm text-lt-text-muted">
                Camión {ultimaCarga.camion} ·{" "}
                {formatNumber(
                  ultimaCarga.lineas.reduce((s, l) => s + l.cantidad, 0),
                )}{" "}
                unidades en {formatNumber(ultimaCarga.lineas.length)} producto
                {ultimaCarga.lineas.length === 1 ? "" : "s"}
              </p>
            </div>
            <div className="flex flex-wrap gap-2">
              <Button
                href={`/autoventas/carga/imprimir?d=${encodeCargaTicket(ultimaCarga)}`}
                variant="primary"
              >
                Imprimir carga
              </Button>
              <Button
                type="button"
                variant="secondary"
                onClick={() => setUltimaCarga(null)}
              >
                Cerrar
              </Button>
            </div>
          </div>
        </Card>
      ) : null}

      {ultimaDescarga ? (
        <Card className="space-y-3 p-4">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div>
              <h2 className="text-base font-semibold text-lt-success-text">
                Descarga confirmada
              </h2>
              <p className="text-sm text-lt-text-muted">
                Camión {ultimaDescarga.camion} ·{" "}
                {formatNumber(
                  ultimaDescarga.lineas.reduce((s, l) => s + l.cantidad, 0),
                )}{" "}
                unidades devueltas al almacén en{" "}
                {formatNumber(ultimaDescarga.lineas.length)} producto
                {ultimaDescarga.lineas.length === 1 ? "" : "s"}
              </p>
            </div>
            <div className="flex flex-wrap gap-2">
              <Button
                href={`/autoventas/carga/imprimir?d=${encodeCargaTicket(ultimaDescarga)}`}
                variant="primary"
              >
                Imprimir descarga
              </Button>
              <Button
                type="button"
                variant="secondary"
                onClick={() => setUltimaDescarga(null)}
              >
                Cerrar
              </Button>
            </div>
          </div>
        </Card>
      ) : null}

      <Card className="space-y-4 p-4">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
          <div className="min-w-[14rem] flex-1 space-y-1.5">
            <label className="block text-sm font-medium text-lt-text">
              Camión
            </label>
            <select
              value={camionId}
              onChange={(e) => {
                setCamionId(e.target.value);
                setUltimaCarga(null);
                setUltimaDescarga(null);
              }}
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
              <div className="flex flex-wrap gap-2">
                {cargaActualTicket ? (
                  <Button
                    href={`/autoventas/carga/imprimir?d=${encodeCargaTicket(cargaActualTicket)}`}
                    variant="primary"
                  >
                    Imprimir carga
                  </Button>
                ) : null}
                {camionId && inventarioResumen.length > 0 ? (
                  <Button
                    href={`/autoventas/entregas/imprimir?camionId=${camionId}`}
                    variant="primary"
                  >
                    Imprimir Entregas
                  </Button>
                ) : null}
                <Button
                  type="button"
                  variant="secondary"
                  disabled={isPending || inventarioResumen.length === 0}
                  onClick={handleReversar}
                >
                  Descargar camión (devolver sobrante)
                </Button>
              </div>
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
            <ClienteCombobox
              label="Cliente *"
              options={clienteOptions}
              value={clienteId}
              onChange={seleccionarCliente}
              placeholder="Escribe razón social o RIF…"
              minChars={2}
            />
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
            ) : agregandoProducto ? (
              <p className="rounded-xl border border-dashed border-lt-border px-4 py-8 text-center text-sm text-lt-text-muted">
                Calculando descuento...
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
                        {linea.aplica_descuento && linea.precio_lista_usd != null && (
                          <div className="flex flex-col text-xs text-lt-text-muted mt-0.5">
                            <p>Precio base: {formatCurrency(linea.precio_lista_usd)}</p>
                            {(linea.porcentaje_descuento ?? 0) > 0 && (
                              <p className="text-lt-success-text font-medium">
                                Desc. {linea.porcentaje_descuento}% ({formatCurrency(linea.monto_descuento_usd ?? 0)} · {formatNumber((linea.monto_descuento_usd ?? 0) * tasaOficial)} Bs)
                              </p>
                            )}
                          </div>
                        )}
                        <div className="grid grid-cols-2 gap-2 pt-1">
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

            <div className="mt-4 border-t border-lt-border-light pt-4">
              <EnvasesVentaFields
                tipos={contenedores}
                clienteSeleccionado={Boolean(clienteId)}
                cargandoSaldos={cargandoSaldos}
                saldos={saldosEnvases}
                entregados={envasesEntregados}
                retirados={retiradosEnvases}
                onRetiradosChange={(id, valor) =>
                  setRetiradosEnvases((prev) => ({ ...prev, [id]: valor }))
                }
              />
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
