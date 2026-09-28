import { createClient } from "@/lib/supabase/server";
import { joinOne } from "@/lib/supabase/join";
import { PageHeader } from "@/components/layout/page-header";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { InventarioAlmacenTabla } from "./inventario-almacen-tabla";

export default async function InventarioAlmacenPage() {
  const supabase = await createClient();
  const { data } = await supabase
    .from("inventario_almacen")
    .select("*, productos(nombre, codigo_producto, codigo_barras)")
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
        <InventarioAlmacenTabla
          filas={(data ?? []).map((row) => {
            const producto = joinOne(row.productos);
            return {
              id: row.id,
              producto: producto?.nombre ?? "—",
              codigo: producto?.codigo_producto ?? null,
              codigo_barras: producto?.codigo_barras ?? null,
              disponible: Number(row.stock_disponible ?? 0),
              comprometido: Number(row.stock_comprometido ?? 0),
              ubicacion: row.ubicacion_pasillo ?? null,
            };
          })}
        />
      </Card>
    </div>
  );
}
