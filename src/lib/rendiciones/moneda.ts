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

/**
 * Monto comercial en USD de una orden.
 *
 * Los precios de lista / `valor_unitario_recaudar` están en USD. Hoy
 * `total_recaudar_bs` / `subtotal_recaudar` suelen cargar ese total comercial,
 * y `total_recaudar_usd` queda como `bs / tasa` (p.ej. 184 → 0,24). Preferimos
 * el monto comercial frente al USD “convertido”.
 */
export function resolverMontoUsdOrden(input: {
  total_recaudar_usd?: number | null;
  total_recaudar_bs?: number | null;
  tasa_cambio?: number | null;
  sum_lineas_usd?: number | null;
  sum_lineas_recaudar?: number | null;
}): number {
  const comercialLineas = Number(input.sum_lineas_recaudar ?? 0);
  const comercialHeader = Number(input.total_recaudar_bs ?? 0);
  const usdLineas = Number(input.sum_lineas_usd ?? 0);
  const usdHeader = Number(input.total_recaudar_usd ?? 0);
  const tasa = Number(input.tasa_cambio ?? 0);

  const comercial =
    comercialLineas > 0
      ? comercialLineas
      : comercialHeader > 0
        ? comercialHeader
        : 0;
  const convertido = usdLineas > 0 ? usdLineas : usdHeader > 0 ? usdHeader : 0;

  if (comercial > 0 && convertido > 0 && tasa > 1) {
    const comoUsdDesdeComercial = comercial / tasa;
    // convertido ≈ comercial/tasa → el comercial es el USD real
    if (
      Math.abs(convertido - comoUsdDesdeComercial) <=
      Math.max(0.05, Math.abs(comoUsdDesdeComercial) * 0.25)
    ) {
      return Math.round(comercial * 100) / 100;
    }
  }

  if (comercial > 0) return Math.round(comercial * 100) / 100;
  if (convertido > 0) return Math.round(convertido * 100) / 100;
  return 0;
}
