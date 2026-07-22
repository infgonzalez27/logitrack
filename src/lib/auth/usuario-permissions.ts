import { normalizeRolNombre, type RolNombre } from "@/lib/auth/roles";

/** Quién puede asignar una contraseña nueva a otro usuario desde la UI. */
export function canResetUserPassword(
  actorRol: RolNombre | null,
  targetRolNombre: string | null,
): boolean {
  if (!actorRol) return false;

  const target = normalizeRolNombre(targetRolNombre);

  if (actorRol === "admin") return true;

  if (actorRol === "gerente") {
    return target !== null && target !== "admin";
  }

  return false;
}
