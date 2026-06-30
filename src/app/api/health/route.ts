import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { toDisplayError } from "@/lib/errors";

export async function GET(request: Request) {
  try {
    const { searchParams } = new URL(request.url);
    const email = searchParams.get("email")?.trim().toLowerCase();

    const admin = createAdminClient();

    const [roles, perfiles, authList] = await Promise.all([
      admin.from("roles").select("nombre", { count: "exact" }),
      admin.from("perfiles_usuario").select("id, nombre_completo, activo", {
        count: "exact",
      }),
      admin.auth.admin.listUsers({ page: 1, perPage: 1000 }),
    ]);

    const authUsers = authList.data?.users ?? [];
    const authListError = authList.error
      ? toDisplayError(authList.error)
      : null;

    let emailCheck: Record<string, unknown> | null = null;

    if (email) {
      if (authListError) {
        emailCheck = {
          email,
          authUser: false,
          error: authListError,
        };
      } else {
        const authUser = authUsers.find(
          (u) => u.email?.toLowerCase() === email,
        );
        const perfil = (perfiles.data ?? []).find((p) => p.id === authUser?.id);

        emailCheck = {
          email,
          authUser: Boolean(authUser),
          authUserId: authUser?.id ?? null,
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
      projectRef: process.env.NEXT_PUBLIC_SUPABASE_URL?.match(
        /https:\/\/([^.]+)\.supabase\.co/,
      )?.[1],
      roles: roles.count ?? 0,
      perfiles: perfiles.count ?? 0,
      auth: {
        enabled: true,
        userCount: authUsers.length,
        emails: authUsers.map((u) => u.email).filter(Boolean),
        listError: authListError,
        dashboardUrl: process.env.NEXT_PUBLIC_SUPABASE_URL
          ? `https://supabase.com/dashboard/project/${process.env.NEXT_PUBLIC_SUPABASE_URL.match(/https:\/\/([^.]+)\.supabase\.co/)?.[1]}/auth/users`
          : null,
      },
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
