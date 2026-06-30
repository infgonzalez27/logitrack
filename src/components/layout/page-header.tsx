import type { ReactNode } from "react";

export function PageHeader({
  title,
  description,
  action,
}: {
  title: string;
  description?: string;
  action?: ReactNode;
}) {
  return (
    <div className="mb-8 flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
      <div>
        <h1 className="font-display text-2xl font-bold tracking-tight text-lt-text">
          {title}
        </h1>
        {description && (
          <p className="mt-1.5 text-sm text-lt-text-muted">{description}</p>
        )}
      </div>
      {action}
    </div>
  );
}
