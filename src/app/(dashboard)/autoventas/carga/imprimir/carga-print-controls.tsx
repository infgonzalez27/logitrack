"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";

export function CargaPrintControls() {
  const [aviso, setAviso] = useState<string | null>(null);

  function imprimir() {
    setAviso(null);
    try {
      window.print();
    } catch {
      setAviso(
        "No se pudo abrir el diálogo de impresión. Usa el menú del navegador → Imprimir.",
      );
    }
  }

  return (
    <div className="lt-no-print mb-4 flex flex-col gap-3">
      <div>
        <p className="text-sm font-medium text-lt-text">Comprobante de carga</p>
        <p className="text-sm text-lt-text-muted">
          Toca <strong>Imprimir carga</strong> y elige la impresora térmica en el
          diálogo del sistema.
        </p>
        {aviso ? <p className="mt-2 text-sm text-lt-danger-text">{aviso}</p> : null}
      </div>
      <div className="flex flex-wrap gap-2">
        <Button type="button" variant="primary" onClick={imprimir}>
          Imprimir carga
        </Button>
        <Button type="button" variant="secondary" href="/autoventas">
          Volver a AutoVentas
        </Button>
      </div>
    </div>
  );
}
