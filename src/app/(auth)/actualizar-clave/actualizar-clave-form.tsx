"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Card } from "@/components/ui/card";

export function ActualizarClaveForm() {
  const [ready, setReady] = useState(false);
  const [hasSession, setHasSession] = useState(false);
  const [password, setPassword] = useState("");
  const [passwordConfirmacion, setPasswordConfirmacion] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState(false);
  const [pending, setPending] = useState(false);

  useEffect(() => {
    const supabase = createClient();

    async function init() {
      const hash = window.location.hash.replace(/^#/, "");
      const params = new URLSearchParams(hash);
      const accessToken = params.get("access_token");
      const refreshToken = params.get("refresh_token");

      if (accessToken && refreshToken) {
        const { error: sessionError } = await supabase.auth.setSession({
          access_token: accessToken,
          refresh_token: refreshToken,
        });

        if (sessionError) {
          setError(sessionError.message);
          setReady(true);
          return;
        }

        window.history.replaceState(null, "", window.location.pathname);
        setHasSession(true);
        setReady(true);
        return;
      }

      const { data } = await supabase.auth.getSession();
      setHasSession(Boolean(data.session));
      setReady(true);
    }

    void init();
  }, []);

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setPending(true);
    setError(null);

    if (password !== passwordConfirmacion) {
      setError("Las contraseñas no coinciden.");
      setPending(false);
      return;
    }

    if (password.length < 6) {
      setError("La contraseña debe tener al menos 6 caracteres.");
      setPending(false);
      return;
    }

    const supabase = createClient();
    const { error: updateError } = await supabase.auth.updateUser({
      password,
    });

    if (updateError) {
      setError(updateError.message);
      setPending(false);
      return;
    }

    await supabase.auth.signOut();
    setSuccess(true);
    setPending(false);
  }

  return (
    <Card title="Nueva contraseña" description="Define tu clave de acceso a LogiTrack">
      {!ready ? (
        <p className="text-sm text-lt-text-muted">Validando enlace…</p>
      ) : success ? (
        <div className="space-y-4">
          <p className="lt-alert-success">
            Contraseña actualizada. Ya puedes iniciar sesión.
          </p>
          <Button href="/login" className="w-full">
            Ir al inicio de sesión
          </Button>
        </div>
      ) : !hasSession ? (
        <div className="space-y-4">
          <p className="lt-alert-error">
            El enlace no es válido o ya expiró. Solicita uno nuevo.
          </p>
          <Link
            href="/recuperar-clave"
            className="text-sm font-medium text-lt-primary underline"
          >
            Recuperar contraseña
          </Link>
        </div>
      ) : (
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
          <Button type="submit" className="w-full" disabled={pending}>
            {pending ? "Guardando…" : "Guardar contraseña"}
          </Button>
        </form>
      )}
    </Card>
  );
}
