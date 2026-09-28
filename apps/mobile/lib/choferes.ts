import { supabase } from "./supabase";
import { unwrapRpcData } from "./rpc";

export type ChoferEstado =
  | "disponible"
  | "en_ruta"
  | "libre"
  | "suspendido";

export const CHOFER_ESTADOS: { value: ChoferEstado; label: string }[] = [
  { value: "disponible", label: "Disponible" },
  { value: "en_ruta", label: "En ruta" },
  { value: "libre", label: "Libre" },
  { value: "suspendido", label: "Suspendido" },
];

export type Chofer = {
  perfil_id: string;
  cedula_licencia: string;
  movil1: string | null;
  estado: ChoferEstado;
  nombre_completo?: string | null;
  telefono?: string | null;
};

export type PerfilChoferOption = {
  id: string;
  nombre_completo: string;
};

export function labelEstadoChofer(estado: string): string {
  return CHOFER_ESTADOS.find((e) => e.value === estado)?.label ?? estado;
}

export async function listChoferes(): Promise<
  { ok: true; choferes: Chofer[] } | { ok: false; error: string }
> {
  const { data, error } = await supabase
    .from("choferes")
    .select(
      "perfil_id, cedula_licencia, movil1, estado, perfiles_usuario(nombre_completo, telefono)",
    )
    .order("created_at", { ascending: false });

  if (error) return { ok: false, error: error.message };

  const choferes: Chofer[] = (data ?? []).map((row: Record<string, unknown>) => {
    const perfil = row.perfiles_usuario as
      | { nombre_completo?: string; telefono?: string | null }
      | { nombre_completo?: string; telefono?: string | null }[]
      | null;
    const p = Array.isArray(perfil) ? perfil[0] : perfil;
    return {
      perfil_id: String(row.perfil_id),
      cedula_licencia: String(row.cedula_licencia ?? ""),
      movil1: (row.movil1 as string) ?? null,
      estado: row.estado as ChoferEstado,
      nombre_completo: p?.nombre_completo ?? null,
      telefono: p?.telefono ?? null,
    };
  });

  return { ok: true, choferes };
}

export async function getChofer(
  perfilId: string,
): Promise<{ ok: true; chofer: Chofer } | { ok: false; error: string }> {
  const { data, error } = await supabase
    .from("choferes")
    .select(
      "perfil_id, cedula_licencia, movil1, estado, perfiles_usuario(nombre_completo, telefono)",
    )
    .eq("perfil_id", perfilId)
    .maybeSingle();

  if (error) return { ok: false, error: error.message };
  if (!data) return { ok: false, error: "Chofer no encontrado." };

  const row = data as Record<string, unknown>;
  const perfil = row.perfiles_usuario as
    | { nombre_completo?: string; telefono?: string | null }
    | { nombre_completo?: string; telefono?: string | null }[]
    | null;
  const p = Array.isArray(perfil) ? perfil[0] : perfil;

  return {
    ok: true,
    chofer: {
      perfil_id: String(row.perfil_id),
      cedula_licencia: String(row.cedula_licencia ?? ""),
      movil1: (row.movil1 as string) ?? null,
      estado: row.estado as ChoferEstado,
      nombre_completo: p?.nombre_completo ?? null,
      telefono: p?.telefono ?? null,
    },
  };
}

/** Perfiles con rol chofer que aún no tienen ficha en `choferes`. */
export async function listPerfilesChoferDisponibles(): Promise<
  { ok: true; perfiles: PerfilChoferOption[] } | { ok: false; error: string }
> {
  const { data, error } = await supabase.rpc(
    "retorna_lista_usuarios_segun_parametros",
    { p_nombre: "", p_rol: "chofer" },
  );

  if (error) return { ok: false, error: error.message };

  const usuarios =
    unwrapRpcData<{ id: string; nombre_completo: string }[]>(data) ??
    (Array.isArray(data) ? data : []);

  const { data: fichas } = await supabase.from("choferes").select("perfil_id");
  const usados = new Set((fichas ?? []).map((f) => f.perfil_id));

  return {
    ok: true,
    perfiles: (usuarios as { id: string; nombre_completo: string }[])
      .filter((u) => u.id && !usados.has(u.id))
      .map((u) => ({
        id: u.id,
        nombre_completo: u.nombre_completo || "Sin nombre",
      })),
  };
}

export async function createChofer(input: {
  perfil_id: string;
  cedula_licencia: string;
  movil1?: string | null;
  estado?: ChoferEstado;
}): Promise<{ ok: true; id: string } | { ok: false; error: string }> {
  const perfilId = input.perfil_id.trim();
  const licencia = input.cedula_licencia.trim();
  if (!perfilId) return { ok: false, error: "Selecciona un perfil de chofer." };
  if (!licencia) return { ok: false, error: "La cédula/licencia es requerida." };

  const { error } = await supabase.from("choferes").insert({
    perfil_id: perfilId,
    cedula_licencia: licencia,
    movil1: input.movil1?.trim() || null,
    estado: input.estado ?? "disponible",
  });

  if (error) return { ok: false, error: error.message };
  return { ok: true, id: perfilId };
}

export async function updateChofer(input: {
  perfil_id: string;
  cedula_licencia: string;
  movil1?: string | null;
  estado: ChoferEstado;
}): Promise<{ ok: true } | { ok: false; error: string }> {
  const licencia = input.cedula_licencia.trim();
  if (!licencia) return { ok: false, error: "La cédula/licencia es requerida." };

  const { error } = await supabase
    .from("choferes")
    .update({
      cedula_licencia: licencia,
      movil1: input.movil1?.trim() || null,
      estado: input.estado,
    })
    .eq("perfil_id", input.perfil_id);

  if (error) return { ok: false, error: error.message };
  return { ok: true };
}
