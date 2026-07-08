import { createClient } from "@/lib/supabase/server";
import { createInventarioMovilAction } from "@/lib/actions/entities";
import { PageHeader } from "@/components/layout/page-header";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { Button } from "@/components/ui/button";
import { ActionForm } from "@/components/forms/action-form";
import { ProductoFields } from "./producto-fields";

export default async function NuevoInventarioMovilPage() {
  const supabase = await createClient();
  const [{ data: camiones }, { data: productos }] = await Promise.all([
    supabase.from("camiones").select("id, placa").order("placa"),
    supabase.from("productos").select("id, nombre, codigo_barras").order("nombre"),
  ]);

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <PageHeader title="Registrar carga móvil" />
      <Card>
        <ActionForm action={createInventarioMovilAction} redirectTo="/inventario-movil">
          <Select
            label="Camión"
            name="camion_id"
            required
            placeholder="Selecciona camión"
            options={(camiones ?? []).map((c) => ({
              value: c.id,
              label: c.placa,
            }))}
          />
          <ProductoFields productos={productos ?? []} />
          <Input
            label="Cantidad cargada"
            name="cantidad_cargada"
            type="number"
            min="0"
            defaultValue="0"
            required
          />
          <Button type="submit">Guardar</Button>
        </ActionForm>
      </Card>
    </div>
  );
}
