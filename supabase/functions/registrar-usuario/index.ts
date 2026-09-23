// Edge Function: registrar-usuario
// Espejo de src/lib/auth/register-user.ts (createAdminClient + RPC registra_nuevo_usuario).
// Requiere SUPABASE_SERVICE_ROLE_KEY en el entorno de la función.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type Body = {
  email?: string;
  password?: string;
  nombre_completo?: string;
  telefono?: string;
  rol_nombre?: string;
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

    // Validar JWT del llamador (usuario autenticado).
    const userClient = createClient(supabaseUrl, anonKey || serviceKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userError } =
      await userClient.auth.getUser();
    if (userError || !userData.user) {
      return json({ ok: false, error: "JWT inválido o expirado." }, 401);
    }

    const body = (await req.json()) as Body;
    const email = String(body.email ?? "").trim().toLowerCase();
    const password = String(body.password ?? "");
    const nombre = String(body.nombre_completo ?? "").trim();
    const telefono = String(body.telefono ?? "").trim();
    const rol = String(body.rol_nombre ?? "").trim();

    if (!email || !password || !nombre || !rol) {
      return json(
        { ok: false, error: "Completa los campos obligatorios." },
        400,
      );
    }
    if (password.length < 6) {
      return json(
        {
          ok: false,
          error: "La contraseña debe tener al menos 6 caracteres.",
        },
        400,
      );
    }

    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const { data, error } = await admin.rpc("registra_nuevo_usuario", {
      p_email: email,
      p_password: password,
      p_nombre_completo: nombre,
      p_telefono: telefono,
      p_rol_nombre: rol,
    });

    if (error) {
      return json({ ok: false, error: error.message }, 400);
    }

    const result = data as {
      success?: boolean;
      message?: string;
      user_id?: string;
    } | null;

    if (!result?.success || !result.user_id) {
      return json(
        {
          ok: false,
          error: result?.message ?? "No se pudo registrar el usuario.",
        },
        400,
      );
    }

    return json({ ok: true, userId: result.user_id });
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
