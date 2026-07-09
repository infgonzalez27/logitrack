import Link from "next/link";
import { listarUsuariosAction } from "@/lib/actions/usuarios";
import { getRolesOptions } from "@/lib/data/roles";
import { PageHeader } from "@/components/layout/page-header";
import { Button } from "@/components/ui/button";
import { DataTable } from "@/components/ui/data-table";
import { Card } from "@/components/ui/card";
import { UsuariosBusqueda } from "./usuarios-busqueda";

export default async function UsuariosPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string; rol?: string }>;
}) {
  const { q = "", rol = "" } = await searchParams;
  const [result, roles] = await Promise.all([
    listarUsuariosAction({ nombre: q, rol }),
    getRolesOptions(),
  ]);

  const usuarios = result.ok ? result.usuarios : [];

  return (
    <div className="space-y-6">
      <PageHeader
        title="Usuarios"
        description="Perfiles vinculados a Supabase Auth"
        action={
          <Button href="/usuarios/registrar" variant="primary">
            Registrar usuario
          </Button>
        }
      />

      <UsuariosBusqueda defaultValue={q} rolValue={rol} roles={roles} />

      {!result.ok && (
        <p className="text-sm text-lt-danger-text">{result.error}</p>
      )}

      <Card>
        <DataTable
          columns={[
            { key: "nombre", label: "Nombre del perfil" },
            { key: "rol", label: "Rol" },
            { key: "acciones", label: "" },
          ]}
          rows={usuarios.map((u) => ({
            id: u.id,
            cells: {
              nombre: u.nombre_completo,
              rol: u.rol_nombre ?? "—",
              acciones: (
                <Link
                  href={`/usuarios/${u.id}`}
                  className="text-sm font-medium text-lt-primary hover:underline"
                >
                  Editar
                </Link>
              ),
            },
          }))}
          emptyMessage={
            q || rol
              ? "No se encontraron usuarios con ese criterio."
              : "No hay usuarios registrados."
          }
        />
      </Card>

      <p className="text-sm text-lt-text-muted">
        También puedes registrar desde{" "}
        <Link href="/register" className="underline">
          /register
        </Link>{" "}
        (ruta pública de desarrollo).
      </p>
    </div>
  );
}
