import { createCentralAdminClient } from "@/lib/supabase/admin";
import { getTenantForCurrentUser } from "@/lib/supabase/tenant-context";
import { syncUserToTenant } from "@/lib/tenants/bootstrap";
import { serializeErrorForLog } from "@/lib/debug";
import { toDisplayError } from "@/lib/errors";

export type RegisterInput = {
  email: string;
  password: string;
  nombre_completo: string;
  telefono?: string;
  rol_nombre: string;
};

export type RegisterResult =
  | { ok: true; userId: string }
  | { ok: false; error: string; debug?: Record<string, unknown> };

export type RegisterTenant = { empresaId: string; projectRef: string };

type RegisterOptions = {
  includeDebug?: boolean;
  /** Empresa destino; si se omite se usa la del usuario que registra. */
  tenant?: RegisterTenant | null;
};

/** Respuesta JSONB del SP `registra_nuevo_usuario` en PostgreSQL. */
type RegistraUsuarioRpcResult = {
  success: boolean;
  message?: string;
  user_id?: string;
};

export async function registerUser(
  input: RegisterInput,
  options?: RegisterOptions,
): Promise<RegisterResult> {
  const email = input.email.trim();
  const password = input.password;
  const nombre = input.nombre_completo.trim();
  const telefono = (input.telefono ?? "").trim();
  const rol = input.rol_nombre.trim();

  if (!email || !password || !nombre || !rol) {
    return { ok: false, error: "Completa los campos obligatorios." };
  }

  if (password.length < 6) {
    return { ok: false, error: "La contraseña debe tener al menos 6 caracteres." };
  }

  try {
    const tenant =
      options?.tenant !== undefined
        ? options.tenant
        : await getTenantForCurrentUser();

    const normalized = { email, password, nombre_completo: nombre, telefono, rol_nombre: rol };
    return tenant
      ? await registerTenantUser(normalized, tenant, options)
      : await registerCentralUser(normalized, options);
  } catch (err) {
    console.error("[LogiTrack Register] exception:", serializeErrorForLog(err));
    return {
      ok: false,
      error: toDisplayError(err),
      debug: options?.includeDebug
        ? { step: "exception", error: serializeErrorForLog(err) }
        : undefined,
    };
  }
}

/** Usuarios sin empresa (plataforma): cuenta + perfil en la BD Central. */
async function registerCentralUser(
  input: Required<RegisterInput>,
  options?: RegisterOptions,
): Promise<RegisterResult> {
  const supabaseAdmin = createCentralAdminClient();

  const { data, error } = await supabaseAdmin.rpc("registra_nuevo_usuario", {
    p_email: input.email,
    p_password: input.password,
    p_nombre_completo: input.nombre_completo,
    p_telefono: input.telefono,
    p_rol_nombre: input.rol_nombre,
  });

  console.info("[LogiTrack Register] rpc registra_nuevo_usuario:", {
    email: input.email,
    ok: !error,
    data,
    error: error ? serializeErrorForLog(error) : null,
  });

  if (error) {
    return {
      ok: false,
      error: toDisplayError(error),
      debug: options?.includeDebug
        ? { step: "rpc", error: serializeErrorForLog(error) }
        : undefined,
    };
  }

  const result = data as RegistraUsuarioRpcResult | null;
  if (!result?.success || !result.user_id) {
    return {
      ok: false,
      error: result?.message ?? "No se pudo registrar el usuario.",
      debug: options?.includeDebug ? { step: "rpc_result", data: result } : undefined,
    };
  }

  return { ok: true, userId: result.user_id };
}

/**
 * Usuarios de una empresa (INTEGRACION-RPC, registro en 3 fases):
 * 1) cuenta en auth.users de Central (login), 2) usuarios_empresas (enrutamiento),
 * 3) auth.users + perfiles_usuario del tenant con el mismo UUID.
 * No deja perfil en Central; si una fase falla, se borra la cuenta creada.
 */
async function registerTenantUser(
  input: Required<RegisterInput>,
  tenant: RegisterTenant,
  options?: RegisterOptions,
): Promise<RegisterResult> {
  const central = createCentralAdminClient();

  const { data: created, error: createError } = await central.auth.admin.createUser({
    email: input.email,
    password: input.password,
    email_confirm: true,
    user_metadata: { nombre_completo: input.nombre_completo, telefono: input.telefono },
  });
  const userId = created?.user?.id;
  if (createError || !userId) {
    return {
      ok: false,
      error: toDisplayError(createError ?? new Error("No se pudo crear la cuenta.")),
      debug: options?.includeDebug
        ? { step: "central_auth", error: serializeErrorForLog(createError) }
        : undefined,
    };
  }

  const fallar = async (step: string, err: unknown): Promise<RegisterResult> => {
    console.error(`[LogiTrack Register] ${step}:`, serializeErrorForLog(err));
    await central.auth.admin.deleteUser(userId);
    return {
      ok: false,
      error: toDisplayError(err),
      debug: options?.includeDebug
        ? { step, error: serializeErrorForLog(err) }
        : undefined,
    };
  };

  // El trigger crear_perfil_usuario_nuevo de Central crea un perfil por cada cuenta nueva.
  const { error: perfilError } = await central
    .from("perfiles_usuario")
    .delete()
    .eq("id", userId);
  if (perfilError) return fallar("central_perfil", perfilError);

  const { data: asignarData, error: asignarError } = await central.rpc(
    "asignar_usuario_empresa",
    { p_user_id: userId, p_empresa_id: tenant.empresaId, p_rol: input.rol_nombre },
  );
  const asignar = asignarData as
    | { success?: boolean; error?: { message?: string } | null }
    | null;
  if (asignarError || !asignar?.success) {
    return fallar(
      "asignar_empresa",
      asignarError ??
        new Error(
          `No se pudo asignar a la empresa: ${asignar?.error?.message ?? "error desconocido"}`,
        ),
    );
  }

  try {
    await syncUserToTenant(tenant.projectRef, {
      id: userId,
      email: input.email,
      rol_nombre: input.rol_nombre,
      nombre_completo: input.nombre_completo,
      telefono: input.telefono,
    });
  } catch (err) {
    return fallar("tenant", err);
  }

  return { ok: true, userId };
}
