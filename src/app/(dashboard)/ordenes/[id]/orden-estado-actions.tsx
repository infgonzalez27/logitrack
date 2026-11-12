"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { getOrdenEstadoTransiciones } from "@/lib/auth/orden-permissions";
import type { RolNombre } from "@/lib/auth/roles";
import {
  generarDespachoOrdenAlmacenAction,
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
  const [mostrarModalGenerarDespacho, setMostrarModalGenerarDespacho] =
    useState(false);
  const [notaGenerarDespacho, setNotaGenerarDespacho] = useState("");

  const acciones = getOrdenEstadoTransiciones(rol, estadoActual, { esCreador });
  const esGerencia = rol === "admin" || rol === "gerente";

  // Solo Gerencia/Admin puede anular el despacho (siempre que la orden no esté liquidada)
  const puedeAnularDespacho =
    esGerencia &&
    (estadoActual === "por_liquidar" ||
      estadoActual === "despachada" ||
      estadoActual === "devuelta");

  // Solo Gerencia/Admin puede generar el despacho directo desde almacén cuando está aprobada
  const puedeGenerarDespachoAlmacen =
    esGerencia && estadoActual === "aprobada";

  const mostrarAvisoLiquidada =
    esGerencia && estadoActual === "liquidada";

  if (
    !acciones.length &&
    !puedeAnularDespacho &&
    !puedeGenerarDespachoAlmacen &&
    !mostrarAvisoLiquidada
  ) {
    return null;
  }

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

  function handleAnularDespacho() {
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

  function handleGenerarDespachoAlmacen() {
    setError(null);
    setSuccess(null);
    startTransition(async () => {
      const result = await generarDespachoOrdenAlmacenAction(
        ordenId,
        notaGenerarDespacho.trim() || undefined,
      );
      if (!result.ok) {
        setError(result.error);
        return;
      }
      setSuccess(result.message);
      setMostrarModalGenerarDespacho(false);
      setNotaGenerarDespacho("");
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

        {puedeGenerarDespachoAlmacen && (
          <button
            type="button"
            disabled={pending}
            onClick={() => {
              setError(null);
              setMostrarModalGenerarDespacho(true);
            }}
            className="inline-flex items-center gap-1.5 rounded-xl border border-emerald-400 bg-emerald-50 px-3 py-2 text-sm font-semibold text-emerald-900 shadow-xs hover:bg-emerald-100 disabled:opacity-50"
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              className="h-4 w-4 text-emerald-700"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M5 13l4 4L19 7"
              />
            </svg>
            Generar Despacho (Almacén)
          </button>
        )}

        {puedeAnularDespacho && (
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
            Anular Despacho
          </button>
        )}
      </div>

      {mostrarAvisoLiquidada && (
        <div className="rounded-xl border border-amber-500/30 bg-amber-500/10 p-3 text-xs text-amber-800 dark:text-amber-300">
          <strong>Orden Liquidada:</strong> Para anular el despacho y modificar
          esta orden, primero debes reversar la cobranza asociada en el módulo
          de Cobranzas.
        </div>
      )}

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

      {/* Modal / Diálogo de confirmación para Anular Despacho */}
      {mostrarModalReversar ? (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4 backdrop-blur-xs">
          <div className="w-full max-w-md space-y-4 rounded-2xl border border-lt-border bg-lt-surface p-6 shadow-xl">
            <h3 className="text-lg font-bold text-lt-text">
              ¿Anular Despacho de la Orden?
            </h3>
            <p className="text-sm text-lt-text-muted">
              La mercancía despachada reingresará directamente al{" "}
              <strong>Inventario de Almacén</strong> y la orden pasará a estado{" "}
              <strong>Aprobada</strong> para que puedas editar precios o
              cantidades y volver a generar el despacho (aunque el radar ya esté
              aprobado). Si la orden posee abonos parciales, estos se
              conservarán.
            </p>

            <Input
              label="Motivo de la anulación de despacho (opcional)"
              placeholder="Ej: Ajuste de precio o cantidad autorizado por Gerencia..."
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
                onClick={handleAnularDespacho}
              >
                {pending ? "Anulando despacho..." : "Confirmar anulación"}
              </Button>
            </div>
          </div>
        </div>
      ) : null}

      {/* Modal / Diálogo de confirmación para Generar Despacho desde Almacén */}
      {mostrarModalGenerarDespacho ? (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4 backdrop-blur-xs">
          <div className="w-full max-w-md space-y-4 rounded-2xl border border-lt-border bg-lt-surface p-6 shadow-xl">
            <h3 className="text-lg font-bold text-lt-text">
              ¿Generar Despacho desde Almacén?
            </h3>
            <p className="text-sm text-lt-text-muted">
              Se descontará del <strong>Inventario de Almacén</strong> la
              cantidad indicada en la orden, se asentarán los envases
              correspondientes y la orden pasará a estado{" "}
              <strong>Por Liquidar</strong> (evaluando automáticamente cualquier
              abono previo registrado).
            </p>

            <Input
              label="Observación (opcional)"
              placeholder="Ej: Despacho regenerado tras ajuste de Gerencia..."
              value={notaGenerarDespacho}
              onChange={(e) => setNotaGenerarDespacho(e.target.value)}
              disabled={pending}
            />

            <div className="flex justify-end gap-2 pt-2">
              <Button
                type="button"
                variant="secondary"
                disabled={pending}
                onClick={() => setMostrarModalGenerarDespacho(false)}
              >
                Cancelar
              </Button>
              <Button
                type="button"
                variant="primary"
                disabled={pending}
                onClick={handleGenerarDespachoAlmacen}
              >
                {pending ? "Generando despacho..." : "Generar Despacho"}
              </Button>
            </div>
          </div>
        </div>
      ) : null}

      {/* Modal / Diálogo de confirmación para anulación completa de la orden */}
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
