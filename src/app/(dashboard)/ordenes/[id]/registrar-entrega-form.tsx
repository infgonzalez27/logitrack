"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { registrarEntregaDetalleAction } from "@/lib/actions/ordenes";
import { ESTADO_ENTREGA } from "@/lib/constants";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import type { EstadoEntrega } from "@/types/database";

const OPCIONES_ENTREGA = ESTADO_ENTREGA.filter((e) => e.value !== "pendiente");

export function RegistrarEntregaForm({
  detalleId,
  cantidadSolicitada,
  productoNombre,
}: {
  detalleId: string;
  cantidadSolicitada: number;
  productoNombre: string;
}) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [estadoEntrega, setEstadoEntrega] =
    useState<EstadoEntrega>("entregado");
  const [cantidad, setCantidad] = useState(cantidadSolicitada);
  const [motivo, setMotivo] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);

  function onEstadoChange(value: string) {
    const next = value as EstadoEntrega;
    setEstadoEntrega(next);
    if (next === "entregado") {
      setCantidad(cantidadSolicitada);
      setMotivo("");
    } else if (next === "rechazado") {
      setCantidad(0);
    }
  }

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setOk(null);

    startTransition(async () => {
      const result = await registrarEntregaDetalleAction({
        detalle_id: detalleId,
        cantidad_despachada: cantidad,
        estado_entrega: estadoEntrega,
        motivo_rechazo: motivo,
      });

      if (result?.error) {
        setError(result.error);
        return;
      }

      setOk(
        result.orden_estado === "por_liquidar"
          ? "Entrega registrada. La orden quedó por liquidar."
          : "Entrega registrada.",
      );
      router.refresh();
    });
  }

  return (
    <form
      onSubmit={handleSubmit}
      className="mt-3 space-y-3 rounded-xl border border-lt-border-light bg-lt-surface-muted/40 p-3"
    >
      <p className="text-xs text-lt-text-muted">
        Registrar entrega — {productoNombre}
      </p>
      <div className="grid gap-3 sm:grid-cols-2">
        <Select
          label="Estado entrega"
          name={`estado_entrega_${detalleId}`}
          required
          options={OPCIONES_ENTREGA.map((o) => ({
            value: o.value,
            label: o.label,
          }))}
          value={estadoEntrega}
          onChange={(e) => onEstadoChange(e.target.value)}
        />
        <Input
          label="Cantidad despachada"
          type="number"
          min={0}
          max={cantidadSolicitada}
          required
          value={cantidad}
          onChange={(e) => setCantidad(Number(e.target.value))}
        />
      </div>
      {estadoEntrega !== "entregado" ? (
        <Input
          label="Motivo"
          required
          value={motivo}
          onChange={(e) => setMotivo(e.target.value)}
          placeholder="Motivo de parcial o rechazo"
        />
      ) : null}
      {error ? <p className="text-sm text-lt-danger-text">{error}</p> : null}
      {ok ? <p className="text-sm text-lt-success-text">{ok}</p> : null}
      <Button type="submit" variant="secondary" disabled={pending}>
        {pending ? "Guardando…" : "Registrar entrega"}
      </Button>
    </form>
  );
}
