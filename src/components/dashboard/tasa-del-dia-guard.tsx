"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { ensureTasaCambioDelDia } from "@/lib/actions/tasa-cambio";

export function TasaDelDiaGuard({ puedeGestionar }: { puedeGestionar: boolean }) {
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;

    async function run() {
      const result = await ensureTasaCambioDelDia();
      if (cancelled) return;
      setError(result.ok ? null : (result.error ?? "No hay tasa para hoy."));
    }

    void run();
    const onVisible = () => {
      if (document.visibilityState === "visible") void run();
    };
    document.addEventListener("visibilitychange", onVisible);
    return () => {
      cancelled = true;
      document.removeEventListener("visibilitychange", onVisible);
    };
  }, []);

  if (!error) return null;

  return (
    <div className="lt-alert-error mb-4" role="status">
      {error}{" "}
      {puedeGestionar ? (
        <Link href="/tasas-cambio" className="font-medium underline">
          Registrar tasa
        </Link>
      ) : (
        <span>Pide a gerencia registrar la tasa del día.</span>
      )}
    </div>
  );
}
