import * as XLSX from "xlsx";
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

/**
 * Exporta el reporte de Despachos a un archivo .XLSX nativo real.
 * Anchos especificados:
 * - Columna A (Producto): 46
 * - Columna B (Código): 16
 * - Columna C (Cantidad Solicitada): 16
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
    rows.push(["Producto", "Código", "Cantidad Solicitada"]);

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
        rows.push([d.nombre_producto ?? "Producto", d.codigo_producto ?? "—", cant]);
      }
      rows.push(["Subtotal Cliente:", "", subtotalCliente]);
    }
    rows.push([]);
  }

  rows.push([`TOTAL GENERAL CARGA (${totalLineasGlobal} ítems):`, "", totalUnidadesGlobal]);

  const worksheet = XLSX.utils.aoa_to_sheet(rows);

  // Anchos exactos según el informe técnico de integración
  worksheet["!cols"] = [
    { wch: 46 }, // Columna A: Producto
    { wch: 16 }, // Columna B: Código
    { wch: 16 }, // Columna C: Cantidad Solicitada
  ];

  const workbook = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(workbook, worksheet, "Despachos");

  XLSX.writeFile(workbook, `Radar_${correlativo}_Despachos.xlsx`);
}

/**
 * Exporta el reporte de Resumen a un archivo .XLSX nativo real.
 * Anchos especificados:
 * - Columna A (Producto): 35
 * - Columna B (Código): 12
 * - Columna C (Cargado): 8
 * - Columna D (Despachado): 10
 * - Columna E (Sobrante): 8
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
    rows.push(["Cliente", "RIF / NIT", "Envase", "Entregado", "Retirado"]);

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

  // Anchos exactos según el informe técnico de integración
  worksheet["!cols"] = [
    { wch: 35 }, // Columna A: Producto (o Cliente)
    { wch: 12 }, // Columna B: Código (o RIF)
    { wch: 8 },  // Columna C: Cargado (o Envase)
    { wch: 10 }, // Columna D: Despachado (o Entregado)
    { wch: 8 },  // Columna E: Sobrante (o Retirado)
  ];

  const workbook = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(workbook, worksheet, "Resumen");

  XLSX.writeFile(workbook, `Radar_${correlativo}_Resumen.xlsx`);
}
