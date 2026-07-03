import { createAdminClient } from "@/lib/supabase/admin";
import { serializeErrorForLog } from "@/lib/debug";
import { toDisplayError } from "@/lib/errors";

export type RegisterInput = {
  email: string;
  password: string;
  nombre_completo: string;
  telefono?: string;
  rol_nombre: string;
};

export type RegisterResult =
  | { ok: true; userId: string }
  | { ok: false; error: string; debug?: Record<string, unknown> };

/** Respuesta JSONB del SP `registra_nuevo_usuario` en PostgreSQL. */
type RegistraUsuarioRpcResult = {
  success: boolean;
  message?: string;
  user_id?: string;
};

export async function registerUser(
  input: RegisterInput,
  options?: { includeDebug?: boolean },
): Promise<RegisterResult> {
  const email = input.email.trim();
  const password = input.password;
  const nombre = input.nombre_completo.trim();
  const telefono = (input.telefono ?? "").trim();
  const rol = input.rol_nombre.trim();

  if (!email || !password || !nombre || !rol) {
    return { ok: false, error: "Completa los campos obligatorios." };
  }

  if (password.length < 6) {
    return { ok: false, error: "La contraseña debe tener al menos 6 caracteres." };
  }

  try {
    const supabaseAdmin = createAdminClient();

    const { data, error } = await supabaseAdmin.rpc("registra_nuevo_usuario", {
      p_email: email,
      p_password: password,
      p_nombre_completo: nombre,
      p_telefono: telefono,
      p_rol_nombre: rol,
    });

    console.info("[LogiTrack Register] rpc registra_nuevo_usuario:", {
      email,
      ok: !error,
      data,
      error: error ? serializeErrorForLog(error) : null,
    });

    if (error) {
      return {
        ok: false,
        error: toDisplayError(error),
        debug: options?.includeDebug
          ? { step: "rpc", error: serializeErrorForLog(error) }
          : undefined,
      };
    }

    const result = data as RegistraUsuarioRpcResult | null;

    if (!result?.success) {
      return {
        ok: false,
        error: result?.message ?? "No se pudo registrar el usuario.",
        debug: options?.includeDebug ? { step: "rpc_result", data: result } : undefined,
      };
    }

    if (!result.user_id) {
      return {
        ok: false,
        error: result.message ?? "El registro no devolvió el ID del usuario.",
        debug: options?.includeDebug ? { step: "rpc_result", data: result } : undefined,
      };
    }

    return { ok: true, userId: result.user_id };
  } catch (err) {
    console.error("[LogiTrack Register] exception:", serializeErrorForLog(err));
    return {
      ok: false,
      error: toDisplayError(err),
      debug: options?.includeDebug
        ? { step: "exception", error: serializeErrorForLog(err) }
        : undefined,
    };
  }
}
