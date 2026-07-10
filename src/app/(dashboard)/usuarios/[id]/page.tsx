import { notFound } from "next/navigation";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { canResetUserPassword } from "@/lib/auth/usuario-permissions";
import { obtenerPerfilUsuarioAction } from "@/lib/actions/usuarios";
import { getRolesWithIds } from "@/lib/data/roles";
import { PageHeader } from "@/components/layout/page-header";
import { UsuarioEditarForm } from "./usuario-editar-form";
import { UsuarioContrasenaForm } from "./usuario-contrasena-form";
import { UsuarioContrasenaAviso } from "./usuario-contrasena-aviso";

export default async function UsuarioEditarPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const [result, roles, actorProfile] = await Promise.all([
    obtenerPerfilUsuarioAction(id),
    getRolesWithIds(),
    getCurrentProfile(),
  ]);

  if (!result.ok) {
    notFound();
  }

  const actorRol = getRoleNameFromProfile(actorProfile);
  const puedeResetearContrasena = canResetUserPassword(
    actorRol,
    result.perfil.rol_nombre,
  );

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
      {puedeResetearContrasena ? (
        <UsuarioContrasenaForm
          userId={result.perfil.id}
          email={result.perfil.email}
        />
      ) : (
        <UsuarioContrasenaAviso email={result.perfil.email} />
      )}
    </div>
  );
}
