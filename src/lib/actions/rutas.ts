"use server";

import { revalidatePath } from "next/cache";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile, type RolNombre } from "@/lib/auth/roles";
import { callDbProcedure, rpcErrorMessage } from "@/lib/actions/db-rpc";
import { createClient } from "@/lib/supabase/server";
import type { DespachadorListaRpc, Ruta } from "@/types/database";

const ROLES_GESTION: RolNombre[] = ["admin", "gerente"];

async function canManageRutas(): Promise<boolean> {
  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);
  return !!rol && ROLES_GESTION.includes(rol);
}

export async function retornaListaRutasAction(): Promise<
  | { ok: true; rutas: Ruta[]; total: number }
  | { ok: false; error: string }
> {
  const response = await callDbProcedure<Ruta[]>("retorna_lista_rutas");

  if (!response.success) {
    return {
      ok: false,
      error: rpcErrorMessage(response, "No se pudieron consultar las rutas."),
    };
  }

  const rutas = Array.isArray(response.data) ? response.data : [];
  return { ok: true, rutas, total: rutas.length };
}

export async function retornaUsuariosDespachadoresAction(): Promise<
  | { ok: true; despachadores: DespachadorListaRpc[] }
  | { ok: false; error: string }
> {
  const response = await callDbProcedure<DespachadorListaRpc[]>(
    "retorna_usuarios_despachadores",
  );

  if (!response.success) {
    return {
      ok: false,
      error: rpcErrorMessage(
        response,
        "No se pudieron consultar los despachadores.",
      ),
    };
  }

  return {
    ok: true,
    despachadores: Array.isArray(response.data) ? response.data : [],
  };
}

export async function actualizaRegistroRutaAction(input: {
  id_ruta: string;
  nombre_ruta: string;
  descripcion_ruta?: string | null;
}): Promise<
  { ok: true; ruta: Ruta } | { ok: false; error: string; code?: string }
> {
  if (!(await canManageRutas())) {
    return { ok: false, error: "Solo admin o gerente pueden editar rutas." };
  }

  const id = input.id_ruta?.trim();
  const nombre = input.nombre_ruta?.trim();
  const descripcion = input.descripcion_ruta?.trim() || null;

  if (!id) {
    return { ok: false, error: "La ruta es requerida.", code: "PARAMETRO_INVALIDO" };
  }
  if (!nombre) {
    return {
      ok: false,
      error: "El nombre de la ruta es obligatorio.",
      code: "PARAMETRO_INVALIDO",
    };
  }

  const response = await callDbProcedure<Ruta>(
    "actualiza_registro_rutas_segun_uuid",
    {
      p_id_ruta: id,
      p_nombre_ruta: nombre,
      p_descripcion_ruta: descripcion,
    },
  );

  if (!response.success || !response.data) {
    return {
      ok: false,
      error: rpcErrorMessage(response, "No se pudo actualizar la ruta."),
      code: response.error?.code,
    };
  }

  revalidatePath("/rutas");
  revalidatePath("/clientes");
  return { ok: true, ruta: response.data };
}

/** Alta directa (RLS admin/gerente). No hay RPC de creación en INTEGRACION-RPC. */
export async function crearRutaAction(input: {
  nombre_ruta: string;
  descripcion_ruta?: string | null;
}): Promise<
  { ok: true; ruta: Ruta } | { ok: false; error: string; code?: string }
> {
  if (!(await canManageRutas())) {
    return { ok: false, error: "Solo admin o gerente pueden crear rutas." };
  }

  const nombre = input.nombre_ruta?.trim();
  const descripcion = input.descripcion_ruta?.trim() || null;
  if (!nombre) {
    return {
      ok: false,
      error: "El nombre de la ruta es obligatorio.",
      code: "PARAMETRO_INVALIDO",
    };
  }

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("rutas")
    .insert({
      nombre_ruta: nombre,
      descripcion_ruta: descripcion,
    })
    .select("id_ruta, nombre_ruta, descripcion_ruta, created_at")
    .single();

  if (error || !data) {
    return {
      ok: false,
      error: error?.message ?? "No se pudo crear la ruta.",
      code: "SQL_ERROR",
    };
  }

  revalidatePath("/rutas");
  revalidatePath("/clientes");
  return { ok: true, ruta: data as Ruta };
}
