import Link from "next/link";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile, labelRol } from "@/lib/auth/roles";
import { listarEmpresasAction } from "@/lib/actions/empresas";
import { PageHeader } from "@/components/layout/page-header";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { DataTable } from "@/components/ui/data-table";
import { SincronizarEmpresaButton } from "./sincronizar-empresa-button";

function truncateUrl(url: string, max = 42): string {
  if (url.length <= max) return url;
  return `${url.slice(0, max)}…`;
}

export default async function AdminPage() {
  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);

  if (rol !== "admin") {
    return (
      <div className="mx-auto max-w-lg space-y-4">
        <PageHeader title="Superadmin" description="Empresas / tenants" />
        <Card>
          <p className="text-sm text-lt-text">
            Esta sección es solo para rol <strong>admin</strong>. Tu sesión
            actual es <strong>{labelRol(rol)}</strong>
            {profile?.nombre_completo
              ? ` (${profile.nombre_completo})`
              : ""}
            .
          </p>
          <p className="mt-3 text-sm text-lt-text-muted">
            Cierra sesión e inicia con una cuenta administrador (por ejemplo{" "}
            <code className="text-xs">inf.gonzalez27@gmail.com</code>).
          </p>
          <div className="mt-4">
            <Button href="/login" variant="primary">
              Ir a login
            </Button>
          </div>
        </Card>
      </div>
    );
  }

  const result = await listarEmpresasAction();
  const empresas = result.ok ? result.empresas : [];

  return (
    <div className="space-y-6">
      <PageHeader
        title="Superadmin"
        description="Alta de empresas lt_*: se aprovisiona el proyecto Supabase y se crea el gerente. No hace falta pegar URL ni anon key."
        action={
          <Button href="/admin/nuevo" variant="primary">
            Nueva empresa
          </Button>
        }
      />

      {!result.ok && (
        <p className="text-sm text-lt-danger-text">{result.error}</p>
      )}

      <Card>
        <DataTable
          columns={[
            { key: "codigo", label: "Código" },
            { key: "nombre", label: "Nombre" },
            { key: "url", label: "Supabase URL" },
            { key: "activo", label: "Estado" },
            { key: "tenant", label: "Tenant" },
          ]}
          rows={empresas.map((e) => ({
            id: e.id,
            cells: {
              codigo: (
                <span className="font-mono text-sm">{e.codigo_empresa}</span>
              ),
              nombre: e.nombre_empresa,
              url: (
                <span
                  className="text-xs text-lt-text-muted"
                  title={e.supabase_url}
                >
                  {truncateUrl(e.supabase_url)}
                </span>
              ),
              activo: e.activo ? "Activa" : "Inactiva",
              tenant: <SincronizarEmpresaButton empresaId={e.id} />,
            },
          }))}
          emptyMessage="No hay empresas registradas. Crea la primera con «Nueva empresa»."
        />
      </Card>

      <p className="text-sm text-lt-text-muted">
        El alta clona el esquema, prepara el tenant y copia al gerente.
        «Sincronizar» repite la preparación y copia a todos los usuarios de la
        empresa (útil para empresas creadas antes de este flujo). Formulario:{" "}
        <Link
          href="/admin/nuevo"
          className="font-medium text-lt-primary hover:underline"
        >
          /admin/nuevo
        </Link>
        .
      </p>
    </div>
  );
}
