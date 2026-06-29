import { createProductoAction } from "@/lib/actions/entities";
import { PageHeader } from "@/components/layout/page-header";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { ActionForm } from "@/components/forms/action-form";

export default function NuevoProductoPage() {
  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <PageHeader title="Nuevo producto" />
      <Card>
        <ActionForm action={createProductoAction} redirectTo="/productos">
          <Input label="Código de barras" name="codigo_barras" />
          <Input label="Nombre" name="nombre" required />
          <Input label="Descripción" name="descripcion" />
          <Input label="Unidad de medida" name="unidad_medida" defaultValue="unidades" />
          <Input
            label="Peso unitario (kg)"
            name="peso_unitario_kg"
            type="number"
            step="0.01"
            defaultValue="0"
          />
          <Input
            label="Cant. por unidad de medida"
            name="cant_unidad_medida"
            type="number"
            defaultValue="0"
          />
          <Button type="submit">Guardar producto</Button>
        </ActionForm>
      </Card>
    </div>
  );
}
