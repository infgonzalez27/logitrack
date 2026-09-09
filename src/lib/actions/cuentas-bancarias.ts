"use server";

import { revalidatePath } from "next/cache";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile, type RolNombre } from "@/lib/auth/roles";
import { callDbProcedure, rpcErrorMessage } from "@/lib/actions/db-rpc";
import type { CuentaBancariaEmpresa } from "@/types/database";

const ROLES_GESTION: RolNombre[] = ["admin", "gerente"];

async function canManageCuentas(): Promise<boolean> {
  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);
  return !!rol && ROLES_GESTION.includes(rol);
}

function revalidateCuentas() {
  revalidatePath("/cuentas-bancarias");
  revalidatePath("/rendiciones");
  revalidatePath("/rendiciones/nuevo");
}

/** §2.29 */
export async function listarCuentasBancariasEmpresaAction(
  soloActivas = false,
): Promise<
  | { ok: true; cuentas: CuentaBancariaEmpresa[] }
  | { ok: false; error: string }
> {
  const response = await callDbProcedure<CuentaBancariaEmpresa[]>(
    "retorna_cuentas_bancarias_empresa",
    { p_solo_activas: soloActivas },
  );

  if (!response.success) {
    return {
      ok: false,
      error: rpcErrorMessage(
        response,
        "No se pudieron cargar las cuentas bancarias.",
      ),
    };
  }

  return {
    ok: true,
    cuentas: Array.isArray(response.data) ? response.data : [],
  };
}

/** §2.26 — solo registrar */
export async function crearCuentaBancariaEmpresaAction(input: {
  cuenta_bancaria: string;
  entidad_bancaria: string;
}): Promise<
  | { ok: true; cuenta: CuentaBancariaEmpresa }
  | { ok: false; error: string; code?: string }
> {
  if (!(await canManageCuentas())) {
    return {
      ok: false,
      error: "Solo admin o gerente pueden registrar cuentas bancarias.",
      code: "ACCESO_DENEGADO",
    };
  }

  const cuenta = input.cuenta_bancaria?.trim() ?? "";
  const entidad = input.entidad_bancaria?.trim() ?? "";
  if (!cuenta) {
    return { ok: false, error: "El número de cuenta es requerido." };
  }
  if (!entidad) {
    return { ok: false, error: "La entidad bancaria es requerida." };
  }

  const response = await callDbProcedure<CuentaBancariaEmpresa>(
    "crear_cuenta_bancaria_empresa",
    {
      p_cuenta_bancaria: cuenta,
      p_entidad_bancaria: entidad,
    },
  );

  if (!response.success || !response.data) {
    return {
      ok: false,
      error: rpcErrorMessage(response, "No se pudo registrar la cuenta."),
      code: response.error?.code,
    };
  }

  revalidateCuentas();
  return {
    ok: true,
    cuenta: {
      id: response.data.id,
      cuenta_bancaria: response.data.cuenta_bancaria,
      entidad_bancaria: response.data.entidad_bancaria,
      status_cuenta: response.data.status_cuenta ?? true,
      created_at: response.data.created_at ?? null,
    },
  };
}

/** §2.27 — modificar */
export async function actualizarCuentaBancariaEmpresaAction(input: {
  id: string;
  cuenta_bancaria?: string | null;
  entidad_bancaria?: string | null;
  status_cuenta?: boolean | null;
}): Promise<
  | { ok: true; cuenta: CuentaBancariaEmpresa }
  | { ok: false; error: string; code?: string }
> {
  if (!(await canManageCuentas())) {
    return {
      ok: false,
      error: "Solo admin o gerente pueden modificar cuentas bancarias.",
      code: "ACCESO_DENEGADO",
    };
  }

  const id = input.id?.trim() ?? "";
  if (!id) {
    return { ok: false, error: "Cuenta inválida." };
  }

  const response = await callDbProcedure<CuentaBancariaEmpresa>(
    "actualizar_cuenta_bancaria_empresa",
    {
      p_id: id,
      p_cuenta_bancaria: input.cuenta_bancaria?.trim() || null,
      p_entidad_bancaria: input.entidad_bancaria?.trim() || null,
      p_status_cuenta:
        input.status_cuenta === undefined ? null : input.status_cuenta,
    },
  );

  if (!response.success || !response.data) {
    return {
      ok: false,
      error: rpcErrorMessage(response, "No se pudo actualizar la cuenta."),
      code: response.error?.code,
    };
  }

  revalidateCuentas();
  return {
    ok: true,
    cuenta: {
      id: response.data.id,
      cuenta_bancaria: response.data.cuenta_bancaria,
      entidad_bancaria: response.data.entidad_bancaria,
      status_cuenta: response.data.status_cuenta ?? true,
      created_at: response.data.created_at ?? null,
    },
  };
}
