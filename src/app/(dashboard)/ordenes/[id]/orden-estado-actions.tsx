"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { getOrdenEstadoTransiciones } from "@/lib/auth/orden-permissions";
import type { RolNombre } from "@/lib/auth/roles";
import { updateOrdenEstadoAction } from "@/lib/actions/ordenes";
import type { OrdenEstado } from "@/types/database";
import { Button } from "@/components/ui/button";

export function OrdenEstadoActions({
  ordenId,
  estadoActual,
  rol,
  esCreador,
}: {
  ordenId: string;
  estadoActual: OrdenEstado;
  rol: RolNombre | null;
  esCreador: boolean;
}) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const acciones = getOrdenEstadoTransiciones(rol, estadoActual, { esCreador });

  if (!acciones.length) return null;

  function cambiarEstado(estado: OrdenEstado) {
    setError(null);
    startTransition(async () => {
      const result = await updateOrdenEstadoAction(ordenId, estado);
      if (result?.error) {
        setError(result.error);
        return;
      }
      router.refresh();
    });
  }

  return (
    <div className="space-y-2">
      <div className="flex flex-wrap gap-2">
      {acciones.map((accion) => (
        <Button
          key={accion.next}
          type="button"
          variant={accion.next === "anulada" ? "danger" : "secondary"}
          disabled={pending}
          onClick={() => cambiarEstado(accion.next)}
        >
          {accion.label}
        </Button>
      ))}
      </div>
      {error ? <p className="text-sm text-lt-danger-text">{error}</p> : null}
    </div>
  );
}
