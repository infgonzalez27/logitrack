"use client";

import { Button } from "@/components/ui/button";

export function PrintButton({
  label = "Imprimir",
  className = "",
}: {
  label?: string;
  className?: string;
}) {
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
