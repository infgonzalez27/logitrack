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

  const dataColumns = columns.filter(
    (col) => col.key !== "acciones" && col.label.trim() !== "",
  );
  const actionColumn = columns.find((col) => col.key === "acciones");

  return (
    <>
      <div className="lt-print-hide space-y-3 md:hidden">
        {rows.map((row) => (
          <article
            key={row.id}
            className="rounded-xl border border-lt-border-light bg-lt-surface p-4 shadow-sm"
          >
            <dl className="space-y-3">
              {dataColumns.map((col) => (
                <div
                  key={col.key}
                  className="flex items-start justify-between gap-4"
                >
                  <dt className="shrink-0 text-xs font-medium uppercase tracking-wide text-lt-text-subtle">
                    {col.label}
                  </dt>
                  <dd className="min-w-0 text-right text-sm text-lt-text">
                    {row.cells[col.key]}
                  </dd>
                </div>
              ))}
            </dl>
            {actionColumn && row.cells.acciones ? (
              <div className="mt-4 border-t border-lt-border-light pt-3">
                {row.cells.acciones}
              </div>
            ) : null}
          </article>
        ))}
      </div>

      <div className="lt-print-table-wrap hidden overflow-x-auto rounded-xl border border-lt-border-light bg-lt-surface md:block">
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
    </>
  );
}
