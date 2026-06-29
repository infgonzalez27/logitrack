import { createClient } from "@/lib/supabase/server";
import { createPagoProveedorAction } from "@/lib/actions/entities";
import { PageHeader } from "@/components/layout/page-header";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { Button } from "@/components/ui/button";
import { ActionForm } from "@/components/forms/action-form";

export default async function NuevoPagoProveedorPage() {
  const supabase = await createClient();
  const { data: proveedores } = await supabase
    .from("proveedores")
    .select("id, razon_social")
    .eq("activo", true)
    .order("razon_social");

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <PageHeader title="Nuevo pago a proveedor" />
      <Card>
        <ActionForm action={createPagoProveedorAction} redirectTo="/pagos-proveedores">
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
          <Input
            label="Monto total pagado"
            name="monto_total_pagado"
            type="number"
            step="0.01"
            min="0.01"
            required
          />
          <Input label="Glosa / concepto" name="glosa_concepto" />
          <Button type="submit">Registrar pago</Button>
        </ActionForm>
      </Card>
    </div>
  );
}
