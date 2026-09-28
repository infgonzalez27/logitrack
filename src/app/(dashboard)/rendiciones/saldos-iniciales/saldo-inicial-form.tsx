"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { registrarSaldoInicialAction } from "@/lib/actions/saldos-iniciales";
import {
  ClienteCombobox,
  type ClienteComboboxOption,
} from "@/components/clientes/cliente-combobox";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { fechaHoyCaracas } from "@/lib/dates";
import { formatCurrency } from "@/lib/format";

export function SaldoInicialForm({
  clientes,
}: {
  clientes: ClienteComboboxOption[];
}) {
  const router = useRouter();
  const hoy = fechaHoyCaracas();
  const [clienteId, setClienteId] = useState("");
  const [factura, setFactura] = useState("");
  const [fecha, setFecha] = useState(hoy);
  const [monto, setMonto] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);
    setOk(null);

    const montoNum = Number(monto);
    if (!clienteId) {
      setError("Selecciona el cliente.");
      return;
    }
    if (!Number.isFinite(montoNum) || montoNum <= 0) {
      setError("La deuda en USD debe ser mayor a cero.");
      return;
    }

    setPending(true);
    const res = await registrarSaldoInicialAction({
      cliente_id: clienteId,
      total_recaudar_usd: montoNum,
      factura_origen_numero: factura,
      fecha_factura: fecha,
    });
    setPending(false);

    if (!res.ok) {
      setError(res.error);
      return;
    }

    const cliente = clientes.find((c) => c.value === clienteId)?.label ?? "el cliente";
    setOk(
      `Cargada la factura ${res.data.factura_origen_numero} de ${cliente} por ${formatCurrency(Number(res.data.total_recaudar_usd))} (Nº ${res.data.correlativo}).`,
    );
    setClienteId("");
    setFactura("");
    setMonto("");
    router.refresh();
  }

  return (
    <Card title="Cargar cuenta inicial">
      <form onSubmit={handleSubmit} className="space-y-4">
        <div className="grid gap-4 sm:grid-cols-2">
          <div className="sm:col-span-2">
            <ClienteCombobox
              required
              options={clientes}
              value={clienteId}
              onChange={setClienteId}
            />
          </div>
          <Input
            label="Nº de factura o documento"
            required
            maxLength={30}
            value={factura}
            onChange={(e) => setFactura(e.target.value)}
            placeholder="Ej. FAC-001234"
          />
          <Input
            label="Fecha de la factura"
            type="date"
            required
            max={hoy}
            value={fecha}
            onChange={(e) => setFecha(e.target.value)}
          />
          <Input
            label="Deuda (USD)"
            type="number"
            required
            min={0.01}
            step="0.01"
            inputMode="decimal"
            value={monto}
            onChange={(e) => setMonto(e.target.value)}
            placeholder="0.00"
          />
        </div>
        <p className="text-xs text-lt-text-muted">
          La fecha de la factura define los días vencidos. El monto queda en
          «total a recaudar USD» y no cuenta como venta del mes.
        </p>

        {error ? <p className="lt-alert-error">{error}</p> : null}
        {ok ? (
          <p className="rounded-xl bg-lt-success-bg px-3.5 py-2.5 text-sm text-lt-success-text">
            {ok}
          </p>
        ) : null}

        <Button type="submit" disabled={pending}>
          {pending ? "Guardando…" : "Cargar cuenta inicial"}
        </Button>
      </form>
    </Card>
  );
}
