"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { crearOObtenerRadarAction } from "@/lib/actions/radar";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Select } from "@/components/ui/select";
import type { DespachadorListaRpc } from "@/types/database";

function todayLocalDate(): string {
  const d = new Date();
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

export function RadarCrearForm({
  despachadores,
}: {
  despachadores: DespachadorListaRpc[];
}) {
  const router = useRouter();
  const [fecha, setFecha] = useState(todayLocalDate);
  const [despachadorId, setDespachadorId] = useState(
    despachadores[0]?.id ?? "",
  );
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    startTransition(async () => {
      const created = await crearOObtenerRadarAction({
        despachador_id: despachadorId,
        fecha_despacho: fecha,
      });
      if (!created.ok) {
        setError(created.error);
        return;
      }
      router.push(`/radar/${created.radar.id}`);
      router.refresh();
    });
  }

  return (
    <Card className="space-y-4 p-4">
      <div>
        <h2 className="text-base font-semibold text-lt-text">Nuevo radar</h2>
        <p className="mt-1 text-sm text-lt-text-muted">
          Fecha de entrega + despachador. Se agrupan las órdenes con esas claves.
        </p>
      </div>
      <form onSubmit={onSubmit} className="grid gap-3 sm:grid-cols-2">
        <div className="space-y-1.5">
          <label
            htmlFor="radar_fecha"
            className="block text-sm font-medium text-lt-text"
          >
            Fecha de entrega <span className="text-lt-danger-text">*</span>
          </label>
          <input
            id="radar_fecha"
            type="date"
            required
            value={fecha}
            onChange={(e) => setFecha(e.target.value)}
            className="lt-input w-full"
          />
        </div>
        <Select
          label="Despachador"
          name="despachador_id"
          required
          placeholder="Selecciona despachador"
          options={despachadores.map((d) => ({
            value: d.id,
            label: d.nombre_completo,
          }))}
          value={despachadorId}
          onChange={(e) => setDespachadorId(e.target.value)}
        />
        <div className="sm:col-span-2">
          <Button type="submit" disabled={pending || !despachadorId}>
            {pending ? "Creando…" : "Crear radar"}
          </Button>
        </div>
      </form>
      {error ? <p className="lt-alert-error text-sm">{error}</p> : null}
    </Card>
  );
}
