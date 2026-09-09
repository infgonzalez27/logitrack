"use client";

import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";
import { Button } from "@/components/ui/button";
import { solicitaAprobarRadarAction } from "@/lib/actions/radar";

export function RadarAprobarButton({
  radarId,
  yaAprobado = false,
}: {
  radarId: string;
  yaAprobado?: boolean;
}) {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  if (yaAprobado) {
    return (
      <p className="lt-alert-success text-sm">
        Radar ya aprobado por gerencia.
      </p>
    );
  }

  function onClick() {
    const ok = window.confirm(
      "¿Aprobar este radar?\nSe acreditarán vacíos retirados, se restituirá inventario no despachado al almacén y las órdenes de vuelta pasarán a anuladas.",
    );
    if (!ok) return;

    setError(null);
    setSuccess(null);
    startTransition(async () => {
      const result = await solicitaAprobarRadarAction(radarId);
      if (!result.ok) {
        setError(result.error);
        return;
      }
      const extra = result.data
        ? ` Contenedores: ${result.data.contenedores_procesados ?? 0}. Órdenes anuladas: ${result.data.ordenes_anuladas ?? 0}.`
        : "";
      setSuccess(
        (result.message ?? "Radar aprobado exitosamente.") + extra,
      );
      router.refresh();
    });
  }

  return (
    <div className="space-y-2">
      <Button type="button" disabled={pending} onClick={onClick}>
        {pending ? "Aprobando…" : "Aprobar radar"}
      </Button>
      {error ? <p className="lt-alert-error text-sm">{error}</p> : null}
      {success ? <p className="lt-alert-success text-sm">{success}</p> : null}
    </div>
  );
}
