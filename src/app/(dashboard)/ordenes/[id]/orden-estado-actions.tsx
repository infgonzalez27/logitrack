"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { getOrdenEstadoTransiciones } from "@/lib/auth/orden-permissions";
import type { RolNombre } from "@/lib/auth/roles";
import { updateOrdenEstadoAction } from "@/lib/actions/ordenes";
import type { OrdenEstado } from "@/types/database";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";

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
  const [mostrarModalAnular, setMostrarModalAnular] = useState(false);
  const [motivoAnular, setMotivoAnular] = useState("");

  const acciones = getOrdenEstadoTransiciones(rol, estadoActual, { esCreador });

  if (!acciones.length) return null;

  function cambiarEstado(estado: OrdenEstado, motivo?: string) {
    setError(null);
    startTransition(async () => {
      const result = await updateOrdenEstadoAction(ordenId, estado, motivo);
      if (result?.error) {
        setError(result.error);
        return;
      }
      setMostrarModalAnular(false);
      setMotivoAnular("");
      router.refresh();
    });
  }

  function handleActionClick(accion: { next: OrdenEstado; label: string }) {
    if (accion.next === "anulada") {
      setMostrarModalAnular(true);
    } else {
      cambiarEstado(accion.next);
    }
  }

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap gap-2">
        {acciones.map((accion) => (
          <Button
            key={accion.next}
            type="button"
            variant={accion.next === "anulada" ? "danger" : "secondary"}
            disabled={pending}
            onClick={() => handleActionClick(accion)}
          >
            {accion.label}
          </Button>
        ))}
      </div>

      {error ? (
        <div className="rounded-xl border border-rose-500/30 bg-rose-500/10 p-3 text-sm text-rose-700 dark:text-rose-400">
          <strong>Aviso:</strong> {error}
        </div>
      ) : null}

      {/* Modal / Diálogo de confirmación para anulación */}
      {mostrarModalAnular ? (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4 backdrop-blur-xs">
          <div className="w-full max-w-md space-y-4 rounded-2xl border border-lt-border bg-lt-surface p-6 shadow-xl">
            <h3 className="text-lg font-bold text-lt-text">
              ¿Anular Orden de Distribución?
            </h3>
            <p className="text-sm text-lt-text-muted">
              Esta acción revertirá transaccionalmente los movimientos de
              inventario (móvil o almacén) y los saldos de envases dejados al
              cliente. Si la orden ya posee rendición de cuentas activa, la
              operación será rechazada.
            </p>

            <Input
              label="Motivo de anulación (opcional)"
              placeholder="Ej: Cliente canceló el pedido por error en cantidades..."
              value={motivoAnular}
              onChange={(e) => setMotivoAnular(e.target.value)}
              disabled={pending}
            />

            <div className="flex justify-end gap-2 pt-2">
              <Button
                type="button"
                variant="secondary"
                disabled={pending}
                onClick={() => setMostrarModalAnular(false)}
              >
                Cancelar
              </Button>
              <Button
                type="button"
                variant="danger"
                disabled={pending}
                onClick={() => cambiarEstado("anulada", motivoAnular)}
              >
                {pending ? "Anulando..." : "Confirmar anulación"}
              </Button>
            </div>
          </div>
        </div>
      ) : null}
    </div>
  );
}

