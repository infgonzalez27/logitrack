import { formatDateOnly } from "@/lib/format";

export function PrintDocumentHeader({
  title,
  subtitle,
  meta,
}: {
  title: string;
  subtitle?: string;
  meta?: string;
}) {
  const fecha = formatDateOnly(new Date().toISOString());

  return (
    <header className="lt-print-only mb-4 hidden border-b border-lt-border pb-3">
      <p className="text-xs font-semibold uppercase tracking-wider text-lt-text-muted">
        LogiTrack
      </p>
      <h1 className="mt-1 font-display text-xl font-bold text-lt-text">{title}</h1>
      {subtitle ? (
        <p className="mt-1 text-sm text-lt-text-muted">{subtitle}</p>
      ) : null}
      <p className="mt-2 text-xs text-lt-text-subtle">
        {meta ? `${meta} · ` : ""}
        Impreso el {fecha}
      </p>
    </header>
  );
}
