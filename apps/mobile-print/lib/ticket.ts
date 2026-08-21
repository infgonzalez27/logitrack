/** Tipos y builder de ticket térmico (sin DOM) — 58mm ESC/POS. */

export type TicketLinea = {
  id: string;
  secuencia: number | string;
  codigo: string;
  producto: string;
  cantidad: number;
  unitario: number;
  subtotal: number;
};

export type OrdenTicketData = {
  correlativo: number;
  facturaOrigen: string;
  estado: string;
  creadaAt: string;
  clienteNombre: string;
  clienteRif: string;
  clienteDireccion: string;
  camionLabel: string;
  despachadorNombre: string;
  pesoKg: number;
  lineas: TicketLinea[];
  totalRecaudar: number;
};

const LINE = "--------------------------------";

function moneyThermal(value: number): string {
  return `Bs ${Number(value).toFixed(2)}`;
}

function formatNumber(value: number): string {
  return Number(value).toLocaleString("es-VE", { maximumFractionDigits: 2 });
}

function formatDate(value: string): string {
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return value;
  return d.toLocaleString("es-VE", {
    dateStyle: "short",
    timeStyle: "short",
  });
}

export function toThermalText(value: string): string {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[—–]/g, "-")
    .replace(/[^\x09\x0A\x0D\x20-\x7E]/g, " ")
    .replace(/[ \t]+\n/g, "\n")
    .trimEnd();
}

export function buildOrdenTicketText(data: OrdenTicketData): string {
  const lines: string[] = [
    "LogiTrack",
    "ORDEN DE DISTRIBUCION",
    `#${data.correlativo}`,
    data.facturaOrigen,
    data.estado,
    formatDate(data.creadaAt),
    LINE,
    "CLIENTE",
    data.clienteNombre,
    data.clienteRif,
    data.clienteDireccion,
    LINE,
    `Camion: ${data.camionLabel}`,
    `Despachador: ${data.despachadorNombre}`,
    `Peso: ${formatNumber(data.pesoKg)} kg`,
    LINE,
    "DETALLE",
  ];

  for (const linea of data.lineas) {
    lines.push(`${linea.secuencia}. ${linea.producto}`);
    if (linea.codigo && linea.codigo !== "—") {
      lines.push(`   ${linea.codigo}`);
    }
    lines.push(
      `   ${formatNumber(linea.cantidad)} x ${moneyThermal(linea.unitario)}`,
    );
    lines.push(`   ${moneyThermal(linea.subtotal)}`);
  }

  if (!data.lineas.length) {
    lines.push("(sin lineas)");
  }

  lines.push(LINE);
  lines.push(`TOTAL: ${moneyThermal(data.totalRecaudar)}`);
  lines.push(LINE);
  lines.push("Gracias por su preferencia");
  lines.push("*** Fin del ticket ***");

  return `${toThermalText(lines.join("\n"))}\n\n\n`;
}

/** ESC @ + texto latin1 + feed. */
export function buildEscPosBytes(
  texto: string,
  opts?: { cut?: boolean },
): Uint8Array {
  const ESC = 0x1b;
  const GS = 0x1d;
  const parts: number[] = [ESC, 0x40];
  const thermal = toThermalText(texto);
  for (let i = 0; i < thermal.length; i++) {
    const code = thermal.charCodeAt(i);
    parts.push(code <= 0xff ? code : 0x3f);
  }
  parts.push(0x0a, 0x0a, 0x0a);
  parts.push(ESC, 0x64, 0x08);
  if (opts?.cut !== false) {
    parts.push(GS, 0x56, 0x00);
  }
  return Uint8Array.from(parts);
}

export function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]!);
  }
  // btoa disponible en Hermes/RN modernos; fallback manual
  if (typeof btoa === "function") return btoa(binary);
  const chars =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
  let output = "";
  for (let i = 0; i < binary.length; i += 3) {
    const a = binary.charCodeAt(i);
    const b = binary.charCodeAt(i + 1);
    const c = binary.charCodeAt(i + 2);
    const bitmap = (a << 16) | ((b || 0) << 8) | (c || 0);
    output +=
      chars.charAt((bitmap >> 18) & 63) +
      chars.charAt((bitmap >> 12) & 63) +
      (Number.isNaN(b) ? "=" : chars.charAt((bitmap >> 6) & 63)) +
      (Number.isNaN(c) ? "=" : chars.charAt(bitmap & 63));
  }
  return output;
}
