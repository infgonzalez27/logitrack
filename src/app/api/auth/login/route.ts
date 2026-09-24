import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { joinOne } from "@/lib/supabase/join";
import {
  createTenantDataClient,
  tenantFromEmpresa,
} from "@/lib/supabase/tenant-context";
import { serializeErrorForLog } from "@/lib/debug";
import { mapAuthTokenError } from "@/lib/errors";

type TokenResponse = {
  access_token?: string;
  refresh_token?: string;
  error_code?: string;
  msg?: string;
  error_description?: string;
};

export async function POST(request: Request) {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!url || !anonKey) {
    return NextResponse.json(
      { error: "Configuración de Supabase incompleta en el servidor." },
      { status: 500 },
    );
  }

  try {
    const body = (await request.json()) as {
      email?: string;
      password?: string;
    };

    const email = String(body.email ?? "").trim();
    const password = String(body.password ?? "");

    if (!email || !password) {
      return NextResponse.json(
        { error: "Ingresa correo y contraseña." },
        { status: 400 },
      );
    }

    // fetch directo: el cliente supabase-js devuelve AuthRetryableFetchError en este entorno
    const tokenRes = await fetch(`${url}/auth/v1/token?grant_type=password`, {
      method: "POST",
      headers: {
        apikey: anonKey,
        Authorization: `Bearer ${anonKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ email, password }),
    });

    const tokenJson = (await tokenRes.json()) as TokenResponse;

    console.info("[LogiTrack Auth API] token response:", {
      status: tokenRes.status,
      error_code: tokenJson.error_code ?? null,
      msg: tokenJson.msg ?? null,
    });

    if (!tokenRes.ok || !tokenJson.access_token || !tokenJson.refresh_token) {
      const errorMessage = mapAuthTokenError(tokenJson);

      return NextResponse.json(
        {
          error: errorMessage,
          debug:
            process.env.NODE_ENV === "development"
              ? { status: tokenRes.status, body: tokenJson }
              : undefined,
        },
        { status: tokenRes.status >= 500 ? 503 : 401 },
      );
    }

    const supabase = await createClient();
    const { data, error: sessionError } = await supabase.auth.setSession({
      access_token: tokenJson.access_token,
      refresh_token: tokenJson.refresh_token,
    });

    if (sessionError || !data.session) {
      const debug = serializeErrorForLog(sessionError);
      console.error("[LogiTrack Auth API] setSession error:", debug);
      return NextResponse.json(
        {
          error: "Credenciales válidas pero no se pudo crear la sesión.",
          debug: process.env.NODE_ENV === "development" ? debug : undefined,
        },
        { status: 500 },
      );
    }

    console.info("[LogiTrack Auth API] login OK:", data.user?.id);

    let redirectTo = "/";
    const userId = data.user?.id;
    if (userId) {
      const { data: asignacion } = await supabase
        .from("usuarios_empresas")
        .select("empresas(id, activo, supabase_url, supabase_anon_key)")
        .eq("user_id", userId)
        .limit(1)
        .maybeSingle();
      const tenant = tenantFromEmpresa(joinOne(asignacion?.empresas));
      const dataClient = tenant
        ? createTenantDataClient(tenant, async () => tokenJson.access_token ?? null)
        : supabase;

      const { data: profile } = await dataClient
        .from("perfiles_usuario")
        .select("roles(nombre)")
        .eq("id", userId)
        .maybeSingle();

      const rolesRaw = profile?.roles as unknown;
      const rolNombre = Array.isArray(rolesRaw)
        ? (rolesRaw[0] as { nombre?: string } | undefined)?.nombre
        : (rolesRaw as { nombre?: string } | null | undefined)?.nombre;

      if (rolNombre === "despachador") redirectTo = "/radar";
      else if (rolNombre === "chofer") redirectTo = "/ordenes";
      else if (rolNombre === "cobrador") redirectTo = "/rendiciones";
    }

    return NextResponse.json({
      ok: true,
      userId,
      redirectTo,
    });
  } catch (err) {
    const debug = serializeErrorForLog(err);
    console.error("[LogiTrack Auth API] exception:", debug);
    return NextResponse.json(
      {
        error: "Error inesperado al iniciar sesión.",
        debug: process.env.NODE_ENV === "development" ? debug : undefined,
      },
      { status: 500 },
    );
  }
}
