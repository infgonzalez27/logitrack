"use server";

import { revalidatePath } from "next/cache";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { registerUser } from "@/lib/auth/register-user";
import { createCentralAdminClient } from "@/lib/supabase/admin";
import type { Empresa } from "@/types/database";

interface RPCResponse<T> {
  success: boolean;
  data: T | null;
  error: {
    code: string;
    message: string;
    details: string | null;
  } | null;
}

interface CrearEmpresaData {
  empresa_id: string;
  codigo_empresa: string;
  nombre_empresa: string;
}

interface AsignarUsuarioEmpresaData {
  asignacion_id: string;
  user_id: string;
  empresa_id: string;
  rol: string;
}

async function requireAdmin(): Promise<
  { ok: true } | { ok: false; error: string }
> {
  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);
  if (rol !== "admin") {
    return { ok: false, error: "Solo un administrador puede gestionar empresas." };
  }
  return { ok: true };
}

function str(formData: FormData, key: string): string {
  return String(formData.get(key) ?? "").trim();
}

/**
 * Lista todas las empresas del catálogo central (bypass RLS vía service role).
 */
export async function listarEmpresasAction(): Promise<
  { ok: true; empresas: Empresa[] } | { ok: false; error: string }
> {
  const guard = await requireAdmin();
  if (!guard.ok) return guard;

  try {
    const admin = createCentralAdminClient();
    const { data, error } = await admin
      .from("empresas")
      .select(
        "id, codigo_empresa, nombre_empresa, supabase_url, supabase_anon_key, activo, created_at",
      )
      .order("created_at", { ascending: false });

    if (error) {
      return { ok: false, error: error.message };
    }

    return { ok: true, empresas: (data ?? []) as Empresa[] };
  } catch (err) {
    return {
      ok: false,
      error: err instanceof Error ? err.message : "No se pudo listar empresas.",
    };
  }
}

/**
 * Registra una nueva empresa (tenant lt_*) en la BD Central.
 */
export async function submitCrearEmpresaAction(formData: FormData) {
  const guard = await requireAdmin();
  if (!guard.ok) {
    return { success: false as const, error: guard.error, code: "ACCESO_DENEGADO" };
  }

  const params = {
    p_codigo_empresa: str(formData, "codigoEmpresa"),
    p_nombre_empresa: str(formData, "nombreEmpresa"),
    p_supabase_url: str(formData, "supabaseUrl"),
    p_supabase_anon_key: str(formData, "supabaseAnonKey"),
  };

  if (
    !params.p_codigo_empresa ||
    !params.p_nombre_empresa ||
    !params.p_supabase_url ||
    !params.p_supabase_anon_key
  ) {
    return {
      success: false as const,
      error: "Completa código, nombre, URL y anon key de la empresa.",
      code: "PARAMETRO_INVALIDO",
    };
  }

  const supabase = createCentralAdminClient();
  const { data, error } = await supabase.rpc("crea_nueva_empresa", params);

  if (error) {
    return { success: false as const, error: error.message, code: "API_ERROR" };
  }

  const response = data as RPCResponse<CrearEmpresaData>;

  if (!response.success) {
    return {
      success: false as const,
      error: response.error?.message || "Error al crear la empresa.",
      code: response.error?.code,
    };
  }

  revalidatePath("/admin");

  return { success: true as const, data: response.data };
}

/**
 * Asigna un usuario (auth.users) a una empresa en el catálogo central.
 */
export async function submitAsignarUsuarioEmpresaAction(formData: FormData) {
  const guard = await requireAdmin();
  if (!guard.ok) {
    return { success: false as const, error: guard.error, code: "ACCESO_DENEGADO" };
  }

  const params = {
    p_user_id: str(formData, "userId"),
    p_empresa_id: str(formData, "empresaId"),
    p_rol: str(formData, "rol") || "operador",
  };

  if (!params.p_user_id || !params.p_empresa_id) {
    return {
      success: false as const,
      error: "Usuario y empresa son requeridos.",
      code: "PARAMETRO_INVALIDO",
    };
  }

  const supabase = createCentralAdminClient();
  const { data, error } = await supabase.rpc("asignar_usuario_empresa", params);

  if (error) {
    return { success: false as const, error: error.message, code: "API_ERROR" };
  }

  const response = data as RPCResponse<AsignarUsuarioEmpresaData>;

  if (!response.success) {
    return {
      success: false as const,
      error: response.error?.message || "Error al asignar el usuario a la empresa.",
      code: response.error?.code,
    };
  }

  revalidatePath("/admin");
  revalidatePath("/usuarios");

  return { success: true as const, data: response.data };
}

export type CrearEmpresaConGerenteInput = {
  codigoEmpresa: string;
  nombreEmpresa: string;
  supabaseUrl: string;
  supabaseAnonKey: string;
  gerente: {
    email: string;
    password: string;
    nombreCompleto: string;
    telefono?: string;
  };
};

/**
 * Flujo Superadmin: crea empresa en Central, registra gerente (Auth + perfil)
 * y lo vincula a la empresa con rol `gerente`.
 */
export async function crearEmpresaConGerenteAction(
  input: CrearEmpresaConGerenteInput,
): Promise<
  | {
      ok: true;
      empresaId: string;
      userId: string;
      codigoEmpresa: string;
    }
  | {
      ok: false;
      error: string;
      code?: string;
      empresaCreada?: boolean;
      empresaId?: string;
    }
> {
  const guard = await requireAdmin();
  if (!guard.ok) {
    return { ok: false, error: guard.error, code: "ACCESO_DENEGADO" };
  }

  const codigoEmpresa = input.codigoEmpresa.trim().toLowerCase();
  const nombreEmpresa = input.nombreEmpresa.trim();
  const supabaseUrl = input.supabaseUrl.trim();
  const supabaseAnonKey = input.supabaseAnonKey.trim();
  const email = input.gerente.email.trim();
  const password = input.gerente.password;
  const nombreCompleto = input.gerente.nombreCompleto.trim();
  const telefono = (input.gerente.telefono ?? "").trim();

  if (
    !codigoEmpresa ||
    !nombreEmpresa ||
    !supabaseUrl ||
    !supabaseAnonKey ||
    !email ||
    !password ||
    !nombreCompleto
  ) {
    return {
      ok: false,
      error: "Completa todos los campos de empresa y gerente.",
      code: "PARAMETRO_INVALIDO",
    };
  }

  const central = createCentralAdminClient();
  const { data: crearData, error: crearError } = await central.rpc(
    "crea_nueva_empresa",
    {
      p_codigo_empresa: codigoEmpresa,
      p_nombre_empresa: nombreEmpresa,
      p_supabase_url: supabaseUrl,
      p_supabase_anon_key: supabaseAnonKey,
    },
  );

  if (crearError) {
    return { ok: false, error: crearError.message, code: "API_ERROR" };
  }

  const crearResponse = crearData as RPCResponse<CrearEmpresaData>;
  if (!crearResponse.success || !crearResponse.data?.empresa_id) {
    return {
      ok: false,
      error: crearResponse.error?.message || "Error al crear la empresa.",
      code: crearResponse.error?.code,
    };
  }

  const empresaId = crearResponse.data.empresa_id;

  const registerResult = await registerUser({
    email,
    password,
    nombre_completo: nombreCompleto,
    telefono,
    rol_nombre: "gerente",
  });

  if (!registerResult.ok) {
    revalidatePath("/admin");
    return {
      ok: false,
      error: `Empresa creada, pero falló el gerente: ${registerResult.error}. Asigna el usuario manualmente a la empresa ${codigoEmpresa}.`,
      code: "GERENTE_NO_CREADO",
      empresaCreada: true,
      empresaId,
    };
  }

  const { data: asignarData, error: asignarError } = await central.rpc(
    "asignar_usuario_empresa",
    {
      p_user_id: registerResult.userId,
      p_empresa_id: empresaId,
      p_rol: "gerente",
    },
  );

  if (asignarError) {
    revalidatePath("/admin");
    return {
      ok: false,
      error: `Empresa y gerente creados, pero falló la asignación: ${asignarError.message}`,
      code: "ASIGNACION_FALLIDA",
      empresaCreada: true,
      empresaId,
    };
  }

  const asignarResponse = asignarData as RPCResponse<AsignarUsuarioEmpresaData>;
  if (!asignarResponse.success) {
    revalidatePath("/admin");
    return {
      ok: false,
      error: `Empresa y gerente creados, pero falló la asignación: ${asignarResponse.error?.message ?? "error desconocido"}`,
      code: asignarResponse.error?.code ?? "ASIGNACION_FALLIDA",
      empresaCreada: true,
      empresaId,
    };
  }

  revalidatePath("/admin");

  return {
    ok: true,
    empresaId,
    userId: registerResult.userId,
    codigoEmpresa,
  };
}
