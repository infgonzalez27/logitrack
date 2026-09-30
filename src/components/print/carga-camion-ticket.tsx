import { formatDate, formatNumber } from "@/lib/format";
import type { CargaTicketData } from "@/lib/autoventas/carga-ticket";

export function CargaCamionTicket({
  camion,
  fecha,
  lineas,
  tipo,
}: CargaTicketData) {
  const total = lineas.reduce((s, l) => s + l.cantidad, 0);
  const descarga = tipo === "descarga";

  return (
    <article
      className="lt-ticket"
      aria-label={`${descarga ? "Descarga" : "Carga"} de camión ${camion}`}
    >
      <header className="lt-ticket__header">
        <p className="lt-ticket__brand">LogiTrack</p>
        <h1 className="lt-ticket__title">
          {descarga ? "DESCARGA DE CAMIÓN" : "CARGA DE CAMIÓN"}
        </h1>
        <p className="lt-ticket__muted">Camión: {camion}</p>
        {fecha ? <p className="lt-ticket__muted">{formatDate(fecha)}</p> : null}
      </header>

      <div className="lt-ticket__rule" />

      <table className="w-full border-collapse">
        <thead>
          <tr className="lt-ticket__label">
            <th className="pr-1 text-left align-top">Código</th>
            <th className="pr-1 text-left align-top">Producto</th>
            <th className="text-right align-top">
              {descarga ? "Devuelto" : "Cargado"}
            </th>
          </tr>
        </thead>
        <tbody>
          {lineas.map((l, i) => (
            <tr key={`${l.codigo}-${i}`}>
              <td className="pr-1 align-top">{l.codigo || "—"}</td>
              <td className="lt-ticket__wrap pr-1 align-top">{l.producto}</td>
              <td className="text-right align-top tabular-nums">
                {formatNumber(l.cantidad)}
              </td>
            </tr>
          ))}
          {lineas.length === 0 ? (
            <tr>
              <td colSpan={3} className="lt-ticket__muted">
                Sin productos
              </td>
            </tr>
          ) : null}
        </tbody>
      </table>

      <div className="lt-ticket__rule" />

      <p className="lt-ticket__total">
        <span>TOTAL</span>
        <span>{formatNumber(total)}</span>
      </p>

      <div className="lt-ticket__rule" />

      <footer className="lt-ticket__footer">
        <p className="lt-ticket__muted">*** Fin del comprobante ***</p>
      </footer>
    </article>
  );
}
