"use client";

import { Button } from "@/components/ui/button";
import type { ReporteFormasPagoData } from "@/types/database";
import { exportFormasPagoToExcel } from "@/lib/export/formas-pago-excel";

export function ExportFormasPagoExcelButton({
  data,
}: {
  data: ReporteFormasPagoData;
}) {
  return (
    <Button
      type="button"
      variant="secondary"
      onClick={() => exportFormasPagoToExcel(data)}
      className="flex items-center gap-1.5 px-3 py-2 text-xs font-medium border-emerald-700/30 text-emerald-700 hover:bg-emerald-50 dark:border-emerald-500/30 dark:text-emerald-400 dark:hover:bg-emerald-950/20"
    >
      <svg
        className="size-4 text-emerald-600 dark:text-emerald-400"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
      >
        <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
        <polyline points="14 2 14 8 20 8" />
        <line x1="8" y1="13" x2="16" y2="13" />
        <line x1="8" y1="17" x2="16" y2="17" />
        <polyline points="10 9 9 9 8 9" />
      </svg>
      Exportar a Excel
    </Button>
  );
}
