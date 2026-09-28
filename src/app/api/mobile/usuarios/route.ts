import { NextResponse } from "next/server";
import { getBearerActor } from "@/lib/auth/bearer";
import { registerUser } from "@/lib/auth/register-user";
import { canRegisterUser } from "@/lib/auth/usuario-permissions";

/** Alta de usuario desde la app móvil (misma lógica que /usuarios/registrar). */
export async function POST(request: Request) {
  const auth = await getBearerActor(request);
  if (!auth.ok) {
    return NextResponse.json({ ok: false, error: auth.error }, { status: auth.status });
  }
  const { actor } = auth;

  const body = (await request.json().catch(() => ({}))) as {
    email?: string;
    password?: string;
    nombre_completo?: string;
    telefono?: string;
    rol_nombre?: string;
  };
  const rolNombre = String(body.rol_nombre ?? "").trim();

  if (!canRegisterUser(actor.rol, rolNombre)) {
    return NextResponse.json(
      { ok: false, error: "No tienes permiso para registrar usuarios con ese rol." },
      { status: 403 },
    );
  }

  const result = await registerUser(
    {
      email: String(body.email ?? ""),
      password: String(body.password ?? ""),
      nombre_completo: String(body.nombre_completo ?? ""),
      telefono: String(body.telefono ?? ""),
      rol_nombre: rolNombre,
    },
    {
      tenant: actor.tenant
        ? { empresaId: actor.tenant.empresaId, projectRef: actor.tenant.projectRef }
        : null,
    },
  );

  if (!result.ok) {
    return NextResponse.json({ ok: false, error: result.error }, { status: 400 });
  }
  return NextResponse.json({ ok: true, userId: result.userId });
}
