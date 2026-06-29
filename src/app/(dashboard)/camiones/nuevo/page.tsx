import { createCamionAction } from "@/lib/actions/entities";
import { PageHeader } from "@/components/layout/page-header";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { ActionForm } from "@/components/forms/action-form";

export default function NuevoCamionPage() {
  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <PageHeader title="Nuevo camión" />
      <Card>
        <ActionForm action={createCamionAction} redirectTo="/camiones">
          <Input label="Placa" name="placa" required />
          <Input label="Modelo" name="modelo" required />
          <Input
            label="Capacidad (kg)"
            name="capacidad_kg"
            type="number"
            step="0.01"
            required
          />
          <Input
            label="Volumen (m³)"
            name="volumen_m3"
            type="number"
            step="0.01"
          />
          <Button type="submit">Guardar camión</Button>
        </ActionForm>
      </Card>
    </div>
  );
}
