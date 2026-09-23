"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { crearEmpresaConGerenteAction } from "@/lib/actions/empresas";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";

export function NuevaEmpresaForm() {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setPending(true);
    setError(null);

    const form = new FormData(e.currentTarget);
    const result = await crearEmpresaConGerenteAction({
      codigoEmpresa: String(form.get("codigoEmpresa") ?? ""),
      nombreEmpresa: String(form.get("nombreEmpresa") ?? ""),
      supabaseUrl: String(form.get("supabaseUrl") ?? ""),
      supabaseAnonKey: String(form.get("supabaseAnonKey") ?? ""),
      gerente: {
        nombreCompleto: String(form.get("gerenteNombre") ?? ""),
        email: String(form.get("gerenteEmail") ?? ""),
        password: String(form.get("gerentePassword") ?? ""),
        telefono: String(form.get("gerenteTelefono") ?? ""),
      },
    });

    if (!result.ok) {
      setError(result.error);
      setPending(false);
      if (result.empresaCreada) {
        router.refresh();
      }
      return;
    }

    router.push("/admin");
    router.refresh();
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-6">
      <Card
        title="Empresa (tenant)"
        description="Código corto (ej. ramirez → proyecto lt_ramirez). URL y anon key del proyecto Supabase ya creado."
      >
        <div className="space-y-4">
          <Input
            label="Código empresa"
            name="codigoEmpresa"
            required
            placeholder="ramirez"
            autoComplete="off"
            pattern="[a-z0-9_\-]+"
            title="Minúsculas, números, guion o guion bajo"
          />
          <Input
            label="Nombre comercial"
            name="nombreEmpresa"
            required
            placeholder="Comercializadora Ramírez C.A."
          />
          <Input
            label="Supabase URL"
            name="supabaseUrl"
            required
            type="url"
            placeholder="https://xxxx.supabase.co"
          />
          <Input
            label="Supabase anon key"
            name="supabaseAnonKey"
            required
            autoComplete="off"
          />
        </div>
      </Card>

      <Card
        title="Gerente de la empresa"
        description="Se crea en Auth con rol gerente y se vincula a esta empresa en el catálogo central."
      >
        <div className="space-y-4">
          <Input
            label="Nombre completo"
            name="gerenteNombre"
            required
            autoComplete="name"
          />
          <Input
            label="Correo"
            name="gerenteEmail"
            type="email"
            required
            autoComplete="email"
          />
          <Input
            label="Contraseña inicial"
            name="gerentePassword"
            type="password"
            required
            minLength={6}
            autoComplete="new-password"
          />
          <Input
            label="Teléfono (opcional)"
            name="gerenteTelefono"
            type="tel"
            autoComplete="tel"
          />
        </div>
      </Card>

      {error ? <p className="text-sm text-lt-danger-text">{error}</p> : null}

      <div className="flex flex-wrap gap-3">
        <Button type="submit" variant="primary" disabled={pending}>
          {pending ? "Creando…" : "Crear empresa y gerente"}
        </Button>
        <Button href="/admin" variant="secondary" disabled={pending}>
          Cancelar
        </Button>
      </div>
    </form>
  );
}
