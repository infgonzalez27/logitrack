import { createClient } from "@/lib/supabase/server";
import { PageHeader } from "@/components/layout/page-header";
import { Button } from "@/components/ui/button";
import { DataTable } from "@/components/ui/data-table";
import { Card } from "@/components/ui/card";
import { formatNumber } from "@/lib/format";

export default async function ProductosPage() {
  const supabase = await createClient();
  const { data } = await supabase.from("productos").select("*").order("nombre");

  return (
    <div className="space-y-6">
      <PageHeader
        title="Productos"
        action={<Button href="/productos/nuevo">Nuevo producto</Button>}
      />
      <Card>
        <DataTable
          columns={[
            { key: "codigo", label: "Código" },
            { key: "nombre", label: "Nombre" },
            { key: "unidad", label: "Unidad" },
            { key: "peso", label: "Peso unit. (kg)" },
          ]}
          rows={(data ?? []).map((p) => ({
            id: p.id,
            cells: {
              codigo: p.codigo_barras ?? "—",
              nombre: p.nombre,
              unidad: p.unidad_medida,
              peso: formatNumber(p.peso_unitario_kg),
            },
          }))}
        />
      </Card>
    </div>
  );
}
