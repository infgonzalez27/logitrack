import { NextResponse } from "next/server";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { registerUser } from "@/lib/auth/register-user";
import { canRegisterUser } from "@/lib/auth/usuario-permissions";

export async function POST(request: Request) {
  const body = (await request.json()) as {
    email?: string;
    password?: string;
    nombre_completo?: string;
    telefono?: string;
    rol_nombre?: string;
  };
  const rolNombre = String(body.rol_nombre ?? "");

  const actorRol = getRoleNameFromProfile(await getCurrentProfile());
  if (!canRegisterUser(actorRol, rolNombre)) {
    return NextResponse.json(
      {
        error: actorRol
          ? "No tienes permiso para registrar usuarios con ese rol."
          : "Inicia sesión como administrador o gerente para registrar usuarios.",
      },
      { status: actorRol ? 403 : 401 },
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
    { includeDebug: process.env.NODE_ENV === "development" },
  );

  if (!result.ok) {
    return NextResponse.json(
      {
        error: result.error,
        debug: result.debug,
      },
      { status: 400 },
    );
  }

  return NextResponse.json({
    ok: true,
    userId: result.userId,
  });
}
