import { createClient } from "@/lib/supabase/server";
import { joinOne } from "@/lib/supabase/join";
import { CHOFER_ESTADOS } from "@/lib/constants";
import { PageHeader } from "@/components/layout/page-header";
import { DataTable } from "@/components/ui/data-table";
import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";

export default async function ChoferesPage() {
  const supabase = await createClient();
  const { data } = await supabase
    .from("choferes")
    .select("*, perfiles_usuario(nombre_completo, telefono)")
    .order("created_at", { ascending: false });

  return (
    <div className="space-y-6">
      <PageHeader
        title="Choferes"
        description="Extensión 1:1 con perfiles de usuario con rol chofer"
      />
      <Card>
        <DataTable
          columns={[
            { key: "nombre", label: "Nombre" },
            { key: "licencia", label: "Licencia" },
            { key: "movil", label: "Móvil" },
            { key: "estado", label: "Estado" },
          ]}
          rows={(data ?? []).map((c) => {
            const perfil = joinOne(c.perfiles_usuario);
            return {
              id: c.perfil_id,
              cells: {
                nombre: perfil?.nombre_completo ?? "—",
                licencia: c.cedula_licencia,
                movil: c.movil1 ?? perfil?.telefono ?? "—",
                estado: (
                  <Badge>
                    {CHOFER_ESTADOS.find((e) => e.value === c.estado)?.label ??
                      c.estado}
                  </Badge>
                ),
              },
            };
          })}
          emptyMessage="No hay choferes. Registra un usuario con rol chofer."
        />
      </Card>
    </div>
  );
}
