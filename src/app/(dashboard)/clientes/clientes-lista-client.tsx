"use client";

import { useState } from "react";
import Link from "next/link";
import { DataTable } from "@/components/ui/data-table";
import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { ModalDescuentosCliente } from "@/components/forms/modal-descuentos-cliente";
import type { Cliente } from "@/types/database";

export function ClientesListaClient({ clientes }: { clientes: Cliente[] }) {
  const [selectedCliente, setSelectedCliente] = useState<{
    id: string;
    razon_social: string;
  } | null>(null);

  return (
    <>
      <Card>
        <DataTable
          columns={[
            { key: "rif", label: "RIF/NIT" },
            { key: "razon", label: "Razón social" },
            { key: "telefono", label: "Teléfono" },
            { key: "estado", label: "Estado" },
            { key: "acciones", label: "Acciones" },
          ]}
          rows={clientes.map((c) => ({
            id: c.id,
            cells: {
              rif: c.rif_nit,
              razon: c.razon_social,
              telefono: c.telefono ?? c.movil1 ?? "—",
              estado: (
                <Badge tone={c.activo ? "success" : "danger"}>
                  {c.activo ? "Activo" : "Inactivo"}
                </Badge>
              ),
              acciones: (
                <div className="flex flex-wrap items-center gap-3">
                  <Button
                    type="button"
                    variant="secondary"
                    className="px-2.5 py-1 text-xs"
                    onClick={() =>
                      setSelectedCliente({
                        id: c.id,
                        razon_social: c.razon_social,
                      })
                    }
                  >
                    Descuentos
                  </Button>
                  <Link
                    href={`/clientes/${c.id}`}
                    className="text-sm font-medium text-lt-primary underline-offset-2 hover:underline"
                  >
                    Editar
                  </Link>
                </div>
              ),
            },
          }))}
        />
      </Card>

      {selectedCliente ? (
        <ModalDescuentosCliente
          clienteId={selectedCliente.id}
          clienteNombre={selectedCliente.razon_social}
          isOpen={!!selectedCliente}
          onClose={() => setSelectedCliente(null)}
        />
      ) : null}
    </>
  );
}
