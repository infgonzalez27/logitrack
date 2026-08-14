"use server";

import { cookies } from "next/headers";
import { revalidatePath } from "next/cache";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile, type RolNombre } from "@/lib/auth/roles";
import { callDbProcedure, rpcErrorMessage } from "@/lib/actions/db-rpc";
import { scrapeTasaUsdBcv } from "@/lib/bcv/scrape-tasa";
import { fechaHoyCaracas, fechaIsoDia } from "@/lib/dates";
import type { TasaCambio } from "@/types/database";

const ROLES_GESTION: RolNombre[] = ["admin", "gerente"];
const COOKIE_TASA = "lt_tasa_ensure";

function canManageTasas(): Promise<boolean> {
  return getCurrentProfile().then((profile) => {
    const rol = getRoleNameFromProfile(profile);
    return !!rol && ROLES_GESTION.includes(rol);
  });
}

function asTasaCambio(data: TasaCambio | null): TasaCambio | null {
  if (!data) return null;
  return {
    fecha_tasa: fechaIsoDia(data.fecha_tasa) ?? data.fecha_tasa,
    tasa_cambio: Number(data.tasa_cambio),
    created_at: data.created_at ?? null,
  };
}

async function insertaTasaInterna(
  fecha: string,
  tasa: number,
): Promise<{ ok: true; tasa: TasaCambio } | { ok: false; error: string; code?: string }> {
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
  revalidatePath("/", "layout");
  return {
    ok: true,
    tasa: {
      fecha_tasa: fechaIsoDia(response.data?.fecha_tasa) ?? fecha,
      tasa_cambio: Number(response.data?.tasa_cambio ?? tasa),
      created_at: null,
    },
  };
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

  return { ok: true, tasa: asTasaCambio(response.data) };
}

/**
 * Al entrar al sistema / una vez al día: consulta la última tasa.
 * Si no hay registro para la fecha de hoy (America/Caracas), la registra
 * con la tasa BCV del día.
 */
export async function ensureTasaCambioDelDia(): Promise<{
  ok: boolean;
  hoy: string;
  tasa: TasaCambio | null;
  registrada: boolean;
  error?: string;
}> {
  const hoy = fechaHoyCaracas();
  const jar = await cookies();
  const cookie = jar.get(COOKIE_TASA)?.value;

  if (cookie === `${hoy}:ok`) {
    return { ok: true, hoy, tasa: null, registrada: false };
  }

  const ultima = await retornaUltimaTasaCambioAction();
  if (!ultima.ok) {
    return { ok: false, hoy, tasa: null, registrada: false, error: ultima.error };
  }

  if (fechaIsoDia(ultima.tasa?.fecha_tasa) === hoy) {
    jar.set(COOKIE_TASA, `${hoy}:ok`, {
      path: "/",
      maxAge: 60 * 60 * 20,
      sameSite: "lax",
    });
    return { ok: true, hoy, tasa: ultima.tasa, registrada: false };
  }

  if (cookie === `${hoy}:fail`) {
    return {
      ok: false,
      hoy,
      tasa: ultima.tasa,
      registrada: false,
      error:
        "No hay tasa para hoy. Intenta de nuevo más tarde o regístrala en Tasas de cambio.",
    };
  }

  const bcv = await scrapeTasaUsdBcv();
  if (!bcv.ok) {
    jar.set(COOKIE_TASA, `${hoy}:fail`, {
      path: "/",
      maxAge: 60 * 30,
      sameSite: "lax",
    });
    return {
      ok: false,
      hoy,
      tasa: ultima.tasa,
      registrada: false,
      error: bcv.error,
    };
  }

  const inserted = await insertaTasaInterna(hoy, bcv.data.tasa);
  if (!inserted.ok) {
    if (inserted.code === "FECHA_TASA_DUPLICADA") {
      const refresh = await retornaUltimaTasaCambioAction();
      return {
        ok: true,
        hoy,
        tasa: refresh.ok ? refresh.tasa : ultima.tasa,
        registrada: false,
      };
    }
    jar.set(COOKIE_TASA, `${hoy}:fail`, {
      path: "/",
      maxAge: 60 * 30,
      sameSite: "lax",
    });
    return {
      ok: false,
      hoy,
      tasa: ultima.tasa,
      registrada: false,
      error: inserted.error,
    };
  }

  jar.set(COOKIE_TASA, `${hoy}:ok`, {
    path: "/",
    maxAge: 60 * 60 * 20,
    sameSite: "lax",
  });

  return { ok: true, hoy, tasa: inserted.tasa, registrada: true };
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

  return insertaTasaInterna(fecha, tasa);
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
