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
      "¿Aprobar este radar?\nSe acreditarán vacíos entregados y retirados, se restituirá inventario no despachado (móvil → almacén) y las órdenes de vuelta pasarán a anuladas.",
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
      const d = result.data;
      const entregados =
        d?.contenedores_entregados_procesados ?? d?.contenedores_procesados ?? 0;
      const retirados = d?.contenedores_retirados_procesados ?? 0;
      const anuladas = d?.ordenes_anuladas ?? 0;
      const extra = d
        ? ` Entregados: ${entregados}. Retirados: ${retirados}. Órdenes anuladas: ${anuladas}.`
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
