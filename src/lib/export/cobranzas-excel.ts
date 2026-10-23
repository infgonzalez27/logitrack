import { formatDate } from "@/lib/format";

export interface CobranzaExcelRow {
  id: string;
  fecha_rendicion: string | null;
  cliente: string;
  estado: string;
  tasa_cambio: number;
  total_efectivo: number;
  total_transferencias: number;
  total_recaudado_usd: number;
  total_recaudado_bs: number;
}

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
    td.tasa {
      text-align: right;
      mso-number-format: "#,##0.0000";
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

export function exportCobranzasToExcel(
  items: CobranzaExcelRow[],
  filtros?: { desde?: string; hasta?: string },
) {
  const hoy = new Date().toISOString().slice(0, 10);
  const totalRegistros = items.length;
  const totalEfectivo = items.reduce((s, i) => s + (Number(i.total_efectivo) || 0), 0);
  const totalTransferencias = items.reduce((s, i) => s + (Number(i.total_transferencias) || 0), 0);
  const totalRecaudadoUsd = items.reduce((s, i) => s + (Number(i.total_recaudado_usd) || 0), 0);
  const totalRecaudadoBs = items.reduce((s, i) => s + (Number(i.total_recaudado_bs) || 0), 0);

  let rowsHtml = "";
  for (const item of items) {
    rowsHtml += `
      <tr>
        <td class="text">${escapeHtml(item.fecha_rendicion ? formatDate(item.fecha_rendicion) : "—")}</td>
        <td class="text">${escapeHtml(item.cliente || "—")}</td>
        <td class="text">${escapeHtml(item.estado || "—")}</td>
        <td class="tasa">${Number(item.tasa_cambio || 0).toFixed(4)}</td>
        <td class="num">${Number(item.total_efectivo || 0).toFixed(2)}</td>
        <td class="num">${Number(item.total_transferencias || 0).toFixed(2)}</td>
        <td class="num">${Number(item.total_recaudado_usd || 0).toFixed(2)}</td>
        <td class="num">${Number(item.total_recaudado_bs || 0).toFixed(2)}</td>
      </tr>
    `;
  }

  const rangoTexto =
    filtros?.desde || filtros?.hasta
      ? `Rango: ${filtros.desde || "Inicio"} al ${filtros.hasta || "Hoy"}`
      : "Todos los registros";

  const html = `
    <html xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:x="urn:schemas-microsoft-com:office:excel" xmlns="http://www.w3.org/TR/REC-html40">
      <head>
        <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
        <!--[if gte mso 9]>
        <xml>
          <x:ExcelWorkbook>
            <x:ExcelWorksheets>
              <x:ExcelWorksheet>
                <x:Name>Cobranzas</x:Name>
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
            <td colspan="8" class="header-title">LOGITRACK — REPORTE DE COBRANZAS</td>
          </tr>
          <tr>
            <td colspan="8" class="header-meta">${escapeHtml(rangoTexto)} | Emisión: ${escapeHtml(hoy)} | Total registros: ${totalRegistros}</td>
          </tr>
          <tr><td colspan="8" style="height: 6px;"></td></tr>
          <thead>
            <tr>
              <th style="width: 110px;">Fecha</th>
              <th style="width: 250px;">Cliente</th>
              <th style="width: 100px;">Estado</th>
              <th class="num" style="width: 90px;">Tasa Cambio</th>
              <th class="num" style="width: 120px;">Efectivo ($)</th>
              <th class="num" style="width: 130px;">Transferencias ($)</th>
              <th class="num" style="width: 140px;">Total USD</th>
              <th class="num" style="width: 140px;">Total Bs</th>
            </tr>
          </thead>
          <tbody>
            ${rowsHtml || `<tr><td colspan="8" style="text-align:center; padding: 8px;">No hay cobranzas registradas en el período seleccionado.</td></tr>`}
            <tr class="total">
              <td colspan="4" style="text-align: right;">TOTAL GENERAL:</td>
              <td class="num">${totalEfectivo.toFixed(2)}</td>
              <td class="num">${totalTransferencias.toFixed(2)}</td>
              <td class="num">${totalRecaudadoUsd.toFixed(2)}</td>
              <td class="num">${totalRecaudadoBs.toFixed(2)}</td>
            </tr>
          </tbody>
        </table>

        <!-- Resumen final compacto con puros montos totales -->
        <table class="resumen-final" style="margin-top: 14px;">
          <tr>
            <td colspan="2" class="header-title" style="font-size: 11pt; border-bottom: 1pt solid #0B3A5C;">RESUMEN DE COBRANZAS</td>
          </tr>
          <tr>
            <td class="text" style="background:#f7fafc; font-weight:bold; width: 180px;">Total Cobranzas:</td>
            <td class="int" style="background:#f7fafc; font-weight:bold; width: 140px;">${totalRegistros}</td>
          </tr>
          <tr>
            <td class="text" style="background:#ffffff; font-weight:bold;">Total Efectivo (USD):</td>
            <td class="num" style="background:#ffffff; font-weight:bold;">${totalEfectivo.toFixed(2)}</td>
          </tr>
          <tr>
            <td class="text" style="background:#f7fafc; font-weight:bold;">Total Transferencias (USD):</td>
            <td class="num" style="background:#f7fafc; font-weight:bold;">${totalTransferencias.toFixed(2)}</td>
          </tr>
          <tr>
            <td class="text" style="background:#ffffff; font-weight:bold; color: #0B3A5C;">Total Recaudado (USD):</td>
            <td class="num" style="background:#ffffff; font-weight:bold; color: #0B3A5C;">${totalRecaudadoUsd.toFixed(2)}</td>
          </tr>
          <tr>
            <td class="text" style="background:#f7fafc; font-weight:bold; color: #0B3A5C;">Total Recaudado (Bs):</td>
            <td class="num" style="background:#f7fafc; font-weight:bold; color: #0B3A5C;">${totalRecaudadoBs.toFixed(2)}</td>
          </tr>
        </table>
      </body>
    </html>
  `;

  const sufijo = filtros?.desde && filtros?.hasta ? `_${filtros.desde}_${filtros.hasta}` : `_${hoy}`;
  downloadExcel(html, `Cobranzas${sufijo}.xls`);
}
