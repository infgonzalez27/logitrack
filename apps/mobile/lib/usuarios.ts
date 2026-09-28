import { supabase } from "./supabase";
import { joinOne } from "./join";
import { APP_ROLES, roleLabel } from "./auth";

const API_URL = (
  process.env.EXPO_PUBLIC_API_URL ?? "https://logitrack.informaticagonzalez.com"
).replace(/\/$/, "");

export type UsuarioListaItem = {
  id: string;
  nombre_completo: string;
  rol_nombre: string | null;
  activo?: boolean;
  telefono?: string | null;
};

export type PerfilUsuarioEditar = {
  id: string;
  nombre_completo: string;
  telefono: string;
  activo: boolean;
  rol_id: string;
  rol_nombre: string | null;
};

export type RolOption = { id: string; nombre: string; label: string };

async function authHeaders(): Promise<
  | { ok: true; headers: Record<string, string> }
  | { ok: false; error: string }
> {
  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token;
  if (!token) return { ok: false, error: "Sesión no disponible." };
  return {
    ok: true,
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
  };
}

async function postApi(
  path: string,
  payload: unknown,
  fallbackError: string,
): Promise<{ ok: true; body: Record<string, unknown> } | { ok: false; error: string }> {
  const auth = await authHeaders();
  if (!auth.ok) return auth;

  try {
    const res = await fetch(`${API_URL}${path}`, {
      method: "POST",
      headers: auth.headers,
      body: JSON.stringify(payload),
    });
    const body = (await res.json().catch(() => ({}))) as Record<string, unknown>;
    if (!res.ok || body.ok === false) {
      return {
        ok: false,
        error: typeof body.error === "string" ? body.error : `Error HTTP ${res.status}`,
      };
    }
    return { ok: true, body };
  } catch (err) {
    return { ok: false, error: err instanceof Error ? err.message : fallbackError };
  }
}

export async function listRoles(): Promise<
  { ok: true; roles: RolOption[] } | { ok: false; error: string }
> {
  const { data, error } = await supabase
    .from("roles")
    .select("id, nombre, descripcion")
    .order("nombre");

  if (error || !data?.length) {
    return {
      ok: true,
      roles: APP_ROLES.map((nombre) => ({
        id: nombre,
        nombre,
        label: roleLabel(nombre),
      })),
    };
  }

  return {
    ok: true,
    roles: data.map((r) => ({
      id: r.id,
      nombre: r.nombre,
      label: r.descripcion
        ? `${roleLabel(r.nombre)} — ${r.descripcion}`
        : roleLabel(r.nombre),
    })),
  };
}

export async function listUsuarios(params?: {
  nombre?: string;
  rol?: string;
}): Promise<
  { ok: true; usuarios: UsuarioListaItem[] } | { ok: false; error: string }
> {
  const { data, error } = await supabase.rpc(
    "retorna_lista_usuarios_segun_parametros",
    {
      p_nombre: params?.nombre?.trim() ?? "",
      p_rol: params?.rol?.trim() ?? "",
    },
  );

  if (!error && Array.isArray(data)) {
    const rows = data as {
      id: string;
      nombre_completo: string;
      rol_nombre?: string | null;
    }[];
    return {
      ok: true,
      usuarios: rows.map((u) => ({
        id: u.id,
        nombre_completo: u.nombre_completo,
        rol_nombre: u.rol_nombre ?? null,
      })),
    };
  }

  let query = supabase
    .from("perfiles_usuario")
    .select("id, nombre_completo, telefono, activo, roles(nombre)")
    .order("nombre_completo");

  const nombre = params?.nombre?.trim();
  if (nombre) {
    query = query.ilike("nombre_completo", `%${nombre}%`);
  }

  const { data: perfiles, error: perfilesError } = await query;
  if (perfilesError) {
    return {
      ok: false,
      error: error?.message ?? perfilesError.message,
    };
  }

  let usuarios: UsuarioListaItem[] = (perfiles ?? []).map((p) => {
    const rol = joinOne(
      p.roles as { nombre?: string } | { nombre?: string }[] | null,
    );
    return {
      id: p.id,
      nombre_completo: p.nombre_completo,
      rol_nombre: rol?.nombre ?? null,
      activo: p.activo,
      telefono: p.telefono,
    };
  });

  const rolFiltro = params?.rol?.trim().toLowerCase();
  if (rolFiltro) {
    usuarios = usuarios.filter(
      (u) => (u.rol_nombre ?? "").toLowerCase() === rolFiltro,
    );
  }

  return { ok: true, usuarios };
}

export async function getPerfilUsuario(
  id: string,
): Promise<
  { ok: true; perfil: PerfilUsuarioEditar } | { ok: false; error: string }
> {
  const perfilId = id.trim();
  if (!perfilId) return { ok: false, error: "ID de perfil inválido." };

  const { data, error } = await supabase
    .from("perfiles_usuario")
    .select("id, nombre_completo, telefono, activo, rol_id, roles(nombre)")
    .eq("id", perfilId)
    .maybeSingle();

  if (error || !data) {
    return { ok: false, error: error?.message ?? "Perfil no encontrado." };
  }
  if (!data.rol_id) {
    return { ok: false, error: "El perfil no tiene un rol asignado." };
  }

  const rol = joinOne(
    data.roles as { nombre?: string } | { nombre?: string }[] | null,
  );

  return {
    ok: true,
    perfil: {
      id: data.id,
      nombre_completo: data.nombre_completo,
      telefono: data.telefono ?? "",
      activo: Boolean(data.activo),
      rol_id: data.rol_id,
      rol_nombre: rol?.nombre ?? null,
    },
  };
}

export async function actualizarPerfilUsuario(input: {
  id: string;
  rol_id: string;
  nombre_completo: string;
  telefono: string;
  activo: boolean;
}): Promise<{ ok: true } | { ok: false; error: string }> {
  if (!input.id.trim()) return { ok: false, error: "ID de perfil requerido." };
  if (!input.rol_id.trim()) return { ok: false, error: "Selecciona un rol." };
  if (!input.nombre_completo.trim()) {
    return { ok: false, error: "El nombre completo es requerido." };
  }

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
    const upd = await supabase
      .from("perfiles_usuario")
      .update({
        rol_id: input.rol_id.trim(),
        nombre_completo: input.nombre_completo.trim(),
        telefono: input.telefono.trim(),
        activo: input.activo,
      })
      .eq("id", input.id.trim());
    if (upd.error) return { ok: false, error: upd.error.message };
    return { ok: true };
  }

  if (data === false) {
    return { ok: false, error: "No se encontró el perfil especificado." };
  }
  return { ok: true };
}

/** Alta de usuario en la empresa del usuario en sesión (servidor web). */
export async function registrarUsuario(input: {
  email: string;
  password: string;
  nombre_completo: string;
  telefono?: string;
  rol_nombre: string;
}): Promise<{ ok: true; userId?: string } | { ok: false; error: string }> {
  const email = input.email.trim().toLowerCase();
  const password = input.password;
  const nombre = input.nombre_completo.trim();
  const rol = input.rol_nombre.trim();

  if (!email || !password || !nombre || !rol) {
    return { ok: false, error: "Completa los campos obligatorios." };
  }
  if (password.length < 6) {
    return { ok: false, error: "La contraseña debe tener al menos 6 caracteres." };
  }

  const res = await postApi(
    "/api/mobile/usuarios",
    {
      email,
      password,
      nombre_completo: nombre,
      telefono: (input.telefono ?? "").trim(),
      rol_nombre: rol,
    },
    "No se pudo registrar.",
  );
  if (!res.ok) return res;
  return {
    ok: true,
    userId: typeof res.body.userId === "string" ? res.body.userId : undefined,
  };
}

/** Asigna una contraseña nueva a otro usuario, sin pedir la anterior. */
export async function cambiarContrasenaUsuario(input: {
  userId: string;
  password: string;
}): Promise<{ ok: true } | { ok: false; error: string }> {
  if (input.password.length < 6) {
    return { ok: false, error: "La contraseña debe tener al menos 6 caracteres." };
  }
  const res = await postApi(
    "/api/mobile/usuarios/contrasena",
    input,
    "No se pudo cambiar la contraseña.",
  );
  return res.ok ? { ok: true } : res;
}

