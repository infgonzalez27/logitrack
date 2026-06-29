import { createClient } from "@/lib/supabase/server";
import { joinOne } from "@/lib/supabase/join";
import { formatDate, formatCurrency } from "@/lib/format";
import { PageHeader } from "@/components/layout/page-header";
import { Button } from "@/components/ui/button";
import { DataTable } from "@/components/ui/data-table";
import { Card } from "@/components/ui/card";

export default async function PagosProveedoresPage() {
  const supabase = await createClient();
  const { data } = await supabase
    .from("pagos_proveedores")
    .select("*, proveedores(razon_social)")
    .order("fecha_pago", { ascending: false });

  return (
    <div className="space-y-6">
      <PageHeader
        title="Pagos a proveedores"
        action={<Button href="/pagos-proveedores/nuevo">Nuevo pago</Button>}
      />
      <Card>
        <DataTable
          columns={[
            { key: "proveedor", label: "Proveedor" },
            { key: "fecha", label: "Fecha" },
            { key: "monto", label: "Monto pagado" },
            { key: "concepto", label: "Concepto" },
          ]}
          rows={(data ?? []).map((p) => ({
            id: p.id,
            cells: {
              proveedor: joinOne(p.proveedores)?.razon_social ?? "—",
              fecha: formatDate(p.fecha_pago),
              monto: formatCurrency(p.monto_total_pagado),
              concepto: p.glosa_concepto ?? "—",
            },
          }))}
        />
      </Card>
    </div>
  );
}
