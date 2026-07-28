"use client";

import { useState } from "react";
import { PageHeader } from "@/components/layout/page-header";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { buildPruebaImpresionTicket } from "@/lib/print/rawbt";

export function PruebaImpresionClient() {
  const [aviso, setAviso] = useState<string | null>(null);
  const preview = buildPruebaImpresionTicket();

  function imprimirNavegador() {
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
    <div className="mx-auto max-w-lg space-y-6">
      <PageHeader
        title="Prueba de impresión"
        description="Imprime un ticket de prueba con el diálogo del navegador."
      />

      <Card title="Ticket de prueba" className="lt-print-allow-break">
        <pre className="lt-ticket overflow-x-auto rounded-xl border border-lt-border-light bg-white p-4 font-mono text-xs leading-relaxed text-black whitespace-pre-wrap">
          {preview}
        </pre>
        {aviso ? (
          <p className="lt-no-print mt-3 text-sm text-lt-danger-text">{aviso}</p>
        ) : null}
        <div className="lt-no-print mt-4 flex flex-col gap-2 sm:flex-row">
          <Button type="button" onClick={imprimirNavegador}>
            Imprimir (navegador)
          </Button>
        </div>
      </Card>
    </div>
  );
}
