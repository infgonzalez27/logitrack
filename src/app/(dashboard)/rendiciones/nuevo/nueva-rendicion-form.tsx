"use client";

import { useEffect, useMemo, useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import {
  registrarRendicionCuentasAction,
  solicitaAbonosOrdenDistribucionAction,
  uploadCaptureRendicionAction,
  type OrdenParaRendicion,
} from "@/lib/actions/rendiciones";
import { formatCurrency, formatDateOnly, formatNumber } from "@/lib/format";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import {
  convertirBsAUsd,
  convertirUsdABs,
  esFormaPagoEnBs,
} from "@/lib/rendiciones/moneda";
import type {
  CuentaBancariaEmpresa,
  Fpago,
  TasaCambio,
} from "@/types/database";

export type ClienteOption = {
  value: string;
  label: string;
  codigo: string;
};

type PagoAgregado = {
  key: string;
  fpago_id: string;
  concepto: string;
  fpago_info: boolean;
  en_bs: boolean;
  monto_ingresado: number;
  monto_usd: number;
  monto_bs: number;
  tasa_aplicada: number | null;
  fecha: string;
  referencia_bancaria: string | null;
  cuenta_bancaria_id: string | null;
  cuenta_label: string | null;
  capture_url: string | null;
  preview_url: string | null;
};

type OrdenAgregada = {
  key: string;
  orden_id: string;
  correlativo: number;
  monto_orden: number;
  monto_orden_bs: number | null;
  abonos: number;
  saldo_pendiente: number;
  saldo_pendiente_bs: number | null;
  monto_rendicion: number;
  monto_rendicion_bs: number;
};

function newKey() {
  return `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
}

function hoyLocal(): string {
  const d = new Date();
  const yyyy = d.getFullYear();
  const mm = String(d.getMonth() + 1).padStart(2, "0");
  const dd = String(d.getDate()).padStart(2, "0");
  return `${yyyy}-${mm}-${dd}`;
}

export function NuevaRendicionForm({
  clientes,
  formasPago,
  formasError,
  cuentasBancarias,
  cuentasError = null,
  tasaDelDia = null,
  tasaError = null,
}: {
  clientes: ClienteOption[];
  formasPago: Fpago[];
  formasError?: string | null;
  cuentasBancarias: CuentaBancariaEmpresa[];
  cuentasError?: string | null;
  tasaDelDia?: TasaCambio | null;
  tasaError?: string | null;
}) {
  const router = useRouter();
  const captureInputRef = useRef<HTMLInputElement>(null);

  const [buscarCliente, setBuscarCliente] = useState("");
  const [clienteId, setClienteId] = useState("");
  const [fechaPago, setFechaPago] = useState(hoyLocal);
  const [observaciones, setObservaciones] = useState("");
  const [saldoFavor, setSaldoFavor] = useState(0);
  const [saldoFavorBs, setSaldoFavorBs] = useState<number | null>(null);
  const [tasaOficial, setTasaOficial] = useState<number | null>(
    tasaDelDia != null && Number(tasaDelDia.tasa_cambio) > 0
      ? Number(tasaDelDia.tasa_cambio)
      : null,
  );

  const [ordenesDisponibles, setOrdenesDisponibles] = useState<
    OrdenParaRendicion[]
  >([]);
  const [ordenesError, setOrdenesError] = useState<string | null>(null);
  const [cargandoOrdenes, setCargandoOrdenes] = useState(false);

  const [borradorFpagoId, setBorradorFpagoId] = useState("");
  const [borradorMontoForma, setBorradorMontoForma] = useState("0.00");
  const [borradorFechaPago, setBorradorFechaPago] = useState(hoyLocal);
  const [borradorReferencia, setBorradorReferencia] = useState("");
  const [borradorCuentaId, setBorradorCuentaId] = useState(
    () => cuentasBancarias[0]?.id ?? "",
  );
  const [borradorCaptureUrl, setBorradorCaptureUrl] = useState<string | null>(
    null,
  );
  const [borradorPreview, setBorradorPreview] = useState<string | null>(null);
  const [subiendoCapture, setSubiendoCapture] = useState(false);
  const [pagoSeleccionadoKey, setPagoSeleccionadoKey] = useState<string | null>(
    null,
  );

  const [borradorOrdenId, setBorradorOrdenId] = useState("");
  const [borradorMontoOrden, setBorradorMontoOrden] = useState("0.00");
  const [borradorRendicion, setBorradorRendicion] = useState("0.00");

  const [pagos, setPagos] = useState<PagoAgregado[]>([]);
  const [ordenes, setOrdenes] = useState<OrdenAgregada[]>([]);

  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  const tasaValor =
    tasaOficial != null && tasaOficial > 0
      ? tasaOficial
      : tasaDelDia != null && Number(tasaDelDia.tasa_cambio) > 0
        ? Number(tasaDelDia.tasa_cambio)
        : null;

  const formaSeleccionada = formasPago.find(
    (f) => f.fpago_id === borradorFpagoId,
  );
  const pideInfoBancaria = formaSeleccionada?.fpago_info === true;
  const borradorEnBs = formaSeleccionada
    ? esFormaPagoEnBs(formaSeleccionada.fpago_concepto)
    : false;
  const borradorEquivUsd =
    borradorEnBs && tasaValor != null
      ? convertirBsAUsd(Number(borradorMontoForma) || 0, tasaValor)
      : Number(borradorMontoForma) || 0;
  const borradorEquivBs =
    !borradorEnBs && tasaValor != null
      ? convertirUsdABs(Number(borradorMontoForma) || 0, tasaValor)
      : Number(borradorMontoForma) || 0;

  const clientesFiltrados = useMemo(() => {
    const q = buscarCliente.trim().toLowerCase();
    if (!q) return clientes;
    return clientes.filter(
      (c) =>
        c.label.toLowerCase().includes(q) ||
        c.codigo.toLowerCase().includes(q),
    );
  }, [clientes, buscarCliente]);

  const cuentasOptions = useMemo(
    () =>
      cuentasBancarias.map((c) => ({
        value: c.id,
        label: `${c.entidad_bancaria} · ${c.cuenta_bancaria}`,
      })),
    [cuentasBancarias],
  );

  useEffect(() => {
    if (!clienteId) {
      setOrdenesDisponibles([]);
      setOrdenesError(null);
      setOrdenes([]);
      setSaldoFavor(0);
      setSaldoFavorBs(null);
      setBorradorOrdenId("");
      setBorradorMontoOrden("0.00");
      setBorradorRendicion("0.00");
      return;
    }

    let cancelled = false;
    setCargandoOrdenes(true);
    setOrdenesError(null);

    void solicitaAbonosOrdenDistribucionAction(clienteId).then((result) => {
      if (cancelled) return;
      setCargandoOrdenes(false);
      if (!result.ok) {
        setOrdenesError(result.error);
        setOrdenesDisponibles([]);
        setSaldoFavor(0);
        setSaldoFavorBs(null);
        return;
      }
      setOrdenesDisponibles(result.data.ordenes);
      setSaldoFavor(result.data.saldo_favor);
      setSaldoFavorBs(result.data.saldo_favor_bs);
      if (
        result.data.tasa_oficial_actual != null &&
        result.data.tasa_oficial_actual > 0
      ) {
        setTasaOficial(result.data.tasa_oficial_actual);
      }
      setOrdenes([]);
      setBorradorOrdenId("");
      setBorradorMontoOrden("0.00");
      setBorradorRendicion("0.00");
    });

    return () => {
      cancelled = true;
    };
  }, [clienteId]);

  const ordenesParaSelect = useMemo(() => {
    const usadas = new Set(ordenes.map((o) => o.orden_id));
    return ordenesDisponibles
      .filter((o) => !usadas.has(o.id) && o.saldo_pendiente > 0)
      .map((o) => ({
        value: o.id,
        label: `#${o.correlativo} · pendiente ${formatCurrency(o.saldo_pendiente)}`,
      }));
  }, [ordenesDisponibles, ordenes]);

  const totalOrdenes = useMemo(
    () => ordenes.reduce((sum, o) => sum + o.monto_rendicion, 0),
    [ordenes],
  );
  const totalRendicion = useMemo(
    () => pagos.reduce((sum, p) => sum + p.monto_usd, 0),
    [pagos],
  );
  const diferencia = totalRendicion - totalOrdenes;

  function resetFormulario() {
    setBuscarCliente("");
    setClienteId("");
    setFechaPago(hoyLocal());
    setObservaciones("");
    setSaldoFavor(0);
    setSaldoFavorBs(null);
    setOrdenesDisponibles([]);
    setOrdenesError(null);
    setBorradorFpagoId("");
    setBorradorMontoForma("0.00");
    setBorradorFechaPago(hoyLocal());
    setBorradorReferencia("");
    setBorradorCuentaId(cuentasBancarias[0]?.id ?? "");
    setBorradorCaptureUrl(null);
    setBorradorPreview(null);
    setPagoSeleccionadoKey(null);
    setBorradorOrdenId("");
    setBorradorMontoOrden("0.00");
    setBorradorRendicion("0.00");
    setPagos([]);
    setOrdenes([]);
    setError(null);
    if (captureInputRef.current) captureInputRef.current.value = "";
  }

  function onFormaChange(value: string) {
    setBorradorFpagoId(value);
    setBorradorReferencia("");
  }

  function onOrdenChange(value: string) {
    setBorradorOrdenId(value);
    const found = ordenesDisponibles.find((o) => o.id === value);
    if (found) {
      const monto = found.saldo_pendiente.toFixed(2);
      setBorradorMontoOrden(monto);
      setBorradorRendicion(monto);
    } else {
      setBorradorMontoOrden("0.00");
      setBorradorRendicion("0.00");
    }
  }

  async function onCaptureSelected(file: File | undefined) {
    if (!file) return;
    setError(null);

    if (borradorPreview?.startsWith("blob:")) {
      URL.revokeObjectURL(borradorPreview);
    }
    const localPreview = URL.createObjectURL(file);
    setBorradorPreview(localPreview);
    setSubiendoCapture(true);

    const formData = new FormData();
    formData.set("file", file);
    const result = await uploadCaptureRendicionAction(formData);
    setSubiendoCapture(false);

    if (!result.ok) {
      setError(result.error);
      setBorradorCaptureUrl(null);
      return;
    }
    setBorradorCaptureUrl(result.url);
  }

  function incluirPago() {
    setError(null);
    if (!formaSeleccionada) {
      setError("Selecciona una forma de pago.");
      return;
    }
    const montoIngresado = Number(borradorMontoForma);
    if (!Number.isFinite(montoIngresado) || montoIngresado <= 0) {
      setError("El monto de la forma de pago debe ser mayor a 0.");
      return;
    }
    const enBs = esFormaPagoEnBs(formaSeleccionada.fpago_concepto);
    if (enBs && (tasaValor == null || tasaValor <= 0)) {
      setError(
        "No hay tasa del día para convertir bolívares. Regístrala en Tasas de cambio (BCV).",
      );
      return;
    }
    if (formaSeleccionada.fpago_info) {
      if (!borradorReferencia.trim()) {
        setError("Ingresa la referencia bancaria.");
        return;
      }
      if (!borradorCuentaId) {
        setError("Selecciona la cuenta bancaria de la empresa.");
        return;
      }
    }

    const montoUsd = enBs
      ? convertirBsAUsd(montoIngresado, tasaValor as number)
      : montoIngresado;
    const montoBs = enBs
      ? montoIngresado
      : tasaValor != null
        ? convertirUsdABs(montoIngresado, tasaValor)
        : 0;

    const cuenta = cuentasBancarias.find((c) => c.id === borradorCuentaId);

    setPagos((prev) => [
      ...prev,
      {
        key: newKey(),
        fpago_id: formaSeleccionada.fpago_id,
        concepto: formaSeleccionada.fpago_concepto,
        fpago_info: formaSeleccionada.fpago_info,
        en_bs: enBs,
        monto_ingresado: montoIngresado,
        monto_usd: montoUsd,
        monto_bs: montoBs,
        tasa_aplicada: tasaValor,
        fecha: borradorFechaPago || fechaPago,
        referencia_bancaria: formaSeleccionada.fpago_info
          ? borradorReferencia.trim()
          : null,
        cuenta_bancaria_id: formaSeleccionada.fpago_info
          ? borradorCuentaId
          : null,
        cuenta_label: formaSeleccionada.fpago_info
          ? cuenta
            ? `${cuenta.entidad_bancaria} · ${cuenta.cuenta_bancaria}`
            : null
          : null,
        capture_url: borradorCaptureUrl,
        preview_url: borradorPreview,
      },
    ]);

    setBorradorFpagoId("");
    setBorradorMontoForma("0.00");
    setBorradorFechaPago(fechaPago);
    setBorradorReferencia("");
    setBorradorCaptureUrl(null);
    setBorradorPreview(null);
    setPagoSeleccionadoKey(null);
    if (captureInputRef.current) captureInputRef.current.value = "";
  }

  function quitarPagoSeleccionado() {
    if (!pagoSeleccionadoKey) {
      setError("Selecciona una opción de pago para quitar.");
      return;
    }
    setPagos((prev) => prev.filter((p) => p.key !== pagoSeleccionadoKey));
    setPagoSeleccionadoKey(null);
  }

  function agregarOrden() {
    setError(null);
    if (!borradorOrdenId) {
      setError("Selecciona una orden.");
      return;
    }
    const found = ordenesDisponibles.find((o) => o.id === borradorOrdenId);
    if (!found) {
      setError("Orden no válida.");
      return;
    }
    const montoRendicion = Number(borradorRendicion);
    if (!Number.isFinite(montoRendicion) || montoRendicion <= 0) {
      setError("El monto a rendir debe ser mayor a 0.");
      return;
    }
    if (montoRendicion > found.saldo_pendiente + 0.009) {
      setError(
        `El monto a rendir no puede superar el saldo pendiente (${formatCurrency(found.saldo_pendiente)}).`,
      );
      return;
    }

    const montoBs =
      tasaValor != null
        ? convertirUsdABs(montoRendicion, tasaValor)
        : found.saldo_pendiente_bs != null && found.saldo_pendiente > 0
          ? (montoRendicion / found.saldo_pendiente) * found.saldo_pendiente_bs
          : 0;

    setOrdenes((prev) => [
      ...prev,
      {
        key: newKey(),
        orden_id: found.id,
        correlativo: found.correlativo,
        monto_orden: found.monto_total_orden,
        monto_orden_bs: found.monto_total_orden_bs,
        abonos: found.abonos_acumulados,
        saldo_pendiente: found.saldo_pendiente,
        saldo_pendiente_bs: found.saldo_pendiente_bs,
        monto_rendicion: montoRendicion,
        monto_rendicion_bs: montoBs,
      },
    ]);

    setBorradorOrdenId("");
    setBorradorMontoOrden("0.00");
    setBorradorRendicion("0.00");
  }

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);

    if (!clienteId) {
      setError("Selecciona un cliente.");
      return;
    }
    if (!pagos.length) {
      setError("Agrega al menos una opción de pago.");
      return;
    }
    if (!ordenes.length) {
      setError("Agrega al menos una orden.");
      return;
    }

    const obs = [
      observaciones.trim(),
      fechaPago ? `Fecha de pago: ${fechaPago}` : "",
    ]
      .filter(Boolean)
      .join(" · ");

    startTransition(async () => {
      const result = await registrarRendicionCuentasAction({
        cliente_id: clienteId,
        observaciones: obs || undefined,
        tasa_cambio: tasaValor,
        ordenes: ordenes.map((o) => ({
          orden_id: o.orden_id,
          monto_recaudado: o.monto_rendicion,
          monto_recaudado_bs: o.monto_rendicion_bs,
        })),
        pagos: pagos.map((p) => ({
          fpago_id: p.fpago_id,
          monto: p.monto_ingresado,
          en_bs: p.en_bs,
          monto_bs: p.monto_bs,
          monto_usd: p.monto_usd,
          fpago_info: p.fpago_info,
          referencia_bancaria: p.referencia_bancaria,
          cuenta_bancaria_id: p.cuenta_bancaria_id,
          capture_url: p.capture_url,
        })),
      });

      if (result?.error) {
        setError(result.error);
      }
    });
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-4 pb-28">
      <section className="overflow-hidden rounded-2xl border border-lt-border bg-[color-mix(in_srgb,var(--lt-primary)_18%,#0f2a3d)] text-white shadow-sm">
        <div className="border-b border-white/15 px-4 py-3 sm:px-5">
          <h1 className="font-display text-xl tracking-tight sm:text-2xl">
            Rendición de Cuentas
          </h1>
        </div>
        <div className="grid gap-3 p-4 sm:grid-cols-2 sm:p-5 lg:grid-cols-4">
          <div className="space-y-1.5">
            <label className="block text-xs font-medium text-white/80">
              Proceso No.
            </label>
            <input
              readOnly
              value="Nuevo"
              className="w-full rounded-xl border border-white/20 bg-white/95 px-3.5 py-2.5 text-sm text-lt-text"
            />
          </div>
          <div className="space-y-1.5">
            <label className="block text-xs font-medium text-white/80">
              Fecha de pago
            </label>
            <input
              type="date"
              value={fechaPago}
              onChange={(e) => {
                setFechaPago(e.target.value);
                setBorradorFechaPago(e.target.value);
              }}
              className="w-full rounded-xl border border-white/20 bg-white/95 px-3.5 py-2.5 text-sm text-lt-text"
            />
          </div>
          <div className="space-y-1.5">
            <label className="block text-xs font-medium text-white/80">
              Tasa del día (BCV)
            </label>
            <input
              readOnly
              value={
                tasaValor != null
                  ? `${formatNumber(tasaValor)}${
                      tasaDelDia?.fecha_tasa
                        ? ` · ${formatDateOnly(tasaDelDia.fecha_tasa)}`
                        : ""
                    }`
                  : "Sin tasa"
              }
              className="w-full rounded-xl border border-white/20 bg-white/95 px-3.5 py-2.5 text-sm text-lt-text"
            />
            {tasaError ? (
              <p className="text-xs text-amber-200">{tasaError}</p>
            ) : !tasaValor ? (
              <p className="text-xs text-amber-200">
                Registra la tasa en Tasas de cambio para pagos en Bs.
              </p>
            ) : null}
          </div>
          <div className="space-y-1.5">
            <label className="block text-xs font-medium text-white/80">
              Saldo a favor
            </label>
            <input
              readOnly
              value={
                clienteId
                  ? `${formatCurrency(saldoFavor)}${
                      saldoFavorBs != null
                        ? ` · ${formatNumber(saldoFavorBs)} Bs`
                        : ""
                    }`
                  : "—"
              }
              className="w-full rounded-xl border border-white/20 bg-white/95 px-3.5 py-2.5 text-sm text-lt-text"
            />
          </div>
          <div className="space-y-1.5 sm:col-span-2 lg:col-span-4">
            <label className="block text-xs font-medium text-white/80">
              Cliente
            </label>
            <input
              type="search"
              placeholder="Buscar por razón social o RIF…"
              value={buscarCliente}
              onChange={(e) => setBuscarCliente(e.target.value)}
              className="mb-2 w-full rounded-xl border border-white/20 bg-white/95 px-3.5 py-2 text-sm text-lt-text"
              autoComplete="off"
            />
            <select
              required
              value={clienteId}
              onChange={(e) => setClienteId(e.target.value)}
              className="w-full rounded-xl border border-white/20 bg-white/95 px-3.5 py-2.5 text-sm text-lt-text"
            >
              <option value="">Selecciona cliente</option>
              {clientesFiltrados.map((c) => (
                <option key={c.value} value={c.value}>
                  {c.codigo ? `${c.label} (${c.codigo})` : c.label}
                </option>
              ))}
            </select>
          </div>
          <div className="space-y-1.5 sm:col-span-2 lg:col-span-4">
            <label className="block text-xs font-medium text-white/80">
              Observaciones
            </label>
            <input
              value={observaciones}
              onChange={(e) => setObservaciones(e.target.value)}
              placeholder="Opcional"
              className="w-full rounded-xl border border-white/20 bg-white/95 px-3.5 py-2.5 text-sm text-lt-text"
            />
          </div>
        </div>
      </section>

      <section className="overflow-hidden rounded-2xl border border-lt-border bg-lt-surface shadow-sm">
        <div className="flex flex-wrap items-center justify-between gap-2 border-b border-lt-border-light bg-lt-surface-muted px-4 py-3">
          <h2 className="text-base font-semibold text-lt-text">Órdenes</h2>
          <Button type="button" onClick={agregarOrden} disabled={!clienteId}>
            + Orden
          </Button>
        </div>

        <div className="space-y-3 border-b border-lt-border-light p-4">
          {cargandoOrdenes ? (
            <p className="text-sm text-lt-text-muted">Cargando órdenes…</p>
          ) : null}
          {ordenesError ? (
            <p className="text-sm text-lt-danger-text">{ordenesError}</p>
          ) : null}
          {clienteId && !cargandoOrdenes && ordenesDisponibles.length === 0 ? (
            <p className="text-sm text-lt-text-muted">
              No hay órdenes por liquidar para este cliente.
            </p>
          ) : null}

          <div className="grid gap-3 sm:grid-cols-3">
            <Select
              label="Orden"
              placeholder="Órdenes por liquidar"
              options={ordenesParaSelect}
              value={borradorOrdenId}
              onChange={(e) => onOrdenChange(e.target.value)}
              disabled={!clienteId || cargandoOrdenes}
            />
            <Input
              label="Saldo pendiente $"
              type="number"
              min={0}
              step="0.01"
              readOnly
              value={borradorMontoOrden}
            />
            <Input
              label="Monto a rendir $"
              type="number"
              min={0}
              step="0.01"
              value={borradorRendicion}
              onChange={(e) => setBorradorRendicion(e.target.value)}
            />
          </div>
        </div>

        <div className="hidden overflow-x-auto md:block">
          <table className="min-w-full text-left text-sm">
            <thead className="bg-lt-surface-muted text-xs uppercase tracking-wide text-lt-text-muted">
              <tr>
                <th className="px-4 py-3 font-medium">Correlativo</th>
                <th className="px-4 py-3 font-medium">Total orden</th>
                <th className="px-4 py-3 font-medium">Abonos</th>
                <th className="px-4 py-3 font-medium">Saldo pend.</th>
                <th className="px-4 py-3 font-medium">Monto a rendir</th>
                <th className="px-4 py-3 font-medium" />
              </tr>
            </thead>
            <tbody>
              {ordenes.length === 0 ? (
                <tr>
                  <td
                    colSpan={6}
                    className="px-4 py-8 text-center text-lt-text-muted"
                  >
                    Agrega órdenes con el botón + Orden.
                  </td>
                </tr>
              ) : (
                ordenes.map((o) => (
                  <tr
                    key={o.key}
                    className="border-t border-lt-border-light"
                  >
                    <td className="px-4 py-3 font-medium text-lt-text">
                      {o.correlativo}
                    </td>
                    <td className="px-4 py-3">
                      {formatCurrency(o.monto_orden)}
                    </td>
                    <td className="px-4 py-3">{formatCurrency(o.abonos)}</td>
                    <td className="px-4 py-3">
                      {formatCurrency(o.saldo_pendiente)}
                    </td>
                    <td className="px-4 py-3 font-medium">
                      {formatCurrency(o.monto_rendicion)}
                      <span className="block text-xs text-lt-text-muted">
                        {formatNumber(o.monto_rendicion_bs)} Bs
                      </span>
                    </td>
                    <td className="px-4 py-3 text-right">
                      <button
                        type="button"
                        className="rounded-lg px-2 py-1 text-sm font-medium text-lt-danger-text hover:bg-lt-danger-bg"
                        onClick={() =>
                          setOrdenes((prev) =>
                            prev.filter((item) => item.key !== o.key),
                          )
                        }
                      >
                        Quitar
                      </button>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>

        <ul className="space-y-2 p-4 md:hidden">
          {ordenes.length === 0 ? (
            <li className="py-4 text-center text-sm text-lt-text-muted">
              Agrega órdenes con el botón + Orden.
            </li>
          ) : (
            ordenes.map((o) => (
              <li
                key={o.key}
                className="rounded-xl border border-lt-border-light p-3"
              >
                <div className="flex items-start justify-between gap-2">
                  <div>
                    <p className="font-semibold text-lt-text">
                      Orden No. {o.correlativo}
                    </p>
                    <p className="mt-1 text-sm text-lt-text-muted">
                      Pendiente {formatCurrency(o.saldo_pendiente)}
                    </p>
                    <p className="text-sm font-medium text-lt-text">
                      A rendir {formatCurrency(o.monto_rendicion)}
                    </p>
                  </div>
                  <button
                    type="button"
                    className="text-sm font-medium text-lt-danger-text"
                    onClick={() =>
                      setOrdenes((prev) =>
                        prev.filter((item) => item.key !== o.key),
                      )
                    }
                  >
                    Quitar
                  </button>
                </div>
              </li>
            ))
          )}
        </ul>

        <div className="flex justify-end border-t border-lt-border-light bg-lt-surface-muted px-4 py-3">
          <p className="text-sm font-semibold text-lt-text">
            Monto total a cobrar:{" "}
            <span className="text-lt-primary">
              {formatCurrency(totalOrdenes)}
            </span>
          </p>
        </div>
      </section>

      <section className="overflow-hidden rounded-2xl border border-lt-border bg-lt-surface shadow-sm">
        <div className="flex flex-wrap items-center justify-between gap-2 border-b border-lt-border-light bg-lt-surface-muted px-4 py-3">
          <h2 className="text-base font-semibold text-lt-text">
            Opciones de pago
          </h2>
          <div className="flex flex-wrap gap-2">
            <Button
              type="button"
              onClick={incluirPago}
              disabled={formasPago.length === 0}
            >
              Incluir
            </Button>
            <Button
              type="button"
              variant="secondary"
              onClick={quitarPagoSeleccionado}
              disabled={!pagoSeleccionadoKey}
            >
              Quitar
            </Button>
          </div>
        </div>

        <div className="space-y-3 border-b border-lt-border-light p-4">
          {formasError ? (
            <p className="text-sm text-lt-danger-text">{formasError}</p>
          ) : null}
          {cuentasError ? (
            <p className="text-sm text-lt-danger-text">{cuentasError}</p>
          ) : null}
          {!cuentasError && cuentasBancarias.length === 0 ? (
            <p className="text-sm text-amber-700">
              No hay cuentas bancarias activas de la empresa. Regístralas antes
              de pagos con transferencia / pago móvil.
            </p>
          ) : null}

          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <Select
              label="Forma de pago"
              placeholder="Selecciona forma"
              options={formasPago.map((f) => ({
                value: f.fpago_id,
                label: f.fpago_concepto,
              }))}
              value={borradorFpagoId}
              onChange={(e) => onFormaChange(e.target.value)}
              disabled={formasPago.length === 0}
            />
            <Input
              label="Fecha"
              type="date"
              value={borradorFechaPago}
              onChange={(e) => setBorradorFechaPago(e.target.value)}
            />
            <Input
              label={borradorEnBs ? "Monto Bs" : "Monto $"}
              type="number"
              min={0}
              step="0.01"
              value={borradorMontoForma}
              onChange={(e) => setBorradorMontoForma(e.target.value)}
            />
            {pideInfoBancaria ? (
              <div className="flex items-end gap-2">
                <Button
                  type="button"
                  variant="secondary"
                  disabled={subiendoCapture}
                  onClick={() => captureInputRef.current?.click()}
                >
                  {subiendoCapture ? "Subiendo…" : "Captura"}
                </Button>
                <div className="flex h-11 w-11 items-center justify-center overflow-hidden rounded-lg border border-lt-border bg-lt-surface-muted">
                  {borradorPreview ? (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img
                      src={borradorPreview}
                      alt="Vista previa captura"
                      className="h-full w-full object-cover"
                    />
                  ) : (
                    <span className="text-[10px] text-lt-text-muted">img</span>
                  )}
                </div>
                <input
                  ref={captureInputRef}
                  type="file"
                  accept="image/*"
                  capture="environment"
                  className="hidden"
                  onChange={(e) => void onCaptureSelected(e.target.files?.[0])}
                />
              </div>
            ) : (
              <div className="flex items-end">
                <p className="pb-2 text-xs text-lt-text-muted">
                  {borradorFpagoId
                    ? borradorEnBs
                      ? tasaValor != null
                        ? `Equivale a ${formatCurrency(borradorEquivUsd)}`
                        : "Falta tasa del día"
                      : tasaValor != null
                        ? `Equivale a ${formatNumber(borradorEquivBs)} Bs`
                        : "Monto en dólares"
                    : " "}
                </p>
              </div>
            )}
          </div>

          {borradorFpagoId && tasaValor != null ? (
            <p className="text-sm text-lt-text-muted">
              {borradorEnBs ? (
                <>
                  Conversión BCV:{" "}
                  <span className="font-medium text-lt-text">
                    {formatNumber(Number(borradorMontoForma) || 0)} Bs ÷{" "}
                    {formatNumber(tasaValor)} ={" "}
                    {formatCurrency(borradorEquivUsd)}
                  </span>
                </>
              ) : (
                <>
                  Equivalente:{" "}
                  <span className="font-medium text-lt-text">
                    {formatCurrency(Number(borradorMontoForma) || 0)} ×{" "}
                    {formatNumber(tasaValor)} ={" "}
                    {formatNumber(borradorEquivBs)} Bs
                  </span>
                </>
              )}
            </p>
          ) : null}

          {pideInfoBancaria ? (
            <div className="grid gap-3 sm:grid-cols-2">
              <Input
                label="Referencia bancaria"
                required
                value={borradorReferencia}
                onChange={(e) => setBorradorReferencia(e.target.value)}
                placeholder="Nº de referencia"
              />
              <Select
                label="Cuenta bancaria empresa"
                required
                placeholder="Selecciona cuenta destino"
                options={cuentasOptions}
                value={borradorCuentaId}
                onChange={(e) => setBorradorCuentaId(e.target.value)}
                disabled={cuentasBancarias.length === 0}
              />
            </div>
          ) : null}
        </div>

        <div className="hidden overflow-x-auto md:block">
          <table className="min-w-full text-left text-sm">
            <thead className="bg-lt-surface-muted text-xs uppercase tracking-wide text-lt-text-muted">
              <tr>
                <th className="px-4 py-3 font-medium">Forma de pago</th>
                <th className="px-4 py-3 font-medium">Fecha</th>
                <th className="px-4 py-3 font-medium">Monto ingresado</th>
                <th className="px-4 py-3 font-medium">USD</th>
                <th className="px-4 py-3 font-medium">Bs</th>
                <th className="px-4 py-3 font-medium">Cuenta / ref.</th>
                <th className="px-4 py-3 font-medium">Captura</th>
              </tr>
            </thead>
            <tbody>
              {pagos.length === 0 ? (
                <tr>
                  <td
                    colSpan={7}
                    className="px-4 py-8 text-center text-lt-text-muted"
                  >
                    Incluye opciones de pago con el botón Incluir.
                  </td>
                </tr>
              ) : (
                pagos.map((p) => (
                  <tr
                    key={p.key}
                    className={`cursor-pointer border-t border-lt-border-light ${
                      pagoSeleccionadoKey === p.key
                        ? "bg-lt-primary-muted"
                        : "hover:bg-lt-surface-muted"
                    }`}
                    onClick={() => setPagoSeleccionadoKey(p.key)}
                  >
                    <td className="px-4 py-3 font-medium text-lt-text">
                      {p.concepto}
                    </td>
                    <td className="px-4 py-3">{p.fecha || "—"}</td>
                    <td className="px-4 py-3">
                      {p.en_bs
                        ? `${formatNumber(p.monto_ingresado)} Bs`
                        : formatCurrency(p.monto_ingresado)}
                    </td>
                    <td className="px-4 py-3 font-medium">
                      {formatCurrency(p.monto_usd)}
                    </td>
                    <td className="px-4 py-3">
                      {formatNumber(p.monto_bs)}
                    </td>
                    <td className="px-4 py-3 text-lt-text-muted">
                      {p.cuenta_label ?? "—"}
                      {p.referencia_bancaria
                        ? ` · ${p.referencia_bancaria}`
                        : ""}
                    </td>
                    <td className="px-4 py-3">
                      {p.preview_url || p.capture_url ? (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img
                          src={p.preview_url ?? p.capture_url ?? ""}
                          alt=""
                          className="h-9 w-9 rounded object-cover"
                        />
                      ) : (
                        "—"
                      )}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>

        <ul className="space-y-2 p-4 md:hidden">
          {pagos.length === 0 ? (
            <li className="py-4 text-center text-sm text-lt-text-muted">
              Incluye opciones de pago con el botón Incluir.
            </li>
          ) : (
            pagos.map((p) => (
              <li
                key={p.key}
                className={`rounded-xl border p-3 ${
                  pagoSeleccionadoKey === p.key
                    ? "border-lt-primary bg-lt-primary-muted"
                    : "border-lt-border-light"
                }`}
                onClick={() => setPagoSeleccionadoKey(p.key)}
              >
                <p className="font-semibold text-lt-text">{p.concepto}</p>
                <p className="mt-1 text-sm text-lt-text-muted">
                  {p.en_bs
                    ? `${formatNumber(p.monto_ingresado)} Bs → ${formatCurrency(p.monto_usd)}`
                    : formatCurrency(p.monto_usd)}
                </p>
              </li>
            ))
          )}
        </ul>

        <div className="flex flex-wrap items-end justify-between gap-3 border-t border-lt-border-light bg-lt-surface-muted px-4 py-4">
          <div className="grid min-w-[16rem] flex-1 gap-3 sm:grid-cols-2 lg:max-w-xl">
            <Input
              label="Total Rendición $"
              readOnly
              value={formatNumber(totalRendicion)}
            />
            <Input
              label="Monto total a cobrar $"
              readOnly
              value={formatNumber(totalOrdenes)}
            />
          </div>
          <div className="text-right text-sm">
            {diferencia > 0 ? (
              <p className="text-lt-success-text">
                Saldo a favor: {formatCurrency(diferencia)}
              </p>
            ) : diferencia < 0 ? (
              <p className="text-lt-danger-text">
                Faltante: {formatCurrency(Math.abs(diferencia))}
              </p>
            ) : clienteId ? (
              <p className="text-lt-text-muted">Cuadra sin diferencia</p>
            ) : null}
          </div>
        </div>
      </section>

      {error ? <p className="lt-alert-error">{error}</p> : null}

      <div className="fixed inset-x-0 bottom-0 z-30 border-t border-lt-border bg-lt-surface/95 backdrop-blur">
        <div className="mx-auto flex max-w-6xl flex-wrap items-center justify-center gap-2 px-3 py-3 sm:justify-between">
          <div className="flex flex-wrap justify-center gap-2">
            <Button
              type="button"
              variant="secondary"
              onClick={() => router.push("/rendiciones")}
            >
              Buscar
            </Button>
            <Button
              type="button"
              variant="secondary"
              onClick={() => router.push("/rendiciones")}
            >
              Abandonar
            </Button>
          </div>
          <Button
            type="submit"
            disabled={pending || !clienteId || subiendoCapture}
          >
            {pending ? "Guardando…" : "Guardar"}
          </Button>
        </div>
      </div>
    </form>
  );
}
