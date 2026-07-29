import { createClient } from "@/lib/supabase/server";

export type RpcErrorPayload = {
  code: string;
  message: string;
  details: string | null;
};

export type RpcResponse<T> = {
  success: boolean;
  data: T | null;
  error: RpcErrorPayload | null;
  /** Formato legado de algunos SPs (`message` en raíz). */
  message?: string;
};

/** Wrapper estándar para supabase.rpc según docs/INTEGRACION-RPC.md */
export async function callDbProcedure<T>(
  procedureName: string,
  params: Record<string, unknown>,
): Promise<RpcResponse<T>> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc(procedureName, params);

  if (error) {
    return {
      success: false,
      data: null,
      error: {
        code: "NETWORK_OR_API_ERROR",
        message: error.message,
        details: error.details ?? null,
      },
    };
  }

  if (data == null) {
    return {
      success: false,
      data: null,
      error: {
        code: "SQL_ERROR",
        message: "El procedimiento no devolvió respuesta.",
        details: null,
      },
    };
  }

  if (typeof data === "object") {
    const response = data as RpcResponse<T> & {
      orden_id?: string;
      message?: string;
    };

    if (typeof response.success === "boolean") {
      return {
        success: response.success,
        data: response.data ?? null,
        error: response.error ?? null,
        message: response.message,
      };
    }
  }

  return {
    success: true,
    data: data as T,
    error: null,
  };
}

export function rpcErrorMessage(
  response: RpcResponse<unknown>,
  fallback: string,
): string {
  return (
    response.error?.message ??
    response.message ??
    fallback
  );
}
