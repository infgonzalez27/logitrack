import { createClient } from "@/lib/supabase/server";
import { joinOne } from "@/lib/supabase/join";
import { ESTADO_PAGO_FACTURA } from "@/lib/constants";
import { formatDateOnly, formatCurrency } from "@/lib/format";
import { PageHeader } from "@/components/layout/page-header";
import { Button } from "@/components/ui/button";
import { DataTable } from "@/components/ui/data-table";
import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";

export default async function FacturasComprasPage() {
  const supabase = await createClient();
  const { data } = await supabase
    .from("facturas_compras")
    .select("*, proveedores(razon_social)")
    .order("fecha_emision", { ascending: false });

  return (
    <div className="space-y-6">
      <PageHeader
        title="Facturas de compra"
        description="Módulo 5 — Recepción de mercancía"
        action={
          <Button href="/facturas-compras/nuevo">Nueva factura</Button>
        }
      />
      <Card>
        <DataTable
          columns={[
            { key: "numero", label: "Nº factura" },
            { key: "proveedor", label: "Proveedor" },
            { key: "emision", label: "Emisión" },
            { key: "total", label: "Total" },
            { key: "estado", label: "Estado pago" },
          ]}
          rows={(data ?? []).map((f) => ({
            id: f.id,
            cells: {
              numero: f.numero_factura,
              proveedor: joinOne(f.proveedores)?.razon_social ?? "—",
              emision: formatDateOnly(f.fecha_emision),
              total: formatCurrency(f.monto_total),
              estado: (
                <Badge>
                  {ESTADO_PAGO_FACTURA.find((e) => e.value === f.estado_pago)
                    ?.label ?? f.estado_pago}
                </Badge>
              ),
            },
          }))}
        />
      </Card>
    </div>
  );
}
