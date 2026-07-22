import type { ReactNode } from "react";

export function Card({
  title,
  description,
  children,
  action,
  className = "",
}: {
  title?: string;
  description?: string;
  children: ReactNode;
  action?: ReactNode;
  className?: string;
}) {
  return (
    <section
      className={`lt-card rounded-2xl border border-lt-border-light bg-lt-surface shadow-[var(--lt-shadow-card)] ${className}`}
    >
      {(title || action) && (
        <div className="flex flex-col gap-3 border-b border-lt-border-light px-4 py-4 sm:flex-row sm:items-start sm:justify-between sm:px-6">
          <div className="min-w-0">
            {title ? (
              <h2 className="font-display text-base font-semibold text-lt-text sm:text-lg">
                {title}
              </h2>
            ) : null}
            {description ? (
              <p className="mt-1 text-sm text-lt-text-muted">{description}</p>
            ) : null}
          </div>
          {action ? (
            <div className="w-full shrink-0 sm:w-auto [&_a]:w-full [&_button]:w-full sm:[&_a]:w-auto sm:[&_button]:w-auto">
              {action}
            </div>
          ) : null}
        </div>
      )}
      <div className="p-4 sm:p-6">{children}</div>
    </section>
  );
}
