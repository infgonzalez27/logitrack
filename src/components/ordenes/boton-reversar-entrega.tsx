"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { reversarEntregaOrdenAction } from "@/lib/actions/ordenes";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";

export function BotonReversarEntrega({
  ordenId,
  correlativo,
  className,
}: {
  ordenId: string;
  correlativo?: number | string;
  className?: string;
}) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [motivo, setMotivo] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  function handleReversar() {
    setError(null);
    startTransition(async () => {
      const res = await reversarEntregaOrdenAction(
        ordenId,
        motivo.trim() || undefined,
      );
      if (!res.ok) {
        setError(res.error);
        return;
      }
      setOpen(false);
      setMotivo("");
      router.refresh();
    });
  }

  return (
    <>
      <button
        type="button"
        onClick={() => {
          setError(null);
          setOpen(true);
        }}
        className={
          className ||
          "inline-flex items-center gap-1.5 rounded-xl border border-amber-300 bg-amber-50 px-3 py-2 text-xs font-semibold text-amber-900 shadow-xs hover:bg-amber-100"
        }
      >
        <svg
          xmlns="http://www.w3.org/2000/svg"
          className="h-3.5 w-3.5 text-amber-700"
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

      {open && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4 backdrop-blur-xs">
          <div className="w-full max-w-md space-y-4 rounded-2xl border border-lt-border bg-lt-surface p-6 shadow-xl">
            <h3 className="text-lg font-bold text-lt-text">
              ¿Reversar Entrega {correlativo ? `de la Orden #${correlativo}` : ""}?
            </h3>
            <p className="text-sm text-lt-text-muted">
              La orden <strong>NO será anulada</strong>. Regresará a estado{" "}
              <strong>En Tránsito</strong> o <strong>Aprobada</strong> según su
              origen, y la mercancía despachada se reincorporará automáticamente al
              inventario correspondiente.
            </p>

            {error && (
              <div className="rounded-xl border border-rose-500/30 bg-rose-500/10 p-3 text-xs text-rose-700">
                <strong>Error:</strong> {error}
              </div>
            )}

            <Input
              label="Motivo de la reversión (opcional)"
              placeholder="Ej: Ajuste en despacho o error de cantidades..."
              value={motivo}
              onChange={(e) => setMotivo(e.target.value)}
              disabled={pending}
            />

            <div className="flex justify-end gap-2 pt-2">
              <Button
                type="button"
                variant="secondary"
                disabled={pending}
                onClick={() => setOpen(false)}
              >
                Cancelar
              </Button>
              <Button
                type="button"
                variant="primary"
                disabled={pending}
                onClick={handleReversar}
              >
                {pending ? "Reversando..." : "Confirmar reversión"}
              </Button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}

