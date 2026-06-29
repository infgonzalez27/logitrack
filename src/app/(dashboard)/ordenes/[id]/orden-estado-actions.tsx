"use client";

import { useTransition } from "react";
import { useRouter } from "next/navigation";
import { updateOrdenEstadoAction } from "@/lib/actions/ordenes";
import type { OrdenEstado } from "@/types/database";
import { Button } from "@/components/ui/button";

const TRANSICIONES: Partial<Record<OrdenEstado, { next: OrdenEstado; label: string }[]>> = {
  borrador: [
    { next: "lista_para_carga", label: "Marcar lista para carga" },
    { next: "anulada", label: "Anular" },
  ],
  lista_para_carga: [
    { next: "en_transito", label: "Despachar (en tránsito)" },
    { next: "borrador", label: "Volver a borrador" },
    { next: "anulada", label: "Anular" },
  ],
  en_transito: [
    { next: "liquidada", label: "Liquidar" },
  ],
};

export function OrdenEstadoActions({
  ordenId,
  estadoActual,
}: {
  ordenId: string;
  estadoActual: OrdenEstado;
}) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const acciones = TRANSICIONES[estadoActual] ?? [];

  if (!acciones.length) return null;

  function cambiarEstado(estado: OrdenEstado) {
    startTransition(async () => {
      const result = await updateOrdenEstadoAction(ordenId, estado);
      if (!result?.error) router.refresh();
    });
  }

  return (
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
  );
}
