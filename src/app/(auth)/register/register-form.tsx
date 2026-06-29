"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useActionState, useEffect } from "react";
import { registerUserAction } from "@/lib/actions/auth";
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
  const [state, formAction, pending] = useActionState(registerUserAction, null);

  useEffect(() => {
    if (state?.success) {
      router.push("/login?registered=1");
      router.refresh();
    }
  }, [state?.success, router]);

  return (
    <Card
      title="Registrar usuario"
      description="Crea un usuario en Supabase Auth y su perfil en LogiTrack"
    >
      <form action={formAction} className="space-y-4">
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
        {typeof state?.error === "string" && state.error ? (
          <p className="rounded-lg bg-red-50 px-3 py-2 text-sm text-red-700">
            {state.error}
          </p>
        ) : null}
        <Button type="submit" className="w-full" disabled={pending}>
          {pending ? "Registrando…" : "Registrar"}
        </Button>
      </form>
      <p className="mt-4 text-center text-sm text-zinc-500">
        <Link href="/login" className="font-medium text-zinc-900 underline">
          Volver al inicio de sesión
        </Link>
      </p>
    </Card>
  );
}
