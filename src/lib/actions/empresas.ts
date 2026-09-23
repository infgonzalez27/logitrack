"use server";

import { revalidatePath } from "next/cache";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { registerUser } from "@/lib/auth/register-user";
import { createCentralAdminClient } from "@/lib/supabase/admin";
import {
  provisionTenantProject,
  tenantProjectName,
} from "@/lib/tenants/provision";
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

function normalizeCodigo(codigo: string): string {
  return codigo
    .trim()
    .toLowerCase()
    .replace(/^lt_/, "")
    .replace(/[^a-z0-9_-]/g, "");
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

export type CrearEmpresaConGerenteInput = {
  codigoEmpresa: string;
  nombreEmpresa: string;
  gerente: {
    email: string;
    password: string;
    nombreCompleto: string;
    telefono?: string;
  };
};

/**
 * Flujo Superadmin (opción 1: Server Action + RPCs):
 * 1) Aprovisiona proyecto Supabase `lt_[codigo]` (Management API)
 * 2) `crea_nueva_empresa` en BD Central con URL/anon key obtenidos
 * 3) `registra_nuevo_usuario` (gerente)
 * 4) `asignar_usuario_empresa`
 *
 * El usuario del panel NO carga URL ni anon key.
 */
export async function crearEmpresaConGerenteAction(
  input: CrearEmpresaConGerenteInput,
): Promise<
  | {
      ok: true;
      empresaId: string;
      userId: string;
      codigoEmpresa: string;
      projectName: string;
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

  const codigoEmpresa = normalizeCodigo(input.codigoEmpresa);
  const nombreEmpresa = input.nombreEmpresa.trim();
  const email = input.gerente.email.trim();
  const password = input.gerente.password;
  const nombreCompleto = input.gerente.nombreCompleto.trim();
  const telefono = (input.gerente.telefono ?? "").trim();

  if (!codigoEmpresa || !nombreEmpresa || !email || !password || !nombreCompleto) {
    return {
      ok: false,
      error: "Completa código, nombre comercial y datos del gerente.",
      code: "PARAMETRO_INVALIDO",
    };
  }

  let provisioned: Awaited<ReturnType<typeof provisionTenantProject>>;
  try {
    provisioned = await provisionTenantProject(codigoEmpresa);
  } catch (err) {
    return {
      ok: false,
      error: err instanceof Error ? err.message : "Error al aprovisionar el tenant.",
      code: "PROVISION_FALLIDA",
    };
  }

  const central = createCentralAdminClient();
  const { data: crearData, error: crearError } = await central.rpc(
    "crea_nueva_empresa",
    {
      p_codigo_empresa: codigoEmpresa,
      p_nombre_empresa: nombreEmpresa,
      p_supabase_url: provisioned.supabaseUrl,
      p_supabase_anon_key: provisioned.supabaseAnonKey,
    },
  );

  if (crearError) {
    return { ok: false, error: crearError.message, code: "API_ERROR" };
  }

  const crearResponse = crearData as RPCResponse<CrearEmpresaData>;
  if (!crearResponse.success || !crearResponse.data?.empresa_id) {
    return {
      ok: false,
      error: crearResponse.error?.message || "Error al registrar la empresa en Central.",
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
      error: `Proyecto ${tenantProjectName(codigoEmpresa)} y empresa en catálogo OK, pero falló el gerente: ${registerResult.error}`,
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
    projectName: provisioned.projectName,
  };
}
