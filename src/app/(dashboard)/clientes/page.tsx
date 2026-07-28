import { createClient } from "@/lib/supabase/server";
import { getNombresPerfilByIds } from "@/lib/data/perfiles";
import { joinOne } from "@/lib/supabase/join";
import { PageHeader } from "@/components/layout/page-header";
import { Button } from "@/components/ui/button";
import { DataTable } from "@/components/ui/data-table";
import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";

type ClienteRow = {
  id: string;
  rif_nit: string;
  razon_social: string;
  telefono: string | null;
  movil1: string | null;
  activo: boolean;
  vendedor_id?: string | null;
  vendedor?:
    | { nombre_completo: string }
    | { nombre_completo: string }[]
    | null;
};

export default async function ClientesPage() {
  const supabase = await createClient();

  let clientes: ClienteRow[] | null = null;
  let listError: string | null = null;

  const withVendedor = await supabase
    .from("clientes")
    .select("*, vendedor:perfiles_usuario!vendedor_id(nombre_completo)")
    .order("razon_social");

  if (withVendedor.error) {
    const fallback = await supabase
      .from("clientes")
      .select("*")
      .order("razon_social");
    clientes = (fallback.data ?? []) as ClienteRow[];
    if (fallback.error) {
      listError = fallback.error.message;
    } else if (/vendedor_id/i.test(withVendedor.error.message)) {
      listError =
        "Pendiente en BD: ejecutar assets/docs/SQL_clientes_vendedor_id.sql para habilitar vendedor en clientes.";
    }
  } else {
    clientes = (withVendedor.data ?? []) as ClienteRow[];
  }

  const nombresVendedor = await getNombresPerfilByIds(
    (clientes ?? [])
      .map((c) => c.vendedor_id)
      .filter((id): id is string => Boolean(id)),
  );

  return (
    <div className="space-y-6">
      <PageHeader
        title="Clientes"
        description="Módulo 1 — Entidades maestras"
        action={<Button href="/clientes/nuevo">Nuevo cliente</Button>}
      />
      {listError ? (
        <p className="text-sm text-amber-700">{listError}</p>
      ) : null}
      <Card>
        <DataTable
          columns={[
            { key: "rif", label: "RIF/NIT" },
            { key: "razon", label: "Razón social" },
            { key: "vendedor", label: "Vendedor" },
            { key: "telefono", label: "Teléfono" },
            { key: "estado", label: "Estado" },
          ]}
          rows={(clientes ?? []).map((c) => {
            const vendedorJoin = joinOne(c.vendedor);
            return {
              id: c.id,
              cells: {
                rif: c.rif_nit,
                razon: c.razon_social,
                vendedor:
                  vendedorJoin?.nombre_completo ??
                  (c.vendedor_id ? nombresVendedor[c.vendedor_id] : null) ??
                  "—",
                telefono: c.telefono ?? c.movil1 ?? "—",
                estado: (
                  <Badge tone={c.activo ? "success" : "danger"}>
                    {c.activo ? "Activo" : "Inactivo"}
                  </Badge>
                ),
              },
            };
          })}
        />
      </Card>
    </div>
  );
}
