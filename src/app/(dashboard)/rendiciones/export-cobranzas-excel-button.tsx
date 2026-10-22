"use client";

import { useState } from "react";
import { exportCobranzasToExcel, type CobranzaExcelRow } from "@/lib/export/cobranzas-excel";

interface ExportCobranzasExcelButtonProps {
  items: CobranzaExcelRow[];
  filtros?: { desde?: string; hasta?: string };
  label?: string;
}

export function ExportCobranzasExcelButton({
  items,
  filtros,
  label = "Exportar a Excel",
}: ExportCobranzasExcelButtonProps) {
  const [exporting, setExporting] = useState(false);

  const handleExport = () => {
    try {
      setExporting(true);
      exportCobranzasToExcel(items, filtros);
    } finally {
      setExporting(false);
    }
  };

  return (
    <button
      type="button"
      onClick={handleExport}
      disabled={exporting || items.length === 0}
      className="lt-no-print inline-flex items-center gap-1.5 rounded-xl border border-emerald-600 bg-emerald-50 px-4 py-2 text-sm font-semibold text-emerald-800 shadow-sm transition hover:bg-emerald-100 disabled:cursor-not-allowed disabled:opacity-50"
      title="Exportar listado a archivo Excel (.xls)"
    >
      <svg
        className="h-4 w-4"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
        aria-hidden="true"
      >
        <path
          strokeLinecap="round"
          strokeLinejoin="round"
          strokeWidth={2}
          d="M12 10v6m0 0l-3-3m3 3l3-3m2 8H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
        />
      </svg>
      {exporting ? "Generando…" : label}
    </button>
  );
}
