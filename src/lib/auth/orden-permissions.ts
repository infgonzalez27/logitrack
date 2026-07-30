import type { OrdenEstado } from "@/types/database";
import type { RolNombre } from "@/lib/auth/roles";

const STAFF_ROLES: RolNombre[] = ["admin", "gerente", "despachador"];
const APROBADORES: RolNombre[] = ["admin", "gerente"];
const DESPACHADORES: RolNombre[] = ["admin", "gerente", "despachador"];
const ENTREGA_ROLES: RolNombre[] = ["admin", "gerente", "despachador", "chofer"];

export const ORDEN_ESTADOS_VALIDOS: OrdenEstado[] = [
  "borrador",
  "aprobada",
  "lista_para_carga", // legado (pre-migración)
  "en_transito",
  "por_liquidar",
  "liquidada",
  "anulada",
];

/**
 * Transiciones de UI hacia acciones con RPC dedicado (DB-002..006).
 */
const TRANSICIONES_UI: Partial<
  Record<OrdenEstado, { next: OrdenEstado; label: string; rpc: string }[]>
> = {
  borrador: [
    {
      next: "aprobada",
      label: "Aprobar orden",
      rpc: "aprobar_orden_distribucion",
    },
    { next: "anulada", label: "Anular", rpc: "anular_orden_distribucion" },
  ],
  aprobada: [
    {
      next: "en_transito",
      label: "Cargar y despachar",
      rpc: "cargar_inventario_movil",
    },
    { next: "anulada", label: "Anular", rpc: "anular_orden_distribucion" },
  ],
  // Compatibilidad si la BD aún tiene lista_para_carga
  lista_para_carga: [
    {
      next: "en_transito",
      label: "Cargar y despachar",
      rpc: "cargar_inventario_movil",
    },
    { next: "anulada", label: "Anular", rpc: "anular_orden_distribucion" },
  ],
  en_transito: [],
  por_liquidar: [
    {
      next: "liquidada",
      label: "Liquidar (recaudación aprobada)",
      rpc: "liquidar_orden_distribucion",
    },
  ],
  liquidada: [],
  anulada: [],
};

const LABELS: Record<OrdenEstado, string> = {
  borrador: "Borrador",
  aprobada: "Aprobada",
  lista_para_carga: "Lista para carga",
  en_transito: "En tránsito",
  por_liquidar: "Por liquidar",
  liquidada: "Liquidada",
  anulada: "Anulada",
};

export function esEstadoOrdenValido(estado: string): estado is OrdenEstado {
  return ORDEN_ESTADOS_VALIDOS.includes(estado as OrdenEstado);
}

export function labelOrdenEstadoValue(estado: OrdenEstado): string {
  return LABELS[estado] ?? estado;
}

export function isOrdenStaff(rol: RolNombre | null): boolean {
  return rol !== null && STAFF_ROLES.includes(rol);
}

export function canCreateOrden(rol: RolNombre | null): boolean {
  return isOrdenStaff(rol) || rol === "vendedor";
}

/** Editar cabecera/detalle solo en borrador (RPC actualiza_orden_…_correlativo). */
export function canEditarOrdenBorrador(
  rol: RolNombre | null,
  estado: OrdenEstado,
  opts?: { esCreador?: boolean },
): boolean {
  if (estado !== "borrador") return false;
  if (isOrdenStaff(rol)) return true;
  if (rol === "vendedor") return !!opts?.esCreador;
  return false;
}

export function canRegistrarEntrega(rol: RolNombre | null): boolean {
  return rol !== null && ENTREGA_ROLES.includes(rol);
}

export function canRegistrarContenedores(rol: RolNombre | null): boolean {
  return rol !== null && DESPACHADORES.includes(rol);
}

export function canLiquidarOrden(rol: RolNombre | null): boolean {
  return rol !== null && APROBADORES.includes(rol);
}

export function vendedorPuedeAnular(estado: OrdenEstado): boolean {
  return estado === "borrador";
}

function puedeEjecutarTransicion(
  rol: RolNombre | null,
  estadoActual: OrdenEstado,
  estadoDestino: OrdenEstado,
  opts?: { esCreador?: boolean },
): boolean {
  if (!rol) return false;

  if (estadoDestino === "aprobada") {
    return APROBADORES.includes(rol);
  }

  if (estadoDestino === "en_transito") {
    return DESPACHADORES.includes(rol);
  }

  if (estadoDestino === "liquidada") {
    return canLiquidarOrden(rol);
  }

  if (estadoDestino === "anulada") {
    if (APROBADORES.includes(rol) || rol === "despachador") {
      return estadoActual === "borrador" || estadoActual === "aprobada" || estadoActual === "lista_para_carga";
    }
    if (rol === "vendedor" && opts?.esCreador) {
      return vendedorPuedeAnular(estadoActual);
    }
  }

  return false;
}

export function puedeCambiarEstadoOrden(
  rol: RolNombre | null,
  estadoActual: OrdenEstado,
  estadoDestino: OrdenEstado,
  opts?: { esCreador?: boolean },
): boolean {
  const permitidas = TRANSICIONES_UI[estadoActual] ?? [];
  if (!permitidas.some((t) => t.next === estadoDestino)) {
    return false;
  }
  return puedeEjecutarTransicion(rol, estadoActual, estadoDestino, opts);
}

export function getOrdenEstadoTransiciones(
  rol: RolNombre | null,
  estadoActual: OrdenEstado,
  opts?: { esCreador?: boolean },
): { next: OrdenEstado; label: string; rpc: string }[] {
  const destinos = TRANSICIONES_UI[estadoActual] ?? [];

  return destinos.filter((destino) =>
    puedeCambiarEstadoOrden(rol, estadoActual, destino.next, opts),
  );
}
