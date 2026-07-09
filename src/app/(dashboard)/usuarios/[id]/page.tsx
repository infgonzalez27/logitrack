import { notFound } from "next/navigation";
import { obtenerPerfilUsuarioAction } from "@/lib/actions/usuarios";
import { getRolesWithIds } from "@/lib/data/roles";
import { PageHeader } from "@/components/layout/page-header";
import { UsuarioEditarForm } from "./usuario-editar-form";

export default async function UsuarioEditarPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const [result, roles] = await Promise.all([
    obtenerPerfilUsuarioAction(id),
    getRolesWithIds(),
  ]);

  if (!result.ok) {
    notFound();
  }

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <PageHeader
        title="Editar usuario"
        description={result.perfil.nombre_completo}
      />
      <UsuarioEditarForm
        perfil={result.perfil}
        roles={roles.map((r) => ({ id: r.id, label: r.label }))}
      />
    </div>
  );
}
