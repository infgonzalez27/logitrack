import type { OrdenEstado } from "@/types/database";
import type { RolNombre } from "@/lib/auth/roles";

const STAFF_ROLES: RolNombre[] = ["admin", "gerente", "despachador"];

export const ORDEN_ESTADOS_VALIDOS: OrdenEstado[] = [
  "borrador",
  "lista_para_carga",
  "en_transito",
  "liquidada",
  "anulada",
];

/** Transiciones permitidas por el SP actualizar_estado_orden_distribucion. */
const TRANSICIONES_SP: Record<OrdenEstado, OrdenEstado[]> = {
  borrador: ["lista_para_carga", "anulada"],
  lista_para_carga: ["en_transito", "borrador", "anulada"],
  en_transito: ["liquidada", "anulada"],
  liquidada: [],
  anulada: [],
};

const LABELS: Record<OrdenEstado, string> = {
  borrador: "Borrador",
  lista_para_carga: "Lista para carga",
  en_transito: "En tránsito",
  liquidada: "Liquidada",
  anulada: "Anulada",
};

const ACCION_LABELS: Partial<Record<OrdenEstado, string>> = {
  lista_para_carga: "Marcar lista para carga",
  en_transito: "Despachar (en tránsito)",
  borrador: "Volver a borrador",
  liquidada: "Liquidar",
  anulada: "Anular",
};

export function esEstadoOrdenValido(estado: string): estado is OrdenEstado {
  return ORDEN_ESTADOS_VALIDOS.includes(estado as OrdenEstado);
}

export function transicionPermitidaPorSp(
  estadoActual: OrdenEstado,
  estadoDestino: OrdenEstado,
): boolean {
  return TRANSICIONES_SP[estadoActual]?.includes(estadoDestino) ?? false;
}

export function isOrdenStaff(rol: RolNombre | null): boolean {
  return rol !== null && STAFF_ROLES.includes(rol);
}

export function canCreateOrden(rol: RolNombre | null): boolean {
  return isOrdenStaff(rol) || rol === "vendedor";
}

export function vendedorPuedeAnular(estado: OrdenEstado): boolean {
  return estado === "borrador" || estado === "lista_para_carga";
}

export function puedeCambiarEstadoOrden(
  rol: RolNombre | null,
  estadoActual: OrdenEstado,
  estadoDestino: OrdenEstado,
  opts?: { esCreador?: boolean },
): boolean {
  if (!transicionPermitidaPorSp(estadoActual, estadoDestino)) {
    return false;
  }

  if (isOrdenStaff(rol)) {
    return true;
  }

  if (rol === "vendedor" && opts?.esCreador) {
    return estadoDestino === "anulada" && vendedorPuedeAnular(estadoActual);
  }

  return false;
}

function labelTransicion(estadoDestino: OrdenEstado): string {
  return ACCION_LABELS[estadoDestino] ?? LABELS[estadoDestino];
}

export function getOrdenEstadoTransiciones(
  rol: RolNombre | null,
  estadoActual: OrdenEstado,
  opts?: { esCreador?: boolean },
): { next: OrdenEstado; label: string }[] {
  const destinos = TRANSICIONES_SP[estadoActual] ?? [];

  return destinos
    .filter((destino) =>
      puedeCambiarEstadoOrden(rol, estadoActual, destino, opts),
    )
    .map((next) => ({
      next,
      label: labelTransicion(next),
    }));
}
