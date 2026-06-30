const DEV = process.env.NODE_ENV === "development";

export function isDevDebug(): boolean {
  return DEV || process.env.NEXT_PUBLIC_DEBUG_AUTH === "true";
}

/** Serializa errores de Supabase/fetch sin exponer contraseñas. */
export function serializeErrorForLog(error: unknown): Record<string, unknown> {
  if (error == null) return { type: "null" };

  if (error instanceof Error) {
    const base: Record<string, unknown> = {
      type: error.constructor.name,
      name: error.name,
      message: error.message,
    };
    const extra = error as Error & {
      code?: string;
      status?: number;
      cause?: unknown;
      __isAuthError?: boolean;
    };
    if (extra.code) base.code = extra.code;
    if (extra.status) base.status = extra.status;
    if (extra.__isAuthError) base.isAuthError = true;
    if (extra.cause) base.cause = serializeErrorForLog(extra.cause);
    return base;
  }

  if (typeof error === "object") {
    try {
      return JSON.parse(JSON.stringify(error)) as Record<string, unknown>;
    } catch {
      return { type: "object", raw: String(error) };
    }
  }

  return { type: typeof error, value: String(error) };
}

export function logAuthDebug(scope: string, payload: Record<string, unknown>) {
  if (!isDevDebug()) return;
  console.group(`[LogiTrack Auth] ${scope}`);
  console.log(payload);
  console.groupEnd();
}
