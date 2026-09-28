import { NextResponse } from "next/server";
import { getBearerActor } from "@/lib/auth/bearer";
import { canResetUserPassword } from "@/lib/auth/usuario-permissions";
import { createCentralAdminClient } from "@/lib/supabase/admin";
import { joinOne } from "@/lib/supabase/join";

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Asigna una contraseña nueva a otro usuario (sin pedir la anterior). */
export async function POST(request: Request) {
  const auth = await getBearerActor(request);
  if (!auth.ok) {
    return NextResponse.json({ ok: false, error: auth.error }, { status: auth.status });
  }
  const { actor } = auth;

  const body = (await request.json().catch(() => ({}))) as {
    userId?: string;
    password?: string;
  };
  const userId = String(body.userId ?? "").trim();
  const password = String(body.password ?? "");

  if (!UUID_RE.test(userId)) {
    return NextResponse.json({ ok: false, error: "ID de usuario inválido." }, { status: 400 });
  }
  if (password.length < 6) {
    return NextResponse.json(
      { ok: false, error: "La contraseña debe tener al menos 6 caracteres." },
      { status: 400 },
    );
  }

  // Buscar el perfil en la BD del actor limita el cambio a usuarios de su empresa.
  const { data: perfil } = await actor.data
    .from("perfiles_usuario")
    .select("roles(nombre)")
    .eq("id", userId)
    .maybeSingle();
  if (!perfil) {
    return NextResponse.json({ ok: false, error: "Usuario no encontrado." }, { status: 404 });
  }
  const targetRol =
    joinOne(perfil.roles as { nombre?: string } | { nombre?: string }[] | null)?.nombre ??
    null;

  if (!canResetUserPassword(actor.rol, targetRol)) {
    return NextResponse.json(
      { ok: false, error: "No tienes permiso para cambiar la contraseña de este usuario." },
      { status: 403 },
    );
  }

  const { error } = await createCentralAdminClient().auth.admin.updateUserById(userId, {
    password,
  });
  if (error) {
    return NextResponse.json({ ok: false, error: error.message }, { status: 400 });
  }
  return NextResponse.json({ ok: true });
}
