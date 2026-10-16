import type { RadarDetalleReporte } from "@/types/database";

function formatFecha(value: string | null | undefined): string {
  if (!value) return "—";
  const d = new Date(value.includes("T") ? value : `${value}T12:00:00`);
  if (Number.isNaN(d.getTime())) return value;
  const dd = String(d.getDate()).padStart(2, "0");
  const mm = String(d.getMonth() + 1).padStart(2, "0");
  const yyyy = d.getFullYear();
  return `${dd}/${mm}/${yyyy}`;
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

/**
 * Estilos para Excel:
 * - Fuente en 10pt (exacto a la instrucción del usuario).
 * - Menor espaciado entre registros / line-height compacto (line-height: 1.15, padding: 2px 5px).
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
    .section-title {
      font-size: 10pt;
      font-weight: bold;
      color: #0B3A5C;
      background-color: #f0f4f8;
      padding: 3px 6px;
      border: 0.5pt solid #cbd5e0;
      line-height: 1.15;
    }
    .client-header {
      font-size: 10pt;
      font-weight: bold;
      color: #0B3A5C;
      background-color: #EAF2F8;
      padding: 3px 6px;
      border: 0.5pt solid #B8D5E8;
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
      padding: 2.5px 6px;
    }
  </style>
`;

/**
 * Exporta el reporte de Despachos a Excel.
 * Contiene el listado de clientes con sus órdenes y productos solicitados.
 */
export function exportRadarDespachosToExcel(reporte: RadarDetalleReporte) {
  const { radar, despachador, ordenes } = reporte;
  const correlativo = radar.correlativo ?? "—";
  const fecha = formatFecha(radar.fecha_despacho);
  const despachadorNombre = despachador?.nombre_completo ?? "—";

  const ordenesOrdenadas = [...(ordenes ?? [])].sort((a, b) => {
    const na =
      a.cliente?.razon_social ??
      (a.cliente as { nombre?: string } | undefined)?.nombre ??
      "";
    const nb =
      b.cliente?.razon_social ??
      (b.cliente as { nombre?: string } | undefined)?.nombre ??
      "";
    return na.localeCompare(nb, "es");
  });

  let rowsHtml = "";
  let totalLineasGlobal = 0;
  let totalUnidadesGlobal = 0;

  for (const o of ordenesOrdenadas) {
    const cNombre =
      o.cliente?.razon_social ??
      (o.cliente as { nombre?: string } | undefined)?.nombre ??
      "Cliente";
    const cRif = o.cliente?.rif_nit ? ` (${o.cliente.rif_nit})` : "";
    const oCorrelativo = o.correlativo ? ` · Orden #${o.correlativo}` : "";
    const raw = Array.isArray(o.detalles) ? o.detalles : [];
    const lineas = [...raw].sort((a, b) =>
      String(a.nombre_producto ?? "").localeCompare(
        String(b.nombre_producto ?? ""),
        "es",
      ),
    );

    rowsHtml += `
      <tr>
        <td colspan="3" class="client-header">
          <strong>Cliente:</strong> ${escapeHtml(cNombre)}${escapeHtml(cRif)}${escapeHtml(oCorrelativo)}
        </td>
      </tr>
      <tr>
        <th style="width: 55%;">Producto</th>
        <th style="width: 25%;">Código</th>
        <th class="num" style="width: 20%;">Cantidad Solicitada</th>
      </tr>
    `;

    if (lineas.length === 0) {
      rowsHtml += `
        <tr>
          <td colspan="3" class="text" style="color: #718096; font-style: italic;">Sin líneas de producto.</td>
        </tr>
      `;
    } else {
      let subtotalCliente = 0;
      for (const d of lineas) {
        const cant = Number(d.cantidad_solicitada ?? 0);
        subtotalCliente += cant;
        totalLineasGlobal++;
        totalUnidadesGlobal += cant;
        rowsHtml += `
          <tr>
            <td class="text">${escapeHtml(d.nombre_producto ?? "Producto")}</td>
            <td class="text">${escapeHtml(d.codigo_producto ?? "—")}</td>
            <td class="num">${cant}</td>
          </tr>
        `;
      }
      rowsHtml += `
        <tr class="total">
          <td colspan="2" style="text-align: right;">Subtotal Cliente:</td>
          <td class="num">${subtotalCliente}</td>
        </tr>
      `;
    }
    rowsHtml += `<tr><td colspan="3" style="border: none; height: 6px;"></td></tr>`;
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
                <x:Name>Despachos</x:Name>
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
        <div class="header-title">RADAR #${escapeHtml(correlativo)} — REPORTE DE DESPACHOS</div>
        <div class="header-meta"><strong>Fecha de despacho:</strong> ${escapeHtml(fecha)}</div>
        <div class="header-meta"><strong>Despachador:</strong> ${escapeHtml(despachadorNombre)}</div>
        <div class="header-meta"><strong>Total Paradas:</strong> ${ordenesOrdenadas.length} · <strong>Total Uds:</strong> ${totalUnidadesGlobal}</div>
        <br />
        <table border="0" cellpadding="0" cellspacing="0" style="width: 100%; border-collapse: collapse;">
          ${rowsHtml}
          <tr class="total">
            <td colspan="2" style="text-align: right; font-size: 10pt;">TOTAL GENERAL CARGA (${totalLineasGlobal} ítems):</td>
            <td class="num">${totalUnidadesGlobal}</td>
          </tr>
        </table>
      </body>
    </html>
  `;

  downloadExcel(html, `Radar_${correlativo}_Despachos.xls`);
}

/**
 * Exporta el reporte de Resumen a Excel.
 * Contiene el resumen de carga/despacho consolidado y el resumen de vacíos.
 */
export function exportRadarResumenToExcel(reporte: RadarDetalleReporte) {
  const { radar, despachador, resumen_productos, resumen_vacios } = reporte;
  const correlativo = radar.correlativo ?? "—";
  const fecha = formatFecha(radar.fecha_despacho);
  const despachadorNombre = despachador?.nombre_completo ?? "—";

  const resumen = [...(resumen_productos ?? [])].sort(
    (a, b) =>
      Number(b.cargado) - Number(a.cargado) ||
      String(a.nombre_producto).localeCompare(String(b.nombre_producto), "es"),
  );

  let totalCargado = 0;
  let totalDespachado = 0;
  let totalSobrante = 0;

  let prodRows = "";
  for (const p of resumen) {
    const cargado = Number(p.cargado ?? 0);
    const despachado = Number(p.despachado ?? 0);
    const sobrante = Number(p.sobrante ?? 0);
    totalCargado += cargado;
    totalDespachado += despachado;
    totalSobrante += sobrante;

    prodRows += `
      <tr>
        <td class="text">${escapeHtml(p.nombre_producto)}</td>
        <td class="text">${escapeHtml(p.codigo_producto ?? "—")}</td>
        <td class="num">${cargado}</td>
        <td class="num">${despachado}</td>
        <td class="num" style="font-weight: bold;">${sobrante}</td>
      </tr>
    `;
  }

  let vaciosHtml = "";
  const vacios = resumen_vacios ?? [];
  if (vacios.length > 0) {
    let vaciosRows = "";
    let totalEntregados = 0;
    let totalRetirados = 0;

    for (const v of vacios) {
      for (let i = 0; i < v.detalles.length; i++) {
        const d = v.detalles[i];
        const entregado = Number(d.entregado ?? 0);
        const retirado = Number(d.retirado ?? 0);
        totalEntregados += entregado;
        totalRetirados += retirado;

        vaciosRows += `
          <tr>
            <td class="text">${escapeHtml(v.razon_social)}</td>
            <td class="text">${escapeHtml(v.rif_nit ?? "—")}</td>
            <td class="text">${escapeHtml(d.nombre_producto)}</td>
            <td class="num">${entregado}</td>
            <td class="num">${retirado}</td>
          </tr>
        `;
      }
    }

    vaciosHtml = `
      <br />
      <div class="section-title">RESUMEN DE CONTENEDORES (VACÍOS)</div>
      <table border="0" cellpadding="0" cellspacing="0" style="width: 100%; border-collapse: collapse;">
        <thead>
          <tr>
            <th style="width: 30%;">Cliente</th>
            <th style="width: 18%;">RIF / NIT</th>
            <th style="width: 26%;">Envase</th>
            <th class="num" style="width: 13%;">Entregado</th>
            <th class="num" style="width: 13%;">Retirado</th>
          </tr>
        </thead>
        <tbody>
          ${vaciosRows}
          <tr class="total">
            <td colspan="3" style="text-align: right;">Total Envases:</td>
            <td class="num">${totalEntregados}</td>
            <td class="num">${totalRetirados}</td>
          </tr>
        </tbody>
      </table>
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
                <x:Name>Resumen</x:Name>
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
        <div class="header-title">RADAR #${escapeHtml(correlativo)} — REPORTE DE RESUMEN</div>
        <div class="header-meta"><strong>Fecha de despacho:</strong> ${escapeHtml(fecha)}</div>
        <div class="header-meta"><strong>Despachador:</strong> ${escapeHtml(despachadorNombre)}</div>
        <br />
        <div class="section-title">RESUMEN DE CARGA Y DESPACHO</div>
        <table border="0" cellpadding="0" cellspacing="0" style="width: 100%; border-collapse: collapse;">
          <thead>
            <tr>
              <th style="width: 45%;">Producto</th>
              <th style="width: 19%;">Código</th>
              <th class="num" style="width: 12%;">Cargado</th>
              <th class="num" style="width: 12%;">Despachado</th>
              <th class="num" style="width: 12%;">Sobrante</th>
            </tr>
          </thead>
          <tbody>
            ${prodRows}
            <tr class="total">
              <td colspan="2" style="text-align: right;">Totales:</td>
              <td class="num">${totalCargado}</td>
              <td class="num">${totalDespachado}</td>
              <td class="num">${totalSobrante}</td>
            </tr>
          </tbody>
        </table>
        ${vaciosHtml}
      </body>
    </html>
  `;

  downloadExcel(html, `Radar_${correlativo}_Resumen.xls`);
}
