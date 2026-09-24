"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { submitCrearEmpresaAction } from "@/lib/actions/empresas";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";

export function NuevaEmpresaForm() {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [successMsg, setSuccessMsg] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const [codigo, setCodigo] = useState("");

  const proyectoPreview = codigo.trim()
    ? `lt_${codigo.trim().toLowerCase().replace(/^lt_/, "")}`
    : "lt_…";

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setPending(true);
    setError(null);
    setSuccessMsg(null);

    const formData = new FormData(e.currentTarget);
    const response = await submitCrearEmpresaAction(formData);

    if (!response.success) {
      setError(response.error);
      setPending(false);
      if (response.empresaCreada) {
        router.refresh();
      }
      return;
    }

    setSuccessMsg(response.data.mensaje);
    setPending(false);
    router.push("/admin");
    router.refresh();
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-6">
      <Card
        title="Empresa"
        description={`Solo datos comerciales. Se aprovisiona ${proyectoPreview} y se registra en Central; luego se crea el gerente.`}
      >
        <div className="space-y-4">
          <Input
            label="Código empresa"
            name="codigoEmpresa"
            required
            placeholder="adonis"
            autoComplete="off"
            pattern="[a-z0-9_\-]+"
            title="Minúsculas, números, guion o guion bajo (sin prefijo lt_)"
            value={codigo}
            onChange={(ev) => setCodigo(ev.target.value)}
          />
          <p className="text-xs text-lt-text-muted">
            Proyecto Supabase:{" "}
            <span className="font-mono text-lt-text">{proyectoPreview}</span>
          </p>
          <Input
            label="Nombre comercial"
            name="nombreEmpresa"
            required
            placeholder="Comercializadora Adonis C.A."
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
      {successMsg ? (
        <p className="text-sm text-lt-success-text">{successMsg}</p>
      ) : null}

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
