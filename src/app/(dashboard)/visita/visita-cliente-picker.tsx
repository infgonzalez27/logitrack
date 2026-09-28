"use client";

import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import {
  ClienteCombobox,
  type ClienteComboboxOption,
} from "@/components/clientes/cliente-combobox";

export function VisitaClientePicker({
  clientes,
}: {
  clientes: ClienteComboboxOption[];
}) {
  const router = useRouter();
  const [clienteId, setClienteId] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  function onContinue(e: React.FormEvent) {
    e.preventDefault();
    if (!clienteId.trim()) {
      setError("Selecciona un cliente para continuar.");
      return;
    }
    setError(null);
    startTransition(() => {
      router.push(`/clientes/${clienteId}/visita`);
    });
  }

  return (
    <Card title="Seleccionar cliente">
      <form onSubmit={onContinue} className="space-y-4">
        <ClienteCombobox
          required
          options={clientes}
          value={clienteId}
          onChange={setClienteId}
          disabled={!clientes.length}
        />
        {error ? <p className="lt-alert-error text-sm">{error}</p> : null}
        <Button type="submit" disabled={pending || !clientes.length}>
          {pending ? "Abriendo…" : "Continuar"}
        </Button>
        {!clientes.length ? (
          <p className="text-sm text-lt-text-muted">
            No hay clientes asignados a tu cartera.
          </p>
        ) : null}
      </form>
    </Card>
  );
}
