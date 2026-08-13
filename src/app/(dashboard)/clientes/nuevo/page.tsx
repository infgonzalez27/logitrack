import { createClienteAction } from "@/lib/actions/entities";
import { listarUsuariosAction } from "@/lib/actions/usuarios";
import {
  retornaListaRutasAction,
  retornaUsuariosDespachadoresAction,
} from "@/lib/actions/rutas";
import { PageHeader } from "@/components/layout/page-header";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { Button } from "@/components/ui/button";
import { ActionForm } from "@/components/forms/action-form";

export default async function NuevoClientePage() {
  const [vendedoresResult, rutasResult, despachadoresResult] =
    await Promise.all([
      listarUsuariosAction({ rol: "vendedor" }),
      retornaListaRutasAction(),
      retornaUsuariosDespachadoresAction(),
    ]);

  const vendedores = vendedoresResult.ok
    ? vendedoresResult.usuarios.map((u) => ({
        value: u.id,
        label: u.nombre_completo,
      }))
    : [];

  const rutas = rutasResult.ok
    ? rutasResult.rutas.map((r) => ({
        value: r.id_ruta,
        label: r.nombre_ruta,
      }))
    : [];

  const despachadores = despachadoresResult.ok
    ? despachadoresResult.despachadores.map((d) => ({
        value: d.id,
        label: d.nombre_completo,
      }))
    : [];

  const rutaUnica = rutas.length === 1 ? rutas[0] : null;

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <PageHeader
        title="Nuevo cliente"
        description="Alta de cliente con vendedor, ruta y despachador."
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
            label="Vendedor asignado"
            name="vendedor_id"
            placeholder="Sin asignar"
            options={vendedores}
          />

          {!rutasResult.ok ? (
            <p className="text-sm text-lt-danger-text">{rutasResult.error}</p>
          ) : rutas.length === 0 ? (
            <p className="text-sm text-amber-700">
              No hay rutas disponibles en la licencia. El administrador de BD
              debe provisionarlas antes de asignar.
            </p>
          ) : rutaUnica ? (
            <>
              <Input
                label="Ruta"
                name="ruta_display"
                readOnly
                value={rutaUnica.label}
              />
              <input type="hidden" name="id_ruta" value={rutaUnica.value} />
              <p className="text-xs text-lt-text-muted">
                Hay una sola ruta en la licencia; se asigna automáticamente.
              </p>
            </>
          ) : (
            <Select
              label="Ruta"
              name="id_ruta"
              required
              placeholder="Selecciona ruta"
              options={rutas}
            />
          )}

          <Select
            label="Despachador"
            name="despachador_id"
            required
            placeholder="Selecciona despachador"
            options={despachadores}
          />
          {!vendedoresResult.ok ? (
            <p className="text-sm text-lt-danger-text">
              {vendedoresResult.error}
            </p>
          ) : null}
          {!despachadoresResult.ok ? (
            <p className="text-sm text-lt-danger-text">
              {despachadoresResult.error}
            </p>
          ) : null}
          {despachadoresResult.ok && despachadores.length === 0 ? (
            <p className="text-sm text-amber-700">
              No hay usuarios con rol despachador activos.
            </p>
          ) : null}
          <Button type="submit">Guardar cliente</Button>
        </ActionForm>
      </Card>
    </div>
  );
}
