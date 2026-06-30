import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { serializeErrorForLog } from "@/lib/debug";
import { mapAuthTokenError } from "@/lib/errors";

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const probeEmail = searchParams.get("email")?.trim();

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  const result: Record<string, unknown> = {
    timestamp: new Date().toISOString(),
    env: {
      hasUrl: Boolean(url),
      url: url ?? null,
      anonKeyLength: anonKey?.length ?? 0,
      anonKeyPrefix: anonKey?.slice(0, 12) ?? null,
      serviceKeyLength: serviceKey?.length ?? 0,
    },
    probes: {} as Record<string, unknown>,
  };

  const probes = result.probes as Record<string, unknown>;

  async function probeToken(email: string, label: string) {
    if (!url) return;

    try {
      const tokenRes = await fetch(`${url}/auth/v1/token?grant_type=password`, {
        method: "POST",
        headers: {
          apikey: anonKey ?? "",
          Authorization: `Bearer ${anonKey ?? ""}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ email, password: "__probe_invalid_password__" }),
      });
      const tokenBody = (await tokenRes.json()) as {
        error_code?: string;
        msg?: string;
      };

      probes[label] = {
        email,
        status: tokenRes.status,
        error_code: tokenBody.error_code ?? null,
        msg: tokenBody.msg ?? null,
        userMessage: mapAuthTokenError(tokenBody),
        note:
          tokenRes.status === 400 && tokenBody.error_code === "invalid_credentials"
            ? "Usuario existe y Auth responde bien (contraseña incorrecta esperada)."
            : tokenRes.status === 400
              ? "Auth respondió 400."
              : tokenRes.status === 500
                ? "Usuario probablemente dañado en auth.users — revisar Supabase Auth logs."
                : "Respuesta inesperada.",
      };
    } catch (err) {
      probes[label] = { email, failed: true, error: serializeErrorForLog(err) };
    }
  }

  // 1. Auth health (público)
  if (url) {
    try {
      const healthRes = await fetch(`${url}/auth/v1/health`, {
        headers: { apikey: anonKey ?? "" },
      });
      probes.authHealth = {
        status: healthRes.status,
        ok: healthRes.ok,
        body: await healthRes.text(),
      };
    } catch (err) {
      probes.authHealth = { failed: true, error: serializeErrorForLog(err) };
    }

    // 2. Token con email inexistente (debe responder 400 invalid_credentials)
    await probeToken("probe-invalid@logitrack.local", "authTokenProbe");

    if (probeEmail) {
      await probeToken(probeEmail, "authTokenProbeEmail");
    }

    // 3. REST roles (anon)
    try {
      const restRes = await fetch(`${url}/rest/v1/roles?select=id&limit=1`, {
        headers: {
          apikey: anonKey ?? "",
          Authorization: `Bearer ${anonKey ?? ""}`,
        },
      });
      probes.restRoles = {
        status: restRes.status,
        ok: restRes.ok,
        body: (await restRes.text()).slice(0, 200),
      };
    } catch (err) {
      probes.restRoles = { failed: true, error: serializeErrorForLog(err) };
    }
  }

  // 4. Admin listUsers (service role)
  try {
    const admin = createAdminClient();
    const { data, error } = await admin.auth.admin.listUsers({
      page: 1,
      perPage: 1,
    });
    probes.adminListUsers = error
      ? { failed: true, error: serializeErrorForLog(error) }
      : { ok: true, userCount: data.users.length };
  } catch (err) {
    probes.adminListUsers = { failed: true, error: serializeErrorForLog(err) };
  }

  return NextResponse.json(result, { status: 200 });
}
