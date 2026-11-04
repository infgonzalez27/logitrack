"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { registrarMovimientoContenedoresAClientesAction } from "@/lib/actions/contenedores";

export type TipoContenedorInput = {
  id: string;
  label: string;
  saldoActual?: number;
};

export function ModalRetirarContenedores({
  clienteId,
  clienteNombre,
  tipos,
}: {
  clienteId: string;
  clienteNombre: string;
  tipos: TipoContenedorInput[];
}) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [isPending, startTransition] = useTransition();
  const [cantidades, setCantidades] = useState<Record<string, number>>({});
  const [observaciones, setObservaciones] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  const totalRetirar = Object.values(cantidades).reduce(
    (sum, v) => sum + (v || 0),
    0,
  );

  function handleCantidadChange(id: string, val: string) {
    const num = Math.max(0, parseInt(val.replace(/[^0-9]/g, "") || "0", 10));
    setCantidades((prev) => ({ ...prev, [id]: num }));
  }

  function handleOpen() {
    setCantidades({});
    setObservaciones("");
    setError(null);
    setSuccess(null);
    setOpen(true);
  }

  function handleClose() {
    if (isPending) return;
    setOpen(false);
  }

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (totalRetirar <= 0) {
      setError("Indica al menos una cantidad mayor a 0 para retirar.");
      return;
    }

    setError(null);
    startTransition(async () => {
      const movimientos = Object.entries(cantidades)
        .filter(([, cant]) => cant > 0)
        .map(([contenedor_id, cantidad_retirada]) => ({
          contenedor_id,
          cantidad_retirada,
          cantidad_entregada: 0,
        }));

      const res = await registrarMovimientoContenedoresAClientesAction({
        cliente_id: clienteId,
        movimientos,
        observaciones: observaciones.trim() || null,
      });

      if (!res.ok) {
        setError(res.error);
      } else {
        setSuccess(res.message);
        router.refresh();
        setTimeout(() => {
          setOpen(false);
        }, 1200);
      }
    });
  }

  return (
    <>
      <button
        type="button"
        onClick={handleOpen}
        className="lt-no-print inline-flex items-center justify-center rounded-xl bg-lt-primary px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-lt-primary-hover focus:outline-none focus:ring-2 focus:ring-lt-primary focus:ring-offset-2"
      >
        <svg
          xmlns="http://www.w3.org/2000/svg"
          className="mr-1.5 h-4 w-4"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
        >
          <path
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth={2}
            d="M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10M4 7v10l8 4"
          />
        </svg>
        Retirar contenedores (sin orden)
      </button>

      {open && (
        <div className="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-black/50 p-4">
          <div className="relative w-full max-w-lg rounded-2xl bg-lt-surface p-6 shadow-2xl border border-lt-border">
            <h3 className="text-lg font-bold text-lt-text">
              Retiro de contenedores sin orden
            </h3>
            <p className="mt-1 text-sm text-lt-text-muted">
              Cliente:{" "}
              <span className="font-semibold text-lt-text">
                {clienteNombre}
              </span>
            </p>

            {error && (
              <div className="mt-3 rounded-xl bg-red-50 p-3 text-sm text-red-700 border border-red-200">
                {error}
              </div>
            )}

            {success && (
              <div className="mt-3 rounded-xl bg-emerald-50 p-3 text-sm text-emerald-800 border border-emerald-200">
                {success}
              </div>
            )}

            <form onSubmit={handleSubmit} className="mt-4 space-y-4">
              <div className="max-h-60 overflow-y-auto space-y-3 pr-1">
                {tipos.map((t) => {
                  const saldoActual = t.saldoActual ?? 0;
                  const retirar = cantidades[t.id] || 0;
                  const nuevoSaldo = saldoActual - retirar;

                  return (
                    <div
                      key={t.id}
                      className="flex items-center justify-between rounded-xl border border-lt-border p-3 bg-lt-surface-muted"
                    >
                      <div className="flex-1 pr-3">
                        <p className="text-sm font-semibold text-lt-text">
                          {t.label}
                        </p>
                        <p className="text-xs text-lt-text-muted">
                          {saldoActual < 0 ? (
                            <span className="text-emerald-700 font-medium">
                              A favor del cliente: {Math.abs(saldoActual)}
                            </span>
                          ) : saldoActual > 0 ? (
                            `Pendiente actual: ${saldoActual}`
                          ) : (
                            "Saldo actual: 0"
                          )}
                        </p>
                        {retirar > 0 && (
                          <p className="text-xs font-semibold mt-0.5">
                            {nuevoSaldo < 0 ? (
                              <span className="text-emerald-700">
                                Resultante: {Math.abs(nuevoSaldo)} a favor
                              </span>
                            ) : nuevoSaldo === 0 ? (
                              <span className="text-lt-text">
                                Resultante: 0 (al día)
                              </span>
                            ) : (
                              <span className="text-amber-800">
                                Resultante: {nuevoSaldo} pendientes
                              </span>
                            )}
                          </p>
                        )}
                      </div>

                      <div className="w-24">
                        <label className="sr-only">Cantidad a retirar</label>
                        <input
                          type="number"
                          min="0"
                          className="w-full rounded-lg border border-lt-border bg-lt-surface px-3 py-1.5 text-center text-sm font-bold text-lt-text focus:border-lt-primary focus:outline-none"
                          value={cantidades[t.id] ?? 0}
                          onChange={(e) =>
                            handleCantidadChange(t.id, e.target.value)
                          }
                        />
                      </div>
                    </div>
                  );
                })}
              </div>

              <div>
                <label className="block text-xs font-semibold uppercase tracking-wider text-lt-text-subtle mb-1">
                  Observaciones (opcional)
                </label>
                <textarea
                  rows={2}
                  value={observaciones}
                  onChange={(e) => setObservaciones(e.target.value)}
                  placeholder="Detalles del retiro, estado de vacíos, etc."
                  className="w-full rounded-xl border border-lt-border bg-lt-surface p-2.5 text-sm text-lt-text focus:border-lt-primary focus:outline-none"
                />
              </div>

              <div className="flex justify-end gap-3 pt-2">
                <button
                  type="button"
                  onClick={handleClose}
                  disabled={isPending}
                  className="rounded-xl border border-lt-border px-4 py-2 text-sm font-medium text-lt-text hover:bg-lt-surface-muted"
                >
                  Cancelar
                </button>
                <button
                  type="submit"
                  disabled={isPending || totalRetirar <= 0}
                  className="rounded-xl bg-lt-primary px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-lt-primary-hover disabled:opacity-50"
                >
                  {isPending ? "Guardando…" : `Confirmar retiro (${totalRetirar})`}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </>
  );
}

