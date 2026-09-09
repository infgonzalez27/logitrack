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
