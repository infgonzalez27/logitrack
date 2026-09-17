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
  searchParams: Promise<{
    ok?: string;
    usado?: string;
    generado?: string;
    ordenes?: string;
    pagos?: string;
  }>;
}) {
  const { ok, usado, generado, ordenes, pagos } = await searchParams;
  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);
  const canApprove = rol === "admin" || rol === "gerente";

  const saldoUsado = Number(usado ?? 0);
  const saldoGenerado = Number(generado ?? 0);
  const totalOrdenes = Number(ordenes ?? 0);
  const totalPagos = Number(pagos ?? 0);

  const supabase = await createClient();
  const { data } = await supabase
    .from("rendiciones_cuentas")
    .select("*, clientes(razon_social)")
    .order("fecha_rendicion", { ascending: false });

  return (
    <div className="space-y-6">
      <PageHeader
        title="Rendición de Cuentas"
        description="Registro de órdenes por liquidar y opciones de pago."
        action={<Button href="/rendiciones/nuevo">Nueva rendición</Button>}
      />
      {ok ? (
        <div className="lt-alert-success space-y-1">
          <p>
            Rendición registrada en revisión. Un gerente debe aprobarla para
            liquidar las órdenes asociadas.
          </p>
          {(totalOrdenes > 0 || totalPagos > 0) && (
            <p className="text-sm">
              Órdenes: {formatCurrency(totalOrdenes)} · Pagos:{" "}
              {formatCurrency(totalPagos)}
            </p>
          )}
          <p className="text-sm">
            Saldo a favor usado:{" "}
            <strong>{formatCurrency(saldoUsado)}</strong>
            {" · "}
            Saldo a favor generado:{" "}
            <strong>{formatCurrency(saldoGenerado)}</strong>
          </p>
        </div>
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
