"use client";

import { useState, useTransition } from "react";
import { sincronizarEmpresaAction } from "@/lib/actions/empresas";
import { Button } from "@/components/ui/button";

export function SincronizarEmpresaButton({ empresaId }: { empresaId: string }) {
  const [pending, startTransition] = useTransition();
  const [mensaje, setMensaje] = useState<{ ok: boolean; texto: string } | null>(
    null,
  );

  return (
    <div className="flex flex-col items-start gap-1">
      <Button
        type="button"
        variant="secondary"
        className="px-3 py-1.5 text-xs"
        disabled={pending}
        onClick={() =>
          startTransition(async () => {
            const result = await sincronizarEmpresaAction(empresaId);
            setMensaje(
              result.ok
                ? { ok: true, texto: `Listo: ${result.usuarios} usuario(s) copiados.` }
                : { ok: false, texto: result.error },
            );
          })
        }
      >
        {pending ? "Sincronizando…" : "Sincronizar"}
      </Button>
      {mensaje ? (
        <span
          className={`max-w-xs text-xs ${mensaje.ok ? "text-lt-text-muted" : "text-lt-danger-text"}`}
        >
          {mensaje.texto}
        </span>
      ) : null}
    </div>
  );
}
