export function formatDate(value: string | null | undefined): string {
  if (!value) return "—";
  return new Intl.DateTimeFormat("es-VE", {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(new Date(value));
}

export function formatDateOnly(value: string | null | undefined): string {
  if (!value) return "—";
  return new Intl.DateTimeFormat("es-VE", { dateStyle: "medium" }).format(
    new Date(value),
  );
}

export function formatCurrency(value: number | null | undefined): string {
  if (value == null) return "—";
  return new Intl.NumberFormat("es-VE", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: 2,
  }).format(value);
}

export function formatNumber(value: number | null | undefined): string {
  if (value == null) return "—";
  return new Intl.NumberFormat("es-VE").format(value);
}

/** Monto editable con miles (es-VE): 99195.5 → "99.195,50" */
export function formatMoneyInput(
  value: number | null | undefined,
  fractionDigits = 2,
): string {
  if (value == null || !Number.isFinite(value)) {
    return (0).toLocaleString("es-VE", {
      minimumFractionDigits: fractionDigits,
      maximumFractionDigits: fractionDigits,
    });
  }
  return value.toLocaleString("es-VE", {
    minimumFractionDigits: fractionDigits,
    maximumFractionDigits: fractionDigits,
  });
}

/**
 * Parsea montos en es-VE o en formato crudo.
 * "99.195,50" | "99195,50" | "99195.50" → number
 */
export function parseLocaleNumber(raw: string): number {
  const trimmed = raw.trim();
  if (!trimmed) return NaN;

  const cleaned = trimmed.replace(/[^\d.,\-]/g, "");
  if (!cleaned || cleaned === "-" || cleaned === "." || cleaned === ",") {
    return NaN;
  }

  const lastComma = cleaned.lastIndexOf(",");
  const lastDot = cleaned.lastIndexOf(".");

  let normalized: string;
  if (lastComma >= 0 && lastDot >= 0) {
    // Ambos: el último es decimal.
    if (lastComma > lastDot) {
      normalized = cleaned.replace(/\./g, "").replace(",", ".");
    } else {
      normalized = cleaned.replace(/,/g, "");
    }
  } else if (lastComma >= 0) {
    // En es-VE la coma es siempre el separador decimal.
    normalized = cleaned.replace(/\./g, "").replace(",", ".");
  } else if (lastDot >= 0) {
    const decimals = cleaned.length - lastDot - 1;
    // Un solo punto con ≤2 decimales → decimal EN; si no, miles EN.
    normalized =
      decimals <= 2 && cleaned.indexOf(".") === lastDot
        ? cleaned
        : cleaned.replace(/\./g, "");
  } else {
    normalized = cleaned;
  }

  return Number(normalized);
}
