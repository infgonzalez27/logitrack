// Edge Function: reset-password
// Espejo de src/lib/actions/usuarios.ts (createAdminClient):
// - email → auth.resetPasswordForEmail
// - userId + password → auth.admin.updateUserById
// Requiere SUPABASE_SERVICE_ROLE_KEY.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type Body = {
  email?: string;
  userId?: string;
  password?: string;
  redirectTo?: string;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return json({ ok: false, error: "Falta Authorization Bearer." }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

    if (!supabaseUrl || !serviceKey) {
      return json(
        {
          ok: false,
          error:
            "Stub: faltan SUPABASE_URL o SUPABASE_SERVICE_ROLE_KEY en la función.",
        },
        500,
      );
    }

    const userClient = createClient(supabaseUrl, anonKey || serviceKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userError } =
      await userClient.auth.getUser();
    if (userError || !userData.user) {
      return json({ ok: false, error: "JWT inválido o expirado." }, 401);
    }

    const body = (await req.json()) as Body;
    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const userId = String(body.userId ?? "").trim();
    const password = String(body.password ?? "");
    let email = String(body.email ?? "").trim().toLowerCase();

    if (userId && password) {
      if (password.length < 6) {
        return json(
          {
            ok: false,
            error: "La contraseña debe tener al menos 6 caracteres.",
          },
          400,
        );
      }
      const { error } = await admin.auth.admin.updateUserById(userId, {
        password,
      });
      if (error) return json({ ok: false, error: error.message }, 400);
      return json({ ok: true });
    }

    // Recuperación por email: aceptar email directo o resolver desde userId.
    if (!email && userId) {
      const { data: authUser, error: lookupError } =
        await admin.auth.admin.getUserById(userId);
      if (lookupError || !authUser.user?.email) {
        return json(
          {
            ok: false,
            error: "No se pudo obtener el correo del usuario.",
          },
          400,
        );
      }
      email = authUser.user.email.toLowerCase();
    }

    if (email) {
      const redirectTo =
        body.redirectTo?.trim() ||
        Deno.env.get("PASSWORD_RESET_REDIRECT") ||
        undefined;
      const { error } = await admin.auth.resetPasswordForEmail(email, {
        redirectTo,
      });
      if (error) return json({ ok: false, error: error.message }, 400);
      return json({ ok: true });
    }

    return json(
      {
        ok: false,
        error: "Indica email (recuperación) o userId + password (cambio admin).",
      },
      400,
    );
  } catch (err) {
    return json(
      {
        ok: false,
        error: err instanceof Error ? err.message : "Error interno",
      },
      500,
    );
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
