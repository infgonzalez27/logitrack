import { listarUsuariosAction } from "@/lib/actions/usuarios";
import {
  retornaListaRutasAction,
  retornaUsuariosDespachadoresAction,
} from "@/lib/actions/rutas";
import { PageHeader } from "@/components/layout/page-header";
import { NuevoClienteForm } from "./nuevo-cliente-form";

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
  const rutaUnica =
    rutasResult.ok &&
    (rutasResult.total_registros === 1 || rutas.length === 1)
      ? rutas[0]
      : null;

  const despachadores = despachadoresResult.ok
    ? despachadoresResult.despachadores.map((d) => ({
        value: d.id,
        label: d.nombre_completo,
      }))
    : [];

  return (
    <div className="mx-auto max-w-3xl space-y-6">
      <PageHeader
        title="Nuevo cliente"
        description="Alta de cliente con vendedor, ruta, despachador, políticas de crédito y descuentos por producto."
      />
      <NuevoClienteForm
        vendedores={vendedores}
        rutas={rutas}
        rutaUnica={rutaUnica}
        despachadores={despachadores}
        vendedoresError={
          vendedoresResult.ok ? null : vendedoresResult.error
        }
        rutasError={rutasResult.ok ? null : rutasResult.error}
        despachadoresError={
          despachadoresResult.ok ? null : despachadoresResult.error
        }
      />
    </div>
  );
}
