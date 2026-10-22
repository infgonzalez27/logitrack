"use client";

import { useRouter, usePathname, useSearchParams } from "next/navigation";
import { useTransition } from "react";
import Link from "next/link";
import { Button } from "@/components/ui/button";

export function CobranzasFiltros({
  defaultDesde,
  defaultHasta,
}: {
  defaultDesde?: string;
  defaultHasta?: string;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const [pending, startTransition] = useTransition();

  const hasFilter = Boolean(defaultDesde || defaultHasta);

  return (
    <form
      className="flex flex-wrap items-end gap-3 rounded-2xl border border-lt-border bg-lt-surface p-4 shadow-sm"
      onSubmit={(e) => {
        e.preventDefault();
        const fd = new FormData(e.currentTarget);
        const desde = String(fd.get("desde") || "").trim();
        const hasta = String(fd.get("hasta") || "").trim();
        const next = new URLSearchParams(searchParams.toString());
        if (desde) next.set("desde", desde);
        else next.delete("desde");
        if (hasta) next.set("hasta", hasta);
        else next.delete("hasta");
        const qs = next.toString();
        startTransition(() => {
          router.push(qs ? `${pathname}?${qs}` : pathname);
        });
      }}
    >
      <div className="space-y-1">
        <label htmlFor="filtro-desde" className="block text-xs font-medium text-lt-text-muted">
          Desde
        </label>
        <input
          id="filtro-desde"
          type="date"
          name="desde"
          defaultValue={defaultDesde || ""}
          className="rounded-xl border border-lt-border bg-lt-surface px-3 py-2 text-sm text-lt-text focus:border-lt-primary focus:outline-none"
        />
      </div>

      <div className="space-y-1">
        <label htmlFor="filtro-hasta" className="block text-xs font-medium text-lt-text-muted">
          Hasta
        </label>
        <input
          id="filtro-hasta"
          type="date"
          name="hasta"
          defaultValue={defaultHasta || ""}
          className="rounded-xl border border-lt-border bg-lt-surface px-3 py-2 text-sm text-lt-text focus:border-lt-primary focus:outline-none"
        />
      </div>

      <div className="flex items-center gap-2">
        <Button type="submit" disabled={pending}>
          {pending ? "Consultando…" : "Consultar"}
        </Button>
        {hasFilter ? (
          <Link
            href={pathname}
            className="rounded-xl border border-lt-border bg-lt-surface-muted px-3 py-2 text-sm font-medium text-lt-text-muted hover:text-lt-text"
          >
            Limpiar
          </Link>
        ) : null}
      </div>
    </form>
  );
}
