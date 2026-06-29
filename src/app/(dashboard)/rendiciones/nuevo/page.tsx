import { createClient } from "@/lib/supabase/server";
import { createRendicionAction } from "@/lib/actions/entities";
import { PageHeader } from "@/components/layout/page-header";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { Button } from "@/components/ui/button";
import { ActionForm } from "@/components/forms/action-form";

export default async function NuevaRendicionPage() {
  const supabase = await createClient();
  const { data: clientes } = await supabase
    .from("clientes")
    .select("id, razon_social")
    .eq("activo", true)
    .order("razon_social");

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <PageHeader title="Nueva rendición de cuentas" />
      <Card>
        <ActionForm action={createRendicionAction} redirectTo="/rendiciones">
          <Select
            label="Cliente"
            name="cliente_id"
            required
            placeholder="Selecciona cliente"
            options={(clientes ?? []).map((c) => ({
              value: c.id,
              label: c.razon_social,
            }))}
          />
          <Input label="Observaciones" name="observaciones" />
          <Button type="submit">Crear rendición</Button>
        </ActionForm>
      </Card>
    </div>
  );
}
