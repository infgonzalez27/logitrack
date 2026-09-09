"use client";

import { useRouter } from "next/navigation";
import { useTransition } from "react";
import { Button } from "@/components/ui/button";

export function RadarFiltroFechas({
  fechaInicial,
  fechaLimite,
}: {
  fechaInicial: string;
  fechaLimite: string;
}) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();

  function onSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const fd = new FormData(e.currentTarget);
    const fi = String(fd.get("fecha_inicial") ?? "").slice(0, 10);
    const fl = String(fd.get("fecha_limite") ?? "").slice(0, 10);
    const params = new URLSearchParams();
    if (fi) params.set("fecha_inicial", fi);
    if (fl) params.set("fecha_limite", fl);
    startTransition(() => {
      router.push(`/radar?${params.toString()}`);
    });
  }

  return (
    <form
      onSubmit={onSubmit}
      className="flex flex-wrap items-end gap-3 rounded-2xl border border-lt-border bg-lt-surface p-4"
    >
      <label className="block min-w-[10rem] flex-1 text-sm">
        <span className="mb-1 block text-lt-text-muted">Fecha inicial</span>
        <input
          type="date"
          name="fecha_inicial"
          defaultValue={fechaInicial}
          className="lt-input w-full"
          required
        />
      </label>
      <label className="block min-w-[10rem] flex-1 text-sm">
        <span className="mb-1 block text-lt-text-muted">Fecha límite</span>
        <input
          type="date"
          name="fecha_limite"
          defaultValue={fechaLimite}
          className="lt-input w-full"
          required
        />
      </label>
      <Button type="submit" disabled={pending} className="shrink-0">
        {pending ? "Buscando…" : "Buscar"}
      </Button>
    </form>
  );
}
