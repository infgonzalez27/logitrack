"use client";

import { useState } from "react";
import { cambiarContrasenaUsuarioAction } from "@/lib/actions/usuarios";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";

export function UsuarioContrasenaForm({
  userId,
  email,
}: {
  userId: string;
  email: string | null;
}) {
  const [password, setPassword] = useState("");
  const [passwordConfirmacion, setPasswordConfirmacion] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setPending(true);
    setError(null);
    setSuccess(null);

    const result = await cambiarContrasenaUsuarioAction({
      userId,
      password,
      passwordConfirmacion,
    });

    if (!result.ok) {
      setError(result.error);
      setPending(false);
      return;
    }

    setPassword("");
    setPasswordConfirmacion("");
    setSuccess("Contraseña actualizada. El usuario ya puede iniciar sesión.");
    setPending(false);
  }

  return (
    <Card title="Contraseña de acceso">
      <p className="mb-4 text-sm text-lt-text-muted">
        La contraseña vive en Supabase Auth, no en el perfil. Aquí puedes
        asignar una nueva si el usuario la olvidó.
      </p>
      {email ? (
        <p className="mb-4 text-sm">
          <span className="text-lt-text-muted">Correo de acceso: </span>
          <span className="font-medium text-lt-text">{email}</span>
        </p>
      ) : null}

      <form onSubmit={handleSubmit} className="space-y-4">
        <Input
          label="Nueva contraseña"
          name="password"
          type="password"
          required
          minLength={6}
          autoComplete="new-password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
        />
        <Input
          label="Confirmar contraseña"
          name="password_confirmacion"
          type="password"
          required
          minLength={6}
          autoComplete="new-password"
          value={passwordConfirmacion}
          onChange={(e) => setPasswordConfirmacion(e.target.value)}
        />

        {error ? <p className="lt-alert-error">{error}</p> : null}
        {success ? <p className="lt-alert-success">{success}</p> : null}

        <Button type="submit" variant="secondary" disabled={pending}>
          {pending ? "Guardando…" : "Asignar nueva contraseña"}
        </Button>
      </form>
    </Card>
  );
}
