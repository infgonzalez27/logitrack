"use server";

import { revalidatePath } from "next/cache";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import { joinOne } from "@/lib/supabase/join";
import type {
  ActualizarPerfilUsuarioRpcInput,
  PerfilUsuarioEditar,
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

  const usuarios = (data ?? []) as UsuarioListaRpc[];
  const ids = usuarios.map((u) => u.id);

  if (!ids.length) {
    return { ok: true, usuarios: [] };
  }

  const { data: perfiles, error: perfilesError } = await createAdminClient()
    .from("perfiles_usuario")
    .select("id, roles(nombre)")
    .in("id", ids);

  if (perfilesError) {
    return { ok: false, error: perfilesError.message };
  }

  const rolPorId = new Map(
    (perfiles ?? []).map((p) => [p.id, joinOne(p.roles)?.nombre ?? null]),
  );

  return {
    ok: true,
    usuarios: usuarios.map((u) => ({
      ...u,
      rol_nombre: u.rol_nombre ?? rolPorId.get(u.id) ?? null,
    })),
  };
}

export async function obtenerPerfilUsuarioAction(
  id: string,
): Promise<
  | { ok: true; perfil: PerfilUsuarioEditar }
  | { ok: false; error: string }
> {
  const perfilId = id?.trim();
  if (!perfilId || !isUuid(perfilId)) {
    return { ok: false, error: "ID de perfil inválido." };
  }

  const supabase = createAdminClient();
  const { data, error } = await supabase
    .from("perfiles_usuario")
    .select("id, nombre_completo, telefono, activo, rol_id, roles(nombre)")
    .eq("id", perfilId)
    .single();

  if (error || !data) {
    return { ok: false, error: "Perfil de usuario no encontrado." };
  }

  const rol = joinOne(data.roles);

  if (!data.rol_id) {
    return { ok: false, error: "El perfil no tiene un rol asignado." };
  }

  return {
    ok: true,
    perfil: {
      id: data.id,
      nombre_completo: data.nombre_completo,
      telefono: data.telefono ?? "",
      activo: data.activo,
      rol_id: data.rol_id,
      rol_nombre: rol?.nombre ?? null,
    },
  };
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
  revalidatePath(`/usuarios/${input.id.trim()}`);
  return { ok: true };
}
