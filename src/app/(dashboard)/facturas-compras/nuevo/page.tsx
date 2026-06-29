import { createClient } from "@/lib/supabase/server";
import { createFacturaCompraAction } from "@/lib/actions/entities";
import { PageHeader } from "@/components/layout/page-header";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { Button } from "@/components/ui/button";
import { ActionForm } from "@/components/forms/action-form";

export default async function NuevaFacturaCompraPage() {
  const supabase = await createClient();
  const { data: proveedores } = await supabase
    .from("proveedores")
    .select("id, razon_social")
    .eq("activo", true)
    .order("razon_social");

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <PageHeader title="Nueva factura de compra" />
      <Card>
        <ActionForm action={createFacturaCompraAction} redirectTo="/facturas-compras">
          <Select
            label="Proveedor"
            name="proveedor_id"
            required
            placeholder="Selecciona proveedor"
            options={(proveedores ?? []).map((p) => ({
              value: p.id,
              label: p.razon_social,
            }))}
          />
          <Input label="Nº factura" name="numero_factura" required />
          <Input
            label="Fecha emisión"
            name="fecha_emision"
            type="date"
            required
          />
          <Input label="Fecha vencimiento" name="fecha_vencimiento" type="date" />
          <Input
            label="Subtotal"
            name="monto_subtotal"
            type="number"
            step="0.01"
            required
          />
          <Input
            label="Impuesto"
            name="monto_impuesto"
            type="number"
            step="0.01"
            defaultValue="0"
          />
          <Button type="submit">Guardar factura</Button>
        </ActionForm>
      </Card>
    </div>
  );
}
