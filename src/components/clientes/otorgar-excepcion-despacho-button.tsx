"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { otorgarExcepcionDespachoGerenciaAction } from "@/lib/actions/clientes";
import { Button } from "@/components/ui/button";

export function OtorgarExcepcionDespachoButton({
  clienteId,
  yaActiva = false,
}: {
  clienteId: string;
  yaActiva?: boolean;
}) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);

  function handleClick() {
    setError(null);
    setOk(null);
    if (
      !window.confirm(
        "¿Otorgar excepción de despacho de un solo uso a este cliente?",
      )
    ) {
      return;
    }

    startTransition(async () => {
      const result = await otorgarExcepcionDespachoGerenciaAction(clienteId);
      if (!result.ok) {
        setError(result.error);
        return;
      }
      setOk("Excepción otorgada. El despachador podrá registrar esta entrega.");
      router.refresh();
    });
  }

  return (
    <div className="space-y-2">
      <Button
        type="button"
        variant="secondary"
        disabled={pending || yaActiva}
        onClick={handleClick}
      >
        {yaActiva
          ? "Excepción ya activa"
          : pending
            ? "Otorgando…"
            : "Autorizar despacho (excepción gerencia)"}
      </Button>
      {error ? <p className="text-sm text-lt-danger-text">{error}</p> : null}
      {ok ? <p className="text-sm text-lt-success-text">{ok}</p> : null}
    </div>
  );
}
