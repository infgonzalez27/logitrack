"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { Button } from "@/components/ui/button";

export function UsuariosBusqueda({
  defaultValue,
  rolValue,
  roles,
}: {
  defaultValue: string;
  rolValue: string;
  roles: { value: string; label: string }[];
}) {
  const router = useRouter();
  const [busqueda, setBusqueda] = useState(defaultValue);
  const [rol, setRol] = useState(rolValue);

  function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const params = new URLSearchParams();
    const q = busqueda.trim();
    if (q) params.set("q", q);
    if (rol) params.set("rol", rol);
    const query = params.toString();
    router.push(query ? `/usuarios?${query}` : "/usuarios");
  }

  return (
    <form
      onSubmit={handleSubmit}
      className="flex flex-col gap-3 sm:flex-row sm:items-end"
    >
      <div className="flex-1">
        <Input
          label="Buscar usuario"
          name="q"
          placeholder="Nombre del perfil…"
          value={busqueda}
          onChange={(e) => setBusqueda(e.target.value)}
        />
      </div>
      <div className="sm:w-56">
        <Select
          label="Filtrar por rol"
          name="rol"
          placeholder="Todos los roles"
          value={rol}
          onChange={(e) => setRol(e.target.value)}
          options={roles}
        />
      </div>
      <Button type="submit" variant="secondary">
        Buscar
      </Button>
    </form>
  );
}
