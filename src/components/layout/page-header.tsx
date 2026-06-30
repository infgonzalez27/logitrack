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
    <div className="mb-6 flex flex-col gap-4 sm:mb-8 lg:flex-row lg:items-center lg:justify-between">
      <div className="min-w-0">
        <h1 className="font-display text-xl font-bold tracking-tight text-lt-text sm:text-2xl">
          {title}
        </h1>
        {description ? (
          <p className="mt-1.5 text-sm text-lt-text-muted">{description}</p>
        ) : null}
      </div>
      {action ? (
        <div className="w-full shrink-0 lg:w-auto [&_a]:w-full [&_button]:w-full lg:[&_a]:w-auto lg:[&_button]:w-auto">
          {action}
        </div>
      ) : null}
    </div>
  );
}
