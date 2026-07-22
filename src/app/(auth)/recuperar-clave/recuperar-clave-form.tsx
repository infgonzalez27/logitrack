"use client";

import Link from "next/link";
import { useState } from "react";
import { solicitarRecuperacionClaveAction } from "@/lib/actions/usuarios";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Card } from "@/components/ui/card";

export function RecuperarClaveForm() {
  const [email, setEmail] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState(false);
  const [pending, setPending] = useState(false);

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setPending(true);
    setError(null);
    setSuccess(false);

    const result = await solicitarRecuperacionClaveAction(email);

    if (!result.ok) {
      setError(result.error);
      setPending(false);
      return;
    }

    setSuccess(true);
    setPending(false);
  }

  return (
    <Card
      title="Recuperar contraseña"
      description="Te enviaremos un enlace al correo registrado en LogiTrack"
    >
      {success ? (
        <div className="space-y-4">
          <p className="lt-alert-success">
            Si el correo está registrado, recibirás un enlace para crear una
            nueva contraseña. Revisa también la carpeta de spam.
          </p>
          <Link
            href="/login"
            className="text-sm font-medium text-lt-primary underline"
          >
            Volver al inicio de sesión
          </Link>
        </div>
      ) : (
        <form onSubmit={handleSubmit} className="space-y-4">
          <Input
            label="Correo electrónico"
            name="email"
            type="email"
            required
            autoComplete="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
          />
          {error ? <p className="lt-alert-error">{error}</p> : null}
          <Button type="submit" className="w-full" disabled={pending}>
            {pending ? "Enviando…" : "Enviar enlace"}
          </Button>
          <p className="text-center text-sm text-lt-text-muted">
            <Link href="/login" className="text-lt-primary underline">
              Volver al inicio de sesión
            </Link>
          </p>
        </form>
      )}
    </Card>
  );
}
