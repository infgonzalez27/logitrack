"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { reversarRendicionAction } from "@/lib/actions/rendiciones";
import { Button } from "@/components/ui/button";

export function ReversarRendicionButton({
  rendicionId,
  cliente,
}: {
  rendicionId: string;
  cliente: string;
}) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);

  function handleClick() {
    if (
      !confirm(
        `¿Reversar la cobranza de ${cliente}?\n\nSus órdenes vuelven a «por liquidar» y se revierte el saldo a favor que haya movido. Esta acción no se puede deshacer.`,
      )
    ) {
      return;
    }
    setError(null);
    startTransition(async () => {
      const result = await reversarRendicionAction(rendicionId);
      if ("error" in result) {
        setError(result.error);
        return;
      }
      router.refresh();
    });
  }

  return (
    <div className="space-y-1">
      <Button
        type="button"
        variant="danger"
        disabled={pending}
        onClick={handleClick}
      >
        {pending ? "Reversando…" : "Reversar"}
      </Button>
      {error ? (
        <p className="max-w-[16rem] text-xs text-lt-danger-text">{error}</p>
      ) : null}
    </div>
  );
}
