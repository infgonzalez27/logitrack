"use client";

import { useRouter, usePathname, useSearchParams } from "next/navigation";
import { useTransition } from "react";
import { Button } from "@/components/ui/button";

export function ReporteFormasPagoFiltros({
  defaultDesde,
  defaultHasta,
  defaultSoloBancarios,
}: {
  defaultDesde: string;
  defaultHasta: string;
  defaultSoloBancarios: boolean;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const [pending, startTransition] = useTransition();

  return (
    <form
      className="flex flex-wrap items-end gap-3"
      onSubmit={(e) => {
        e.preventDefault();
        const fd = new FormData(e.currentTarget);
        const desde = String(fd.get("desde") || "").trim();
        const hasta = String(fd.get("hasta") || "").trim();
        const bancarios = fd.get("bancarios") === "on";
        const next = new URLSearchParams(searchParams.toString());
        if (desde) next.set("desde", desde);
        else next.delete("desde");
        if (hasta) next.set("hasta", hasta);
        else next.delete("hasta");
        if (bancarios) next.set("bancarios", "1");
        else next.delete("bancarios");
        const qs = next.toString();
        startTransition(() => {
          router.push(qs ? `${pathname}?${qs}` : pathname);
        });
      }}
    >
      <div className="space-y-1">
        <label className="block text-xs font-medium text-lt-text-muted">
          Desde
        </label>
        <input
          type="date"
          name="desde"
          defaultValue={defaultDesde}
          className="rounded-xl border border-lt-border bg-lt-surface px-3 py-2 text-sm text-lt-text"
        />
      </div>
      <div className="space-y-1">
        <label className="block text-xs font-medium text-lt-text-muted">
          Hasta
        </label>
        <input
          type="date"
          name="hasta"
          defaultValue={defaultHasta}
          className="rounded-xl border border-lt-border bg-lt-surface px-3 py-2 text-sm text-lt-text"
        />
      </div>
      <label className="mb-2 flex items-center gap-2 text-sm text-lt-text">
        <input
          type="checkbox"
          name="bancarios"
          defaultChecked={defaultSoloBancarios}
          className="rounded border-lt-border"
        />
        Solo bancarios
      </label>
      <Button type="submit" disabled={pending}>
        {pending ? "Consultando…" : "Consultar"}
      </Button>
    </form>
  );
}
