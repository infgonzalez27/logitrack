"use client";

import { useState } from "react";
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
                <div className="flex items-center gap-2">
                  <Button
                    variant="secondary"
                    className="text-xs px-2.5 py-1 flex items-center gap-1.5"
                    onClick={() =>
                      setSelectedCliente({
                        id: c.id,
                        razon_social: c.razon_social,
                      })
                    }
                  >
                    <span>🏷️</span>
                    <span>Descuentos</span>
                  </Button>
                </div>
              ),
            },
          }))}
        />
      </Card>

      {selectedCliente && (
        <ModalDescuentosCliente
          clienteId={selectedCliente.id}
          clienteNombre={selectedCliente.razon_social}
          isOpen={!!selectedCliente}
          onClose={() => setSelectedCliente(null)}
        />
      )}
    </>
  );
}
