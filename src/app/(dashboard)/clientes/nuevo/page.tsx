import { createClienteAction } from "@/lib/actions/entities";
import { listarUsuariosAction } from "@/lib/actions/usuarios";
import { PageHeader } from "@/components/layout/page-header";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { Button } from "@/components/ui/button";
import { ActionForm } from "@/components/forms/action-form";

export default async function NuevoClientePage() {
  const vendedoresResult = await listarUsuariosAction({ rol: "vendedor" });
  const vendedores = vendedoresResult.ok
    ? vendedoresResult.usuarios.map((u) => ({
        value: u.id,
        label: u.nombre_completo,
      }))
    : [];

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <PageHeader
        title="Nuevo cliente"
        description="Asigna un vendedor responsable de la cartera del cliente."
      />
      <Card>
        <ActionForm action={createClienteAction} redirectTo="/clientes">
          <Input label="RIF/NIT" name="rif_nit" required />
          <Input label="Razón social" name="razon_social" required />
          <Input label="Dirección fiscal" name="direccion_fiscal" required />
          <Input label="Teléfono" name="telefono" />
          <Input label="Móvil" name="movil1" />
          <Input label="Correo" name="correo_e" type="email" />
          <Select
            label="Vendedor"
            name="vendedor_id"
            placeholder="Sin vendedor asignado"
            options={vendedores}
          />
          {!vendedoresResult.ok ? (
            <p className="text-sm text-lt-danger-text">{vendedoresResult.error}</p>
          ) : vendedores.length === 0 ? (
            <p className="text-sm text-lt-text-muted">
              No hay usuarios con rol vendedor para asignar.
            </p>
          ) : null}
          <Button type="submit">Guardar cliente</Button>
        </ActionForm>
      </Card>
    </div>
  );
}
