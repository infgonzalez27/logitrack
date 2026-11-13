"use client";

import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";
import { asignarCamionRadarAction } from "@/lib/actions/radar";
import type { CamionOrdenOption } from "@/lib/actions/entities";
import { Button } from "@/components/ui/button";
import { Select } from "@/components/ui/select";

const ESTADO_LABEL: Record<string, string> = {
  disponible: "Disponible",
  en_ruta: "En ruta",
  mantenimiento: "Mantenimiento",
};

function estadoLabel(estado: string): string {
  return ESTADO_LABEL[estado] ?? estado;
}

/**
 * Camión que realizará el despacho del Radar.
 * Editable solo mientras el radar esté pendiente y sin inventario móvil cargado.
 */
export function RadarCamionSelector({
  radarId,
  camionId,
  camiones,
  editable,
}: {
  radarId: string;
  camionId: string | null;
  camiones: CamionOrdenOption[];
  editable: boolean;
}) {
  const router = useRouter();
  const [seleccion, setSeleccion] = useState(camionId ?? "");
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  const actual = camiones.find((c) => c.id === camionId) ?? null;

  function validar(id: string): string | null {
    const camion = camiones.find((c) => c.id === id);
    if (!camion) return "Selecciona el camión que realizará el despacho.";
    if (camion.id === camionId) return null;
    if (camion.estado === "en_ruta") {
      return `El camión ${camion.placa} está en ruta y no puede asignarse a un nuevo Radar. Selecciona un camión disponible.`;
    }
    if (camion.estado !== "disponible") {
      return `El camión ${camion.placa} no está disponible (${estadoLabel(camion.estado)}). Selecciona otro camión.`;
    }
    return null;
  }

  if (!editable) {
    return (
      <p className="text-sm text-lt-text-muted print:hidden">
        Camión del despacho:{" "}
        <span className="font-medium text-lt-text">
          {actual
            ? `${actual.placa} (${estadoLabel(actual.estado)})`
            : "Sin camión asignado"}
        </span>
      </p>
    );
  }

  function onGuardar() {
    setSuccess(null);
    const msg = validar(seleccion);
    if (msg) {
      setError(msg);
      return;
    }
    setError(null);
    startTransition(async () => {
      const result = await asignarCamionRadarAction({
        radar_id: radarId,
        camion_id: seleccion,
      });
      if (!result.ok) {
        setError(result.error);
        return;
      }
      setSuccess(result.message ?? "Camión asignado al radar.");
      router.refresh();
    });
  }

  return (
    <div className="space-y-2 print:hidden">
      <div className="flex flex-wrap items-end gap-3">
        <div className="min-w-[16rem]">
          <Select
            label="Camión del despacho"
            name="camion_radar"
            placeholder="Selecciona camión"
            options={camiones.map((c) => ({
              value: c.id,
              label: `${c.placa} - ${estadoLabel(c.estado)}`,
            }))}
            value={seleccion}
            onChange={(e) => {
              setSeleccion(e.target.value);
              setSuccess(null);
              setError(e.target.value ? validar(e.target.value) : null);
            }}
          />
        </div>
        <Button
          type="button"
          disabled={pending || !seleccion || seleccion === (camionId ?? "")}
          onClick={onGuardar}
        >
          {pending ? "Guardando…" : "Asignar camión"}
        </Button>
      </div>
      {!camionId ? (
        <p className="text-sm text-amber-700">
          Este radar no tiene camión asignado. Asígnalo antes de cargar el
          camión.
        </p>
      ) : null}
      {error ? <p className="lt-alert-error text-sm">{error}</p> : null}
      {success ? <p className="lt-alert-success text-sm">{success}</p> : null}
    </div>
  );
}
