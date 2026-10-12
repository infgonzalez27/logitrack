import { createClient } from "@/lib/supabase/server";
import { createInventarioMovilAction } from "@/lib/actions/entities";
import { PageHeader } from "@/components/layout/page-header";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { Button } from "@/components/ui/button";
import { ActionForm } from "@/components/forms/action-form";
import { ProductoFields } from "./producto-fields";

export default async function NuevoInventarioMovilPage({
  searchParams,
}: {
  searchParams?: Promise<{ camion_id?: string }>;
}) {
  const resolvedParams = searchParams ? await searchParams : {};
  const defaultCamionId =
    typeof resolvedParams.camion_id === "string"
      ? resolvedParams.camion_id
      : "";

  const supabase = await createClient();
  const [{ data: camiones }, { data: productos }] = await Promise.all([
    supabase.from("camiones").select("id, placa, modelo").order("placa"),
    supabase.from("productos").select("id, nombre, codigo_barras").order("nombre"),
  ]);

  const redirectTo = defaultCamionId
    ? `/inventario-movil?camion_id=${defaultCamionId}`
    : "/inventario-movil";

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <PageHeader title="Registrar carga móvil" />
      <Card>
        <ActionForm action={createInventarioMovilAction} redirectTo={redirectTo}>
          <Select
            label="Camión"
            name="camion_id"
            required
            placeholder="Selecciona camión"
            defaultValue={defaultCamionId}
            options={(camiones ?? []).map((c) => ({
              value: c.id,
              label: `${c.placa}${c.modelo ? ` — ${c.modelo}` : ""}`,
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
