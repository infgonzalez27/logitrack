import { createClient } from "@/lib/supabase/server";
import { joinOne } from "@/lib/supabase/join";
import { PageHeader } from "@/components/layout/page-header";
import { Button } from "@/components/ui/button";
import { DataTable } from "@/components/ui/data-table";
import { Card } from "@/components/ui/card";
import { formatNumber } from "@/lib/format";

export default async function InventarioAlmacenPage() {
  const supabase = await createClient();
  const { data } = await supabase
    .from("inventario_almacen")
    .select("*, productos(nombre, codigo_barras)")
    .order("updated_at", { ascending: false });

  return (
    <div className="space-y-6">
      <PageHeader
        title="Inventario almacén"
        description="Stock en centro de distribución"
        action={
          <Button href="/inventario-almacen/nuevo">Registrar stock</Button>
        }
      />
      <Card>
        <DataTable
          columns={[
            { key: "producto", label: "Producto" },
            { key: "disponible", label: "Disponible" },
            { key: "comprometido", label: "Comprometido" },
            { key: "ubicacion", label: "Ubicación" },
          ]}
          rows={(data ?? []).map((row) => ({
            id: row.id,
            cells: {
              producto: joinOne(row.productos)?.nombre ?? "—",
              disponible: formatNumber(row.stock_disponible),
              comprometido: formatNumber(row.stock_comprometido),
              ubicacion: row.ubicacion_pasillo ?? "—",
            },
          }))}
        />
      </Card>
    </div>
  );
}
