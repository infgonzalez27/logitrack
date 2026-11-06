import * as XLSX from "xlsx";
import type { ReporteFormasPagoData } from "@/types/database";
import { formatDate } from "@/lib/format";

export function exportFormasPagoToExcel(data: ReporteFormasPagoData) {
  const {
    fecha_desde,
    fecha_hasta,
    solo_bancarios,
    total_registros,
    monto_total_usd,
    monto_total_bs,
    movimientos,
  } = data;

  const rows: (string | number)[][] = [
    ["REPORTE DE FORMAS DE PAGO EN RENDICIONES"],
    [`Período: ${fecha_desde} al ${fecha_hasta}`],
    [`Filtro: ${solo_bancarios ? "Solo bancarios" : "Todas las formas de pago"}`],
    [],
    [
      "Fecha",
      "Cliente",
      "RIF",
      "Forma de Pago",
      "Tipo",
      "Referencia",
      "Tasa BCV",
      "Monto USD",
      "Monto Bs",
    ],
  ];

  for (const m of movimientos ?? []) {
    const usd = Number(m.monto_usd ?? 0);
    const bs = Number(m.monto_bs ?? 0);
    const tasa = Number(m.tasa_cambio ?? 0);
    const ref = m.referencia_bancaria || m.cuenta_bancaria || "—";
    const tipo = m.es_bancario ? "Bancario" : "No bancario";

    rows.push([
      formatDate(m.fecha_rendicion),
      m.cliente_nombre ?? "—",
      m.cliente_rif ?? "—",
      m.fpago_concepto ?? "—",
      tipo,
      ref,
      tasa,
      usd,
      bs,
    ]);
  }

  rows.push([
    "TOTALES:",
    "",
    "",
    "",
    "",
    "",
    "",
    Number(monto_total_usd ?? 0),
    Number(monto_total_bs ?? 0),
  ]);

  rows.push([]);
  rows.push(["RESUMEN GENERAL"]);
  rows.push(["Total Registros:", total_registros]);
  rows.push(["Total USD:", Number(monto_total_usd ?? 0)]);
  rows.push(["Total Bs:", Number(monto_total_bs ?? 0)]);

  const worksheet = XLSX.utils.aoa_to_sheet(rows);

  // Formato numérico en celdas numéricas y anchos adecuados
  worksheet["!cols"] = [
    { wch: 14 }, // Fecha
    { wch: 32 }, // Cliente
    { wch: 16 }, // RIF
    { wch: 24 }, // Forma de Pago
    { wch: 14 }, // Tipo
    { wch: 22 }, // Referencia
    { wch: 14 }, // Tasa BCV
    { wch: 14 }, // Monto USD
    { wch: 16 }, // Monto Bs
  ];

  const workbook = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(workbook, worksheet, "FormasDePago");

  XLSX.writeFile(workbook, "Reporte_Formas_Pago.xlsx");
}
