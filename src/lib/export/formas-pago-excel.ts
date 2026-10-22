import type { ReporteFormasPagoData } from "@/types/database";
import { formatCurrency, formatDate, formatNumber } from "@/lib/format";

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
 * - Fuente a 10pt (exacto al requerimiento).
 * - Menos espaciado entre registros / line-height compacto (1.15).
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

  let rowsHtml = "";
  for (const m of movimientos ?? []) {
    const usd = Number(m.monto_usd ?? 0);
    const bs = Number(m.monto_bs ?? 0);
    const ref = m.referencia_bancaria || m.cuenta_bancaria || "—";
    const tipo = m.es_bancario ? "Bancario" : "No bancario";

    rowsHtml += `
      <tr>
        <td class="text">${escapeHtml(formatDate(m.fecha_rendicion))}</td>
        <td class="text">${escapeHtml(m.cliente_nombre ?? "—")}</td>
        <td class="text">${escapeHtml(m.cliente_rif ?? "—")}</td>
        <td class="text">${escapeHtml(m.fpago_concepto ?? "—")}</td>
        <td class="text">${escapeHtml(tipo)}</td>
        <td class="text">${escapeHtml(ref)}</td>
        <td class="num">${usd.toFixed(2)}</td>
        <td class="num">${bs.toFixed(2)}</td>
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
                <x:Name>FormasDePago</x:Name>
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
        <div class="header-title">REPORTE DE FORMAS DE PAGO EN RENDICIONES</div>
        <div class="header-meta"><strong>Período:</strong> ${escapeHtml(fecha_desde)} al ${escapeHtml(fecha_hasta)}</div>
        <div class="header-meta"><strong>Filtro:</strong> ${solo_bancarios ? "Solo bancarios" : "Todas las formas de pago"}</div>
        <br />
        <table border="0" cellpadding="0" cellspacing="0" style="width: 100%; border-collapse: collapse;">
          <thead>
            <tr>
              <th style="width: 10%;">Fecha</th>
              <th style="width: 25%;">Cliente</th>
              <th style="width: 12%;">RIF</th>
              <th style="width: 18%;">Forma de Pago</th>
              <th style="width: 10%;">Tipo</th>
              <th style="width: 11%;">Referencia</th>
              <th class="num" style="width: 7%;">Monto USD</th>
              <th class="num" style="width: 7%;">Monto Bs</th>
            </tr>
          </thead>
          <tbody>
            ${rowsHtml}
            <tr class="total">
              <td colspan="6" style="text-align: right;">TOTALES (${total_registros} registros):</td>
              <td class="num">${Number(monto_total_usd ?? 0).toFixed(2)}</td>
              <td class="num">${Number(monto_total_bs ?? 0).toFixed(2)}</td>
            </tr>
          </tbody>
        </table>
        <br />
        <table class="resumen-final" border="1" cellpadding="0" cellspacing="0">
          <tr style="background-color: #0B3A5C; color: #ffffff;">
            <th colspan="2">RESUMEN GENERAL</th>
          </tr>
          <tr>
            <td><strong>Total Registros:</strong></td>
            <td style="text-align: right;">${total_registros}</td>
          </tr>
          <tr>
            <td><strong>Total USD:</strong></td>
            <td style="text-align: right; font-weight: bold; color: #166534;">$${Number(monto_total_usd ?? 0).toFixed(2)}</td>
          </tr>
          <tr>
            <td><strong>Total Bs:</strong></td>
            <td style="text-align: right; font-weight: bold;">Bs. ${Number(monto_total_bs ?? 0).toFixed(2)}</td>
          </tr>
        </table>
      </body>
    </html>
  `;

  downloadExcel(
    html,
    `Reporte_Formas_Pago_${fecha_desde}_${fecha_hasta}.xls`,
  );
}
