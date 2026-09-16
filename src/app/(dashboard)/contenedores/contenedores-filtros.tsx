"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { Button } from "@/components/ui/button";

export function ContenedoresFiltros({
  defaultQ,
  defaultContenedorId,
  defaultSoloConSaldo,
  tipos,
}: {
  defaultQ: string;
  defaultContenedorId: string;
  defaultSoloConSaldo: boolean;
  tipos: { value: string; label: string }[];
}) {
  const router = useRouter();
  const [q, setQ] = useState(defaultQ);
  const [contenedorId, setContenedorId] = useState(defaultContenedorId);
  const [soloConSaldo, setSoloConSaldo] = useState(defaultSoloConSaldo);

  function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const params = new URLSearchParams();
    const query = q.trim();
    if (query) params.set("q", query);
    if (contenedorId) params.set("contenedor", contenedorId);
    if (!soloConSaldo) params.set("todos", "1");
    const qs = params.toString();
    router.push(qs ? `/contenedores?${qs}` : "/contenedores");
  }

  return (
    <form
      onSubmit={handleSubmit}
      className="lt-no-print flex flex-col gap-3 sm:flex-row sm:flex-wrap sm:items-end"
    >
      <div className="min-w-[12rem] flex-1">
        <Input
          label="Buscar cliente"
          name="q"
          placeholder="Razón social o RIF…"
          value={q}
          onChange={(e) => setQ(e.target.value)}
        />
      </div>
      <div className="sm:w-64">
        <Select
          label="Tipo de contenedor"
          name="contenedor"
          placeholder="Todos"
          value={contenedorId}
          onChange={(e) => setContenedorId(e.target.value)}
          options={tipos}
        />
      </div>
      <label className="flex cursor-pointer items-center gap-2 pb-2 text-sm text-lt-text">
        <input
          type="checkbox"
          className="h-4 w-4 rounded border-lt-border text-lt-primary"
          checked={soloConSaldo}
          onChange={(e) => setSoloConSaldo(e.target.checked)}
        />
        Solo con saldo ≠ 0
      </label>
      <Button type="submit" variant="secondary">
        Buscar
      </Button>
    </form>
  );
}
