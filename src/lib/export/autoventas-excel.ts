import * as XLSXNamespace from "xlsx";
import type { ReporteEntregasResponse } from "@/lib/actions/reporte-entregas";
import type { CargaTicketData } from "@/lib/autoventas/carga-ticket";
import type { VaciosPorOrdenData } from "@/lib/autoventas/vacios-por-orden";
import { formatDate } from "@/lib/format";

const XLSX: typeof XLSXNamespace =
  (XLSXNamespace as unknown as { default?: typeof XLSXNamespace }).default
    ?.utils
    ? (XLSXNamespace as unknown as { default: typeof XLSXNamespace }).default
    : XLSXNamespace;

/**
 * styles.xml exacto extraído de docs/AutoVentas_Entregas.xlsx:
 *
 * Fuentes:
 * - Font 0: Calibri 12 Normal (color theme 1)
 * - Font 1: Calibri 11 Negrita (color theme 3 - Título 3)
 * - Font 2: Tahoma 9 Normal (color theme 1)
 * - Font 3: Tahoma 9 Negrita (color theme 1)
 * - Font 4: Tahoma 11 Negrita (color theme 1)
 *
 * Bordes:
 * - Border 0: Sin bordes
 * - Border 1: Borde inferior medio (medium) color theme 4 tint 0.39997558519241921 (Título 3)
 * - Border 2: Bordes finos completos (thin)
 *
 * Estilos de celda (cellXfs):
 * - s="0": Default (Calibri 12)
 * - s="1": Tahoma 9 Normal (datos de filas y celdas normales)
 * - s="2": Tahoma 9 Negrita (subtítulos tipo "CLIENTE: ...", "RESUMEN CONSOLIDADO...", "TOTALES GENERALES...")
 * - s="3": Tahoma 11 Negrita (nombre de la empresa A1)
 * - s="4": Tahoma 9 Normal con borde fino (totales generales A30..B35)
 * - s="5": Calibri 11 Negrita con borde inferior medio tipo Título 3 (encabezados de tabla A6..G6, A26..D26)
 */
const ENTREGAS_STYLES_XML = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006" mc:Ignorable="x14ac x16r2" xmlns:x14ac="http://schemas.microsoft.com/office/spreadsheetml/2009/9/ac" xmlns:x16r2="http://schemas.microsoft.com/office/spreadsheetml/2015/02/main"><fonts count="5" x14ac:knownFonts="1"><font><sz val="12"/><color theme="1"/><name val="Calibri"/><family val="2"/><scheme val="minor"/></font><font><b/><sz val="11"/><color theme="3"/><name val="Calibri"/><family val="2"/><scheme val="minor"/></font><font><sz val="9"/><color theme="1"/><name val="Tahoma"/><family val="2"/></font><font><b/><sz val="9"/><color theme="1"/><name val="Tahoma"/><family val="2"/></font><font><b/><sz val="11"/><color theme="1"/><name val="Tahoma"/><family val="2"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="3"><border><left/><right/><top/><bottom/><diagonal/></border><border><left/><right/><top/><bottom style="medium"><color theme="4" tint="0.39997558519241921"/></bottom><diagonal/></border><border><left style="thin"><color indexed="64"/></left><right style="thin"><color indexed="64"/></right><top style="thin"><color indexed="64"/></top><bottom style="thin"><color indexed="64"/></bottom><diagonal/></border></borders><cellStyleXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="1" applyNumberFormat="0" applyFill="0" applyAlignment="0" applyProtection="0"/></cellStyleXfs><cellXfs count="6"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/><xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/><xf numFmtId="0" fontId="3" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/><xf numFmtId="0" fontId="4" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/><xf numFmtId="0" fontId="2" fillId="0" borderId="2" xfId="0" applyNumberFormat="1" applyFont="1" applyBorder="1"/><xf numFmtId="0" fontId="1" fillId="0" borderId="1" xfId="1" applyNumberFormat="1"/></cellXfs><cellStyles count="2"><cellStyle name="Normal" xfId="0" builtinId="0"/><cellStyle name="Título 3" xfId="1" builtinId="18"/></cellStyles><dxfs count="0"/><tableStyles count="0" defaultTableStyle="TableStyleMedium9" defaultPivotStyle="PivotStyleMedium4"/><extLst><ext uri="{EB79DEF2-80B8-43e5-95BD-54CBDDF9020C}" xmlns:x14="http://schemas.microsoft.com/office/spreadsheetml/2009/9/main"><x14:slicerStyles defaultSlicerStyle="SlicerStyleLight1"/></ext><ext uri="{9260A510-F301-46a8-8635-F512D64BE5F5}" xmlns:x15="http://schemas.microsoft.com/office/spreadsheetml/2010/11/main"><x15:timelineStyles defaultTimelineStyle="TimeSlicerStyleLight1"/></ext></extLst></styleSheet>`;

/**
 * Ancho exacto de columnas según docs/AutoVentas_Entregas.xlsx:
 * Col A: 30.5
 * Col B: 14.875
 * Col C: 12.625
 * Col D: 11.625
 * Col E: 8.625
 * Col F: 9.625
 * Col G: 10.625
 */
const ENTREGAS_COLS_XML = `<cols><col min="1" max="1" width="30.5" customWidth="1"/><col min="2" max="2" width="14.875" customWidth="1"/><col min="3" max="3" width="12.625" customWidth="1"/><col min="4" max="4" width="11.625" customWidth="1"/><col min="5" max="5" width="8.625" customWidth="1"/><col min="6" max="6" width="9.625" customWidth="1"/><col min="7" max="7" width="10.625" customWidth="1"/></cols>`;

function applyOpenXmlStylesAndDownload(
  workbook: XLSXNamespace.WorkBook,
  filename: string,
  stylesXml: string,
  colsXml: string,
  getCellStyleIndex: (colLetter: string, rowNumber: number) => number | null,
  getRowHeightAndAttrs?: (rowNumber: number) => { ht: number; thickBot?: boolean } | null,
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

    // Asegurar namespaces mc y x14ac en <worksheet>
    sheetXml = sheetXml.replace(
      "<worksheet ",
      '<worksheet xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006" mc:Ignorable="x14ac" xmlns:x14ac="http://schemas.microsoft.com/office/spreadsheetml/2009/9/ac" ',
    );

    // Reemplazar o insertar <sheetFormatPr> y <cols> exactamente antes de <sheetData>
    sheetXml = sheetXml.replace(/<cols>[\s\S]*?<\/cols>/g, "");
    sheetXml = sheetXml.replace(
      "<sheetData>",
      `<sheetFormatPr baseColWidth="10" defaultRowHeight="15" x14ac:dyDescent="0.25"/>${colsXml}<sheetData>`,
    );

    // Ajustar alturas de fila y atributos (thickBot)
    sheetXml = sheetXml.replace(/<row r="(\d+)"([^>]*)>/g, (_m, rNumStr, rest) => {
      const rNum = Number(rNumStr);
      const rowCfg = getRowHeightAndAttrs ? getRowHeightAndAttrs(rNum) : null;
      const cleanRest = rest.replace(/\s+ht="[^"]*"/g, "").replace(/\s+thickBot="[^"]*"/g, "");

      if (rowCfg) {
        const thickAttr = rowCfg.thickBot ? ' thickBot="1"' : "";
        return `<row r="${rNumStr}" ht="${rowCfg.ht}"${thickAttr}${cleanRest}>`;
      }
      return `<row r="${rNumStr}" ht="15.75"${cleanRest}>`;
    });

    // Asignar atributo de estilo s="..." a cada celda <c r="A1" ...>
    sheetXml = sheetXml.replace(
      /<c r="([A-Z]+)(\d+)"([^>]*?)(\/?)>/g,
      (_full, col: string, rowStr: string, attrs: string, selfClose: string) => {
        const rowNum = Number(rowStr);
        const sIdx = getCellStyleIndex(col, rowNum);
        const cleanAttrs = attrs.replace(/\s+s="\d+"/g, "");
        if (sIdx === null || sIdx === 0) {
          return `<c r="${col}${rowStr}" s="0"${cleanAttrs}${selfClose}>`;
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
 * Exporta el reporte de Entregas de AutoVentas a un archivo .xlsx nativo real con formato
 * idéntico a docs/AutoVentas_Entregas.xlsx:
 * - Fuentes: Calibri 11 Negrita (Título 3), Tahoma 11 Negrita, Tahoma 9 Normal, Tahoma 9 Negrita.
 * - Bordes: Inferior medio para encabezados (Título 3) y fino para totales.
 * - Anchos de columna exactos: A (30.5), B (14.875), C (12.625), D (11.625), E (8.625), F (9.625), G (10.625).
 * - Altura de filas: 16.5 para encabezados Título 3, 15.75 para el resto.
 */
export function exportEntregasAutoventasToExcel(
  data: ReporteEntregasResponse,
  empresaNombre?: string | null,
) {
  // Construcción de filas con padding a 7 columnas (A..G) para coincidir con la plantilla exacta
  const rawRows: (string | number)[][] = [
    [empresaNombre ? empresaNombre.toUpperCase() : "LOGITRACK"],
    ["REPORTE DE PRODUCTOS ENTREGADOS (AUTOVIO/AUTOVETAS)"],
    [`Fecha de jornada: ${data.fecha}`],
    [],
  ];

  // Mapas para identificar el estilo y altura de cada fila
  const rowStyleType = new Map<number, "empresa" | "titulo3" | "subtitulo_seccion" | "totales" | "normal">();

  // Fila 1: Nombre de la empresa
  rowStyleType.set(1, "empresa");
  // Filas 2, 3, 4: normal
  rowStyleType.set(2, "normal");
  rowStyleType.set(3, "normal");
  rowStyleType.set(4, "normal");

  let totalGeneralCargados = 0;
  let totalGeneralEntregados = 0;
  let totalGeneralDevolucion = 0;

  for (const entrega of data.entregas) {
    const rIdxCliente = rawRows.length + 1;
    rawRows.push([
      `CLIENTE: ${entrega.razon_social} (${entrega.rif_nit || "S/R"}) — ORDEN #${entrega.correlativo}`,
    ]);
    rowStyleType.set(rIdxCliente, "subtitulo_seccion");

    const rIdxHeader = rawRows.length + 1;
    rawRows.push(["Producto", "Código", "Cargados", "Entregados", "Devolución", "Precio USD", "Subtotal USD"]);
    rowStyleType.set(rIdxHeader, "titulo3");

    for (const prod of entrega.productos) {
      totalGeneralCargados += Number(prod.cantidad_cargada || 0);
      totalGeneralEntregados += Number(prod.cantidad_entregada || 0);
      totalGeneralDevolucion += Number(prod.devolucion || 0);

      const rIdxProd = rawRows.length + 1;
      rawRows.push([
        prod.nombre,
        prod.codigo || "—",
        Number(prod.cantidad_cargada || 0),
        Number(prod.cantidad_entregada || 0),
        Number(prod.devolucion || 0),
        Number(prod.precio_unitario_usd || 0),
        Number(prod.subtotal_usd || 0),
      ]);
      rowStyleType.set(rIdxProd, "normal");
    }

    if (entrega.contenedores && entrega.contenedores.length > 0) {
      const rIdxContHeader = rawRows.length + 1;
      rawRows.push(["  Contenedores / Envases:", "", "Entregado", "Retirado"]);
      rowStyleType.set(rIdxContHeader, "normal");

      for (const c of entrega.contenedores) {
        const rIdxCont = rawRows.length + 1;
        rawRows.push([
          `  ${c.nombre}`,
          c.codigo || "—",
          Number(c.cantidad_entregada || 0),
          Number(c.cantidad_retirada || 0),
        ]);
        rowStyleType.set(rIdxCont, "normal");
      }
    }

    const rIdxBlank = rawRows.length + 1;
    rawRows.push([]);
    rowStyleType.set(rIdxBlank, "normal");
  }

  // Resumen Consolidado de Contenedores
  if (data.resumen_contenedores && data.resumen_contenedores.length > 0) {
    const rIdxResTitle = rawRows.length + 1;
    rawRows.push(["RESUMEN CONSOLIDADO DE CONTENEDORES (VACÍOS)"]);
    rowStyleType.set(rIdxResTitle, "subtitulo_seccion");

    const rIdxResHeader = rawRows.length + 1;
    rawRows.push(["Envase", "Código", "Total Entregado", "Total Retirado"]);
    rowStyleType.set(rIdxResHeader, "titulo3");

    for (const rc of data.resumen_contenedores) {
      const rIdxResRow = rawRows.length + 1;
      rawRows.push([
        rc.nombre,
        rc.codigo || "—",
        Number(rc.total_entregado || 0),
        Number(rc.total_retirado || 0),
      ]);
      rowStyleType.set(rIdxResRow, "normal");
    }

    const rIdxBlankRes = rawRows.length + 1;
    rawRows.push([]);
    rowStyleType.set(rIdxBlankRes, "normal");
  }

  // Totales Generales de la Jornada
  const rIdxTotTitle = rawRows.length + 1;
  rawRows.push(["TOTALES GENERALES DE LA JORNADA"]);
  rowStyleType.set(rIdxTotTitle, "subtitulo_seccion");

  const pushTotalRow = (label: string, value: number) => {
    const rIdx = rawRows.length + 1;
    rawRows.push([label, value]);
    rowStyleType.set(rIdx, "totales");
  };

  pushTotalRow("Total Cargados", totalGeneralCargados);
  pushTotalRow("Total Entregados", totalGeneralEntregados);
  pushTotalRow("Total Devolución", totalGeneralDevolucion);
  if (data.total_general_usd !== undefined) {
    pushTotalRow("Total Facturado USD", Number(data.total_general_usd || 0));
  }
  if (data.total_contenedores_entregados !== undefined) {
    pushTotalRow("Total Contenedores Cargados/Entregados", Number(data.total_contenedores_entregados || 0));
  }
  if (data.total_contenedores_retirados !== undefined) {
    pushTotalRow("Total Contenedores Retirados", Number(data.total_contenedores_retirados || 0));
  }

  // Asegurar que cada fila tenga 7 celdas (A..G) para rellenar las celdas vacías con s="1"
  const paddedRows = rawRows.map((r) => {
    const copy = [...r];
    while (copy.length < 7) {
      copy.push("");
    }
    return copy;
  });

  const worksheet = XLSX.utils.aoa_to_sheet(paddedRows);
  const workbook = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(workbook, worksheet, "Entregas");

  const fileName = `AutoVentas_Entregas_${data.fecha}.xlsx`;

  // Asignador de índices de estilo s="..."
  const getCellStyleIndex = (col: string, rowNum: number): number | null => {
    const type = rowStyleType.get(rowNum) ?? "normal";

    if (type === "empresa") {
      // Fila 1: A1 es s="3" (Tahoma 11 Bold), B1..G1 son s="1"
      return col === "A" ? 3 : 1;
    }

    if (type === "subtitulo_seccion") {
      // "CLIENTE...", "RESUMEN CONSOLIDADO...", "TOTALES GENERALES...":
      // A es s="2" (Tahoma 9 Bold), B..G son s="1"
      return col === "A" ? 2 : 1;
    }

    if (type === "titulo3") {
      // Encabezados de tabla: todas las columnas con s="5" (Calibri 11 Bold con borde inferior medio)
      return 5;
    }

    if (type === "totales") {
      // Totales: Columna A y B con s="4" (Tahoma 9 Normal con borde fino), C..G con s="1"
      return col === "A" || col === "B" ? 4 : 1;
    }

    // "normal": todas las columnas con s="1" (Tahoma 9 Normal)
    return 1;
  };

  // Asignador de alturas y atributos de fila
  const getRowHeightAndAttrs = (rowNum: number): { ht: number; thickBot?: boolean } | null => {
    const type = rowStyleType.get(rowNum);
    if (type === "titulo3") {
      return { ht: 16.5, thickBot: true };
    }
    return { ht: 15.75 };
  };

  return applyOpenXmlStylesAndDownload(
    workbook,
    fileName,
    ENTREGAS_STYLES_XML,
    ENTREGAS_COLS_XML,
    getCellStyleIndex,
    getRowHeightAndAttrs,
  );
}

/**
 * Exporta el reporte de Carga o Descarga de AutoVentas a un archivo .xlsx
 */
export function exportCargaDescargaAutoventasToExcel(
  data: CargaTicketData,
  empresaNombre?: string | null,
  vaciosPorOrden?: VaciosPorOrdenData | null,
) {
  const esDescarga = data.tipo === "descarga";
  const titulo = esDescarga
    ? "COMPROBANTE DE DESCARGA DE CAMIÓN (SOBRANTE A ALMACÉN)"
    : "COMPROBANTE DE CARGA DE CAMIÓN (ALMACÉN A MÓVIL)";

  const rows: (string | number)[][] = [
    [empresaNombre ? empresaNombre.toUpperCase() : "LOGITRACK"],
    [titulo],
    [`Camión: ${data.camion}`],
    [`Fecha: ${data.fecha ? formatDate(data.fecha) : "—"}`],
    [],
    ["Código", "Producto", "Cantidad", "Entregado", "Disponible"],
  ];

  let totalCantidad = 0;
  let totalEntregado = 0;
  let totalDisponible = 0;

  for (const l of data.lineas) {
    const cant = Number(l.cantidad || 0);
    const ent = Number(l.entregado || 0);
    const disp = Number(l.disponible || 0);
    totalCantidad += cant;
    totalEntregado += ent;
    totalDisponible += disp;

    rows.push([
      l.codigo || "—",
      l.producto,
      cant,
      l.entregado !== undefined ? ent : "—",
      l.disponible !== undefined ? disp : "—",
    ]);
  }

  rows.push(["TOTALES:", "", totalCantidad, totalEntregado, totalDisponible]);

  if (vaciosPorOrden && vaciosPorOrden.ordenes.length > 0) {
    rows.push([]);
    rows.push(["VACÍOS RETIRADOS POR ORDEN"]);
    const vaciosHeader = ["Orden", "Cliente", ...vaciosPorOrden.tipos.map((t) => t.nombre), "Total Retirados"];
    rows.push(vaciosHeader);

    for (const o of vaciosPorOrden.ordenes) {
      const row: (string | number)[] = [
        `#${o.correlativo}`,
        o.cliente,
      ];
      for (const t of vaciosPorOrden.tipos) {
        row.push(Number(o.retirados[t.id] ?? 0));
      }
      row.push(Number(o.total || 0));
      rows.push(row);
    }
  }

  const worksheet = XLSX.utils.aoa_to_sheet(rows);
  worksheet["!cols"] = [
    { wch: 14 },
    { wch: 38 },
    { wch: 14 },
    { wch: 14 },
    { wch: 14 },
  ];

  const workbook = XLSX.utils.book_new();
  const sheetName = esDescarga ? "Descarga" : "Carga";
  XLSX.utils.book_append_sheet(workbook, worksheet, sheetName);
  const fileName = `AutoVentas_${sheetName}_${data.camion.replace(/\s+/g, "_")}.xlsx`;
  XLSX.writeFile(workbook, fileName);
}
