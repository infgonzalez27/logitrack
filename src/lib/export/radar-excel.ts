import * as XLSXNamespace from "xlsx";
import type { RadarDetalleReporte } from "@/types/database";

const XLSX: typeof XLSXNamespace =
  (XLSXNamespace as unknown as { default?: typeof XLSXNamespace }).default
    ?.utils
    ? (XLSXNamespace as unknown as { default: typeof XLSXNamespace }).default
    : XLSXNamespace;

function formatFecha(value: string | null | undefined): string {
  if (!value) return "—";
  const d = new Date(value.includes("T") ? value : `${value}T12:00:00`);
  if (Number.isNaN(d.getTime())) return value;
  const dd = String(d.getDate()).padStart(2, "0");
  const mm = String(d.getMonth() + 1).padStart(2, "0");
  const yyyy = d.getFullYear();
  return `${dd}/${mm}/${yyyy}`;
}

/**
 * styles.xml exacto de docs/Radar_6_Despachos.xlsx:
 * s="0" -> Calibri 12 Normal, sin relleno
 * s="1" -> Calibri 12 Negrita, sin relleno
 * s="2" -> Verdana 8 Negrita, sin relleno
 * s="3" -> Verdana 8 Normal, sin relleno
 * s="4" -> Verdana 8 Normal, relleno sólido gris claro (theme="0" tint="-0.14996795556505021")
 */
const DESPACHOS_STYLES_XML = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006" mc:Ignorable="x14ac x16r2" xmlns:x14ac="http://schemas.microsoft.com/office/spreadsheetml/2009/9/ac" xmlns:x16r2="http://schemas.microsoft.com/office/spreadsheetml/2015/02/main"><fonts count="4" x14ac:knownFonts="1"><font><sz val="12"/><color theme="1"/><name val="Calibri"/><family val="2"/><scheme val="minor"/></font><font><b/><sz val="12"/><color theme="1"/><name val="Calibri"/><family val="2"/><scheme val="minor"/></font><font><b/><sz val="8"/><color theme="1"/><name val="Verdana"/><family val="2"/></font><font><sz val="8"/><color theme="1"/><name val="Verdana"/><family val="2"/></font></fonts><fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor theme="0" tint="-0.14996795556505021"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="5"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/><xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/><xf numFmtId="0" fontId="3" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/><xf numFmtId="0" fontId="3" fillId="2" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles><dxfs count="0"/><tableStyles count="0" defaultTableStyle="TableStyleMedium9" defaultPivotStyle="PivotStyleMedium4"/></styleSheet>`;

/**
 * styles.xml exacto de docs/Radar_6_Resumen.xlsx:
 * s="0" -> Calibri 12 Normal, sin relleno
 * s="1" -> Calibri 12 Negrita, sin relleno
 * s="2" -> Verdana 8 Normal, sin relleno
 * s="3" -> Verdana 8 Normal, relleno sólido gris claro (theme="0" tint="-0.14996795556505021")
 */
const RESUMEN_STYLES_XML = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006" mc:Ignorable="x14ac x16r2" xmlns:x14ac="http://schemas.microsoft.com/office/spreadsheetml/2009/9/ac" xmlns:x16r2="http://schemas.microsoft.com/office/spreadsheetml/2015/02/main"><fonts count="4" x14ac:knownFonts="1"><font><sz val="12"/><color theme="1"/><name val="Calibri"/><family val="2"/><scheme val="minor"/></font><font><sz val="11"/><color theme="1"/><name val="Calibri"/><family val="2"/><scheme val="minor"/></font><font><b/><sz val="12"/><color theme="1"/><name val="Calibri"/><family val="2"/><scheme val="minor"/></font><font><sz val="8"/><color theme="1"/><name val="Verdana"/><family val="2"/></font></fonts><fills count="4"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor theme="7" tint="0.79998168889431442"/><bgColor indexed="65"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor theme="0" tint="-0.14996795556505021"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="0" applyNumberFormat="0" applyBorder="0" applyAlignment="0" applyProtection="0"/></cellStyleXfs><cellXfs count="4"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/><xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/><xf numFmtId="0" fontId="3" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/><xf numFmtId="0" fontId="3" fillId="3" borderId="0" xfId="1" applyNumberFormat="1" applyFont="1" applyFill="1"/></cellXfs><cellStyles count="2"><cellStyle name="20% - Énfasis4" xfId="1" builtinId="42"/><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles><dxfs count="0"/><tableStyles count="0" defaultTableStyle="TableStyleMedium9" defaultPivotStyle="PivotStyleMedium4"/></styleSheet>`;

function applyOpenXmlStylesAndDownload(
  workbook: XLSXNamespace.WorkBook,
  filename: string,
  stylesXml: string,
  colsXml: string,
  getCellStyleIndex: (colLetter: string, rowNumber: number) => number | null,
) {
  const rawBuffer = XLSX.write(workbook, {
    type: "array",
    bookType: "xlsx",
  }) as ArrayBuffer;

  const CFB =
    XLSX.CFB ??
    (XLSX as unknown as { default?: typeof XLSX }).default?.CFB;
  if (!CFB) {
    throw new Error("CFB no disponible en XLSX");
  }

  const cfb = CFB.read(new Uint8Array(rawBuffer), { type: "array" });
  const encoder = new TextEncoder();
  const decoder = new TextDecoder();

  const stylesEntry = CFB.find(cfb, "/xl/styles.xml");
  if (stylesEntry) {
    stylesEntry.content = encoder.encode(
      stylesXml,
    ) as unknown as typeof stylesEntry.content;
  }

  const sheetEntry = CFB.find(cfb, "/xl/worksheets/sheet1.xml");
  if (sheetEntry) {
    let sheetXml = decoder.decode(
      new Uint8Array(sheetEntry.content as ArrayLike<number>),
    );

    // Reemplazar o insertar <sheetFormatPr> y <cols> exactamente antes de <sheetData>
    sheetXml = sheetXml.replace(/<cols>[\s\S]*?<\/cols>/g, "");
    sheetXml = sheetXml.replace(
      "<sheetData>",
      `<sheetFormatPr baseColWidth="10" defaultRowHeight="15"/>${colsXml}<sheetData>`,
    );

    // Ajustar altura de fila ht="15.75"
    sheetXml = sheetXml.replace(/<row r="(\d+)"([^>]*)>/g, (_m, rNum, rest) => {
      if (rest.includes("ht=")) return `<row r="${rNum}"${rest}>`;
      return `<row r="${rNum}" ht="15.75"${rest}>`;
    });

    // Asignar atributo de estilo s="..." a cada celda <c r="A1" ...>
    sheetXml = sheetXml.replace(
      /<c r="([A-Z]+)(\d+)"([^>]*?)(\/?)>/g,
      (full, col: string, rowStr: string, attrs: string, selfClose: string) => {
        const rowNum = Number(rowStr);
        const sIdx = getCellStyleIndex(col, rowNum);
        const cleanAttrs = attrs.replace(/\s+s="\d+"/g, "");
        if (sIdx === null || sIdx === 0) {
          return `<c r="${col}${rowStr}"${cleanAttrs}${selfClose}>`;
        }
        return `<c r="${col}${rowStr}" s="${sIdx}"${cleanAttrs}${selfClose}>`;
      },
    );

    sheetEntry.content = encoder.encode(
      sheetXml,
    ) as unknown as typeof sheetEntry.content;
  }

  const finalZip = CFB.write(cfb, {
    type: "array",
    fileType: "zip",
  }) as ArrayBuffer;

  if (typeof window !== "undefined" && typeof document !== "undefined") {
    const blob = new Blob([finalZip], {
      type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
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

  return finalZip;
}

/**
 * Exporta el reporte de Despachos a un archivo .XLSX nativo real con formato idéntico a
 * docs/Radar_6_Despachos.xlsx:
 * - Columna A (Producto): width 46.875
 * - Columna B (Código): width 8.875
 * - Columna C (Cantidad Solicitada): width 16.625
 * - A1: Calibri 12 Negrita
 * - A2, A3: Calibri 12 Normal
 * - Fila "Cliente: ...": Col A en Verdana 8 Negrita (s=2), Col B y C en Verdana 8 Normal (s=3)
 * - Fila encabezado ("Producto", "Código", "Cantidad Solicitada"): Verdana 8 Normal + relleno gris claro (s=4)
 * - Filas de productos y "Subtotal Cliente:": Verdana 8 Normal (s=3)
 * - Fila "TOTAL GENERAL CARGA": Verdana 8 Negrita (s=2)
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

  const rows: (string | number)[][] = [
    [`RADAR #${correlativo} — REPORTE DE DESPACHOS`],
    [`Fecha de despacho: ${fecha}`],
    [`Despachador: ${despachadorNombre}`],
    [],
  ];

  // Mapa de estilos por número de fila (1-based)
  const clientHeaderRows = new Set<number>();
  const tableHeaderRows = new Set<number>();
  let totalGeneralRow = -1;

  let totalLineasGlobal = 0;
  let totalUnidadesGlobal = 0;

  for (const o of ordenesOrdenadas) {
    const cNombre =
      o.cliente?.razon_social ??
      (o.cliente as { nombre?: string } | undefined)?.nombre ??
      "Cliente";
    const cRif = o.cliente?.rif_nit ? ` (${o.cliente.rif_nit})` : "";
    const oCorrelativo = o.correlativo ? ` · Orden #${o.correlativo}` : "";

    rows.push([`Cliente: ${cNombre}${cRif}${oCorrelativo}`]);
    clientHeaderRows.add(rows.length);

    rows.push(["Producto", "Código", "Cantidad Solicitada"]);
    tableHeaderRows.add(rows.length);

    const raw = Array.isArray(o.detalles) ? o.detalles : [];
    const lineas = [...raw].sort((a, b) =>
      String(a.nombre_producto ?? "").localeCompare(
        String(b.nombre_producto ?? ""),
        "es",
      ),
    );

    if (lineas.length === 0) {
      rows.push(["Sin líneas de producto.", "", ""]);
    } else {
      let subtotalCliente = 0;
      for (const d of lineas) {
        const cant = Number(d.cantidad_solicitada ?? 0);
        subtotalCliente += cant;
        totalLineasGlobal++;
        totalUnidadesGlobal += cant;
        rows.push([
          d.nombre_producto ?? "Producto",
          d.codigo_producto ?? "—",
          cant,
        ]);
      }
      rows.push(["Subtotal Cliente:", "", subtotalCliente]);
    }
    rows.push([]);
  }

  rows.push([
    `TOTAL GENERAL CARGA (${totalLineasGlobal} ítems):`,
    "",
    totalUnidadesGlobal,
  ]);
  totalGeneralRow = rows.length;

  const worksheet = XLSX.utils.aoa_to_sheet(rows);
  const workbook = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(workbook, worksheet, "Despachos");

  const colsXml = `<cols><col min="1" max="1" width="46.875" customWidth="1"/><col min="2" max="2" width="8.875" customWidth="1"/><col min="3" max="3" width="16.625" customWidth="1"/></cols>`;

  return applyOpenXmlStylesAndDownload(
    workbook,
    `Radar_${correlativo}_Despachos.xlsx`,
    DESPACHOS_STYLES_XML,
    colsXml,
    (col, rowNum) => {
      if (rowNum === 1) return 1; // Calibri 12 Bold
      if (rowNum === 2 || rowNum === 3 || rowNum === 4) return 0; // Calibri 12 Normal
      if (clientHeaderRows.has(rowNum)) {
        return col === "A" ? 2 : 3; // A: Verdana 8 Bold, B/C: Verdana 8 Normal
      }
      if (tableHeaderRows.has(rowNum)) {
        return 4; // Verdana 8 Normal + Relleno gris claro
      }
      if (rowNum === totalGeneralRow) {
        return 2; // Verdana 8 Bold
      }
      return 3; // Verdana 8 Normal
    },
  );
}

/**
 * Exporta el reporte de Resumen a un archivo .XLSX nativo real con formato idéntico a
 * docs/Radar_6_Resumen.xlsx:
 * - Columna A (Producto / Cliente): width 36.625
 * - Columna B (Código / RIF): width 8.625
 * - Columnas C, D, E (Cargado, Despachado, Sobrante): width 9.625
 * - A1: Calibri 12 Negrita (s=1)
 * - A2, A3, A5 ("RESUMEN DE CARGA Y DESPACHO"): Calibri 12 Normal (s=0)
 * - Encabezados de tabla ("Producto", "Código", "Cargado", "Despachado", "Sobrante"): Verdana 8 Normal + relleno gris claro (s=3)
 * - Filas de datos y "Totales:": Verdana 8 Normal sin relleno (s=2)
 */
export function exportRadarResumenToExcel(reporte: RadarDetalleReporte) {
  const { radar, despachador, resumen_productos, resumen_vacios } = reporte;
  const correlativo = radar.correlativo ?? "—";
  const fecha = formatFecha(radar.fecha_despacho);
  const despachadorNombre = despachador?.nombre_completo ?? "—";

  const rows: (string | number)[][] = [
    [`RADAR #${correlativo} — REPORTE DE RESUMEN`],
    [`Fecha de despacho: ${fecha}`],
    [`Despachador: ${despachadorNombre}`],
    [],
    ["RESUMEN DE CARGA Y DESPACHO"],
    ["Producto", "Código", "Cargado", "Despachado", "Sobrante"],
  ];

  const sectionTitleRows = new Set<number>([5]);
  const tableHeaderRows = new Set<number>([6]);

  const resumen = [...(resumen_productos ?? [])].sort(
    (a, b) =>
      Number(b.cargado) - Number(a.cargado) ||
      String(a.nombre_producto).localeCompare(String(b.nombre_producto), "es"),
  );

  let totalCargado = 0;
  let totalDespachado = 0;
  let totalSobrante = 0;

  for (const p of resumen) {
    const cargado = Number(p.cargado ?? 0);
    const despachado = Number(p.despachado ?? 0);
    const sobrante = Number(p.sobrante ?? 0);
    totalCargado += cargado;
    totalDespachado += despachado;
    totalSobrante += sobrante;

    rows.push([
      p.nombre_producto ?? "—",
      p.codigo_producto ?? "—",
      cargado,
      despachado,
      sobrante,
    ]);
  }

  rows.push(["Totales:", "", totalCargado, totalDespachado, totalSobrante]);

  const vacios = resumen_vacios ?? [];
  if (vacios.length > 0) {
    rows.push([]);
    rows.push(["RESUMEN DE CONTENEDORES (VACÍOS)"]);
    sectionTitleRows.add(rows.length);

    rows.push(["Cliente", "RIF / NIT", "Envase", "Entregado", "Retirado"]);
    tableHeaderRows.add(rows.length);

    let totalEntregados = 0;
    let totalRetirados = 0;

    for (const v of vacios) {
      for (const d of v.detalles) {
        const entregado = Number(d.entregado ?? 0);
        const retirado = Number(d.retirado ?? 0);
        totalEntregados += entregado;
        totalRetirados += retirado;

        rows.push([
          v.razon_social ?? "—",
          v.rif_nit ?? "—",
          d.nombre_producto ?? "—",
          entregado,
          retirado,
        ]);
      }
    }
    rows.push(["Total Envases:", "", "", totalEntregados, totalRetirados]);
  }

  const worksheet = XLSX.utils.aoa_to_sheet(rows);
  const workbook = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(workbook, worksheet, "Resumen");

  const colsXml = `<cols><col min="1" max="1" width="36.625" customWidth="1"/><col min="2" max="2" width="8.625" customWidth="1"/><col min="3" max="5" width="9.625" customWidth="1"/></cols>`;

  return applyOpenXmlStylesAndDownload(
    workbook,
    `Radar_${correlativo}_Resumen.xlsx`,
    RESUMEN_STYLES_XML,
    colsXml,
    (_col, rowNum) => {
      if (rowNum === 1) return 1; // Calibri 12 Bold
      if (
        rowNum === 2 ||
        rowNum === 3 ||
        rowNum === 4 ||
        sectionTitleRows.has(rowNum)
      ) {
        return 0; // Calibri 12 Normal
      }
      if (tableHeaderRows.has(rowNum)) {
        return 3; // Verdana 8 Normal + Relleno gris claro
      }
      return 2; // Verdana 8 Normal sin relleno
    },
  );
}
