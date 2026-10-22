import type { OrdenPorLiquidarCliente } from "@/types/database";
import { formatCurrency, formatNumber } from "@/lib/format";

function escapeHtml(text: unknown): string {
  if (text == null) return "";
  return String(text)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function downloadExcel(html: string, filename: string) {
  const blob = new Blob([`\ufeff${html}`], {
    type: "application/vnd.ms-excel;charset=utf-8",
  });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

/**
 * Estilos para Excel:
 * - Fuente a 10pt.
 * - Line-height compacto (1.15).
 * - Menos espaciado entre registros.
 * - Resumen compacto al final con montos totales.
 */
const EXCEL_STYLES = `
  <style>
    body, table {
      font-family: Calibri, Arial, sans-serif;
      font-size: 10pt;
      line-height: 1.15;
      color: #1a202c;
    }
    .header-title {
      font-size: 12pt;
      font-weight: bold;
      color: #0B3A5C;
      padding: 3px 0;
    }
    .header-meta {
      font-size: 10pt;
      color: #4a5568;
      padding: 1px 0;
      line-height: 1.15;
    }
    th {
      background-color: #0B3A5C;
      color: #ffffff;
      font-size: 10pt;
      font-weight: bold;
      padding: 2.5px 6px;
      text-align: left;
      border: 0.5pt solid #0B3A5C;
      line-height: 1.15;
    }
    th.num {
      text-align: right;
    }
    td {
      font-size: 10pt;
      line-height: 1.15;
      padding: 2px 6px;
      border: 0.5pt solid #e2e8f0;
      vertical-align: middle;
    }
    td.num {
      text-align: right;
      mso-number-format: "#,##0.00";
    }
    td.int {
      text-align: right;
      mso-number-format: "#,##0";
    }
    td.text {
      mso-number-format: "\\@";
    }
    tr.total td {
      font-weight: bold;
      background-color: #f7fafc;
      border-top: 1pt solid #4a5568;
      line-height: 1.15;
      padding: 3px 6px;
    }
    .resumen-final {
      margin-top: 10px;
      border-collapse: collapse;
      width: 320px;
    }
    .resumen-final td {
      font-size: 10pt;
      line-height: 1.15;
      padding: 3px 6px;
    }
  </style>
`;

export function exportPorLiquidarToExcel(items: OrdenPorLiquidarCliente[]) {
  const hoy = new Date().toISOString().slice(0, 10);
  const totalClientes = items.length;
  const totalOrdenes = items.reduce((s, i) => s + (Number(i.cant_ordenes) || 0), 0);
  const totalMontoUsd = items.reduce((s, i) => s + (Number(i.monto_por_liquidar) || 0), 0);

  let rowsHtml = "";
  for (const item of items) {
    const dias = Number(item.dias_vencidos) || 0;
    const ordenes = Number(item.cant_ordenes) || 0;
    const monto = Number(item.monto_por_liquidar) || 0;

    rowsHtml += `
      <tr>
        <td class="text">${escapeHtml(item.razon_social || "—")}</td>
        <td class="text">${escapeHtml(item.rif_nit || "—")}</td>
        <td class="int">${dias}</td>
        <td class="int">${ordenes}</td>
        <td class="num">${monto.toFixed(2)}</td>
      </tr>
    `;
  }

  const html = `
    <html xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:x="urn:schemas-microsoft-com:office:excel" xmlns="http://www.w3.org/TR/REC-html40">
      <head>
        <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
        <!--[if gte mso 9]>
        <xml>
          <x:ExcelWorkbook>
            <x:ExcelWorksheets>
              <x:ExcelWorksheet>
                <x:Name>CuentasPorCobrar</x:Name>
                <x:WorksheetOptions>
                  <x:DisplayGridlines/>
                </x:WorksheetOptions>
              </x:ExcelWorksheet>
            </x:ExcelWorksheets>
          </x:ExcelWorkbook>
        </xml>
        <![endif]-->
        ${EXCEL_STYLES}
      </head>
      <body>
        <table>
          <tr>
            <td colspan="5" class="header-title">LOGITRACK — REPORTE DE CUENTAS POR COBRAR (POR LIQUIDAR)</td>
          </tr>
          <tr>
            <td colspan="5" class="header-meta">Fecha de emisión: ${escapeHtml(hoy)} | Total clientes con deuda: ${formatNumber(totalClientes)}</td>
          </tr>
          <tr><td colspan="5" style="height: 6px;"></td></tr>
          <thead>
            <tr>
              <th style="width: 280px;">Cliente (Razón Social)</th>
              <th style="width: 140px;">RIF / NIT</th>
              <th class="num" style="width: 100px;">Días Vencidos</th>
              <th class="num" style="width: 110px;">Cant. Órdenes</th>
              <th class="num" style="width: 140px;">Monto por Liquidar (USD)</th>
            </tr>
          </thead>
          <tbody>
            ${rowsHtml || `<tr><td colspan="5" style="text-align:center; padding: 8px;">No hay registros de cuentas por cobrar.</td></tr>`}
            <tr class="total">
              <td colspan="2" style="text-align: right;">TOTAL GENERAL:</td>
              <td class="int">—</td>
              <td class="int">${totalOrdenes}</td>
              <td class="num">${totalMontoUsd.toFixed(2)}</td>
            </tr>
          </tbody>
        </table>

        <!-- Resumen final compacto con montos totales -->
        <table class="resumen-final" style="margin-top: 14px;">
          <tr>
            <td colspan="2" class="header-title" style="font-size: 11pt; border-bottom: 1pt solid #0B3A5C;">RESUMEN DE CARTERA</td>
          </tr>
          <tr>
            <td class="text" style="background:#f7fafc; font-weight:bold; width: 180px;">Total Clientes con Saldo:</td>
            <td class="int" style="background:#f7fafc; font-weight:bold; width: 140px;">${totalClientes}</td>
          </tr>
          <tr>
            <td class="text" style="background:#ffffff; font-weight:bold;">Total Órdenes por Liquidar:</td>
            <td class="int" style="background:#ffffff; font-weight:bold;">${totalOrdenes}</td>
          </tr>
          <tr>
            <td class="text" style="background:#f7fafc; font-weight:bold; color: #0B3A5C;">Monto Total por Liquidar (USD):</td>
            <td class="num" style="background:#f7fafc; font-weight:bold; color: #0B3A5C;">${totalMontoUsd.toFixed(2)}</td>
          </tr>
        </table>
      </body>
    </html>
  `;

  downloadExcel(html, `Cuentas_Por_Cobrar_${hoy}.xls`);
}
