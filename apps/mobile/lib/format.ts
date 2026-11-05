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

/**
 * Parsea un string de monto (con o sin separadores de miles `.` y decimales `,`)
 * a un número flotante seguro.
 */
export function parseMoneyInput(val: string | number | null | undefined): number {
  if (typeof val === "number") return Number.isFinite(val) ? val : 0;
  const raw = String(val ?? "").trim();
  if (!raw) return 0;

  if (raw.includes(",")) {
    const normalized = raw.replace(/\./g, "").replace(",", ".");
    const num = Number(normalized);
    return Number.isFinite(num) ? num : 0;
  }

  const parts = raw.split(".");
  if (parts.length > 2) {
    const num = Number(raw.replace(/\./g, ""));
    return Number.isFinite(num) ? num : 0;
  }
  if (parts.length === 2 && parts[1].length === 3 && parts[0].length >= 1) {
    const num = Number(raw.replace(/\./g, ""));
    return Number.isFinite(num) ? num : 0;
  }

  const num = Number(raw);
  return Number.isFinite(num) ? num : 0;
}

/**
 * Formatea en vivo lo que escribe el usuario agregando separador de miles (`.`)
 * y permitiendo `,` para los decimales (máx. 2 decimales).
 */
export function formatMoneyInputLive(text: string): string {
  if (!text) return "";
  let cleaned = text.replace(/[^0-9.,]/g, "");
  if (!cleaned) return "";

  if (!cleaned.includes(",") && cleaned.includes(".")) {
    const lastDot = cleaned.lastIndexOf(".");
    const afterDot = cleaned.slice(lastDot + 1);
    const beforeDot = cleaned.slice(0, lastDot).replace(/\./g, "");
    if (afterDot.length <= 2) {
      cleaned = `${beforeDot},${afterDot}`;
    } else {
      cleaned = cleaned.replace(/\./g, "");
    }
  } else {
    const [intRaw, ...decParts] = cleaned.split(",");
    cleaned =
      decParts.length > 0
        ? `${intRaw.replace(/\./g, "")},${decParts.join("").replace(/\./g, "")}`
        : intRaw.replace(/\./g, "");
  }

  const hasComma = cleaned.includes(",");
  const [intPartRaw, decPartRaw = ""] = cleaned.split(",");
  const intTrimmed = intPartRaw.replace(/^0+(?=\d)/, "");
  const intFormatted = (intTrimmed || (hasComma ? "0" : "")).replace(
    /\B(?=(\d{3})+(?!\d))/g,
    ".",
  );
  const decFormatted = decPartRaw.slice(0, 2);

  return hasComma ? `${intFormatted},${decFormatted}` : intFormatted;
}

/** Convierte un número calculado a string formateado para el TextInput */
export function numberToMoneyInput(num: number): string {
  if (!Number.isFinite(num) || num <= 0) return "";
  const rounded = Math.round(num * 100) / 100;
  const [intPart, decPart] = rounded.toFixed(2).split(".");
  const intFormatted = intPart.replace(/\B(?=(\d{3})+(?!\d))/g, ".");
  return decPart === "00" ? intFormatted : `${intFormatted},${decPart}`;
}
