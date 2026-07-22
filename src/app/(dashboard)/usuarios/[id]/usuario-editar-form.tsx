"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { actualizarPerfilUsuarioAction } from "@/lib/actions/usuarios";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { Button } from "@/components/ui/button";
import type { PerfilUsuarioEditar } from "@/types/database";

export function UsuarioEditarForm({
  perfil,
  roles,
}: {
  perfil: PerfilUsuarioEditar;
  roles: { id: string; label: string }[];
}) {
  const router = useRouter();
  const [nombre, setNombre] = useState(perfil.nombre_completo);
  const [telefono, setTelefono] = useState(perfil.telefono);
  const [rolId, setRolId] = useState(perfil.rol_id);
  const [activo, setActivo] = useState(perfil.activo);
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setPending(true);
    setError(null);

    const result = await actualizarPerfilUsuarioAction({
      id: perfil.id,
      rol_id: rolId,
      nombre_completo: nombre,
      telefono,
      activo,
    });

    if (!result.ok) {
      setError(result.error);
      setPending(false);
      return;
    }

    router.push("/usuarios");
    router.refresh();
  }

  return (
    <Card title="Datos del perfil">
      <form onSubmit={handleSubmit} className="space-y-4">
        <Input
          label="Nombre completo"
          name="nombre_completo"
          required
          value={nombre}
          onChange={(e) => setNombre(e.target.value)}
        />
        <Input
          label="Teléfono"
          name="telefono"
          value={telefono}
          onChange={(e) => setTelefono(e.target.value)}
        />
        <Select
          label="Rol"
          name="rol_id"
          required
          value={rolId}
          onChange={(e) => setRolId(e.target.value)}
          options={roles.map((r) => ({ value: r.id, label: r.label }))}
        />
        <label className="flex items-center gap-2 text-sm text-lt-text">
          <input
            type="checkbox"
            checked={activo}
            onChange={(e) => setActivo(e.target.checked)}
            className="rounded border-lt-border"
          />
          Usuario activo
        </label>

        {error ? <p className="lt-alert-error">{error}</p> : null}

        <div className="flex gap-3">
          <Button type="submit" disabled={pending}>
            {pending ? "Guardando…" : "Guardar cambios"}
          </Button>
          <Button
            type="button"
            variant="secondary"
            onClick={() => router.push("/usuarios")}
          >
            Cancelar
          </Button>
        </div>
      </form>
    </Card>
  );
}
