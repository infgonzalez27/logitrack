export function formatMoney(n: number | null | undefined): string {
  const v = Number(n);
  if (!Number.isFinite(v)) return "—";
  return v.toLocaleString("es-VE", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
}

export function formatNumber(n: number | null | undefined, digits = 0): string {
  const v = Number(n);
  if (!Number.isFinite(v)) return "—";
  return v.toLocaleString("es-VE", {
    minimumFractionDigits: digits,
    maximumFractionDigits: digits > 0 ? digits : 2,
  });
}

export function formatDate(value: string | null | undefined): string {
  if (!value) return "—";
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return value.slice(0, 10);
  return d.toLocaleDateString("es-VE");
}

/** Fecha/hora local YYYY-MM-DDTHH:mm para input despacho (default 08:00 hoy). */
export function defaultFechaDespachoLocal(): string {
  const now = new Date();
  const y = now.getFullYear();
  const m = String(now.getMonth() + 1).padStart(2, "0");
  const d = String(now.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}T08:00`;
}
