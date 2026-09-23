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
  const [codigo, setCodigo] = useState("");

  const proyectoPreview = codigo.trim()
    ? `lt_${codigo.trim().toLowerCase().replace(/^lt_/, "")}`
    : "lt_…";

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setPending(true);
    setError(null);

    const form = new FormData(e.currentTarget);
    const result = await crearEmpresaConGerenteAction({
      codigoEmpresa: String(form.get("codigoEmpresa") ?? ""),
      nombreEmpresa: String(form.get("nombreEmpresa") ?? ""),
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
        title="Empresa"
        description={`Solo datos comerciales. El aprovisionamiento crea el proyecto Supabase ${proyectoPreview} (clon del template LogiTrack) y registra URL/anon key en el catálogo central.`}
      >
        <div className="space-y-4">
          <Input
            label="Código empresa"
            name="codigoEmpresa"
            required
            placeholder="test"
            autoComplete="off"
            pattern="[a-z0-9_\-]+"
            title="Minúsculas, números, guion o guion bajo (sin prefijo lt_)"
            value={codigo}
            onChange={(e) => setCodigo(e.target.value)}
          />
          <p className="text-xs text-lt-text-muted">
            Proyecto Supabase:{" "}
            <span className="font-mono text-lt-text">{proyectoPreview}</span>
          </p>
          <Input
            label="Nombre comercial"
            name="nombreEmpresa"
            required
            placeholder="Comercializadora Ramírez C.A."
          />
        </div>
      </Card>

      <Card
        title="Gerente de la empresa"
        description="Se crea en Auth (Central) con rol gerente y se vincula a esta empresa."
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
          {pending ? "Aprovisionando…" : "Crear empresa y gerente"}
        </Button>
        <Button href="/admin" variant="secondary" disabled={pending}>
          Cancelar
        </Button>
      </div>
    </form>
  );
}
