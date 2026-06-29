import { AuthApiError } from "@supabase/supabase-js";

export function formatSupabaseError(error: unknown): string {
  if (!error) return "Ocurrió un error desconocido.";

  if (error instanceof AuthApiError) {
    if (error.code) return mapAuthCode(error.code);
    if (error.message) return normalizeMessage(error.message);
  }

  if (typeof error === "string" && error.trim()) {
    return normalizeMessage(error);
  }

  if (error instanceof Error && error.message.trim()) {
    return normalizeMessage(error.message);
  }

  if (typeof error === "object") {
    const record = error as Record<string, unknown>;
    if (typeof record.code === "string") {
      return mapAuthCode(record.code);
    }
    if (typeof record.message === "string" && record.message.trim()) {
      return normalizeMessage(record.message);
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

function normalizeMessage(message: string): string {
  const trimmed = message.trim();
  if (!trimmed || trimmed === "{}") {
    return "No se pudo conectar con el servidor. Intenta de nuevo.";
  }
  if (trimmed.startsWith("{")) {
    try {
      const parsed = JSON.parse(trimmed) as Record<string, unknown>;
      if (typeof parsed.url === "string") {
        return "No se pudo conectar con Supabase. Revisa la configuración del proyecto.";
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

function mapAuthCode(code: string): string {
  switch (code) {
    case "invalid_credentials":
      return "Correo o contraseña incorrectos.";
    case "email_not_confirmed":
      return "Debes confirmar tu correo antes de iniciar sesión.";
    case "user_not_found":
      return "No existe un usuario con ese correo.";
    case "over_request_rate_limit":
      return "Demasiados intentos. Espera un momento e intenta de nuevo.";
    default:
      return `Error de autenticación (${code}).`;
  }
}

export function toDisplayError(error: unknown): string {
  const message = formatSupabaseError(error);
  return typeof message === "string" ? message : "Ocurrió un error inesperado.";
}
