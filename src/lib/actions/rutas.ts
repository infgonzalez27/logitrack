"use server";

import { revalidatePath } from "next/cache";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile, type RolNombre } from "@/lib/auth/roles";
import { callDbProcedure, rpcErrorMessage } from "@/lib/actions/db-rpc";
import type { DespachadorListaRpc, Ruta } from "@/types/database";

const ROLES_GESTION: RolNombre[] = ["admin", "gerente"];

async function canManageRutas(): Promise<boolean> {
  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);
  return !!rol && ROLES_GESTION.includes(rol);
}

/** INTEGRACION-RPC §2.12 — `retorna_lista_rutas` */
export async function retornaListaRutasAction(): Promise<
  | { ok: true; rutas: Ruta[]; total_registros: number }
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
  return {
    ok: true,
    rutas,
    total_registros: response.total_registros ?? rutas.length,
  };
}

/** INTEGRACION-RPC §2.13 — `retorna_usuarios_despachadores` */
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

/** INTEGRACION-RPC §2.14 — `actualiza_registro_rutas_segun_uuid` */
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
    return {
      ok: false,
      error: "La ruta es requerida.",
      code: "PARAMETRO_INVALIDO",
    };
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
