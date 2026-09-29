/** Ticket térmico 58mm ESC/POS (portado desde apps/mobile-print). */

export type TicketLinea = {
  id: string;
  secuencia: number | string;
  codigo: string;
  producto: string;
  cantidad: number;
  unitario: number;
  subtotal: number;
};

export type LineaEstadoCuentaVacios = {
  contenedor_id: string;
  nombre: string;
  saldo_anterior: number;
  entregado: number;
  retirado: number;
  saldo_nuevo: number;
};

export type CargaCamionLinea = {
  codigo: string;
  producto: string;
  cantidad: number;
};

export type CargaCamionTicketData = {
  camionLabel: string;
  fecha: string;
  lineas: CargaCamionLinea[];
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
  estadoCuentaVacios?: LineaEstadoCuentaVacios[];
  estadoCuentaProvisional?: boolean;
};

const LINE = "--------------------------------";

function moneyThermal(value: number): string {
  return `USD ${Number(value).toFixed(2)}`;
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

const ANCHO = LINE.length;
const COL_CODIGO = 6;
const COL_CANTIDAD = 7;
const COL_PRODUCTO = ANCHO - COL_CODIGO - COL_CANTIDAD - 2;

function filaValor(label: string, value: number): string {
  const num = formatNumber(value);
  return `${label.padEnd(ANCHO - num.length)}${num}`;
}

function partirTexto(texto: string, ancho: number): string[] {
  const palabras = texto.trim().split(/\s+/).filter(Boolean);
  const out: string[] = [];
  let actual = "";
  for (const palabra of palabras) {
    let resto = palabra;
    while (resto.length > ancho) {
      if (actual) {
        out.push(actual);
        actual = "";
      }
      out.push(resto.slice(0, ancho));
      resto = resto.slice(ancho);
    }
    if (!actual) actual = resto;
    else if (actual.length + 1 + resto.length <= ancho) actual += ` ${resto}`;
    else {
      out.push(actual);
      actual = resto;
    }
  }
  if (actual) out.push(actual);
  return out.length ? out : [""];
}

/** Comprobante de carga de camión: CODIGO | PRODUCTO | CARGADO + total. */
export function buildCargaCamionTicketText(data: CargaCamionTicketData): string {
  const total = data.lineas.reduce((s, l) => s + l.cantidad, 0);
  const lines: string[] = [
    "LogiTrack",
    "CARGA DE CAMION",
    `Camion: ${data.camionLabel}`,
    formatDate(data.fecha),
    LINE,
    `${"CODIGO".padEnd(COL_CODIGO)} ${"PRODUCTO".padEnd(COL_PRODUCTO)} ${"CARGADO".padStart(COL_CANTIDAD)}`,
    LINE,
  ];

  for (const linea of data.lineas) {
    const codigo = toThermalText(linea.codigo || "-").slice(0, COL_CODIGO);
    const nombre = partirTexto(toThermalText(linea.producto), COL_PRODUCTO);
    const cantidad = formatNumber(linea.cantidad);
    lines.push(
      `${codigo.padEnd(COL_CODIGO)} ${nombre[0]!.padEnd(COL_PRODUCTO)} ${cantidad.padStart(COL_CANTIDAD)}`,
    );
    for (const extra of nombre.slice(1)) {
      lines.push(`${"".padEnd(COL_CODIGO)} ${extra}`);
    }
  }

  if (!data.lineas.length) lines.push("(sin productos)");

  lines.push(LINE);
  lines.push(
    `${"TOTAL:".padStart(ANCHO - COL_CANTIDAD - 1)} ${formatNumber(total).padStart(COL_CANTIDAD)}`,
  );
  lines.push(LINE);
  lines.push("*** Fin del comprobante ***");

  return `${toThermalText(lines.join("\n"))}\n\n\n`;
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
    if (linea.codigo && linea.codigo !== "-" && linea.codigo !== "—") {
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
  lines.push("ESTADO DE CUENTA - VACIOS");
  if (data.estadoCuentaVacios && data.estadoCuentaVacios.length > 0) {
    for (const v of data.estadoCuentaVacios) {
      lines.push(v.nombre);
      lines.push(filaValor("  Saldo anterior:", v.saldo_anterior));
      lines.push(filaValor("  Entregados:", v.entregado));
      lines.push(filaValor("  Retirados:", v.retirado));
      lines.push(filaValor("  Saldo final:", v.saldo_nuevo));
    }
    if (data.estadoCuentaProvisional) {
      lines.push("(provisional hasta aprobar radar)");
    }
  } else {
    lines.push("(sin saldo de vacios)");
  }

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
