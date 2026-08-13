import { notFound } from "next/navigation";
import { obtenerClienteParaEditarAction } from "@/lib/actions/clientes";
import { listarUsuariosAction } from "@/lib/actions/usuarios";
import {
  retornaListaRutasAction,
  retornaUsuariosDespachadoresAction,
} from "@/lib/actions/rutas";
import { PageHeader } from "@/components/layout/page-header";
import { ClienteEditarForm } from "./cliente-editar-form";

export default async function ClienteEditarPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const [result, vendedoresResult, rutasResult, despachadoresResult] =
    await Promise.all([
      obtenerClienteParaEditarAction(id),
      listarUsuariosAction({ rol: "vendedor" }),
      retornaListaRutasAction(),
      retornaUsuariosDespachadoresAction(),
    ]);

  if (!result.ok) {
    notFound();
  }

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

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <PageHeader
        title="Editar cliente"
        description={result.cliente.razon_social}
      />
      {!vendedoresResult.ok ? (
        <p className="lt-alert-error">{vendedoresResult.error}</p>
      ) : null}
      {!rutasResult.ok ? (
        <p className="lt-alert-error">{rutasResult.error}</p>
      ) : null}
      {!despachadoresResult.ok ? (
        <p className="lt-alert-error">{despachadoresResult.error}</p>
      ) : null}
      <ClienteEditarForm
        cliente={result.cliente}
        vendedores={vendedores}
        rutas={rutas}
        despachadores={despachadores}
      />
    </div>
  );
}
