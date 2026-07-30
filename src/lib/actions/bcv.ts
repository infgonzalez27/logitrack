"use server";

import { scrapeTasaUsdBcv } from "@/lib/bcv/scrape-tasa";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";

/** Contiene scrape BCV; no inserta — el usuario confirma en UI. */
export async function obtenerTasaBcvAction(): Promise<
  | { ok: true; tasa: number; fecha_tasa: string; fuente: string }
  | { ok: false; error: string }
> {
  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);
  if (rol !== "admin" && rol !== "gerente") {
    return { ok: false, error: "Solo admin o gerente pueden consultar BCV." };
  }

  const result = await scrapeTasaUsdBcv();
  if (!result.ok) {
    return result;
  }

  return {
    ok: true,
    tasa: result.data.tasa,
    fecha_tasa: result.data.fecha_tasa,
    fuente: result.data.fuente,
  };
}
