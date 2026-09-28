import type { StatusTone } from "@/src/ui/StatusBadge";

export interface OrdenStatusVisual {
  label: string;
  tone: StatusTone;
}

/** Mapeo glanceable de estados LogiTrack → badge semántico. */
export function mapOrdenStatus(estado: string): OrdenStatusVisual {
  switch (estado) {
    case "liquidada":
      return { label: "Entregado", tone: "success" };
    case "en_transito":
    case "despachada":
      return { label: "En tránsito", tone: "warning" };
    case "por_liquidar":
      return { label: "Por liquidar", tone: "info" };
    case "aprobada":
    case "lista_para_carga":
      return { label: "Aprobada", tone: "info" };
    case "anulada":
      return { label: "Anulada", tone: "danger" };
    case "devuelta":
      return { label: "Retrasado", tone: "danger" };
    case "borrador":
      return { label: "Borrador", tone: "neutral" };
    default:
      return { label: estado.replace(/_/g, " "), tone: "neutral" };
  }
}
