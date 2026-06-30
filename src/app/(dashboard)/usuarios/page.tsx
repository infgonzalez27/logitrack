import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { joinOne } from "@/lib/supabase/join";
import { PageHeader } from "@/components/layout/page-header";
import { Button } from "@/components/ui/button";
import { DataTable } from "@/components/ui/data-table";
import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";

export default async function UsuariosPage() {
  const supabase = await createClient();
  const { data: usuarios, error } = await supabase
    .from("perfiles_usuario")
    .select("*, roles(nombre)")
    .order("nombre_completo");

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

      {error && (
        <p className="text-sm text-lt-danger-text">{error.message}</p>
      )}

      <Card>
        <DataTable
          columns={[
            { key: "nombre", label: "Nombre" },
            { key: "rol", label: "Rol" },
            { key: "telefono", label: "Teléfono" },
            { key: "estado", label: "Estado" },
          ]}
          rows={(usuarios ?? []).map((u) => ({
            id: u.id,
            cells: {
              nombre: u.nombre_completo,
              rol: joinOne(u.roles)?.nombre ?? "—",
              telefono: u.telefono ?? "—",
              estado: (
                <Badge tone={u.activo ? "success" : "danger"}>
                  {u.activo ? "Activo" : "Inactivo"}
                </Badge>
              ),
            },
          }))}
          emptyMessage="No hay usuarios registrados."
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
