"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { isDevDebug, logAuthDebug, serializeErrorForLog } from "@/lib/debug";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { Card } from "@/components/ui/card";

export function RegisterForm({
  roles,
}: {
  roles: { value: string; label: string }[];
}) {
  const router = useRouter();
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
    const payload = {
      nombre_completo: String(formData.get("nombre_completo") ?? "").trim(),
      email: String(formData.get("email") ?? "").trim(),
      password: String(formData.get("password") ?? ""),
      telefono: String(formData.get("telefono") ?? "").trim(),
      rol_nombre: String(formData.get("rol_nombre") ?? "").trim(),
    };

    logAuthDebug("register:start", {
      email: payload.email,
      rol: payload.rol_nombre,
      hasPassword: Boolean(payload.password),
    });

    try {
      const res = await fetch("/api/auth/register", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });

      const data = (await res.json()) as {
        ok?: boolean;
        error?: string;
        debug?: Record<string, unknown>;
        userId?: string;
      };

      logAuthDebug("register:response", {
        status: res.status,
        ok: data.ok,
        error: data.error,
        debug: data.debug,
      });

      if (!res.ok || data.error) {
        setError(data.error ?? "Error al registrar.");
        if (showDebug) {
          setDebugInfo({
            phase: "api/auth/register",
            httpStatus: res.status,
            debug: data.debug ?? null,
          });
        }
        setPending(false);
        return;
      }

      router.push("/login?registered=1");
      router.refresh();
    } catch (err) {
      const serialized = serializeErrorForLog(err);
      logAuthDebug("register:exception", serialized);
      setDebugInfo({ phase: "fetch", error: serialized });
      setError("No se pudo conectar con el servidor. Intenta de nuevo.");
      setPending(false);
    }
  }

  return (
    <Card
      title="Registrar usuario"
      description="Crea un usuario en Supabase Auth y su perfil en LogiTrack"
    >
      <form onSubmit={handleSubmit} className="space-y-4">
        <Input label="Nombre completo" name="nombre_completo" required />
        <Input label="Correo electrónico" name="email" type="email" required />
        <Input label="Contraseña" name="password" type="password" required />
        <Input label="Teléfono" name="telefono" />
        <Select
          label="Rol"
          name="rol_nombre"
          required
          placeholder="Selecciona un rol"
          options={roles}
        />
        {error ? <p className="lt-alert-error">{error}</p> : null}
        {showDebug && debugInfo ? (
          <details className="lt-alert-debug">
            <summary className="cursor-pointer font-medium text-lt-text">
              Debug registro (solo desarrollo)
            </summary>
            <pre className="mt-2 overflow-x-auto whitespace-pre-wrap text-lt-text-muted">
              {JSON.stringify(debugInfo, null, 2)}
            </pre>
          </details>
        ) : null}
        <Button type="submit" className="w-full" disabled={pending}>
          {pending ? "Registrando…" : "Registrar"}
        </Button>
      </form>
      <p className="mt-4 text-center text-sm text-lt-text-muted">
        <Link
          href="/login"
          className="font-medium text-lt-primary underline hover:text-lt-primary-hover"
        >
          Volver al inicio de sesión
        </Link>
      </p>
    </Card>
  );
}
