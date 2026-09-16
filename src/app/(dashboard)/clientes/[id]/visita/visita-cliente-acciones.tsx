"use client";

import Link from "next/link";
import { Button } from "@/components/ui/button";

export function VisitaClienteAcciones({
  clienteId,
  puedeCrearOrden,
}: {
  clienteId: string;
  puedeCrearOrden: boolean;
}) {
  const visitaHref = `/clientes/${clienteId}/visita`;
  const rendicionHref = `/rendiciones/nuevo?cliente_id=${encodeURIComponent(clienteId)}&volver=${encodeURIComponent(visitaHref)}`;

  return (
    <div className="flex flex-wrap gap-3">
      <Button href={rendicionHref} variant="secondary">
        Rendición de cuentas
      </Button>
      {puedeCrearOrden ? (
        <Button
          href={`/ordenes/nuevo?cliente_id=${encodeURIComponent(clienteId)}&volver=${encodeURIComponent(visitaHref)}`}
        >
          Crear orden de distribución
        </Button>
      ) : (
        <Button
          type="button"
          disabled
          title="No tienes permiso para crear órdenes"
        >
          Crear orden de distribución
        </Button>
      )}
      <Link
        href="/visita"
        className="inline-flex items-center text-sm font-medium text-lt-primary hover:underline"
      >
        Cambiar cliente
      </Link>
    </div>
  );
}
