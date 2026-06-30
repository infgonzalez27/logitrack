import type { ReactNode } from "react";

export function DataTable({
  columns,
  rows,
  emptyMessage = "No hay registros.",
}: {
  columns: { key: string; label: string; className?: string }[];
  rows: { id: string; cells: Record<string, ReactNode> }[];
  emptyMessage?: string;
}) {
  if (!rows.length) {
    return (
      <p className="rounded-xl border border-dashed border-lt-border px-4 py-10 text-center text-sm text-lt-text-muted">
        {emptyMessage}
      </p>
    );
  }

  return (
    <div className="overflow-x-auto rounded-xl border border-lt-border-light bg-lt-surface">
      <table className="min-w-full divide-y divide-lt-border-light text-sm">
        <thead className="bg-lt-surface-muted">
          <tr>
            {columns.map((col) => (
              <th
                key={col.key}
                className={`px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-lt-text-muted ${col.className ?? ""}`}
              >
                {col.label}
              </th>
            ))}
          </tr>
        </thead>
        <tbody className="divide-y divide-lt-border-light bg-lt-surface">
          {rows.map((row) => (
            <tr
              key={row.id}
              className="transition-colors duration-200 hover:bg-lt-primary-muted/40"
            >
              {columns.map((col) => (
                <td
                  key={col.key}
                  className={`px-4 py-3 text-lt-text ${col.className ?? ""}`}
                >
                  {row.cells[col.key]}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
