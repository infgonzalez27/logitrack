import { createClient } from "@/lib/supabase/server";
import { createInventarioAlmacenAction } from "@/lib/actions/entities";
import { PageHeader } from "@/components/layout/page-header";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { Button } from "@/components/ui/button";
import { ActionForm } from "@/components/forms/action-form";

export default async function NuevoInventarioAlmacenPage() {
  const supabase = await createClient();
  const { data: productos } = await supabase
    .from("productos")
    .select("id, nombre")
    .order("nombre");

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <PageHeader title="Registrar stock en almacén" />
      <Card>
        <ActionForm action={createInventarioAlmacenAction} redirectTo="/inventario-almacen">
          <Select
            label="Producto"
            name="producto_id"
            required
            placeholder="Selecciona producto"
            options={(productos ?? []).map((p) => ({
              value: p.id,
              label: p.nombre,
            }))}
          />
          <Input
            label="Stock disponible"
            name="stock_disponible"
            type="number"
            min="0"
            defaultValue="0"
            required
          />
          <Input label="Ubicación / pasillo" name="ubicacion_pasillo" />
          <Button type="submit">Guardar</Button>
        </ActionForm>
      </Card>
    </div>
  );
}
