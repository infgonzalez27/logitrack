"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import type {
  ActualizarPerfilUsuarioRpcInput,
  UsuarioListaRpc,
} from "@/types/database";

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function isUuid(value: string): boolean {
  return UUID_RE.test(value.trim());
}

export async function listarUsuariosAction(params?: {
  nombre?: string;
  rol?: string;
}): Promise<
  | { ok: true; usuarios: UsuarioListaRpc[] }
  | { ok: false; error: string }
> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc(
    "retorna_lista_usuarios_segun_parametros",
    {
      p_nombre: params?.nombre?.trim() ?? "",
      p_rol: params?.rol?.trim() ?? "",
    },
  );

  if (error) {
    return { ok: false, error: error.message };
  }

  return { ok: true, usuarios: (data ?? []) as UsuarioListaRpc[] };
}

function validateActualizarPerfilInput(
  input: ActualizarPerfilUsuarioRpcInput,
): string | null {
  if (!input.id?.trim()) {
    return "ID de perfil requerido.";
  }
  if (!isUuid(input.id)) {
    return "ID de perfil inválido.";
  }
  if (!input.rol_id?.trim()) {
    return "Selecciona un rol.";
  }
  if (!isUuid(input.rol_id)) {
    return "Rol inválido.";
  }
  if (!input.nombre_completo?.trim()) {
    return "El nombre completo es requerido.";
  }
  return null;
}

export async function actualizarPerfilUsuarioAction(
  input: ActualizarPerfilUsuarioRpcInput,
): Promise<{ ok: true } | { ok: false; error: string }> {
  const validationError = validateActualizarPerfilInput(input);
  if (validationError) {
    return { ok: false, error: validationError };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc(
    "actualizar_registro_perfil_usuarios_segun_id",
    {
      p_id: input.id.trim(),
      p_rol_id: input.rol_id.trim(),
      p_nombre_completo: input.nombre_completo.trim(),
      p_telefono: input.telefono.trim(),
      p_activo: input.activo,
    },
  );

  if (error) {
    return { ok: false, error: error.message };
  }

  if (!data) {
    return { ok: false, error: "No se encontró el perfil de usuario especificado." };
  }

  revalidatePath("/usuarios");
  return { ok: true };
}
