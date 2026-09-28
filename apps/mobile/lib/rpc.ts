/** Helpers compartidos para unwrap de envelopes RPC `{ success, data, error }`. */

export type RpcEnvelope<T> = {
  success?: boolean;
  data?: T | null;
  message?: string;
  error?: { message?: string; code?: string } | string | null;
};

export function unwrapRpcData<T>(payload: unknown): T | null {
  if (payload == null) return null;
  if (Array.isArray(payload)) return payload as T;
  if (typeof payload === "object") {
    const env = payload as RpcEnvelope<T>;
    if (env.success === false) return null;
    if (env.data != null) return env.data;
  }
  return payload as T;
}

export function rpcFailMessage(
  payload: unknown,
  fallback: string,
): string {
  if (payload && typeof payload === "object") {
    const env = payload as RpcEnvelope<unknown>;
    if (typeof env.message === "string" && env.message.trim()) return env.message;
    if (typeof env.error === "string" && env.error.trim()) return env.error;
    if (
      env.error &&
      typeof env.error === "object" &&
      typeof env.error.message === "string"
    ) {
      return env.error.message;
    }
  }
  return fallback;
}

export function isRpcSuccess(payload: unknown): boolean {
  if (payload == null) return false;
  if (typeof payload !== "object") return true;
  const env = payload as RpcEnvelope<unknown>;
  if (env.success === false) return false;
  return true;
}
