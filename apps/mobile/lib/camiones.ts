import { supabase } from "./supabase";

export type CamionEstado =
  | "disponible"
  | "en_ruta"
  | "mantenimiento"
  | "inactivo";

export const CAMION_ESTADOS: { value: CamionEstado; label: string }[] = [
  { value: "disponible", label: "Disponible" },
  { value: "en_ruta", label: "En ruta" },
  { value: "mantenimiento", label: "Mantenimiento" },
  { value: "inactivo", label: "Inactivo" },
];

export type Camion = {
  id: string;
  placa: string;
  modelo: string;
  capacidad_kg: number;
  volumen_m3: number | null;
  estado: CamionEstado;
};

export function labelEstadoCamion(estado: string): string {
  return CAMION_ESTADOS.find((e) => e.value === estado)?.label ?? estado;
}

export async function listCamiones(): Promise<
  { ok: true; camiones: Camion[] } | { ok: false; error: string }
> {
  const { data, error } = await supabase
    .from("camiones")
    .select("id, placa, modelo, capacidad_kg, volumen_m3, estado")
    .order("placa");

  if (error) return { ok: false, error: error.message };
  return { ok: true, camiones: (data ?? []) as Camion[] };
}

export async function getCamion(
  id: string,
): Promise<{ ok: true; camion: Camion } | { ok: false; error: string }> {
  const { data, error } = await supabase
    .from("camiones")
    .select("id, placa, modelo, capacidad_kg, volumen_m3, estado")
    .eq("id", id)
    .maybeSingle();

  if (error) return { ok: false, error: error.message };
  if (!data) return { ok: false, error: "Camión no encontrado." };
  return { ok: true, camion: data as Camion };
}

export async function createCamion(input: {
  placa: string;
  modelo: string;
  capacidad_kg: number;
  volumen_m3?: number | null;
}): Promise<{ ok: true; id: string } | { ok: false; error: string }> {
  const placa = input.placa.trim();
  const modelo = input.modelo.trim();
  if (!placa) return { ok: false, error: "La placa es requerida." };
  if (!modelo) return { ok: false, error: "El modelo es requerido." };
  if (!Number.isFinite(input.capacidad_kg) || input.capacidad_kg < 0) {
    return { ok: false, error: "La capacidad (kg) es inválida." };
  }

  const { data, error } = await supabase
    .from("camiones")
    .insert({
      placa,
      modelo,
      capacidad_kg: input.capacidad_kg,
      volumen_m3:
        input.volumen_m3 != null && Number.isFinite(input.volumen_m3)
          ? input.volumen_m3
          : null,
      estado: "disponible",
    })
    .select("id")
    .single();

  if (error) return { ok: false, error: error.message };
  return { ok: true, id: data.id as string };
}

export async function updateCamion(input: {
  id: string;
  placa: string;
  modelo: string;
  capacidad_kg: number;
  volumen_m3?: number | null;
  estado: CamionEstado;
}): Promise<{ ok: true } | { ok: false; error: string }> {
  const placa = input.placa.trim();
  const modelo = input.modelo.trim();
  if (!placa) return { ok: false, error: "La placa es requerida." };
  if (!modelo) return { ok: false, error: "El modelo es requerido." };

  const { error } = await supabase
    .from("camiones")
    .update({
      placa,
      modelo,
      capacidad_kg: input.capacidad_kg,
      volumen_m3:
        input.volumen_m3 != null && Number.isFinite(input.volumen_m3)
          ? input.volumen_m3
          : null,
      estado: input.estado,
    })
    .eq("id", input.id);

  if (error) return { ok: false, error: error.message };
  return { ok: true };
}
