/** Detecta si una forma de pago del catálogo `fpagos` opera en bolívares. */
export function esFormaPagoEnBs(concepto: string): boolean {
  const c = concepto.trim().toLowerCase();
  if (!c) return false;

  if (
    /\b(usd|us\$|\$|zelle|binance|usdt|dólar|dolar)\b/.test(c) ||
    c.includes("efectivo usd") ||
    c.includes("efectivo $")
  ) {
    return false;
  }

  if (
    /\b(bs|ves|bolívar|bolivar)\b/.test(c) ||
    c.includes("efectivo bs") ||
    c.includes("pago movil") ||
    c.includes("pago móvil") ||
    c.includes("transferencia")
  ) {
    return true;
  }

  return false;
}

/** Convierte bolívares a USD con la tasa BCV del día (monto_bs / tasa). */
export function convertirBsAUsd(montoBs: number, tasa: number): number {
  if (!Number.isFinite(montoBs) || montoBs <= 0) return 0;
  if (!Number.isFinite(tasa) || tasa <= 0) return 0;
  return Math.round((montoBs / tasa) * 100) / 100;
}

export function convertirUsdABs(montoUsd: number, tasa: number): number {
  if (!Number.isFinite(montoUsd) || montoUsd <= 0) return 0;
  if (!Number.isFinite(tasa) || tasa <= 0) return 0;
  return Math.round(montoUsd * tasa * 100) / 100;
}

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}

export type MontosOrden = { usd: number; bs: number };

/**
 * Resuelve totales USD y Bs de una orden de distribución.
 *
 * Convención de datos (ver `mapProductosJson` en acciones de órdenes):
 * - `subtotal_recaudar` / `total_recaudar_bs` / `valor_unitario_recaudar` → Bs
 * - `*_usd` / `total_recaudar_usd` → USD (= bs / tasa)
 *
 * Caso legado: si el valor en campos “bs” es pequeño frente a la tasa
 * (p.ej. 184 con tasa ~820), se interpreta como USD mal etiquetado.
 */
export function resolverMontosOrden(input: {
  total_recaudar_usd?: number | null;
  total_recaudar_bs?: number | null;
  tasa_cambio?: number | null;
  sum_lineas_usd?: number | null;
  sum_lineas_recaudar?: number | null;
}): MontosOrden {
  const bsLineas = Number(input.sum_lineas_recaudar ?? 0);
  const bsHeader = Number(input.total_recaudar_bs ?? 0);
  const usdLineas = Number(input.sum_lineas_usd ?? 0);
  const usdHeader = Number(input.total_recaudar_usd ?? 0);
  const tasa = Number(input.tasa_cambio ?? 0);

  const bsRaw = bsLineas > 0 ? bsLineas : bsHeader > 0 ? bsHeader : 0;
  const usdRaw = usdLineas > 0 ? usdLineas : usdHeader > 0 ? usdHeader : 0;

  if (tasa > 1 && bsRaw > 0) {
    // Magnitud típica de Bs (≥ media tasa): el campo es bolívares reales.
    if (bsRaw >= tasa * 0.5) {
      const usdFromBs = convertirBsAUsd(bsRaw, tasa);
      let usd = usdFromBs;
      if (usdRaw > 0) {
        const tol = Math.max(0.05, Math.abs(usdFromBs) * 0.25);
        const matchesConversion = Math.abs(usdRaw - usdFromBs) <= tol;
        const looksDoubleConverted =
          usdFromBs > 0 &&
          Math.abs(usdRaw - usdFromBs / tasa) <=
            Math.max(0.05, Math.abs(usdFromBs / tasa) * 0.25);
        if (matchesConversion) {
          usd = round2(usdRaw);
        } else if (looksDoubleConverted) {
          usd = usdFromBs;
        } else if (usdRaw > usdFromBs * 0.5) {
          usd = round2(usdRaw);
        }
      }
      return { usd, bs: round2(bsRaw) };
    }

    // Valor “bs” pequeño vs tasa → USD comercial guardado en campo bs.
    const usd = round2(bsRaw);
    return { usd, bs: convertirUsdABs(usd, tasa) };
  }

  if (bsRaw > 0 && usdRaw > 0) {
    return { usd: round2(usdRaw), bs: round2(bsRaw) };
  }
  if (bsRaw > 0 && tasa > 0) {
    return { usd: convertirBsAUsd(bsRaw, tasa), bs: round2(bsRaw) };
  }
  if (usdRaw > 0 && tasa > 0) {
    return { usd: round2(usdRaw), bs: convertirUsdABs(usdRaw, tasa) };
  }
  if (usdRaw > 0) return { usd: round2(usdRaw), bs: 0 };
  if (bsRaw > 0) return { usd: 0, bs: round2(bsRaw) };
  return { usd: 0, bs: 0 };
}

/** Atajo: solo el monto USD resuelto. */
export function resolverMontoUsdOrden(
  input: Parameters<typeof resolverMontosOrden>[0],
): number {
  return resolverMontosOrden(input).usd;
}
