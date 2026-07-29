import { createClient } from "@/lib/supabase/server";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { joinOne } from "@/lib/supabase/join";
import { RENDICION_ESTADOS } from "@/lib/constants";
import { formatDate, formatCurrency } from "@/lib/format";
import { PageHeader } from "@/components/layout/page-header";
import { Button } from "@/components/ui/button";
import { DataTable } from "@/components/ui/data-table";
import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { AprobarRendicionButton } from "./aprobar-rendicion-button";

export default async function RendicionesPage({
  searchParams,
}: {
  searchParams: Promise<{ ok?: string }>;
}) {
  const { ok } = await searchParams;
  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);
  const canApprove = rol === "admin" || rol === "gerente";

  const supabase = await createClient();
  const { data } = await supabase
    .from("rendiciones_cuentas")
    .select("*, clientes(razon_social)")
    .order("fecha_rendicion", { ascending: false });

  return (
    <div className="space-y-6">
      <PageHeader
        title="Rendición de cuentas"
        description="Módulo 4 — Cobranzas y devoluciones en ruta"
        action={<Button href="/rendiciones/nuevo">Nueva rendición</Button>}
      />
      {ok ? (
        <p className="lt-alert-success">
          Rendición registrada en revisión. Un gerente debe aprobarla para
          liquidar las órdenes asociadas.
        </p>
      ) : null}
      <Card>
        <DataTable
          columns={[
            { key: "cliente", label: "Cliente" },
            { key: "fecha", label: "Fecha" },
            { key: "efectivo", label: "Efectivo" },
            { key: "transferencias", label: "Transferencias" },
            { key: "estado", label: "Estado" },
            ...(canApprove
              ? [{ key: "acciones", label: "Acciones" as const }]
              : []),
          ]}
          rows={(data ?? []).map((r) => ({
            id: r.id,
            cells: {
              cliente: joinOne(r.clientes)?.razon_social ?? "—",
              fecha: formatDate(r.fecha_rendicion),
              efectivo: formatCurrency(r.total_efectivo_recaudado),
              transferencias: formatCurrency(
                r.total_transferencias_recaudado,
              ),
              estado: (
                <Badge>
                  {RENDICION_ESTADOS.find((e) => e.value === r.estado)?.label ??
                    r.estado}
                </Badge>
              ),
              ...(canApprove
                ? {
                    acciones:
                      r.estado === "revision" ? (
                        <AprobarRendicionButton rendicionId={r.id} />
                      ) : (
                        "—"
                      ),
                  }
                : {}),
            },
          }))}
        />
      </Card>
    </div>
  );
}
