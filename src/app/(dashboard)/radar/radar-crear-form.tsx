"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { crearOObtenerRadarAction } from "@/lib/actions/radar";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Select } from "@/components/ui/select";
import type { CamionOrdenOption } from "@/lib/actions/entities";
import type { DespachadorListaRpc } from "@/types/database";

const ESTADO_CAMION_LABEL: Record<string, string> = {
  disponible: "Disponible",
  en_ruta: "En ruta",
  mantenimiento: "Mantenimiento",
};

function estadoCamionLabel(estado: string): string {
  return ESTADO_CAMION_LABEL[estado] ?? estado;
}

function todayLocalDate(): string {
  const d = new Date();
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

export function RadarCrearForm({
  despachadores,
  camiones,
}: {
  despachadores: DespachadorListaRpc[];
  camiones: CamionOrdenOption[];
}) {
  const router = useRouter();
  const [fecha, setFecha] = useState(todayLocalDate);
  const [despachadorId, setDespachadorId] = useState(
    despachadores[0]?.id ?? "",
  );
  const [camionId, setCamionId] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  function validarCamion(id: string): string | null {
    const camion = camiones.find((c) => c.id === id);
    if (!camion) return "Selecciona el camión que realizará el despacho.";
    if (camion.estado === "en_ruta") {
      return `El camión ${camion.placa} está en ruta y no puede asignarse a un nuevo Radar. Selecciona un camión disponible.`;
    }
    if (camion.estado !== "disponible") {
      return `El camión ${camion.placa} no está disponible (${estadoCamionLabel(camion.estado)}). Selecciona otro camión.`;
    }
    return null;
  }

  function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    const camionError = validarCamion(camionId);
    if (camionError) {
      setError(camionError);
      return;
    }
    startTransition(async () => {
      const created = await crearOObtenerRadarAction({
        despachador_id: despachadorId,
        fecha_despacho: fecha,
        camion_id: camionId,
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
          Fecha de entrega + despachador + camión. Se agrupan las órdenes con la fecha y el despachador; el camión que hará el despacho se elige aquí.
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
        <Select
          label="Camión"
          name="camion_id"
          required
          placeholder="Selecciona camión"
          options={camiones.map((c) => ({
            value: c.id,
            label: `${c.placa} - ${estadoCamionLabel(c.estado)}`,
          }))}
          value={camionId}
          onChange={(e) => {
            setCamionId(e.target.value);
            setError(e.target.value ? validarCamion(e.target.value) : null);
          }}
        />
        <div className="sm:col-span-2">
          <Button type="submit" disabled={pending || !despachadorId || !camionId}>
            {pending ? "Creando…" : "Crear radar"}
          </Button>
        </div>
      </form>
      {error ? <p className="lt-alert-error text-sm">{error}</p> : null}
    </Card>
  );
}
