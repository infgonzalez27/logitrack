"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";

export function ProductosBusqueda({ defaultValue }: { defaultValue: string }) {
  const router = useRouter();
  const [busqueda, setBusqueda] = useState(defaultValue);

  function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const q = busqueda.trim();
    router.push(q ? `/productos?q=${encodeURIComponent(q)}` : "/productos");
  }

  return (
    <form
      onSubmit={handleSubmit}
      className="flex flex-col gap-3 sm:flex-row sm:items-end"
    >
      <div className="flex-1">
        <Input
          label="Buscar producto"
          name="q"
          placeholder="Nombre, código de producto o código de barras…"
          value={busqueda}
          onChange={(e) => setBusqueda(e.target.value)}
        />
      </div>
      <Button type="submit" variant="secondary">
        Buscar
      </Button>
    </form>
  );
}
