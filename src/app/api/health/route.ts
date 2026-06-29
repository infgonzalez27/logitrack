import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { toDisplayError } from "@/lib/errors";

export async function GET(request: Request) {
  try {
    const { searchParams } = new URL(request.url);
    const email = searchParams.get("email")?.trim().toLowerCase();

    const admin = createAdminClient();

    const [roles, perfiles] = await Promise.all([
      admin.from("roles").select("nombre", { count: "exact" }),
      admin.from("perfiles_usuario").select("id, nombre_completo, activo", {
        count: "exact",
      }),
    ]);

    let emailCheck: Record<string, unknown> | null = null;

    if (email) {
      const { data: authData, error: authError } =
        await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });

      if (authError) {
        emailCheck = {
          email,
          authUser: false,
          error: toDisplayError(authError),
        };
      } else {
        const authUser = authData.users.find(
          (u) => u.email?.toLowerCase() === email,
        );
        const perfil = (perfiles.data ?? []).find((p) => p.id === authUser?.id);

        emailCheck = {
          email,
          authUser: Boolean(authUser),
          emailConfirmed: Boolean(authUser?.email_confirmed_at),
          perfil: perfil
            ? {
                nombre: perfil.nombre_completo,
                activo: perfil.activo,
              }
            : null,
        };
      }
    }

    return NextResponse.json({
      ok: true,
      roles: roles.count ?? 0,
      perfiles: perfiles.count ?? 0,
      emailCheck,
      env: {
        hasUrl: Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL),
        hasAnonKey: Boolean(process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY),
        hasServiceRole: Boolean(process.env.SUPABASE_SERVICE_ROLE_KEY),
      },
    });
  } catch (err) {
    return NextResponse.json(
      {
        ok: false,
        error: toDisplayError(err),
      },
      { status: 500 },
    );
  }
}
