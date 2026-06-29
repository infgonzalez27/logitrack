import { createClient } from "@/lib/supabase/server";
import { PageHeader } from "@/components/layout/page-header";
import { Button } from "@/components/ui/button";
import { DataTable } from "@/components/ui/data-table";
import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";

export default async function ProveedoresPage() {
  const supabase = await createClient();
  const { data } = await supabase
    .from("proveedores")
    .select("*")
    .order("razon_social");

  return (
    <div className="space-y-6">
      <PageHeader
        title="Proveedores"
        action={<Button href="/proveedores/nuevo">Nuevo proveedor</Button>}
      />
      <Card>
        <DataTable
          columns={[
            { key: "rif", label: "RIF/NIT" },
            { key: "razon", label: "Razón social" },
            { key: "correo", label: "Correo" },
            { key: "estado", label: "Estado" },
          ]}
          rows={(data ?? []).map((p) => ({
            id: p.id,
            cells: {
              rif: p.rif_nit,
              razon: p.razon_social,
              correo: p.correo_e ?? "—",
              estado: (
                <Badge tone={p.activo ? "success" : "danger"}>
                  {p.activo ? "Activo" : "Inactivo"}
                </Badge>
              ),
            },
          }))}
        />
      </Card>
    </div>
  );
}
