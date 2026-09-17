"use client";

import { useState, useTransition } from "react";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { formatCurrency, formatNumber } from "@/lib/format";
import { obtenerReporteFormasPagoAction } from "@/lib/actions/reportes";
import type { ReporteFormasPagoData } from "@/types/database";

interface ReportePagosClientProps {
  initialData: ReporteFormasPagoData | null;
  fechaDesdeInicial: string;
  fechaHastaInicial: string;
}

export function ReportePagosClient({
  initialData,
  fechaDesdeInicial,
  fechaHastaInicial,
}: ReportePagosClientProps) {
  const [isPending, startTransition] = useTransition();

  const [fechaDesde, setFechaDesde] = useState<string>(fechaDesdeInicial);
  const [fechaHasta, setFechaHasta] = useState<string>(fechaHastaInicial);
  const [soloBancarios, setSoloBancarios] = useState<boolean>(false);

  const [reporteData, setReporteData] = useState<ReporteFormasPagoData | null>(initialData);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  const handleFiltrar = () => {
    setErrorMsg(null);
    startTransition(async () => {
      const res = await obtenerReporteFormasPagoAction(fechaDesde, fechaHasta, soloBancarios);
      if (res.success && res.data) {
        setReporteData(res.data);
      } else {
        setErrorMsg(res.message || "Error al consultar el reporte de formas de pago.");
      }
    });
  };

  const handleImprimir = () => {
    window.print();
  };

  const movimientos = reporteData?.movimientos ?? [];

  return (
    <div className="space-y-6">
      {/* Alertas */}
      {errorMsg && (
        <div className="p-4 rounded-lg bg-red-500/10 border border-red-500/20 text-red-400 text-sm font-medium print:hidden">
          {errorMsg}
        </div>
      )}

      {/* Card de Filtros (Oculto en Impresión) */}
      <Card className="p-5 bg-slate-900 border-slate-800 space-y-4 print:hidden">
        <div className="flex flex-col md:flex-row md:items-end justify-between gap-4">
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 flex-1">
            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1">
                Fecha Inicial
              </label>
              <input
                type="date"
                value={fechaDesde}
                onChange={(e) => setFechaDesde(e.target.value)}
                className="w-full bg-slate-800 border border-slate-700 text-slate-100 rounded-md px-3 py-1.5 text-sm focus:ring-2 focus:ring-emerald-500"
              />
            </div>

            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1">
                Fecha Final
              </label>
              <input
                type="date"
                value={fechaHasta}
                onChange={(e) => setFechaHasta(e.target.value)}
                className="w-full bg-slate-800 border border-slate-700 text-slate-100 rounded-md px-3 py-1.5 text-sm focus:ring-2 focus:ring-emerald-500"
              />
            </div>

            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1">
                Filtro de Transacciones
              </label>
              <select
                value={soloBancarios ? "bancarios" : "todos"}
                onChange={(e) => setSoloBancarios(e.target.value === "bancarios")}
                className="w-full bg-slate-800 border border-slate-700 text-slate-100 rounded-md px-3 py-1.5 text-sm focus:ring-2 focus:ring-emerald-500"
              >
                <option value="todos">🌐 Todas las Formas de Pago</option>
                <option value="bancarios">
                  🏦 Solo Bancarias / Electrónicas (Pago Móvil, Transferencia, Zelle, Binance)
                </option>
              </select>
            </div>
          </div>

          <div className="flex items-center space-x-3 pt-2 md:pt-0">
            <Button
              onClick={handleFiltrar}
              disabled={isPending}
              className="bg-emerald-600 hover:bg-emerald-500 text-white text-xs px-4 py-2 font-semibold"
            >
              {isPending ? "Filtrando..." : "🔍 Generar Reporte"}
            </Button>

            <Button
              variant="secondary"
              onClick={handleImprimir}
              className="text-xs px-4 py-2 font-semibold border-slate-700 text-slate-200 hover:bg-slate-800"
            >
              🖨️ Imprimir Reporte
            </Button>
          </div>
        </div>
      </Card>

      {/* Encabezado Exclusivo de Impresión */}
      <div className="hidden print:block mb-6 space-y-2 text-slate-900 border-b pb-4">
        <div className="flex justify-between items-start">
          <div>
            <h1 className="text-xl font-bold uppercase">LogiTrack — Reporte Gerencial de Formas de Pago</h1>
            <p className="text-sm text-gray-600">
              Modalidad: {soloBancarios ? "Solo Transacciones Bancarias / Electrónicas" : "Todas las Formas de Pago"}
            </p>
          </div>
          <div className="text-right text-xs text-gray-500">
            <p>Fecha de emisión: {new Date().toLocaleDateString("es-VE")}</p>
            <p>Rango: {fechaDesde} al {fechaHasta}</p>
          </div>
        </div>
      </div>

      {/* Tarjetas KPI de Resumen */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <Card className="p-4 bg-slate-900 border-slate-800 print:border-gray-300 print:bg-white">
          <span className="text-xs text-slate-400 print:text-gray-600 uppercase font-semibold">
            Total Transacciones
          </span>
          <p className="text-2xl font-bold text-white print:text-gray-900 mt-1">
            {formatNumber(reporteData?.total_registros ?? 0)}
          </p>
        </Card>

        <Card className="p-4 bg-slate-900 border-slate-800 print:border-gray-300 print:bg-white">
          <span className="text-xs text-slate-400 print:text-gray-600 uppercase font-semibold">
            Total Recaudado (Bs)
          </span>
          <p className="text-2xl font-bold text-blue-400 print:text-blue-700 mt-1">
            Bs. {formatNumber(reporteData?.monto_total_bs ?? 0)}
          </p>
        </Card>

        <Card className="p-4 bg-slate-900 border-slate-800 print:border-gray-300 print:bg-white">
          <span className="text-xs text-slate-400 print:text-gray-600 uppercase font-semibold">
            Total Recaudado (USD)
          </span>
          <p className="text-2xl font-bold text-emerald-400 print:text-emerald-700 mt-1">
            {formatCurrency(reporteData?.monto_total_usd ?? 0)}
          </p>
        </Card>
      </div>

      {/* Tabla Detallada del Reporte */}
      <Card className="p-5 bg-slate-900 border-slate-800 space-y-4 print:border-none print:shadow-none print:p-0">
        <div className="flex items-center justify-between print:hidden">
          <h3 className="text-base font-semibold text-white">Detalle de Pagos Recaudados</h3>
          <span className="text-xs text-slate-400">
            Período: <strong>{fechaDesde}</strong> a <strong>{fechaHasta}</strong>
          </span>
        </div>

        <div className="overflow-x-auto">
          <table className="w-full text-sm text-left text-slate-300 print:text-black print:text-xs">
            <thead className="bg-slate-800/80 print:bg-gray-100 text-xs uppercase text-slate-400 print:text-gray-700 font-medium border-b border-slate-700 print:border-gray-300">
              <tr>
                <th className="px-4 py-2.5">Fecha Rendición</th>
                <th className="px-4 py-2.5">Cliente</th>
                <th className="px-4 py-2.5">Forma de Pago</th>
                <th className="px-4 py-2.5">Referencia</th>
                <th className="px-4 py-2.5">Cuenta Destino</th>
                <th className="px-4 py-2.5 text-right font-bold text-blue-400 print:text-black">Monto Bs</th>
                <th className="px-4 py-2.5 text-right font-bold text-emerald-400 print:text-black">Monto USD</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-800 print:divide-gray-300">
              {movimientos.length === 0 ? (
                <tr>
                  <td colSpan={7} className="px-4 py-6 text-center text-slate-500 print:text-gray-500">
                    No se encontraron movimientos registrados en el rango de fechas seleccionado.
                  </td>
                </tr>
              ) : (
                movimientos.map((m, idx) => (
                  <tr key={`${m.rendicion_id}-${idx}`} className="hover:bg-slate-800/40 print:hover:bg-transparent">
                    <td className="px-4 py-3 font-mono text-xs text-slate-400 print:text-gray-700">
                      {new Date(m.fecha_rendicion).toLocaleDateString("es-VE")}
                    </td>
                    <td className="px-4 py-3 font-medium text-white print:text-gray-900">
                      {m.cliente_nombre}
                      {m.cliente_rif ? <span className="text-xs text-slate-400 print:text-gray-600 block">({m.cliente_rif})</span> : null}
                    </td>
                    <td className="px-4 py-3">
                      <span className="font-semibold text-slate-200 print:text-gray-900 block">{m.fpago_concepto}</span>
                      {m.es_bancario && (
                        <span className="inline-block px-1.5 py-0.5 text-[10px] rounded bg-blue-500/20 text-blue-300 print:border print:border-gray-400 print:text-gray-700">
                          Bancario
                        </span>
                      )}
                    </td>
                    <td className="px-4 py-3 font-mono text-xs text-slate-300 print:text-gray-800">
                      {m.referencia_bancaria ?? "—"}
                    </td>
                    <td className="px-4 py-3 text-xs text-slate-400 print:text-gray-700">
                      {m.cuenta_bancaria ?? "—"}
                    </td>
                    <td className="px-4 py-3 text-right font-medium text-blue-400 print:text-gray-900">
                      Bs. {formatNumber(Number(m.monto_bs || 0))}
                    </td>
                    <td className="px-4 py-3 text-right font-semibold text-emerald-400 print:text-gray-900">
                      {formatCurrency(Number(m.monto_usd || 0))}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
            {movimientos.length > 0 && (
              <tfoot className="bg-slate-800/90 print:bg-gray-200 border-t-2 border-slate-700 print:border-gray-400 font-bold">
                <tr>
                  <td colSpan={5} className="px-4 py-3 text-right text-slate-200 print:text-gray-900 uppercase text-xs">
                    Totales Consolidados:
                  </td>
                  <td className="px-4 py-3 text-right text-blue-400 print:text-black">
                    Bs. {formatNumber(reporteData?.monto_total_bs ?? 0)}
                  </td>
                  <td className="px-4 py-3 text-right text-emerald-400 print:text-black">
                    {formatCurrency(reporteData?.monto_total_usd ?? 0)}
                  </td>
                </tr>
              </tfoot>
            )}
          </table>
        </div>
      </Card>
    </div>
  );
}
