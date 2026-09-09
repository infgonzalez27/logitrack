/** Fecha civil en Venezuela (YYYY-MM-DD). */
export function fechaHoyCaracas(): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Caracas",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date());
}

export function fechaIsoDia(value: string | null | undefined): string | null {
  if (!value) return null;
  const iso = value.trim().slice(0, 10);
  return /^\d{4}-\d{2}-\d{2}$/.test(iso) ? iso : null;
}

/** Resta días a una fecha YYYY-MM-DD (calendario Caracas / UTC date parts). */
export function restarDiasIso(fechaIso: string, dias: number): string {
  const [y, m, d] = fechaIso.split("-").map(Number);
  const date = new Date(Date.UTC(y, m - 1, d));
  date.setUTCDate(date.getUTCDate() - dias);
  return date.toISOString().slice(0, 10);
}
