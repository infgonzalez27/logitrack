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
