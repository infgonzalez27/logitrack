"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import type { CargaTicketData } from "@/lib/autoventas/carga-ticket";
import type { VaciosPorOrdenData } from "@/lib/autoventas/vacios-por-orden";
import type { ReporteEntregasResponse } from "@/lib/actions/reporte-entregas";
import {
  exportCargaDescargaAutoventasToExcel,
  exportEntregasAutoventasToExcel,
} from "@/lib/export/autoventas-excel";

export function CargaPrintControls({
  descarga = false,
  cargaData,
  entregasData,
  empresaNombre,
  vaciosPorOrden,
}: {
  descarga?: boolean;
  cargaData?: CargaTicketData | null;
  entregasData?: ReporteEntregasResponse | null;
  empresaNombre?: string | null;
  vaciosPorOrden?: VaciosPorOrdenData | null;
}) {
  const [aviso, setAviso] = useState<string | null>(null);
  const esEntregas = Boolean(entregasData);
  const etiqueta = esEntregas ? "entregas" : descarga ? "descarga" : "carga";

  function imprimir() {
    setAviso(null);
    try {
      window.print();
    } catch {
      setAviso(
        "No se pudo abrir el diálogo de impresión. Usa el menú del navegador → Imprimir.",
      );
    }
  }

  function exportarExcel() {
    try {
      if (entregasData) {
        exportEntregasAutoventasToExcel(entregasData, empresaNombre);
      } else if (cargaData) {
        exportCargaDescargaAutoventasToExcel(cargaData, empresaNombre, vaciosPorOrden);
      }
    } catch (e) {
      setAviso("Error al generar el archivo Excel: " + (e instanceof Error ? e.message : String(e)));
    }
  }

  return (
    <div className="lt-no-print mb-4 flex flex-col gap-3">
      <div>
        <p className="text-sm font-medium text-lt-text">
          Comprobante de {etiqueta}
        </p>
        <p className="text-sm text-lt-text-muted">
          Toca <strong>Imprimir {etiqueta}</strong> para hoja tamaño carta o{" "}
          <strong>Exportar a Excel</strong> para descargar la planilla en formato .xlsx.
        </p>
        {aviso ? <p className="mt-2 text-sm text-lt-danger-text">{aviso}</p> : null}
      </div>
      <div className="flex flex-wrap gap-2">
        <Button type="button" variant="primary" onClick={imprimir}>
          Imprimir {etiqueta}
        </Button>
        {(entregasData || cargaData) && (
          <Button type="button" variant="secondary" onClick={exportarExcel}>
            📊 Exportar a Excel
          </Button>
        )}
        <Button type="button" variant="secondary" href="/autoventas">
          Volver a AutoVentas
        </Button>
      </div>
    </div>
  );
}
