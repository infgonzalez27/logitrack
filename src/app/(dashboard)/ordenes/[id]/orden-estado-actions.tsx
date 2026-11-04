"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { getOrdenEstadoTransiciones } from "@/lib/auth/orden-permissions";
import type { RolNombre } from "@/lib/auth/roles";
import {
  reversarEntregaOrdenAction,
  updateOrdenEstadoAction,
} from "@/lib/actions/ordenes";
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
  const [success, setSuccess] = useState<string | null>(null);
  const [mostrarModalAnular, setMostrarModalAnular] = useState(false);
  const [motivoAnular, setMotivoAnular] = useState("");
  const [mostrarModalReversar, setMostrarModalReversar] = useState(false);
  const [motivoReversar, setMotivoReversar] = useState("");

  const acciones = getOrdenEstadoTransiciones(rol, estadoActual, { esCreador });

  // Puede reversar si la entrega ya fue procesada y no está anulada ni en borrador
  const puedeReversar =
    (estadoActual === "por_liquidar" ||
      estadoActual === "despachada" ||
      estadoActual === "devuelta") &&
    (rol === "admin" ||
      rol === "gerente" ||
      rol === "despachador" ||
      rol === "vendedor");

  if (!acciones.length && !puedeReversar) return null;

  function cambiarEstado(estado: OrdenEstado, motivo?: string) {
    setError(null);
    setSuccess(null);
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

  function handleReversarEntrega() {
    setError(null);
    setSuccess(null);
    startTransition(async () => {
      const result = await reversarEntregaOrdenAction(
        ordenId,
        motivoReversar.trim() || undefined,
      );
      if (!result.ok) {
        setError(result.error);
        return;
      }
      setSuccess(result.message);
      setMostrarModalReversar(false);
      setMotivoReversar("");
      router.refresh();
    });
  }

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-2">
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

        {puedeReversar && (
          <button
            type="button"
            disabled={pending}
            onClick={() => {
              setError(null);
              setMostrarModalReversar(true);
            }}
            className="inline-flex items-center gap-1.5 rounded-xl border border-amber-300 bg-amber-50 px-3 py-2 text-sm font-semibold text-amber-900 shadow-xs hover:bg-amber-100 disabled:opacity-50"
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              className="h-4 w-4 text-amber-700"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
              />
            </svg>
            Reversar Entrega
          </button>
        )}
      </div>

      {success && (
        <div className="rounded-xl border border-emerald-500/30 bg-emerald-500/10 p-3 text-sm text-emerald-800 dark:text-emerald-300">
          <strong>Éxito:</strong> {success}
        </div>
      )}

      {error ? (
        <div className="rounded-xl border border-rose-500/30 bg-rose-500/10 p-3 text-sm text-rose-700 dark:text-rose-400">
          <strong>Aviso:</strong> {error}
        </div>
      ) : null}

      {/* Modal / Diálogo de confirmación para reversión de entrega */}
      {mostrarModalReversar ? (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4 backdrop-blur-xs">
          <div className="w-full max-w-md space-y-4 rounded-2xl border border-lt-border bg-lt-surface p-6 shadow-xl">
            <h3 className="text-lg font-bold text-lt-text">
              ¿Reversar Entrega de la Orden?
            </h3>
            <p className="text-sm text-lt-text-muted">
              La orden <strong>NO será anulada</strong>. Regresará a estado{" "}
              <strong>En Tránsito</strong> o <strong>Aprobada</strong> según su
              origen (Radar, Venta Directa o AutoVenta), y la mercancía
              despachada regresará al inventario correspondiente (móvil o
              almacén).
            </p>

            <Input
              label="Motivo de la reversión (opcional)"
              placeholder="Ej: Cliente solicitó reprogramación o ajuste en entrega..."
              value={motivoReversar}
              onChange={(e) => setMotivoReversar(e.target.value)}
              disabled={pending}
            />

            <div className="flex justify-end gap-2 pt-2">
              <Button
                type="button"
                variant="secondary"
                disabled={pending}
                onClick={() => setMostrarModalReversar(false)}
              >
                Cancelar
              </Button>
              <Button
                type="button"
                variant="primary"
                disabled={pending}
                onClick={handleReversarEntrega}
              >
                {pending ? "Reversando..." : "Confirmar reversión"}
              </Button>
            </div>
          </div>
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
