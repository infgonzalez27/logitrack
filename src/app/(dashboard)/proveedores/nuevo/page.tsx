import { createProveedorAction } from "@/lib/actions/entities";
import { PageHeader } from "@/components/layout/page-header";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { ActionForm } from "@/components/forms/action-form";

export default function NuevoProveedorPage() {
  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <PageHeader title="Nuevo proveedor" />
      <Card>
        <ActionForm action={createProveedorAction} redirectTo="/proveedores">
          <Input label="RIF/NIT" name="rif_nit" required />
          <Input label="Razón social" name="razon_social" required />
          <Input label="Dirección fiscal" name="direccion_fiscal" />
          <Input label="Teléfono" name="telefono" />
          <Input label="Correo" name="correo_e" type="email" />
          <Button type="submit">Guardar proveedor</Button>
        </ActionForm>
      </Card>
    </div>
  );
}
