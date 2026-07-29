"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { registrarMovimientoContenedoresAction } from "@/lib/actions/ordenes";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";

type ContenedorOption = { id: string; codigo: string; nombre: string };

export function RegistrarContenedoresForm({
  ordenId,
  clienteId,
  contenedores,
}: {
  ordenId: string;
  clienteId: string;
  contenedores: ContenedorOption[];
}) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [contenedorId, setContenedorId] = useState("");
  const [entregada, setEntregada] = useState(0);
  const [retirada, setRetirada] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setOk(null);

    startTransition(async () => {
      const result = await registrarMovimientoContenedoresAction({
        cliente_id: clienteId,
        orden_id: ordenId,
        contenedor_id: contenedorId,
        cantidad_entregada: entregada,
        cantidad_retirada: retirada,
      });

      if (result?.error) {
        setError(result.error);
        return;
      }

      setOk("Movimiento de contenedores registrado.");
      setEntregada(0);
      setRetirada(0);
      setContenedorId("");
      router.refresh();
    });
  }

  if (!contenedores.length) {
    return (
      <p className="text-sm text-amber-700">
        No hay tipos de contenedores en catálogo. El administrador de BD debe
        cargar <code>tipos_contenedores</code>.
      </p>
    );
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-3">
      <Select
        label="Tipo de contenedor"
        name="contenedor_id"
        required
        placeholder="Selecciona contenedor"
        options={contenedores.map((c) => ({
          value: c.id,
          label: `${c.codigo} — ${c.nombre}`,
        }))}
        value={contenedorId}
        onChange={(e) => setContenedorId(e.target.value)}
      />
      <div className="grid gap-3 sm:grid-cols-2">
        <Input
          label="Entregados al cliente"
          type="number"
          min={0}
          required
          value={entregada}
          onChange={(e) => setEntregada(Number(e.target.value))}
        />
        <Input
          label="Retirados del cliente"
          type="number"
          min={0}
          required
          value={retirada}
          onChange={(e) => setRetirada(Number(e.target.value))}
        />
      </div>
      {error ? <p className="text-sm text-lt-danger-text">{error}</p> : null}
      {ok ? <p className="text-sm text-lt-success-text">{ok}</p> : null}
      <Button type="submit" variant="secondary" disabled={pending}>
        {pending ? "Guardando…" : "Registrar movimiento"}
      </Button>
    </form>
  );
}
