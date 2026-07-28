"use client";

import Link from "next/link";
import { Button } from "@/components/ui/button";

export function PrintButton({
  label = "Imprimir",
  className = "",
  href,
}: {
  label?: string;
  className?: string;
  /** Ruta de vista de impresión (recomendado en PWA / móvil). */
  href?: string;
}) {
  if (href) {
    return (
      <Button
        href={href}
        variant="secondary"
        className={`lt-no-print ${className}`}
      >
        {label}
      </Button>
    );
  }

  return (
    <Button
      type="button"
      variant="secondary"
      className={`lt-no-print ${className}`}
      onClick={() => window.print()}
    >
      {label}
    </Button>
  );
}

/** Enlace textual por si el botón primario no aplica. */
export function PrintLink({
  href,
  label = "Imprimir",
}: {
  href: string;
  label?: string;
}) {
  return (
    <Link
      href={href}
      className="lt-no-print text-sm font-medium text-lt-primary hover:underline"
    >
      {label}
    </Link>
  );
}
