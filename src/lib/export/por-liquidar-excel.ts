import type { OrdenPorLiquidarDetalle } from "@/types/database";
import { formatNumber } from "@/lib/format";
import { agruparPorTramoAntiguedad } from "@/lib/rendiciones/antiguedad";

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

function formatFechaCorta(iso: string | null): string {
  if (!iso) return "—";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso.slice(0, 10);
  return d.toISOString().slice(0, 10);
}

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
    .tramo-header {
      background-color: #e2e8f0;
      color: #0B3A5C;
      font-size: 10pt;
      font-weight: bold;
      padding: 4px 6px;
      border: 0.5pt solid #cbd5e1;
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
    tr.subtotal td {
      font-weight: bold;
      background-color: #f8fafc;
      border-top: 1pt solid #94a3b8;
      padding: 2.5px 6px;
    }
    tr.total td {
      font-weight: bold;
      background-color: #edf2f7;
      border-top: 1.5pt solid #0B3A5C;
      color: #0B3A5C;
      line-height: 1.15;
      padding: 3px 6px;
    }
    .resumen-final {
      margin-top: 10px;
      border-collapse: collapse;
    }
    .resumen-final td, .resumen-final th {
      font-size: 10pt;
      line-height: 1.15;
      padding: 3px 6px;
    }
  </style>
`;

export function exportPorLiquidarToExcel(items: OrdenPorLiquidarDetalle[]) {
  const hoy = new Date().toISOString().slice(0, 10);
  const grupos = agruparPorTramoAntiguedad(items);
  const clientesUnicos = new Set(items.map((i) => i.cliente_id)).size;
  const totalOrdenes = items.length;
  const totalMontoUsd = items.reduce(
    (s, i) => s + (Number(i.monto_por_liquidar) || 0),
    0,
  );

  let seccionesHtml = "";
  for (const grupo of grupos) {
    let rowsHtml = "";
    if (grupo.ordenes.length === 0) {
      rowsHtml = `
        <tr>
          <td colspan="7" style="text-align:center; color:#718096; padding: 4px 6px;">Sin órdenes en este tramo.</td>
        </tr>
      `;
    } else {
      for (const ord of grupo.ordenes) {
        const ordenLabel = ord.correlativo ? `#${ord.correlativo}` : ord.orden_id.slice(0, 8);
        rowsHtml += `
          <tr>
            <td class="text">${escapeHtml(ordenLabel)}</td>
            <td class="text">${escapeHtml(ord.factura_origen_numero || "—")}</td>
            <td class="text">${escapeHtml(ord.razon_social || "—")}</td>
            <td class="text">${escapeHtml(ord.rif_nit || "—")}</td>
            <td class="text">${escapeHtml(formatFechaCorta(ord.fecha_despacho))}</td>
            <td class="int">${Number(ord.dias_vencidos) || 0}</td>
            <td class="num">${(Number(ord.monto_por_liquidar) || 0).toFixed(2)}</td>
          </tr>
        `;
      }
    }

    seccionesHtml += `
      <tr><td colspan="7" style="height: 8px; border: none;"></td></tr>
      <tr>
        <td colspan="7" class="tramo-header">
          ${escapeHtml(grupo.label)} (${escapeHtml(grupo.rangoTexto)}) — ${formatNumber(grupo.totalOrdenes)} orden(es)
        </td>
      </tr>
      <tr>
        <th style="width: 90px;">Orden</th>
        <th style="width: 110px;">Factura</th>
        <th style="width: 260px;">Cliente (Razón Social)</th>
        <th style="width: 120px;">RIF / NIT</th>
        <th style="width: 100px;">Fecha Despacho</th>
        <th class="num" style="width: 95px;">Días Vencidos</th>
        <th class="num" style="width: 135px;">Monto por Liquidar (USD)</th>
      </tr>
      ${rowsHtml}
      <tr class="subtotal">
        <td colspan="5" style="text-align: right;">Subtotal ${escapeHtml(grupo.label)}:</td>
        <td class="int">${grupo.totalOrdenes}</td>
        <td class="num">${grupo.totalMonto.toFixed(2)}</td>
      </tr>
    `;
  }

  let resumenTramosHtml = "";
  for (const grupo of grupos) {
    resumenTramosHtml += `
      <tr>
        <td class="text">${escapeHtml(grupo.label)}</td>
        <td class="int">${grupo.totalOrdenes}</td>
        <td class="num">${grupo.totalMonto.toFixed(2)}</td>
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
                <x:Name>OrdenesPorLiquidar</x:Name>
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
            <td colspan="7" class="header-title">LOGITRACK — ÓRDENES POR LIQUIDAR POR ANTIGÜEDAD</td>
          </tr>
          <tr>
            <td colspan="7" class="header-meta">Fecha de emisión: ${escapeHtml(hoy)} | Clientes: ${formatNumber(clientesUnicos)} | Total órdenes: ${formatNumber(totalOrdenes)}</td>
          </tr>
          <tbody>
            ${seccionesHtml}
            <tr><td colspan="7" style="height: 8px; border: none;"></td></tr>
            <tr class="total">
              <td colspan="5" style="text-align: right;">TOTAL GENERAL POR LIQUIDAR:</td>
              <td class="int">${totalOrdenes}</td>
              <td class="num">${totalMontoUsd.toFixed(2)}</td>
            </tr>
          </tbody>
        </table>

        <table class="resumen-final" style="margin-top: 14px;">
          <tr>
            <td colspan="3" class="header-title" style="font-size: 11pt; border-bottom: 1pt solid #0B3A5C;">RESUMEN POR TRAMO DE ANTIGÜEDAD</td>
          </tr>
          <tr>
            <th style="width: 240px;">Tramo</th>
            <th class="num" style="width: 110px;">Cant. Órdenes</th>
            <th class="num" style="width: 140px;">Monto (USD)</th>
          </tr>
          ${resumenTramosHtml}
          <tr class="total">
            <td class="text">TOTAL GENERAL</td>
            <td class="int">${totalOrdenes}</td>
            <td class="num">${totalMontoUsd.toFixed(2)}</td>
          </tr>
        </table>
      </body>
    </html>
  `;

  downloadExcel(html, `Ordenes_Por_Liquidar_${hoy}.xls`);
}
