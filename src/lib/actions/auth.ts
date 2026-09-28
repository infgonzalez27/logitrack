"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { registerUser } from "@/lib/auth/register-user";
import { canRegisterUser } from "@/lib/auth/usuario-permissions";
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
  const redirectTo = String(formData.get("redirect") ?? "/");

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
  const rolNombre = String(formData.get("rol_nombre") ?? "");
  const actorRol = getRoleNameFromProfile(await getCurrentProfile());
  if (!canRegisterUser(actorRol, rolNombre)) {
    return { error: "No tienes permiso para registrar usuarios con ese rol." };
  }

  const result = await registerUser({
    email: String(formData.get("email") ?? ""),
    password: String(formData.get("password") ?? ""),
    nombre_completo: String(formData.get("nombre_completo") ?? ""),
    telefono: String(formData.get("telefono") ?? ""),
    rol_nombre: rolNombre,
  });

  if (!result.ok) {
    return { error: result.error };
  }

  revalidatePath("/usuarios");
  return { success: true, userId: result.userId };
}
