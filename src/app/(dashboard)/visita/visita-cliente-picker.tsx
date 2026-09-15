"use client";

import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Select } from "@/components/ui/select";

type Option = { value: string; label: string };

export function VisitaClientePicker({ clientes }: { clientes: Option[] }) {
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
        <Select
          label="Cliente"
          name="cliente_id"
          required
          placeholder="Busca o selecciona el cliente"
          options={clientes}
          value={clienteId}
          onChange={(e) => setClienteId(e.target.value)}
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
