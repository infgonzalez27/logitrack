import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { createClienteAction } from "@/lib/actions/entities";
import { PageHeader } from "@/components/layout/page-header";
import { Button } from "@/components/ui/button";
import { DataTable } from "@/components/ui/data-table";
import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";

export default async function ClientesPage() {
  const supabase = await createClient();
  const { data: clientes } = await supabase
    .from("clientes")
    .select("*")
    .order("razon_social");

  return (
    <div className="space-y-6">
      <PageHeader
        title="Clientes"
        description="Módulo 1 — Entidades maestras"
        action={<Button href="/clientes/nuevo">Nuevo cliente</Button>}
      />
      <Card>
        <DataTable
          columns={[
            { key: "rif", label: "RIF/NIT" },
            { key: "razon", label: "Razón social" },
            { key: "telefono", label: "Teléfono" },
            { key: "estado", label: "Estado" },
          ]}
          rows={(clientes ?? []).map((c) => ({
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
            },
          }))}
        />
      </Card>
    </div>
  );
}
