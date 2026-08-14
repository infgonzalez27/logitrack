import { createProductoAction } from "@/lib/actions/entities";
import { listarTiposContenedoresAction } from "@/lib/actions/ordenes";
import { PageHeader } from "@/components/layout/page-header";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { Button } from "@/components/ui/button";
import { ActionForm } from "@/components/forms/action-form";

export default async function NuevoProductoPage() {
  const contenedoresResult = await listarTiposContenedoresAction();
  const contenedores = contenedoresResult.ok
    ? contenedoresResult.contenedores
    : [];

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
          <Input
            label="URL / ruta de imagen"
            name="imagen_path"
            placeholder="/productos/zulia-caja.webp o URL pública de Storage"
          />
          <p className="text-xs text-lt-text-muted">
            Ruta relativa en Storage (ej.{" "}
            <code className="rounded bg-lt-surface-muted px-1">
              /productos/nombre.webp
            </code>
            ) o URL pública. Preferir fotos de caja/empaque.
          </p>
          <Select
            label="Empaque / contenedor (opcional)"
            name="contenedor_id"
            placeholder="Sin empaque retornable"
            options={contenedores.map((c) => ({
              value: c.id,
              label: c.nombre,
            }))}
          />
          <Input
            label="Unidades por contenedor"
            name="unidades_por_contenedor"
            type="number"
            min="1"
            step="1"
            defaultValue="1"
          />
          <p className="text-xs text-lt-text-muted">
            Opcional. Solo aplica si el producto usa envase retornable.
          </p>
          <Button type="submit">Guardar producto</Button>
        </ActionForm>
      </Card>
    </div>
  );
}
