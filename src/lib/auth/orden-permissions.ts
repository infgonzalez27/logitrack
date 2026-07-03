import type { OrdenEstado } from "@/types/database";
import type { RolNombre } from "@/lib/auth/roles";

const STAFF_ROLES: RolNombre[] = ["admin", "gerente", "despachador"];

const TRANSICIONES_STAFF: Partial<
  Record<OrdenEstado, { next: OrdenEstado; label: string }[]>
> = {
  borrador: [
    { next: "lista_para_carga", label: "Marcar lista para carga" },
    { next: "anulada", label: "Anular" },
  ],
  lista_para_carga: [
    { next: "en_transito", label: "Despachar (en tránsito)" },
    { next: "borrador", label: "Volver a borrador" },
    { next: "anulada", label: "Anular" },
  ],
  en_transito: [{ next: "liquidada", label: "Liquidar" }],
};

export function isOrdenStaff(rol: RolNombre | null): boolean {
  return rol !== null && STAFF_ROLES.includes(rol);
}

export function canCreateOrden(rol: RolNombre | null): boolean {
  return isOrdenStaff(rol) || rol === "vendedor";
}

export function vendedorPuedeAnular(estado: OrdenEstado): boolean {
  return estado === "borrador" || estado === "lista_para_carga";
}

export function getOrdenEstadoTransiciones(
  rol: RolNombre | null,
  estadoActual: OrdenEstado,
  opts?: { esCreador?: boolean },
): { next: OrdenEstado; label: string }[] {
  if (isOrdenStaff(rol)) {
    return TRANSICIONES_STAFF[estadoActual] ?? [];
  }

  if (rol === "vendedor" && opts?.esCreador && vendedorPuedeAnular(estadoActual)) {
    return [{ next: "anulada", label: "Anular" }];
  }

  return [];
}
