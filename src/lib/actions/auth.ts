"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { registerUser } from "@/lib/auth/register-user";
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
  const result = await registerUser({
    email: String(formData.get("email") ?? ""),
    password: String(formData.get("password") ?? ""),
    nombre_completo: String(formData.get("nombre_completo") ?? ""),
    telefono: String(formData.get("telefono") ?? ""),
    rol_nombre: String(formData.get("rol_nombre") ?? ""),
  });

  if (!result.ok) {
    return { error: result.error };
  }

  revalidatePath("/usuarios");
  return { success: true, userId: result.userId };
}
