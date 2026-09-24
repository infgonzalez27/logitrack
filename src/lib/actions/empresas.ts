"use server";

import { revalidatePath } from "next/cache";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { registerUser } from "@/lib/auth/register-user";
import { createCentralAdminClient } from "@/lib/supabase/admin";
import {
  bootstrapTenant,
  mirrorCentralUserToTenant,
} from "@/lib/tenants/bootstrap";
import { projectRefFromUrl } from "@/lib/tenants/management";
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
 *    — o usa URL/anon key si vienen en el input (flujo manual / agente BD)
 * 2) `crea_nueva_empresa` en BD Central
 * 3) Gerente con `registerUser` en modo tenant: cuenta en Central,
 *    `usuarios_empresas` y perfil solo en el tenant
 */
export async function crearEmpresaConGerenteAction(
  input: CrearEmpresaConGerenteInput & {
    supabaseUrl?: string;
    supabaseAnonKey?: string;
  },
): Promise<
  | {
      ok: true;
      empresaId: string;
      userId: string;
      codigoEmpresa: string;
      projectName: string;
      nombreEmpresa: string;
      gerenteEmail: string;
      mensaje: string;
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
  const urlManual = (input.supabaseUrl ?? "").trim();
  const keyManual = (input.supabaseAnonKey ?? "").trim();

  if (!codigoEmpresa || !nombreEmpresa || !email || !password || !nombreCompleto) {
    return {
      ok: false,
      error: "Completa código, nombre comercial y datos del gerente.",
      code: "PARAMETRO_INVALIDO",
    };
  }

  let supabaseUrl = urlManual;
  let supabaseAnonKey = keyManual;
  let projectName = tenantProjectName(codigoEmpresa);

  if (!supabaseUrl || !supabaseAnonKey) {
    try {
      const provisioned = await provisionTenantProject(codigoEmpresa);
      supabaseUrl = provisioned.supabaseUrl;
      supabaseAnonKey = provisioned.supabaseAnonKey;
      projectName = provisioned.projectName;
    } catch (err) {
      return {
        ok: false,
        error:
          err instanceof Error ? err.message : "Error al aprovisionar el tenant.",
        code: "PROVISION_FALLIDA",
      };
    }
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
      error:
        crearResponse.error?.message ||
        "Error al registrar la empresa en Central.",
      code: crearResponse.error?.code,
    };
  }

  const empresaId = crearResponse.data.empresa_id;

  const projectRef = projectRefFromUrl(supabaseUrl);

  if (urlManual) {
    try {
      await bootstrapTenant(projectRef);
    } catch (err) {
      revalidatePath("/admin");
      return {
        ok: false,
        error: `Empresa creada, pero falló la preparación del tenant (usa "Sincronizar" en /admin): ${
          err instanceof Error ? err.message : String(err)
        }`,
        code: "TENANT_SYNC_FALLIDA",
        empresaCreada: true,
        empresaId,
      };
    }
  }

  const registerResult = await registerUser(
    {
      email,
      password,
      nombre_completo: nombreCompleto,
      telefono,
      rol_nombre: "gerente",
    },
    { tenant: { empresaId, projectRef } },
  );

  if (!registerResult.ok) {
    revalidatePath("/admin");
    return {
      ok: false,
      error: `Proyecto ${projectName} y empresa en catálogo OK, pero falló el gerente: ${registerResult.error}`,
      code: "GERENTE_NO_CREADO",
      empresaCreada: true,
      empresaId,
    };
  }

  revalidatePath("/admin");

  const mensaje = `¡Empresa ${nombreEmpresa} y su Gerente creados exitosamente!`;

  return {
    ok: true,
    empresaId,
    userId: registerResult.userId,
    codigoEmpresa,
    projectName,
    nombreEmpresa,
    gerenteEmail: email,
    mensaje,
  };
}

/**
 * Re-aplica la preparación del tenant (confianza JWT, catálogos, buckets) y
 * copia al tenant los usuarios asignados a la empresa que aún no tengan perfil
 * allí (rol de usuarios_empresas); borra sus perfiles sobrantes en Central.
 */
export async function sincronizarEmpresaAction(
  empresaId: string,
): Promise<{ ok: true; usuarios: number } | { ok: false; error: string }> {
  const guard = await requireAdmin();
  if (!guard.ok) return guard;

  const central = createCentralAdminClient();
  const { data: empresa, error: empresaError } = await central
    .from("empresas")
    .select("id, supabase_url")
    .eq("id", empresaId)
    .maybeSingle();
  if (empresaError || !empresa?.supabase_url) {
    return { ok: false, error: "Empresa no encontrada o sin proyecto asignado." };
  }

  const { data: asignaciones, error: asignacionesError } = await central
    .from("usuarios_empresas")
    .select("user_id, rol")
    .eq("empresa_id", empresaId);
  if (asignacionesError) {
    return { ok: false, error: asignacionesError.message };
  }

  try {
    const projectRef = projectRefFromUrl(empresa.supabase_url);
    await bootstrapTenant(projectRef);
    for (const { user_id, rol } of asignaciones ?? []) {
      await mirrorCentralUserToTenant(projectRef, user_id, rol);
    }
  } catch (err) {
    return {
      ok: false,
      error: err instanceof Error ? err.message : "No se pudo sincronizar el tenant.",
    };
  }

  revalidatePath("/admin");
  return { ok: true, usuarios: asignaciones?.length ?? 0 };
}

/**
 * Server Action orquestado (contrato Frontend / agente BD).
 * FormData: codigoEmpresa, nombreEmpresa, gerenteEmail, gerentePassword,
 * gerenteNombre (recomendado), gerenteTelefono (opcional).
 * supabaseUrl / supabaseAnonKey son opcionales (si faltan, se aprovisiona lt_*).
 */
export async function submitCrearEmpresaAction(formData: FormData) {
  const result = await crearEmpresaConGerenteAction({
    codigoEmpresa: String(formData.get("codigoEmpresa") ?? ""),
    nombreEmpresa: String(formData.get("nombreEmpresa") ?? ""),
    supabaseUrl: String(formData.get("supabaseUrl") ?? ""),
    supabaseAnonKey: String(formData.get("supabaseAnonKey") ?? ""),
    gerente: {
      email: String(formData.get("gerenteEmail") ?? ""),
      password: String(formData.get("gerentePassword") ?? ""),
      nombreCompleto:
        String(formData.get("gerenteNombre") ?? "").trim() ||
        String(formData.get("gerenteEmail") ?? "")
          .split("@")[0]
          .trim(),
      telefono: String(formData.get("gerenteTelefono") ?? ""),
    },
  });

  if (!result.ok) {
    return {
      success: false as const,
      error: result.error,
      code: result.code,
      empresaCreada: result.empresaCreada,
      data: result.empresaId
        ? { empresa_id: result.empresaId }
        : null,
    };
  }

  return {
    success: true as const,
    data: {
      empresa_id: result.empresaId,
      codigo_empresa: result.codigoEmpresa,
      nombre_empresa: result.nombreEmpresa,
      gerente_id: result.userId,
      gerente_email: result.gerenteEmail,
      proyecto_supabase: result.projectName,
      mensaje: result.mensaje,
    },
  };
}

