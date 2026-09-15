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
  return (
    <div className="flex flex-wrap gap-3">
      <Button
        type="button"
        variant="secondary"
        disabled
        title="Próximamente: rendición de cuentas desde esta pantalla"
      >
        Rendición de cuentas
      </Button>
      {puedeCrearOrden ? (
        <Button
          href={`/ordenes/nuevo?cliente_id=${encodeURIComponent(clienteId)}&volver=${encodeURIComponent(`/clientes/${clienteId}/visita`)}`}
        >
          Crear orden de distribución
        </Button>
      ) : (
        <Button type="button" disabled title="No tienes permiso para crear órdenes">
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
