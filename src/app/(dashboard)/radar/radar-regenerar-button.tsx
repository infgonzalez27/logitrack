"use client";

import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";
import { Button } from "@/components/ui/button";
import { solicitaEditarOSincronizarRadarAction } from "@/lib/actions/radar";

export function RadarRegenerarButton({
  radarId,
  yaAprobado = false,
  cargaInventarioMovil = false,
}: {
  radarId: string;
  yaAprobado?: boolean;
  cargaInventarioMovil?: boolean;
}) {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  const blocked = yaAprobado || cargaInventarioMovil;

  function onClick() {
    if (blocked) return;
    const ok = window.confirm(
      "¿Regenerar este radar?\nSe desvincularán y volverán a vincular las órdenes aprobadas del mismo despachador y fecha de despacho.",
    );
    if (!ok) return;

    setError(null);
    setSuccess(null);
    startTransition(async () => {
      const result = await solicitaEditarOSincronizarRadarAction(radarId);
      if (!result.ok) {
        setError(result.error);
        return;
      }
      const d = result.data;
      const extra = d
        ? ` Desvinculadas: ${d.ordenes_desvinculadas ?? 0}. Vinculadas: ${d.ordenes_vinculadas ?? 0}.`
        : "";
      setSuccess(
        (result.message ?? "Radar regenerado exitosamente.") + extra,
      );
      router.refresh();
    });
  }

  return (
    <div className="space-y-1">
      <Button
        type="button"
        variant="secondary"
        className="border-lt-primary text-lt-primary hover:bg-lt-primary-muted"
        disabled={pending || blocked}
        onClick={onClick}
        title={
          yaAprobado
            ? "No se puede regenerar un radar aprobado"
            : cargaInventarioMovil
              ? "Reversa el inventario móvil antes de regenerar"
              : undefined
        }
      >
        {pending ? "Regenerando…" : "Regenerar Radar"}
      </Button>
      {error ? <p className="lt-alert-error text-sm">{error}</p> : null}
      {success ? <p className="lt-alert-success text-sm">{success}</p> : null}
    </div>
  );
}
