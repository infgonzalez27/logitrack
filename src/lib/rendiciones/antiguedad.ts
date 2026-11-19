import type {
  OrdenPorLiquidarDetalle,
  TramoAntiguedadKey,
} from "@/types/database";

export type TramoAntiguedadConfig = {
  key: TramoAntiguedadKey;
  orden: number;
  label: string;
  rangoTexto: string;
  badgeTone: "neutral" | "warning" | "danger";
};

/** Orden exacto definido en la especificación de Cobranzas > Órdenes por liquidar. */
export const TRAMOS_ANTIGUEDAD: readonly TramoAntiguedadConfig[] = [
  {
    key: "menor_7",
    orden: 1,
    label: "Vencidas menores de 7 días",
    rangoTexto: "0 a 6 días",
    badgeTone: "neutral",
  },
  {
    key: "entre_7_15",
    orden: 2,
    label: "Entre 7 y 15 días",
    rangoTexto: "7 a 15 días",
    badgeTone: "neutral",
  },
  {
    key: "entre_16_30",
    orden: 3,
    label: "Entre 16 y 30 días",
    rangoTexto: "16 a 30 días",
    badgeTone: "warning",
  },
  {
    key: "entre_31_45",
    orden: 4,
    label: "Entre 31 y 45 días",
    rangoTexto: "31 a 45 días",
    badgeTone: "warning",
  },
  {
    key: "entre_46_90",
    orden: 5,
    label: "Entre 46 y 90 días",
    rangoTexto: "46 a 90 días",
    badgeTone: "danger",
  },
  {
    key: "mayor_90",
    orden: 6,
    label: "Vencidas mayores a 90 días",
    rangoTexto: "Más de 90 días",
    badgeTone: "danger",
  },
] as const;

export type GrupoTramoAntiguedad = TramoAntiguedadConfig & {
  ordenes: OrdenPorLiquidarDetalle[];
  totalOrdenes: number;
  totalMonto: number;
};

export function agruparPorTramoAntiguedad(
  items: OrdenPorLiquidarDetalle[],
): GrupoTramoAntiguedad[] {
  const porTramo = new Map<TramoAntiguedadKey, OrdenPorLiquidarDetalle[]>();
  for (const tramo of TRAMOS_ANTIGUEDAD) {
    porTramo.set(tramo.key, []);
  }

  for (const item of items) {
    const lista = porTramo.get(item.tramo_key);
    if (lista) {
      lista.push(item);
    }
  }

  return TRAMOS_ANTIGUEDAD.map((tramo) => {
    const ordenes = (porTramo.get(tramo.key) ?? []).slice().sort((a, b) => {
      if (b.dias_vencidos !== a.dias_vencidos) {
        return b.dias_vencidos - a.dias_vencidos;
      }
      return b.correlativo - a.correlativo;
    });

    const totalMonto = ordenes.reduce(
      (sum, o) => sum + (Number(o.monto_por_liquidar) || 0),
      0,
    );

    return {
      ...tramo,
      ordenes,
      totalOrdenes: ordenes.length,
      totalMonto,
    };
  });
}
