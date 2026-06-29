import { createClient } from "@/lib/supabase/server";
import { joinOne } from "@/lib/supabase/join";
import { PageHeader } from "@/components/layout/page-header";
import { Button } from "@/components/ui/button";
import { DataTable } from "@/components/ui/data-table";
import { Card } from "@/components/ui/card";
import { formatNumber } from "@/lib/format";

export default async function InventarioMovilPage() {
  const supabase = await createClient();
  const { data } = await supabase
    .from("inventario_movil")
    .select("*, camiones(placa), productos(nombre)")
    .order("updated_at", { ascending: false });

  return (
    <div className="space-y-6">
      <PageHeader
        title="Inventario móvil"
        description="Carga en unidades de transporte"
        action={
          <Button href="/inventario-movil/nuevo">Registrar carga</Button>
        }
      />
      <Card>
        <DataTable
          columns={[
            { key: "camion", label: "Camión" },
            { key: "producto", label: "Producto" },
            { key: "cargada", label: "Cargada" },
            { key: "entregada", label: "Entregada" },
            { key: "devolucion", label: "Devolución" },
          ]}
          rows={(data ?? []).map((row) => ({
            id: row.id,
            cells: {
              camion: joinOne(row.camiones)?.placa ?? "—",
              producto: joinOne(row.productos)?.nombre ?? "—",
              cargada: formatNumber(row.cantidad_cargada),
              entregada: formatNumber(row.cantidad_entregada),
              devolucion: formatNumber(row.cantidad_devolucion),
            },
          }))}
        />
      </Card>
    </div>
  );
}
