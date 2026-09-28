import { normalizeRolNombre, type RolNombre } from "@/lib/auth/roles";

/** admin gestiona a cualquiera; gerente a cualquiera salvo admin. */
function canManageUser(
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

/** Quién puede asignar una contraseña nueva a otro usuario desde la UI. */
export function canResetUserPassword(
  actorRol: RolNombre | null,
  targetRolNombre: string | null,
): boolean {
  return canManageUser(actorRol, targetRolNombre);
}

/** Quién puede registrar un usuario nuevo con el rol indicado. */
export function canRegisterUser(
  actorRol: RolNombre | null,
  nuevoRolNombre: string | null,
): boolean {
  return canManageUser(actorRol, nuevoRolNombre);
}
