"use client";

import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { useState } from "react";
import { toDisplayError } from "@/lib/errors";
import { isDevDebug, logAuthDebug, serializeErrorForLog } from "@/lib/debug";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Card } from "@/components/ui/card";

export default function LoginForm() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const redirectTo = searchParams.get("redirect") || "/ordenes";
  const registered = searchParams.get("registered") === "1";
  const showDebug = isDevDebug();

  const [error, setError] = useState<string | null>(null);
  const [debugInfo, setDebugInfo] = useState<Record<string, unknown> | null>(
    null,
  );
  const [pending, setPending] = useState(false);

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setPending(true);
    setError(null);
    setDebugInfo(null);

    const formData = new FormData(e.currentTarget);
    const email = String(formData.get("email") ?? "").trim();
    const password = String(formData.get("password") ?? "");

    logAuthDebug("login:start", {
      email,
      hasPassword: Boolean(password),
      mode: "server-api",
      supabaseUrl: process.env.NEXT_PUBLIC_SUPABASE_URL ?? "MISSING",
      anonKeyLength: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY?.length ?? 0,
    });

    if (!email || !password) {
      setError("Ingresa correo y contraseña.");
      setPending(false);
      return;
    }

    try {
      const res = await fetch("/api/auth/login", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email, password }),
      });

      const payload = (await res.json()) as {
        ok?: boolean;
        error?: string;
        debug?: Record<string, unknown>;
        userId?: string;
      };

      logAuthDebug("login:response", {
        status: res.status,
        ok: payload.ok,
        error: payload.error,
        debug: payload.debug,
      });

      if (!res.ok || payload.error) {
        setError(payload.error ?? "Error al iniciar sesión.");
        if (showDebug) {
          setDebugInfo({
            phase: "api/auth/login",
            httpStatus: res.status,
            debug: payload.debug ?? null,
          });
        }
        setPending(false);
        return;
      }

      router.replace(redirectTo.startsWith("/") ? redirectTo : "/ordenes");
      router.refresh();
    } catch (err) {
      const serialized = serializeErrorForLog(err);
      logAuthDebug("login:exception", serialized);
      setDebugInfo({ phase: "fetch", error: serialized });
      setError(toDisplayError(err));
      setPending(false);
    }
  }

  return (
    <Card title="Iniciar sesión" description="Accede a LogiTrack">
      {registered && (
        <p className="lt-alert-success mb-4">
          Usuario registrado. Inicia sesión con tu correo y contraseña.
        </p>
      )}
      <form onSubmit={handleSubmit} className="space-y-4">
        <Input
          label="Correo electrónico"
          name="email"
          type="email"
          required
          autoComplete="email"
        />
        <Input
          label="Contraseña"
          name="password"
          type="password"
          required
          autoComplete="current-password"
        />
        {error ? <p className="lt-alert-error">{error}</p> : null}
        {showDebug && debugInfo ? (
          <details className="lt-alert-debug">
            <summary className="cursor-pointer font-medium text-lt-text">
              Debug auth (solo desarrollo)
            </summary>
            <pre className="mt-2 overflow-x-auto whitespace-pre-wrap text-lt-text-muted">
              {JSON.stringify(debugInfo, null, 2)}
            </pre>
            <p className="mt-2 text-lt-text-muted">
              Consola F12 · terminal del servidor ·{" "}
              <Link
                href="/api/debug/auth-probe"
                target="_blank"
                className="font-medium text-lt-primary underline"
              >
                /api/debug/auth-probe
              </Link>
            </p>
          </details>
        ) : null}
        <Button type="submit" className="w-full" disabled={pending}>
          {pending ? "Entrando…" : "Entrar"}
        </Button>
      </form>
      {showDebug && (
        <p className="mt-3 text-center text-xs text-lt-text-subtle">
          Logs activos ·{" "}
          <Link
            href="/api/debug/auth-probe"
            target="_blank"
            className="text-lt-primary underline"
          >
            diagnóstico Auth API
          </Link>
        </p>
      )}
      <p className="mt-4 text-center text-sm text-lt-text-muted">
        ¿Necesitas crear un usuario?{" "}
        <Link
          href="/register"
          className="font-medium text-lt-primary underline hover:text-lt-primary-hover"
        >
          Registrar usuario
        </Link>
      </p>
    </Card>
  );
}
