"use client";

import { useEffect, useMemo, useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import {
  listarOrdenesParaRendicionAction,
  registrarRendicionCuentasAction,
  uploadCaptureRendicionAction,
  type OrdenParaRendicion,
} from "@/lib/actions/rendiciones";
import { formatCurrency } from "@/lib/format";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { Card } from "@/components/ui/card";
import type { Fpago } from "@/types/database";

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
  monto: number;
  referencia_bancaria: string | null;
  cuenta_bancaria: string | null;
  capture_url: string | null;
  preview_url: string | null;
};

type OrdenAgregada = {
  key: string;
  orden_id: string;
  etiqueta: string;
  monto_orden: number;
  monto_rendicion: number;
};

function newKey() {
  return `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
}

export function NuevaRendicionForm({
  clientes,
  formasPago,
  formasError,
}: {
  clientes: ClienteOption[];
  formasPago: Fpago[];
  formasError?: string | null;
}) {
  const router = useRouter();
  const captureInputRef = useRef<HTMLInputElement>(null);

  const [buscarCliente, setBuscarCliente] = useState("");
  const [clienteId, setClienteId] = useState("");
  const [observaciones, setObservaciones] = useState("");

  const [ordenesDisponibles, setOrdenesDisponibles] = useState<
    OrdenParaRendicion[]
  >([]);
  const [ordenesError, setOrdenesError] = useState<string | null>(null);
  const [cargandoOrdenes, setCargandoOrdenes] = useState(false);

  const [borradorFpagoId, setBorradorFpagoId] = useState("");
  const [borradorMontoForma, setBorradorMontoForma] = useState("0.00");
  const [borradorReferencia, setBorradorReferencia] = useState("");
  const [borradorCuenta, setBorradorCuenta] = useState("");
  const [borradorCaptureUrl, setBorradorCaptureUrl] = useState<string | null>(
    null,
  );
  const [borradorPreview, setBorradorPreview] = useState<string | null>(null);
  const [subiendoCapture, setSubiendoCapture] = useState(false);

  const [borradorOrdenId, setBorradorOrdenId] = useState("");
  const [borradorMontoOrden, setBorradorMontoOrden] = useState("0.00");
  const [borradorRendicion, setBorradorRendicion] = useState("0.00");

  const [pagos, setPagos] = useState<PagoAgregado[]>([]);
  const [ordenes, setOrdenes] = useState<OrdenAgregada[]>([]);

  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  const clienteSeleccionado = clientes.find((c) => c.value === clienteId);
  const formaSeleccionada = formasPago.find(
    (f) => f.fpago_id === borradorFpagoId,
  );
  const pideInfoBancaria = formaSeleccionada?.fpago_info === true;

  const clientesFiltrados = useMemo(() => {
    const q = buscarCliente.trim().toLowerCase();
    if (!q) return clientes;
    return clientes.filter(
      (c) =>
        c.label.toLowerCase().includes(q) ||
        c.codigo.toLowerCase().includes(q),
    );
  }, [clientes, buscarCliente]);

  useEffect(() => {
    if (!clienteId) {
      setOrdenesDisponibles([]);
      setOrdenesError(null);
      setOrdenes([]);
      setBorradorOrdenId("");
      setBorradorMontoOrden("0.00");
      setBorradorRendicion("0.00");
      return;
    }

    let cancelled = false;
    setCargandoOrdenes(true);
    setOrdenesError(null);

    void listarOrdenesParaRendicionAction(clienteId).then((result) => {
      if (cancelled) return;
      setCargandoOrdenes(false);
      if (!result.ok) {
        setOrdenesError(result.error);
        setOrdenesDisponibles([]);
        return;
      }
      setOrdenesDisponibles(result.ordenes);
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
      .filter((o) => !usadas.has(o.id))
      .map((o) => ({
        value: o.id,
        label: `#${o.correlativo} · ${o.factura_origen_numero} · ${formatCurrency(o.total_recaudar)}`,
      }));
  }, [ordenesDisponibles, ordenes]);

  const totalOrdenes = useMemo(
    () => ordenes.reduce((sum, o) => sum + o.monto_orden, 0),
    [ordenes],
  );
  const totalRendicion = useMemo(
    () => pagos.reduce((sum, p) => sum + p.monto, 0),
    [pagos],
  );
  const diferencia = totalRendicion - totalOrdenes;

  function onFormaChange(value: string) {
    setBorradorFpagoId(value);
    setBorradorReferencia("");
    setBorradorCuenta("");
  }

  function onOrdenChange(value: string) {
    setBorradorOrdenId(value);
    const found = ordenesDisponibles.find((o) => o.id === value);
    if (found) {
      const monto = found.total_recaudar.toFixed(2);
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

  function agregarFormaPago() {
    setError(null);
    if (!formaSeleccionada) {
      setError("Selecciona una forma de pago.");
      return;
    }
    const monto = Number(borradorMontoForma);
    if (!Number.isFinite(monto) || monto <= 0) {
      setError("El monto de la forma de pago debe ser mayor a 0.");
      return;
    }
    if (formaSeleccionada.fpago_info) {
      if (!borradorReferencia.trim()) {
        setError("Ingresa la referencia bancaria.");
        return;
      }
      if (!borradorCuenta.trim()) {
        setError("Ingresa la cuenta bancaria.");
        return;
      }
    }

    setPagos((prev) => [
      ...prev,
      {
        key: newKey(),
        fpago_id: formaSeleccionada.fpago_id,
        concepto: formaSeleccionada.fpago_concepto,
        fpago_info: formaSeleccionada.fpago_info,
        monto,
        referencia_bancaria: formaSeleccionada.fpago_info
          ? borradorReferencia.trim()
          : null,
        cuenta_bancaria: formaSeleccionada.fpago_info
          ? borradorCuenta.trim()
          : null,
        capture_url: borradorCaptureUrl,
        preview_url: borradorPreview,
      },
    ]);

    setBorradorFpagoId("");
    setBorradorMontoForma("0.00");
    setBorradorReferencia("");
    setBorradorCuenta("");
    setBorradorCaptureUrl(null);
    setBorradorPreview(null);
    if (captureInputRef.current) captureInputRef.current.value = "";
  }

  function agregarOrden() {
    setError(null);
    if (!borradorOrdenId) {
      setError("Selecciona una orden de distribución.");
      return;
    }
    const found = ordenesDisponibles.find((o) => o.id === borradorOrdenId);
    if (!found) {
      setError("Orden no válida.");
      return;
    }
    const montoRendicion = Number(borradorRendicion);
    if (!Number.isFinite(montoRendicion) || montoRendicion <= 0) {
      setError("El monto de rendición debe ser mayor a 0.");
      return;
    }

    setOrdenes((prev) => [
      ...prev,
      {
        key: newKey(),
        orden_id: found.id,
        etiqueta: `#${found.correlativo} · ${found.factura_origen_numero}`,
        monto_orden: found.total_recaudar,
        monto_rendicion: montoRendicion,
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
      setError("Agrega al menos una forma de pago.");
      return;
    }
    if (!ordenes.length) {
      setError("Agrega al menos una orden.");
      return;
    }

    startTransition(async () => {
      const result = await registrarRendicionCuentasAction({
        cliente_id: clienteId,
        observaciones,
        ordenes: ordenes.map((o) => ({
          orden_id: o.orden_id,
          monto_recaudado: o.monto_rendicion,
        })),
        pagos: pagos.map((p) => ({
          fpago_id: p.fpago_id,
          monto: p.monto,
          fpago_info: p.fpago_info,
          referencia_bancaria: p.referencia_bancaria,
          cuenta_bancaria: p.cuenta_bancaria,
          capture_url: p.capture_url,
        })),
      });

      if (result?.error) {
        setError(result.error);
      }
    });
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-5">
      <Card title="Clientes">
        <div className="space-y-3">
          <Input
            label="Buscar"
            placeholder="Razón social o código…"
            value={buscarCliente}
            onChange={(e) => setBuscarCliente(e.target.value)}
            autoComplete="off"
          />
          <Select
            label="Cliente"
            name="cliente_id"
            required
            placeholder="Selecciona cliente"
            options={clientesFiltrados.map((c) => ({
              value: c.value,
              label: `${c.codigo ? `${c.codigo} — ` : ""}${c.label}`,
            }))}
            value={clienteId}
            onChange={(e) => setClienteId(e.target.value)}
          />
          <Input
            label="Código"
            name="codigo_cliente"
            readOnly
            value={clienteSeleccionado?.codigo ?? ""}
            placeholder="Código del cliente"
          />
          <Input
            label="Observaciones"
            name="observaciones"
            value={observaciones}
            onChange={(e) => setObservaciones(e.target.value)}
          />
        </div>
      </Card>

      <Card title="Forma">
        <div className="space-y-3">
          {formasError ? (
            <p className="text-sm text-lt-danger-text">{formasError}</p>
          ) : null}
          {!formasError && formasPago.length === 0 ? (
            <p className="text-sm text-lt-text-muted">
              No hay formas de pago en el catálogo (`fpagos`).
            </p>
          ) : null}

          <Select
            label="Forma"
            name="forma_pago"
            placeholder="Selecciona forma de pago"
            options={formasPago.map((f) => ({
              value: f.fpago_id,
              label: f.fpago_concepto,
            }))}
            value={borradorFpagoId}
            onChange={(e) => onFormaChange(e.target.value)}
            disabled={formasPago.length === 0}
          />

          <Input
            label="Monto"
            type="number"
            min={0}
            step="0.01"
            value={borradorMontoForma}
            onChange={(e) => setBorradorMontoForma(e.target.value)}
          />

          {pideInfoBancaria ? (
            <>
              <div className="grid gap-3 sm:grid-cols-2">
                <Input
                  label="Referencia bancaria"
                  name="referencia_bancaria"
                  required
                  value={borradorReferencia}
                  onChange={(e) => setBorradorReferencia(e.target.value)}
                  placeholder="Nº de referencia"
                />
                <Input
                  label="Cuenta bancaria"
                  name="cuenta_bancaria"
                  required
                  value={borradorCuenta}
                  onChange={(e) => setBorradorCuenta(e.target.value)}
                  placeholder="Cuenta / banco"
                />
              </div>
              <div className="space-y-1.5">
                <span className="block text-sm font-medium text-lt-text">
                  Capture
                </span>
                <div className="flex items-center gap-2">
                  <Button
                    type="button"
                    variant="secondary"
                    disabled={subiendoCapture}
                    onClick={() => captureInputRef.current?.click()}
                  >
                    {subiendoCapture ? "Subiendo…" : "Capture"}
                  </Button>
                  <div className="flex h-14 w-14 items-center justify-center overflow-hidden rounded-lg border border-lt-border bg-lt-surface-muted">
                    {borradorPreview ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img
                        src={borradorPreview}
                        alt="Vista previa captura"
                        className="h-full w-full object-cover"
                      />
                    ) : (
                      <span className="text-[10px] text-lt-text-muted">
                        img
                      </span>
                    )}
                  </div>
                </div>
                <input
                  ref={captureInputRef}
                  type="file"
                  accept="image/*"
                  capture="environment"
                  className="hidden"
                  onChange={(e) =>
                    void onCaptureSelected(e.target.files?.[0])
                  }
                />
              </div>
            </>
          ) : borradorFpagoId ? (
            <p className="text-xs text-lt-text-muted">
              Efectivo: no se solicita referencia ni cuenta bancaria.
            </p>
          ) : null}

          <Button
            type="button"
            className="w-full"
            onClick={agregarFormaPago}
            disabled={formasPago.length === 0}
          >
            Agregar forma de pago
          </Button>

          {pagos.length > 0 ? (
            <ul className="space-y-2 border-t border-lt-border-light pt-3">
              {pagos.map((p) => (
                <li
                  key={p.key}
                  className="flex items-center justify-between gap-3 rounded-xl border border-lt-border-light px-3 py-2 text-sm"
                >
                  <div className="flex min-w-0 items-center gap-2">
                    {p.preview_url || p.capture_url ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img
                        src={p.preview_url ?? p.capture_url ?? ""}
                        alt=""
                        className="h-9 w-9 rounded object-cover"
                      />
                    ) : null}
                    <span className="truncate">
                      {p.concepto} · {formatCurrency(p.monto)}
                      {p.fpago_info && p.referencia_bancaria
                        ? ` · ref ${p.referencia_bancaria}`
                        : ""}
                    </span>
                  </div>
                  <Button
                    type="button"
                    variant="ghost"
                    onClick={() =>
                      setPagos((prev) =>
                        prev.filter((item) => item.key !== p.key),
                      )
                    }
                  >
                    Quitar
                  </Button>
                </li>
              ))}
            </ul>
          ) : null}
        </div>
      </Card>

      <Card title="Orden de distribución">
        <div className="space-y-3">
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

          <Select
            label="Orden"
            name="orden_id"
            placeholder="Órdenes por liquidar del cliente"
            options={ordenesParaSelect}
            value={borradorOrdenId}
            onChange={(e) => onOrdenChange(e.target.value)}
            disabled={!clienteId || cargandoOrdenes}
          />
          <div className="grid gap-3 sm:grid-cols-2">
            <Input
              label="Monto orden"
              type="number"
              min={0}
              step="0.01"
              readOnly
              value={borradorMontoOrden}
            />
            <Input
              label="Rendición"
              type="number"
              min={0}
              step="0.01"
              value={borradorRendicion}
              onChange={(e) => setBorradorRendicion(e.target.value)}
            />
          </div>
          <Button type="button" className="w-full" onClick={agregarOrden}>
            Agregar orden
          </Button>

          {ordenes.length > 0 ? (
            <ul className="space-y-2 border-t border-lt-border-light pt-3">
              {ordenes.map((o) => (
                <li
                  key={o.key}
                  className="flex items-center justify-between gap-3 rounded-xl border border-lt-border-light px-3 py-2 text-sm"
                >
                  <span className="truncate">
                    {o.etiqueta} · orden {formatCurrency(o.monto_orden)} ·
                    rendición {formatCurrency(o.monto_rendicion)}
                  </span>
                  <Button
                    type="button"
                    variant="ghost"
                    onClick={() =>
                      setOrdenes((prev) =>
                        prev.filter((item) => item.key !== o.key),
                      )
                    }
                  >
                    Quitar
                  </Button>
                </li>
              ))}
            </ul>
          ) : null}
        </div>
      </Card>

      <Card title="Totales">
        <div className="grid gap-3 sm:grid-cols-3">
          <Input
            label="Total en ordenes"
            readOnly
            value={totalOrdenes.toFixed(2)}
          />
          <Input
            label="Total en rendición"
            readOnly
            value={totalRendicion.toFixed(2)}
          />
          <div>
            <Input
              label="Diferencia"
              readOnly
              value={diferencia.toFixed(2)}
            />
            {diferencia > 0 ? (
              <p className="mt-1 text-xs text-lt-success-text">
                Saldo a favor: {formatCurrency(diferencia)}
              </p>
            ) : diferencia < 0 ? (
              <p className="mt-1 text-xs text-lt-danger-text">
                Faltante: {formatCurrency(Math.abs(diferencia))}
              </p>
            ) : null}
          </div>
        </div>
      </Card>

      {error ? <p className="lt-alert-error">{error}</p> : null}

      <div className="flex flex-col gap-3 sm:flex-row">
        <Button
          type="submit"
          disabled={pending || !clienteId || subiendoCapture}
        >
          {pending ? "Registrando…" : "Registrar rendición"}
        </Button>
        <Button
          type="button"
          variant="secondary"
          onClick={() => router.push("/rendiciones")}
        >
          Cancelar
        </Button>
      </div>
    </form>
  );
}
