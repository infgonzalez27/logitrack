"use client";

import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";
import { Button } from "@/components/ui/button";
import { marcarDevolucionRadarAction } from "@/lib/actions/radar";

export function RadarDevolucionButton({
  ordenId,
  detalleIds,
  disabled = false,
}: {
  ordenId: string;
  detalleIds: string[];
  disabled?: boolean;
}) {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  function onClick() {
    if (!detalleIds.length) {
      setError("No hay productos pendientes para devolver.");
      return;
    }
    const ok = window.confirm(
      "Marcar esta parada como Devolución (orden de vuelta).\nSe enviará a Supabase y no se despachará mercancía. ¿Continuar?",
    );
    if (!ok) return;

    setError(null);
    startTransition(async () => {
      const result = await marcarDevolucionRadarAction({
        orden_id: ordenId,
        detalle_ids: detalleIds,
      });
      if (!result.ok) {
        setError(result.error);
        return;
      }
      router.refresh();
    });
  }

  return (
    <div className="space-y-1">
      <Button
        type="button"
        variant="secondary"
        disabled={disabled || pending || !detalleIds.length}
        onClick={onClick}
      >
        {pending ? "Guardando…" : "Devolución"}
      </Button>
      {error ? <p className="text-xs text-lt-danger-text">{error}</p> : null}
    </div>
  );
}
