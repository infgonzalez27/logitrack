import type { ReactNode } from "react";

export function Card({
  title,
  description,
  children,
  action,
}: {
  title?: string;
  description?: string;
  children: ReactNode;
  action?: ReactNode;
}) {
  return (
    <section className="lt-card rounded-2xl border border-lt-border-light bg-lt-surface shadow-[var(--lt-shadow-card)]">
      {(title || action) && (
        <div className="flex items-start justify-between gap-4 border-b border-lt-border-light px-6 py-4">
          <div>
            {title && (
              <h2 className="font-display text-lg font-semibold text-lt-text">
                {title}
              </h2>
            )}
            {description && (
              <p className="mt-1 text-sm text-lt-text-muted">{description}</p>
            )}
          </div>
          {action}
        </div>
      )}
      <div className="p-6">{children}</div>
    </section>
  );
}
