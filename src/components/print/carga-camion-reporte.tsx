import { formatDate, formatNumber } from "@/lib/format";
import type { CargaTicketData } from "@/lib/autoventas/carga-ticket";

export function CargaCamionReporte({
  empresaNombre,
  camion,
  fecha,
  lineas,
  tipo,
}: CargaTicketData & { empresaNombre: string | null }) {
  const total = lineas.reduce((s, l) => s + l.cantidad, 0);
  const descarga = tipo === "descarga";
  const titulo = descarga ? "Descarga de camión" : "Carga de camión";

  return (
    <article
      className="lt-carta rounded-xl border border-lt-border-light bg-white p-8 text-black"
      aria-label={`${titulo} ${camion}`}
    >
      <header className="flex items-start justify-between gap-6 border-b-2 border-black pb-4">
        <div>
          <p className="text-xl font-bold uppercase tracking-wide">
            {empresaNombre || "LogiTrack"}
          </p>
          <h1 className="mt-1 text-lg font-semibold">{titulo}</h1>
        </div>
        <dl className="text-right text-sm">
          <div>
            <dt className="inline font-semibold">Camión: </dt>
            <dd className="inline">{camion}</dd>
          </div>
          <div>
            <dt className="inline font-semibold">Fecha: </dt>
            <dd className="inline">{fecha ? formatDate(fecha) : "—"}</dd>
          </div>
        </dl>
      </header>

      <table className="mt-6 w-full border-collapse text-sm">
        <thead>
          <tr className="border-b border-black text-left">
            <th className="w-10 py-2 pr-2 font-semibold">#</th>
            <th className="w-28 py-2 pr-2 font-semibold">Código</th>
            <th className="py-2 pr-2 font-semibold">Producto</th>
            <th className="w-28 py-2 text-right font-semibold">
              {descarga ? "Devuelto" : "Cargado"}
            </th>
          </tr>
        </thead>
        <tbody>
          {lineas.map((l, i) => (
            <tr key={`${l.codigo}-${i}`} className="border-b border-gray-300">
              <td className="py-1.5 pr-2 tabular-nums">{i + 1}</td>
              <td className="py-1.5 pr-2 font-mono text-xs">{l.codigo || "—"}</td>
              <td className="py-1.5 pr-2">{l.producto}</td>
              <td className="py-1.5 text-right tabular-nums">
                {formatNumber(l.cantidad)}
              </td>
            </tr>
          ))}
          {lineas.length === 0 ? (
            <tr>
              <td colSpan={4} className="py-4 text-center text-gray-600">
                Sin productos
              </td>
            </tr>
          ) : null}
        </tbody>
        <tfoot>
          <tr className="border-t-2 border-black font-semibold">
            <td colSpan={3} className="py-2 pr-2">
              Total ({formatNumber(lineas.length)} producto
              {lineas.length === 1 ? "" : "s"})
            </td>
            <td className="py-2 text-right tabular-nums">{formatNumber(total)}</td>
          </tr>
        </tfoot>
      </table>

      <div className="lt-print-keep-together mt-16 grid grid-cols-2 gap-12 text-center text-sm">
        <div>
          <div className="border-t border-black pt-1">
            {descarga ? "Recibido por (almacén)" : "Entregado por (almacén)"}
          </div>
        </div>
        <div>
          <div className="border-t border-black pt-1">
            {descarga ? "Entregado por (chofer)" : "Recibido por (chofer)"}
          </div>
        </div>
      </div>
    </article>
  );
}
