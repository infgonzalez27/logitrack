"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { aprobarRendicionAction } from "@/lib/actions/rendiciones";
import { Button } from "@/components/ui/button";

export function AprobarRendicionButton({ rendicionId }: { rendicionId: string }) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);

  function handleClick() {
    setError(null);
    startTransition(async () => {
      const result = await aprobarRendicionAction(rendicionId);
      if (result?.error) {
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
        variant="secondary"
        disabled={pending}
        onClick={handleClick}
      >
        {pending ? "Aprobando…" : "Aprobar"}
      </Button>
      {error ? <p className="text-xs text-lt-danger-text">{error}</p> : null}
    </div>
  );
}
