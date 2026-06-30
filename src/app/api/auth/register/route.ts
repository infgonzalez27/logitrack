import { NextResponse } from "next/server";
import { registerUser } from "@/lib/auth/register-user";

export async function POST(request: Request) {
  const body = (await request.json()) as {
    email?: string;
    password?: string;
    nombre_completo?: string;
    telefono?: string;
    rol_nombre?: string;
  };

  const result = await registerUser(
    {
      email: String(body.email ?? ""),
      password: String(body.password ?? ""),
      nombre_completo: String(body.nombre_completo ?? ""),
      telefono: String(body.telefono ?? ""),
      rol_nombre: String(body.rol_nombre ?? ""),
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
