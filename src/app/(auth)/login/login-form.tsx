"use client";

import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { toDisplayError } from "@/lib/errors";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Card } from "@/components/ui/card";

export default function LoginForm() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const redirectTo = searchParams.get("redirect") || "/ordenes";
  const registered = searchParams.get("registered") === "1";

  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setPending(true);
    setError(null);

    const formData = new FormData(e.currentTarget);
    const email = String(formData.get("email") ?? "").trim();
    const password = String(formData.get("password") ?? "");

    if (!email || !password) {
      setError("Ingresa correo y contraseña.");
      setPending(false);
      return;
    }

    try {
      const supabase = createClient();
      const { data, error: authError } = await supabase.auth.signInWithPassword({
        email,
        password,
      });

      if (authError) {
        setError(toDisplayError(authError));
        setPending(false);
        return;
      }

      if (!data.session) {
        setError("No se pudo crear la sesión. Intenta de nuevo.");
        setPending(false);
        return;
      }

      router.replace(redirectTo.startsWith("/") ? redirectTo : "/ordenes");
      router.refresh();
    } catch (err) {
      setError(toDisplayError(err));
      setPending(false);
    }
  }

  return (
    <Card title="Iniciar sesión" description="Accede a LogiTrack">
      {registered && (
        <p className="mb-4 rounded-lg bg-emerald-50 px-3 py-2 text-sm text-emerald-700">
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
        {error ? (
          <p className="rounded-lg bg-red-50 px-3 py-2 text-sm text-red-700">
            {error}
          </p>
        ) : null}
        <Button type="submit" className="w-full" disabled={pending}>
          {pending ? "Entrando…" : "Entrar"}
        </Button>
      </form>
      <p className="mt-4 text-center text-sm text-zinc-500">
        ¿Necesitas crear un usuario?{" "}
        <Link href="/register" className="font-medium text-zinc-900 underline">
          Registrar usuario
        </Link>
      </p>
    </Card>
  );
}
