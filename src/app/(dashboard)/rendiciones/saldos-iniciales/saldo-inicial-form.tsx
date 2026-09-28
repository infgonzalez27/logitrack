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
import { Select } from "@/components/ui/select";
import { fechaHoyCaracas } from "@/lib/dates";
import { formatCurrency, formatNumber } from "@/lib/format";

export function SaldoInicialForm({
  clientes,
  contenedores,
}: {
  clientes: ClienteComboboxOption[];
  contenedores: { value: string; label: string }[];
}) {
  const router = useRouter();
  const hoy = fechaHoyCaracas();
  const [clienteId, setClienteId] = useState("");
  const [factura, setFactura] = useState("");
  const [fecha, setFecha] = useState(hoy);
  const [monto, setMonto] = useState("");
  const [vacios, setVacios] = useState("");
  const [contenedorId, setContenedorId] = useState(contenedores[0]?.value ?? "");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);

  const montoNum = monto.trim() ? Number(monto) : 0;
  const vaciosNum = vacios.trim() ? Number(vacios) : 0;
  const unSoloContenedor = contenedores.length === 1;

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);
    setOk(null);

    if (!clienteId) {
      setError("Selecciona el cliente.");
      return;
    }
    if (!Number.isFinite(montoNum) || montoNum < 0) {
      setError("La deuda en USD no es válida.");
      return;
    }
    if (!Number.isInteger(vaciosNum) || vaciosNum < 0) {
      setError("Los vacíos deben ser un número entero.");
      return;
    }
    if (montoNum === 0 && vaciosNum === 0) {
      setError("Indica la deuda en USD, los vacíos o ambos.");
      return;
    }
    if (montoNum > 0 && !factura.trim()) {
      setError("Indica el número de factura o documento de la deuda.");
      return;
    }

    setPending(true);
    const res = await registrarSaldoInicialAction({
      cliente_id: clienteId,
      total_recaudar_usd: montoNum,
      factura_origen_numero: factura,
      fecha_factura: fecha,
      cantidad_contenedores: vaciosNum,
      contenedor_id: vaciosNum > 0 ? contenedorId || null : null,
    });
    setPending(false);

    if (!res.ok) {
      setError(res.error);
      return;
    }

    const cliente = clientes.find((c) => c.value === clienteId)?.label ?? "el cliente";
    const partes: string[] = [];
    if (res.data.correlativo) {
      partes.push(
        `deuda de ${formatCurrency(Number(res.data.total_recaudar_usd))} (factura ${res.data.factura_origen_numero}, Nº ${res.data.correlativo})`,
      );
    }
    if (res.data.cantidad_contenedores > 0) {
      partes.push(
        `${formatNumber(res.data.cantidad_contenedores)} vacíos (saldo actual: ${formatNumber(res.data.saldo_contenedores ?? 0)})`,
      );
    }
    setOk(`Cargado para ${cliente}: ${partes.join(" y ")}.`);
    setClienteId("");
    setFactura("");
    setMonto("");
    setVacios("");
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
            required={montoNum > 0}
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
            min={0}
            step="0.01"
            inputMode="decimal"
            value={monto}
            onChange={(e) => setMonto(e.target.value)}
            placeholder="0.00"
          />
          <Input
            label={
              unSoloContenedor
                ? `Vacíos · ${contenedores[0].label}`
                : "Vacíos (contenedores)"
            }
            type="number"
            min={0}
            step="1"
            inputMode="numeric"
            value={vacios}
            onChange={(e) => setVacios(e.target.value)}
            placeholder="0"
          />
          {!unSoloContenedor && contenedores.length > 1 ? (
            <Select
              label="Tipo de contenedor"
              options={contenedores}
              value={contenedorId}
              onChange={(e) => setContenedorId(e.target.value)}
              required={vaciosNum > 0}
            />
          ) : null}
        </div>
        <p className="text-xs text-lt-text-muted">
          Puedes cargar la deuda, los vacíos o ambos. La fecha de la factura
          define los días vencidos. La deuda queda en «total a recaudar USD» y no
          cuenta como venta del mes; los vacíos se suman al saldo de contenedores
          del cliente.
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
