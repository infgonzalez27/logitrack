"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";

/**
 * Impresión del navegador. Solo al tocar el botón (gesto del usuario):
 * en Android el diálogo completo (Wi‑Fi / red) no suele aparecer si print()
 * se dispara solo al cargar la página.
 */
export function OrdenPrintControls({ volverHref }: { volverHref: string }) {
  const router = useRouter();
  const [aviso, setAviso] = useState<string | null>(null);

  function imprimir() {
    setAviso(null);
    try {
      window.print();
    } catch {
      setAviso(
        "No se pudo abrir el diálogo de impresión. Usá el menú del navegador → Imprimir.",
      );
    }
  }

  return (
    <div className="lt-no-print mb-4 flex flex-col gap-3">
      <div>
        <p className="text-sm font-medium text-lt-text">Ticket de impresión</p>
        <p className="text-sm text-lt-text-muted">
          Tocá <strong>Imprimir</strong> y elegí la impresora Wi‑Fi / red en el
          diálogo del sistema.
        </p>
        {aviso ? <p className="mt-2 text-sm text-lt-danger-text">{aviso}</p> : null}
      </div>
      <div className="flex flex-wrap gap-2">
        <Button type="button" variant="primary" onClick={imprimir}>
          Imprimir
        </Button>
        <Button
          type="button"
          variant="secondary"
          onClick={() => router.push(volverHref)}
        >
          Volver a la orden
        </Button>
      </div>
    </div>
  );
}
