"use server";

import { revalidatePath } from "next/cache";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile, type RolNombre } from "@/lib/auth/roles";
import { callDbProcedure, rpcErrorMessage } from "@/lib/actions/db-rpc";
import type { TasaCambio } from "@/types/database";

const ROLES_GESTION: RolNombre[] = ["admin", "gerente"];

function canManageTasas(): Promise<boolean> {
  return getCurrentProfile().then((profile) => {
    const rol = getRoleNameFromProfile(profile);
    return !!rol && ROLES_GESTION.includes(rol);
  });
}

export async function retornaUltimaTasaCambioAction(): Promise<
  | { ok: true; tasa: TasaCambio | null }
  | { ok: false; error: string }
> {
  const response = await callDbProcedure<TasaCambio | null>(
    "retorna_ultima_tasa_cambio",
  );

  if (!response.success) {
    return {
      ok: false,
      error: rpcErrorMessage(response, "No se pudo consultar la última tasa."),
    };
  }

  return { ok: true, tasa: response.data ?? null };
}

export async function retornaTasasCambioPorRangoAction(
  fechaDesde: string,
  fechaHasta: string,
): Promise<{ ok: true; tasas: TasaCambio[] } | { ok: false; error: string }> {
  const desde = fechaDesde?.trim();
  const hasta = fechaHasta?.trim();
  if (!desde || !hasta) {
    return { ok: false, error: "Indica fecha desde y hasta." };
  }

  const response = await callDbProcedure<TasaCambio[]>(
    "retorna_tasas_cambio_por_rango",
    {
      p_fecha_desde: desde,
      p_fecha_hasta: hasta,
    },
  );

  if (!response.success) {
    return {
      ok: false,
      error: rpcErrorMessage(response, "No se pudieron consultar las tasas."),
    };
  }

  return {
    ok: true,
    tasas: Array.isArray(response.data) ? response.data : [],
  };
}

export async function insertaTasaCambioAction(input: {
  fecha_tasa: string;
  tasa: number;
}): Promise<{ ok: true; tasa: TasaCambio } | { ok: false; error: string; code?: string }> {
  if (!(await canManageTasas())) {
    return { ok: false, error: "Solo admin o gerente pueden registrar tasas." };
  }

  const fecha = input.fecha_tasa?.trim();
  const tasa = Number(input.tasa);
  if (!fecha) {
    return { ok: false, error: "La fecha es requerida." };
  }
  if (!Number.isFinite(tasa) || tasa <= 0) {
    return { ok: false, error: "La tasa debe ser un número mayor a 0." };
  }

  const response = await callDbProcedure<{
    fecha_tasa: string;
    tasa_cambio: number;
  }>("inserta_tasa_cambio", {
    p_fecha_tasa: fecha,
    p_tasa: tasa,
  });

  if (!response.success) {
    return {
      ok: false,
      error: rpcErrorMessage(response, "No se pudo registrar la tasa."),
      code: response.error?.code,
    };
  }

  revalidatePath("/tasas-cambio");
  return {
    ok: true,
    tasa: {
      fecha_tasa: response.data?.fecha_tasa ?? fecha,
      tasa_cambio: Number(response.data?.tasa_cambio ?? tasa),
      created_at: null,
    },
  };
}

export async function eliminaTasaCambioAction(
  fechaTasa: string,
): Promise<{ ok: true } | { ok: false; error: string; code?: string }> {
  if (!(await canManageTasas())) {
    return { ok: false, error: "Solo admin o gerente pueden eliminar tasas." };
  }

  const fecha = fechaTasa?.trim();
  if (!fecha) {
    return { ok: false, error: "La fecha es requerida." };
  }

  const response = await callDbProcedure<{
    fecha_tasa: string;
    eliminado: boolean;
  }>("elimina_tasa_cambio", {
    p_fecha_tasa: fecha,
  });

  if (!response.success) {
    return {
      ok: false,
      error: rpcErrorMessage(response, "No se pudo eliminar la tasa."),
      code: response.error?.code,
    };
  }

  revalidatePath("/tasas-cambio");
  return { ok: true };
}
