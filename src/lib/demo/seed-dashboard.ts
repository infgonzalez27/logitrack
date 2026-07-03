import type { SupabaseClient } from "@supabase/supabase-js";

export type SeedSummary = {
  ordenes: number;
  rendiciones: number;
  camiones: number;
  facturas: number;
  choferId: string | null;
};

export async function seedDemoDashboard(
  admin: SupabaseClient,
): Promise<{ ok: true; summary: SeedSummary } | { ok: false; error: string }> {
  const { data, error } = await admin.rpc("cargar_datos_demo_dashboard");

  if (error) {
    return { ok: false, error: error.message };
  }

  const summary = data as SeedSummary | null;
  if (!summary) {
    return { ok: false, error: "El SP no devolvió resumen." };
  }

  return { ok: true, summary };
}
