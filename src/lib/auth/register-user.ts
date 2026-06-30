import type { SupabaseClient } from "@supabase/supabase-js";
import { createAdminClient } from "@/lib/supabase/admin";
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

function isDuplicateUserError(error: unknown): boolean {
  if (!error || typeof error !== "object") return false;
  const record = error as Record<string, unknown>;
  const code = String(record.code ?? "");
  const msg = String(record.message ?? "").toLowerCase();
  return (
    code === "23505" ||
    code === "email_exists" ||
    msg.includes("already been registered") ||
    msg.includes("duplicate key") ||
    msg.includes("23505")
  );
}

async function findAuthUserIdByEmail(
  admin: SupabaseClient,
  email: string,
): Promise<string | null> {
  const normalized = email.toLowerCase();
  let page = 1;

  while (page <= 10) {
    const { data, error } = await admin.auth.admin.listUsers({
      page,
      perPage: 1000,
    });
    if (error || !data?.users?.length) break;

    const found = data.users.find((u) => u.email?.toLowerCase() === normalized);
    if (found) return found.id;

    if (data.users.length < 1000) break;
    page += 1;
  }

  return null;
}

export async function registerUser(
  input: RegisterInput,
  options?: { includeDebug?: boolean },
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
    const supabaseAdmin = createAdminClient();

    const { data: rolRow, error: rolError } = await supabaseAdmin
      .from("roles")
      .select("id")
      .eq("nombre", rol)
      .maybeSingle();

    console.info("[LogiTrack Register] rol lookup:", {
      rol,
      found: Boolean(rolRow),
      error: rolError ? serializeErrorForLog(rolError) : null,
    });

    if (rolError || !rolRow) {
      return { ok: false, error: `Rol "${rol}" no encontrado.` };
    }

    const { data: authData, error: createError } =
      await supabaseAdmin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: {
          nombre_completo: nombre,
          telefono: telefono || null,
        },
      });

    console.info("[LogiTrack Register] createUser:", {
      email,
      ok: !createError,
      userId: authData?.user?.id ?? null,
      error: createError ? serializeErrorForLog(createError) : null,
    });

    let userId: string;
    let createdNewAuthUser = true;

    if (createError) {
      if (!isDuplicateUserError(createError)) {
        return {
          ok: false,
          error: toDisplayError(createError),
          debug: options?.includeDebug
            ? { step: "createUser", error: serializeErrorForLog(createError) }
            : undefined,
        };
      }

      const existingId = await findAuthUserIdByEmail(supabaseAdmin, email);
      if (!existingId) {
        return {
          ok: false,
          error:
            "Este correo ya existe en Auth pero no aparece en el listado. Ejecuta el SQL de limpieza en assets/sql/reparar-auth-users-null-tokens.sql.",
          debug: options?.includeDebug ? { step: "duplicateOrphan" } : undefined,
        };
      }

      const { error: updateError } =
        await supabaseAdmin.auth.admin.updateUserById(existingId, {
          password,
          email_confirm: true,
          user_metadata: {
            nombre_completo: nombre,
            telefono: telefono || null,
          },
        });

      console.info("[LogiTrack Register] updateUser:", {
        existingId,
        ok: !updateError,
        error: updateError ? serializeErrorForLog(updateError) : null,
      });

      if (updateError) {
        return {
          ok: false,
          error: toDisplayError(updateError),
          debug: options?.includeDebug
            ? { step: "updateUser", error: serializeErrorForLog(updateError) }
            : undefined,
        };
      }

      userId = existingId;
      createdNewAuthUser = false;
    } else {
      userId = authData.user.id;
    }

    const { error: perfilError } = await supabaseAdmin
      .from("perfiles_usuario")
      .upsert(
        {
          id: userId,
          rol_id: rolRow.id,
          nombre_completo: nombre,
          telefono: telefono || null,
          activo: true,
        },
        { onConflict: "id" },
      );

    console.info("[LogiTrack Register] perfil upsert:", {
      userId,
      ok: !perfilError,
      error: perfilError ? serializeErrorForLog(perfilError) : null,
    });

    if (perfilError) {
      if (createdNewAuthUser) {
        await supabaseAdmin.auth.admin.deleteUser(userId);
        console.warn("[LogiTrack Register] rolled back auth user:", userId);
      }
      return {
        ok: false,
        error: toDisplayError(perfilError),
        debug: options?.includeDebug
          ? { step: "perfil", error: serializeErrorForLog(perfilError) }
          : undefined,
      };
    }

    console.info("[LogiTrack Register] success:", userId);
    return { ok: true, userId };
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
