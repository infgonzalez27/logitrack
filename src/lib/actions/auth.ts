"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import { toDisplayError } from "@/lib/errors";

export type AuthFormState = {
  error?: string;
  success?: boolean;
  userId?: string;
} | null;

export async function loginAction(
  _prev: AuthFormState,
  formData: FormData,
): Promise<AuthFormState> {
  const email = String(formData.get("email") ?? "").trim();
  const password = String(formData.get("password") ?? "");
  const redirectTo = String(formData.get("redirect") ?? "/ordenes");

  if (!email || !password) {
    return { error: "Ingresa correo y contraseña." };
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword({ email, password });

  if (error) {
    return { error: toDisplayError(error) };
  }

  revalidatePath("/", "layout");
  return { success: true };
}

export async function logoutAction() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect("/login");
}

export async function registerUserAction(
  _prev: AuthFormState,
  formData: FormData,
): Promise<AuthFormState> {
  const email = String(formData.get("email") ?? "").trim();
  const password = String(formData.get("password") ?? "");
  const nombre = String(formData.get("nombre_completo") ?? "").trim();
  const telefono = String(formData.get("telefono") ?? "").trim();
  const rol = String(formData.get("rol_nombre") ?? "").trim();

  if (!email || !password || !nombre || !rol) {
    return { error: "Completa los campos obligatorios." };
  }

  try {
    const supabaseAdmin = createAdminClient();
    const { data, error } = await supabaseAdmin.rpc("registra_nuevo_usuario", {
      p_email: email,
      p_password: password,
      p_nombre_completo: nombre,
      p_telefono: telefono,
      p_rol_nombre: rol,
    });

    if (error) {
      return { error: toDisplayError(error) };
    }

    revalidatePath("/usuarios");
    return { success: true, userId: typeof data === "string" ? data : undefined };
  } catch (err) {
    return { error: toDisplayError(err) };
  }
}
