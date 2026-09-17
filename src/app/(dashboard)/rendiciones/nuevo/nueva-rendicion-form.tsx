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

/** Saldo pendiente en Bs: del SP/local, o USD × tasa de la orden / del día. */
function saldoPendienteBsDeOrden(
  orden: OrdenParaRendicion | undefined,
  tasaFallback: number | null,
): number | null {
  if (!orden) return null;
  if (orden.saldo_pendiente_bs != null && orden.saldo_pendiente_bs > 0) {
    return orden.saldo_pendiente_bs;
  }
  const tasa =
    orden.tasa_orden != null && orden.tasa_orden > 0
      ? orden.tasa_orden
      : tasaFallback;
  if (orden.saldo_pendiente > 0 && tasa != null && tasa > 0) {
    return convertirUsdABs(orden.saldo_pendiente, tasa);
  }
  return null;
}

export function NuevaRendicionForm({
  clientes,
  formasPago,
  formasError,
  cuentasBancarias,
  cuentasError = null,
  tasaDelDia = null,
  tasaError = null,
  initialClienteId,
  volverHref = "/rendiciones",
}: {
  clientes: ClienteOption[];
  formasPago: Fpago[];
  formasError?: string | null;
  cuentasBancarias: CuentaBancariaEmpresa[];
  cuentasError?: string | null;
  tasaDelDia?: TasaCambio | null;
  tasaError?: string | null;
  /** Prefill desde visita (`?cliente_id=`). */
  initialClienteId?: string;
  volverHref?: string;
}) {
  const router = useRouter();
  const captureInputRef = useRef<HTMLInputElement>(null);

  const [buscarCliente, setBuscarCliente] = useState("");
  const [clienteId, setClienteId] = useState(initialClienteId ?? "");
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
  const [borradorMontoUsd, setBorradorMontoUsd] = useState("0.00");
  const [borradorMontoBs, setBorradorMontoBs] = useState("0.00");
  const [borradorTasa, setBorradorTasa] = useState(() =>
    tasaDelDia != null && Number(tasaDelDia.tasa_cambio) > 0
      ? String(Number(tasaDelDia.tasa_cambio))
      : "",
  );
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

  const [pagos, setPagos] = useState<PagoAgregado[]>([]);
  /** Cobranza/Abono por orden_id — default "0". */
  const [cobranzas, setCobranzas] = useState<Record<string, string>>({});

  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  const tasaValor =
    (() => {
      const t = Number(borradorTasa);
      if (Number.isFinite(t) && t > 0) return t;
      if (tasaOficial != null && tasaOficial > 0) return tasaOficial;
      if (tasaDelDia != null && Number(tasaDelDia.tasa_cambio) > 0) {
        return Number(tasaDelDia.tasa_cambio);
      }
      return null;
    })();

  const formaSeleccionada = formasPago.find(
    (f) => f.fpago_id === borradorFpagoId,
  );
  const pideInfoBancaria = formaSeleccionada?.fpago_info === true;
  const borradorEnBs = formaSeleccionada
    ? esFormaPagoEnBs(formaSeleccionada.fpago_concepto)
    : false;

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
      setCobranzas({});
      setSaldoFavor(0);
      setSaldoFavorBs(null);
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
        setCobranzas({});
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
        setBorradorTasa(String(result.data.tasa_oficial_actual));
      }
      // Cobranza/Abono inicia en 0 por orden.
      const inicial: Record<string, string> = {};
      for (const o of result.data.ordenes) {
        inicial[o.id] = "0";
      }
      setCobranzas(inicial);
    });

    return () => {
      cancelled = true;
    };
  }, [clienteId]);

  const ordenes = useMemo((): OrdenAgregada[] => {
    return ordenesDisponibles.flatMap((o) => {
      const monto = Number(cobranzas[o.id] ?? 0);
      if (!Number.isFinite(monto) || monto <= 0) return [];
      const saldoPendienteBs = saldoPendienteBsDeOrden(o, tasaValor);
      const montoBs =
        tasaValor != null
          ? convertirUsdABs(monto, tasaValor)
          : saldoPendienteBs != null && o.saldo_pendiente > 0
            ? (monto / o.saldo_pendiente) * saldoPendienteBs
            : 0;
      return [
        {
          key: o.id,
          orden_id: o.id,
          correlativo: o.correlativo,
          monto_orden: o.monto_total_orden,
          monto_orden_bs: o.monto_total_orden_bs,
          abonos: o.abonos_acumulados,
          saldo_pendiente: o.saldo_pendiente,
          saldo_pendiente_bs: saldoPendienteBs,
          monto_rendicion: monto,
          monto_rendicion_bs: montoBs,
        },
      ];
    });
  }, [ordenesDisponibles, cobranzas, tasaValor]);

  const totalOrdenes = useMemo(
    () => ordenes.reduce((sum, o) => sum + o.monto_rendicion, 0),
    [ordenes],
  );
  const totalRendicion = useMemo(
    () => pagos.reduce((sum, p) => sum + p.monto_usd, 0),
    [pagos],
  );
  const diferencia = totalRendicion - totalOrdenes;
  const faltanteCobrar = Math.max(0, totalOrdenes - totalRendicion);

  // Sincroniza tasa del día en el borrador cuando llega del servidor.
  useEffect(() => {
    if (tasaOficial != null && tasaOficial > 0 && !borradorTasa) {
      setBorradorTasa(String(tasaOficial));
    } else if (
      tasaDelDia != null &&
      Number(tasaDelDia.tasa_cambio) > 0 &&
      !borradorTasa
    ) {
      setBorradorTasa(String(Number(tasaDelDia.tasa_cambio)));
    }
  }, [tasaOficial, tasaDelDia, borradorTasa]);

  // Coloca el faltante a cobrar en Monto $ (flecha del total → campo).
  useEffect(() => {
    const usd = faltanteCobrar;
    setBorradorMontoUsd(usd > 0 ? usd.toFixed(2) : "0.00");
    const tasa =
      Number(borradorTasa) > 0
        ? Number(borradorTasa)
        : tasaValor != null && tasaValor > 0
          ? tasaValor
          : null;
    if (tasa != null && usd > 0) {
      setBorradorMontoBs(convertirUsdABs(usd, tasa).toFixed(2));
    } else {
      setBorradorMontoBs("0.00");
    }
    // Solo al cambiar el faltante (cobranzas / pagos incluidos).
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [faltanteCobrar]);

  function onMontoUsdChange(value: string) {
    setBorradorMontoUsd(value);
    const usd = Number(value);
    if (!Number.isFinite(usd) || usd < 0 || tasaValor == null || tasaValor <= 0) {
      return;
    }
    setBorradorMontoBs(convertirUsdABs(usd, tasaValor).toFixed(2));
  }

  function onMontoBsChange(value: string) {
    setBorradorMontoBs(value);
    const bs = Number(value);
    if (!Number.isFinite(bs) || bs < 0 || tasaValor == null || tasaValor <= 0) {
      return;
    }
    setBorradorMontoUsd(convertirBsAUsd(bs, tasaValor).toFixed(2));
  }

  function onTasaChange(value: string) {
    setBorradorTasa(value);
    const tasa = Number(value);
    const usd = Number(borradorMontoUsd);
    if (!Number.isFinite(tasa) || tasa <= 0) return;
    if (Number.isFinite(usd) && usd >= 0) {
      setBorradorMontoBs(convertirUsdABs(usd, tasa).toFixed(2));
    }
  }

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
    setBorradorMontoUsd("0.00");
    setBorradorMontoBs("0.00");
    setBorradorFechaPago(hoyLocal());
    setBorradorReferencia("");
    setBorradorCuentaId(cuentasBancarias[0]?.id ?? "");
    setBorradorCaptureUrl(null);
    setBorradorPreview(null);
    setPagoSeleccionadoKey(null);
    setPagos([]);
    setCobranzas({});
    setError(null);
    if (captureInputRef.current) captureInputRef.current.value = "";
  }

  function onFormaChange(value: string) {
    setBorradorFpagoId(value);
    setBorradorReferencia("");
  }

  function setCobranzaOrden(ordenId: string, value: string) {
    setCobranzas((prev) => ({ ...prev, [ordenId]: value }));
  }

  function aplicarTotalOrden(orden: OrdenParaRendicion) {
    // Total cobrable ahora = saldo pendiente (no superar lo adeudado).
    setCobranzaOrden(orden.id, Number(orden.saldo_pendiente ?? 0).toFixed(2));
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
    const tasa =
      Number(borradorTasa) > 0
        ? Number(borradorTasa)
        : tasaValor != null && tasaValor > 0
          ? tasaValor
          : null;

    const montoUsd = Number(borradorMontoUsd);
    const montoBs = Number(borradorMontoBs);
    if (borradorEnBs) {
      if (!Number.isFinite(montoBs) || montoBs <= 0) {
        setError("El monto en Bs debe ser mayor a 0.");
        return;
      }
      if (tasa == null || tasa <= 0) {
        setError(
          "Indica la TASA BCV para convertir bolívares. Regístrala en Tasas de cambio si falta.",
        );
        return;
      }
    } else if (!Number.isFinite(montoUsd) || montoUsd <= 0) {
      setError("El monto en $ debe ser mayor a 0.");
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

    const usdFinal = borradorEnBs
      ? convertirBsAUsd(montoBs, tasa as number)
      : montoUsd;
    const bsFinal = borradorEnBs
      ? montoBs
      : tasa != null
        ? convertirUsdABs(usdFinal, tasa)
        : montoBs > 0
          ? montoBs
          : 0;
    const montoIngresado = borradorEnBs ? montoBs : montoUsd;

    const cuenta = cuentasBancarias.find((c) => c.id === borradorCuentaId);

    setPagos((prev) => [
      ...prev,
      {
        key: newKey(),
        fpago_id: formaSeleccionada.fpago_id,
        concepto: formaSeleccionada.fpago_concepto,
        fpago_info: formaSeleccionada.fpago_info,
        en_bs: borradorEnBs,
        monto_ingresado: montoIngresado,
        monto_usd: usdFinal,
        monto_bs: bsFinal,
        tasa_aplicada: tasa,
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
    setBorradorMontoUsd("0.00");
    setBorradorMontoBs("0.00");
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
      setError("Indica Cobranza/Abono mayor a 0 en al menos una orden.");
      return;
    }

    for (const o of ordenes) {
      if (o.monto_rendicion > o.saldo_pendiente + 0.009) {
        setError(
          `Orden #${o.correlativo}: la cobranza no puede superar el saldo pendiente (${formatCurrency(o.saldo_pendiente)}).`,
        );
        return;
      }
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
              Saldo a favor acumulado
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
              className={`w-full rounded-xl border px-3.5 py-2.5 text-sm font-semibold ${
                clienteId && saldoFavor > 0
                  ? "border-emerald-300 bg-emerald-50 text-emerald-900"
                  : "border-white/20 bg-white/95 text-lt-text"
              }`}
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

      {clienteId && !cargandoOrdenes && !ordenesError ? (
        <div
          className={`rounded-2xl border px-4 py-3 text-sm ${
            saldoFavor > 0
              ? "border-emerald-200 bg-emerald-50 text-emerald-950"
              : "border-lt-border bg-lt-surface-muted text-lt-text"
          }`}
        >
          <p className="font-semibold">
            Saldo a favor acumulado a la fecha: {formatCurrency(saldoFavor)}
            {saldoFavorBs != null
              ? ` · ${formatNumber(saldoFavorBs)} Bs`
              : ""}
          </p>
          <p className="mt-0.5 text-xs opacity-80">
            Crédito disponible del cliente (consulta automática al seleccionar).
            Al guardar, el SP puede usarlo y/o generar nuevo saldo si hay
            sobrante.
          </p>
        </div>
      ) : null}

      <section className="overflow-hidden rounded-2xl border border-lt-border bg-lt-surface shadow-sm">
        <div className="border-b border-lt-border-light bg-lt-surface-muted px-4 py-3">
          <h2 className="text-base font-semibold text-lt-text">
            Órdenes por liquidar
          </h2>
          <p className="text-sm text-lt-text-muted">
            Indica Cobranza/Abono por orden (inicia en 0). Usa «Total de la
            orden» para cargar el saldo pendiente.
          </p>
        </div>

        <div className="space-y-4 p-4">
          {cargandoOrdenes ? (
            <p className="text-sm text-lt-text-muted">Cargando órdenes…</p>
          ) : null}
          {ordenesError ? (
            <p className="text-sm text-lt-danger-text">{ordenesError}</p>
          ) : null}
          {!clienteId ? (
            <p className="text-sm text-lt-text-muted">
              Selecciona un cliente para ver sus órdenes.
            </p>
          ) : null}
          {clienteId && !cargandoOrdenes && ordenesDisponibles.length === 0 ? (
            <p className="text-sm text-lt-text-muted">
              No hay órdenes por liquidar para este cliente.
            </p>
          ) : null}

          {ordenesDisponibles.length > 0 ? (
            <div className="grid gap-4 sm:grid-cols-2">
              {ordenesDisponibles.map((o) => {
                const cobranza = cobranzas[o.id] ?? "0";
                const saldoBs = saldoPendienteBsDeOrden(o, tasaValor);
                return (
                  <article
                    key={o.id}
                    className="flex flex-col rounded-2xl border border-lt-border bg-lt-surface p-4 shadow-sm"
                  >
                    <h3 className="text-lg font-bold text-lt-text">
                      Orden: #{o.correlativo}
                    </h3>
                    <dl className="mt-3 space-y-2 text-sm">
                      <div className="flex items-start justify-between gap-3">
                        <dt className="text-lt-text-muted">Fecha despacho:</dt>
                        <dd className="text-right font-medium text-lt-text">
                          {o.fecha_despacho
                            ? formatDateOnly(o.fecha_despacho)
                            : "—"}
                        </dd>
                      </div>
                      <div className="flex items-start justify-between gap-3">
                        <dt className="text-lt-text-muted">Días vencidos:</dt>
                        <dd className="text-right font-medium tabular-nums text-lt-text">
                          {formatNumber(o.dias_vencidos ?? 0)}
                        </dd>
                      </div>
                      <div className="flex items-start justify-between gap-3">
                        <dt className="text-lt-text-muted">Total orden:</dt>
                        <dd className="text-right tabular-nums text-lt-text">
                          {formatCurrency(Number(o.monto_total_orden ?? 0))}
                        </dd>
                      </div>
                      <div className="flex items-start justify-between gap-3">
                        <dt className="text-lt-text-muted">Abonado:</dt>
                        <dd className="text-right tabular-nums text-lt-text">
                          {formatCurrency(Number(o.abonos_acumulados ?? 0))}
                        </dd>
                      </div>
                      <div className="flex items-start justify-between gap-3">
                        <dt className="text-lt-text-muted">Saldo pendiente:</dt>
                        <dd className="text-right tabular-nums font-medium text-lt-text">
                          {formatCurrency(Number(o.saldo_pendiente ?? 0))}
                          {saldoBs != null && saldoBs > 0 ? (
                            <span className="block text-xs font-normal text-lt-text-muted">
                              {formatNumber(saldoBs)} Bs
                            </span>
                          ) : null}
                        </dd>
                      </div>
                    </dl>

                    <div className="mt-4 space-y-2 border-t border-lt-border-light pt-3">
                      <label
                        htmlFor={`cobranza-${o.id}`}
                        className="block text-sm font-medium text-lt-text"
                      >
                        Cobranza / Abono
                      </label>
                      <div className="flex flex-col gap-2 sm:flex-row sm:items-center">
                        <input
                          id={`cobranza-${o.id}`}
                          type="number"
                          min={0}
                          step="0.01"
                          value={cobranza}
                          onChange={(e) =>
                            setCobranzaOrden(o.id, e.target.value)
                          }
                          className="lt-input w-full flex-1 rounded-xl border border-lt-border bg-lt-surface px-3.5 py-2.5 text-sm tabular-nums text-lt-text"
                        />
                        <Button
                          type="button"
                          variant="secondary"
                          className="shrink-0 whitespace-nowrap"
                          onClick={() => aplicarTotalOrden(o)}
                        >
                          Total de la orden
                        </Button>
                      </div>
                    </div>
                  </article>
                );
              })}
            </div>
          ) : null}
        </div>

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
          <Button
            type="button"
            variant="secondary"
            onClick={quitarPagoSeleccionado}
            disabled={!pagoSeleccionadoKey}
          >
            Quitar
          </Button>
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

          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
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
              label="Monto $"
              type="number"
              min={0}
              step="0.01"
              value={borradorMontoUsd}
              onChange={(e) => onMontoUsdChange(e.target.value)}
            />
            <Input
              label="TASA BCV"
              type="number"
              min={0}
              step="0.0001"
              value={borradorTasa}
              onChange={(e) => onTasaChange(e.target.value)}
              placeholder="Tasa del día"
            />
            <Input
              label="Monto Bs"
              type="number"
              min={0}
              step="0.01"
              value={borradorMontoBs}
              onChange={(e) => onMontoBsChange(e.target.value)}
            />
          </div>

          {pideInfoBancaria ? (
            <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
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
              <div className="flex items-end gap-2">
                <Button
                  type="button"
                  variant="secondary"
                  disabled={subiendoCapture}
                  onClick={() => captureInputRef.current?.click()}
                >
                  {subiendoCapture ? "Subiendo…" : "Adjuntar imagen"}
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
                  className="hidden"
                  onChange={(e) => void onCaptureSelected(e.target.files?.[0])}
                />
              </div>
            </div>
          ) : null}

          <div className="flex flex-wrap items-center justify-between gap-2">
            <p className="text-xs text-lt-text-muted">
              {tasaValor != null
                ? `Conversión: $ × ${formatNumber(tasaValor)} = Bs · Bs ÷ ${formatNumber(tasaValor)} = $`
                : "Indica la TASA BCV para convertir entre $ y Bs."}
            </p>
            <Button
              type="button"
              onClick={incluirPago}
              disabled={formasPago.length === 0}
            >
              Incluir otra forma de pago
            </Button>
          </div>
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
                    Incluye opciones de pago con «Incluir otra forma de pago».
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
              Incluye opciones de pago con «Incluir otra forma de pago».
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
            {saldoFavor > 0 ? (
              <p className="text-lt-text-muted">
                Acumulado previo: {formatCurrency(saldoFavor)}
              </p>
            ) : null}
            {diferencia > 0 ? (
              <p className="text-lt-success-text">
                Nuevo saldo a favor (sobrante): {formatCurrency(diferencia)}
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
              onClick={() => router.push(volverHref)}
            >
              Volver
            </Button>
            <Button
              type="button"
              variant="secondary"
              onClick={() => router.push(volverHref)}
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
