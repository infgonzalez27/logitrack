import { labelOrdenEstado } from "@/lib/constants";
import { formatCurrency, formatDate, formatNumber } from "@/lib/format";
import type { OrdenEstado } from "@/types/database";

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
  estado: OrdenEstado;
  creadaAt: string;
  clienteNombre: string;
  clienteRif: string;
  clienteDireccion: string;
  camionLabel: string;
  choferNombre: string;
  pesoKg: number;
  lineas: TicketLinea[];
  totalRecaudar: number;
};

const LINE = "--------------------------------";

/** Monto simple para térmicas (evita símbolos Unicode de Intl). */
function moneyThermal(value: number): string {
  return `USD ${value.toFixed(2)}`;
}

/** Quita tildes/símbolos que muchas SAT no imprimen (papel avanza en blanco). */
function toThermalText(value: string): string {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[—–]/g, "-")
    .replace(/[^\x09\x0A\x0D\x20-\x7E]/g, " ")
    .replace(/[ \t]+\n/g, "\n")
    .trimEnd();
}

/** Texto plano para impresora térmica ESC/POS (RawBT / Bluetooth). */
export function buildOrdenTicketText(data: OrdenTicketData): string {
  const lines: string[] = [
    "LogiTrack",
    "ORDEN DE DISTRIBUCION",
    `#${data.correlativo}`,
    data.facturaOrigen,
    labelOrdenEstado(data.estado),
    formatDate(data.creadaAt),
    LINE,
    "CLIENTE",
    data.clienteNombre,
    data.clienteRif,
    data.clienteDireccion,
    LINE,
    `Camion: ${data.camionLabel}`,
    `Chofer: ${data.choferNombre}`,
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

  // Saltos finales: avance de papel en térmica ESC/POS
  return `${toThermalText(lines.join("\n"))}\n\n\n`;
}

export function OrdenTicket(data: OrdenTicketData) {
  const {
    correlativo,
    facturaOrigen,
    estado,
    creadaAt,
    clienteNombre,
    clienteRif,
    clienteDireccion,
    camionLabel,
    choferNombre,
    pesoKg,
    lineas,
    totalRecaudar,
  } = data;

  return (
    <article className="lt-ticket" aria-label={`Ticket orden ${correlativo}`}>
      <header className="lt-ticket__header">
        <p className="lt-ticket__brand">LogiTrack</p>
        <h1 className="lt-ticket__title">ORDEN DE DISTRIBUCIÓN</h1>
        <p className="lt-ticket__big">#{correlativo}</p>
        <p className="lt-ticket__muted">{facturaOrigen}</p>
        <p className="lt-ticket__muted">
          {labelOrdenEstado(estado)} · {formatDate(creadaAt)}
        </p>
      </header>

      <div className="lt-ticket__rule" />

      <section className="lt-ticket__block">
        <p className="lt-ticket__label">CLIENTE</p>
        <p className="lt-ticket__strong">{clienteNombre}</p>
        <p>{clienteRif}</p>
        <p className="lt-ticket__wrap">{clienteDireccion}</p>
      </section>

      <div className="lt-ticket__rule" />

      <section className="lt-ticket__block">
        <p>
          <span className="lt-ticket__label">Camión:</span> {camionLabel}
        </p>
        <p>
          <span className="lt-ticket__label">Chofer:</span> {choferNombre}
        </p>
        <p>
          <span className="lt-ticket__label">Peso:</span>{" "}
          {formatNumber(pesoKg)} kg
        </p>
      </section>

      <div className="lt-ticket__rule" />

      <section className="lt-ticket__block">
        <p className="lt-ticket__label">DETALLE</p>
        {lineas.map((linea) => (
          <div key={linea.id} className="lt-ticket__item">
            <p className="lt-ticket__strong">
              {linea.secuencia}. {linea.producto}
            </p>
            {linea.codigo !== "—" ? (
              <p className="lt-ticket__muted">{linea.codigo}</p>
            ) : null}
            <p className="lt-ticket__row">
              <span>
                {formatNumber(linea.cantidad)} × {formatCurrency(linea.unitario)}
              </span>
              <span>{formatCurrency(linea.subtotal)}</span>
            </p>
          </div>
        ))}
        {lineas.length === 0 ? (
          <p className="lt-ticket__muted">Sin líneas</p>
        ) : null}
      </section>

      <div className="lt-ticket__rule lt-ticket__rule--double" />

      <p className="lt-ticket__total">
        <span>TOTAL A RECAUDAR</span>
        <span>{formatCurrency(totalRecaudar)}</span>
      </p>

      <div className="lt-ticket__rule" />

      <footer className="lt-ticket__footer">
        <p>Gracias por su preferencia</p>
        <p className="lt-ticket__muted">*** Fin del ticket ***</p>
      </footer>
    </article>
  );
}
