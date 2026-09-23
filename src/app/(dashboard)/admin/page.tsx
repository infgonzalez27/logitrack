import { redirect } from "next/navigation";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { listarEmpresasAction } from "@/lib/actions/empresas";
import { PageHeader } from "@/components/layout/page-header";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { DataTable } from "@/components/ui/data-table";

function truncateUrl(url: string, max = 42): string {
  if (url.length <= max) return url;
  return `${url.slice(0, max)}…`;
}

export default async function AdminPage() {
  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);
  if (rol !== "admin") {
    redirect("/");
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
          ]}
          rows={empresas.map((e) => ({
            id: e.id,
            cells: {
              codigo: (
                <span className="font-mono text-sm">{e.codigo_empresa}</span>
              ),
              nombre: e.nombre_empresa,
              url: (
                <span className="text-xs text-lt-text-muted" title={e.supabase_url}>
                  {truncateUrl(e.supabase_url)}
                </span>
              ),
              activo: e.activo ? "Activa" : "Inactiva",
            },
          }))}
          emptyMessage="No hay empresas registradas. Crea la primera con «Nueva empresa»."
        />
      </Card>

      <p className="text-sm text-lt-text-muted">
        Tras el alta, Cursor/ops completa el clon de esquema según{" "}
        <code className="text-xs">docs/procedimiento_duplicacion_tenant.md</code>
        . El formulario solo pide código, nombre y gerente.
      </p>
    </div>
  );
}
