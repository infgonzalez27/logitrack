"use client";

import { Button } from "@/components/ui/button";
import { DescuentosClientePanel } from "@/components/clientes/descuentos-cliente-panel";

interface ModalDescuentosClienteProps {
  clienteId: string;
  clienteNombre: string;
  isOpen: boolean;
  onClose: () => void;
}

export function ModalDescuentosCliente({
  clienteId,
  clienteNombre,
  isOpen,
  onClose,
}: ModalDescuentosClienteProps) {
  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-black/60 p-4 backdrop-blur-sm">
      <div className="relative w-full max-w-2xl space-y-4 rounded-2xl border border-lt-border bg-lt-surface p-6 shadow-2xl">
        <div className="flex items-start justify-between border-b border-lt-border pb-4">
          <div>
            <h2 className="font-display text-xl font-bold text-lt-text">
              Descuentos por producto
            </h2>
            <p className="mt-1 text-sm text-lt-text-muted">
              Cliente:{" "}
              <strong className="font-semibold text-lt-text">
                {clienteNombre}
              </strong>
            </p>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="rounded-lg p-1.5 text-xl font-bold text-lt-text-muted transition-colors hover:bg-lt-surface-muted hover:text-lt-text"
            title="Cerrar"
          >
            ✕
          </button>
        </div>

        <DescuentosClientePanel clienteId={clienteId} />

        <div className="flex justify-end border-t border-lt-border pt-4">
          <Button type="button" variant="secondary" onClick={onClose}>
            Cerrar
          </Button>
        </div>
      </div>
    </div>
  );
}
