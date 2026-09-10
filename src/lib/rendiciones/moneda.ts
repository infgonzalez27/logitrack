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
 * Montos de orden (crédito dolarizado).
 * Fuente de verdad: `total_recaudar_usd` / `subtotal_recaudar_usd` / `valor_unitario_usd`.
 * `bs` es solo equivalente informativo (USD × tasa) para UI/rendición.
 */
export function resolverMontosOrden(input: {
  total_recaudar_usd?: number | null;
  tasa_cambio?: number | null;
  sum_lineas_usd?: number | null;
}): MontosOrden {
  const usdLineas = Number(input.sum_lineas_usd ?? 0);
  const usdHeader = Number(input.total_recaudar_usd ?? 0);
  const tasa = Number(input.tasa_cambio ?? 0);

  const usd = round2(usdLineas > 0 ? usdLineas : usdHeader > 0 ? usdHeader : 0);
  const bs = tasa > 0 && usd > 0 ? convertirUsdABs(usd, tasa) : 0;
  return { usd, bs };
}

/** Atajo: solo el monto USD resuelto. */
export function resolverMontoUsdOrden(
  input: Parameters<typeof resolverMontosOrden>[0],
): number {
  return resolverMontosOrden(input).usd;
}
