import Link from "next/link";
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
        description="Catálogo central de bases lt_*. Registra la URL del proyecto Supabase ya provisionado y crea el gerente."
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
        Antes de registrar aquí, clona el esquema plantilla según{" "}
        <Link
          href="/admin/nuevo"
          className="font-medium text-lt-primary hover:underline"
        >
          el alta de empresa
        </Link>{" "}
        y el procedimiento en{" "}
        <code className="text-xs">docs/procedimiento_duplicacion_tenant.md</code>.
      </p>
    </div>
  );
}
