import { AuthApiError, AuthError } from "@supabase/supabase-js";
import { serializeErrorForLog } from "@/lib/debug";

export function formatSupabaseError(error: unknown): string {
  if (!error) return "Ocurrió un error desconocido.";

  if (error instanceof AuthError) {
    if (error.code) return mapAuthCode(error.code);
    if (error.message) return normalizeMessage(error.message, error);
  }

  if (error instanceof AuthApiError) {
    if (error.code) return mapAuthCode(error.code);
    if (error.message) return normalizeMessage(error.message, error);
  }

  if (typeof error === "string" && error.trim()) {
    return normalizeMessage(error);
  }

  if (error instanceof Error && error.message.trim()) {
    return normalizeMessage(error.message, error);
  }

  if (typeof error === "object") {
    const record = error as Record<string, unknown>;
    if (typeof record.code === "string") {
      return mapAuthCode(record.code);
    }
    if (typeof record.message === "string" && record.message.trim()) {
      return normalizeMessage(record.message, error);
    }
    if (typeof record.error_description === "string") {
      return record.error_description;
    }
    if (typeof record.url === "string") {
      return "No se pudo conectar con Supabase. Verifica tu conexión e intenta de nuevo.";
    }
  }

  return "No se pudo completar la operación. Verifica tus datos e intenta de nuevo.";
}

function normalizeMessage(message: string, error?: unknown): string {
  const trimmed = message.trim();
  if (!trimmed || trimmed === "{}") {
    if (process.env.NODE_ENV === "development" && error) {
      console.error("[LogiTrack] auth error raw:", serializeErrorForLog(error));
    }
    return "No se pudo conectar con el servidor. Intenta de nuevo.";
  }
  if (trimmed.startsWith("{")) {
    try {
      const parsed = JSON.parse(trimmed) as Record<string, unknown>;
      if (typeof parsed.url === "string") {
        if (process.env.NODE_ENV === "development") {
          console.error("[LogiTrack] auth fetch failed URL:", parsed.url);
        }
        return "No se pudo conectar con Supabase Auth. Revisa la consola y /api/debug/auth-probe.";
      }
      if (typeof parsed.msg === "string") return parsed.msg;
      if (typeof parsed.message === "string") return parsed.message;
      if (typeof parsed.error_description === "string") {
        return parsed.error_description;
      }
    } catch {
      // usar mensaje original
    }
  }
  return trimmed;
}

export function mapAuthCode(code: string): string {
  switch (code) {
    case "invalid_credentials":
      return "Correo o contraseña incorrectos.";
    case "email_not_confirmed":
      return "Debes confirmar tu correo antes de iniciar sesión.";
    case "user_not_found":
      return "No existe un usuario con ese correo.";
    case "over_request_rate_limit":
      return "Demasiados intentos. Espera un momento e intenta de nuevo.";
    case "unexpected_failure":
      return "Error interno de Supabase Auth. Revisa los logs del proyecto o contacta al administrador.";
    case "email_exists":
    case "23505":
      return "Este correo ya está registrado. Si no puedes iniciar sesión, contacta al administrador.";
    default:
      return `Error de autenticación (${code}).`;
  }
}

/** Mensajes para respuestas JSON de POST /auth/v1/token */
export function mapAuthTokenError(body: {
  error_code?: string;
  msg?: string;
}): string {
  if (body.error_code === "invalid_credentials") {
    return "Correo o contraseña incorrectos.";
  }

  if (
    body.error_code === "unexpected_failure" &&
    body.msg?.toLowerCase().includes("database error")
  ) {
    return "La cuenta existe pero está dañada en Supabase Auth (error de base de datos al validar el usuario). Un administrador debe eliminarla en Authentication → Users y volver a registrarla.";
  }

  if (body.msg?.trim()) {
    return body.msg;
  }

  if (body.error_code) {
    return mapAuthCode(body.error_code);
  }

  return "Error al iniciar sesión.";
}

export function toDisplayError(error: unknown): string {
  const message = formatSupabaseError(error);
  return typeof message === "string" ? message : "Ocurrió un error inesperado.";
}
