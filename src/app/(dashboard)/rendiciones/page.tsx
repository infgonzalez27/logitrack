import { createClient } from "@/lib/supabase/server";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { joinOne } from "@/lib/supabase/join";
import { RENDICION_ESTADOS } from "@/lib/constants";
import { formatDate, formatCurrency, formatNumber } from "@/lib/format";
import { PageHeader } from "@/components/layout/page-header";
import { Button } from "@/components/ui/button";
import { DataTable } from "@/components/ui/data-table";
import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { AprobarRendicionButton } from "./aprobar-rendicion-button";
import { ReversarRendicionButton } from "./reversar-rendicion-button";
import { CobranzasFiltros } from "./cobranzas-filtros";
import { ExportCobranzasExcelButton } from "./export-cobranzas-excel-button";
import type { CobranzaExcelRow } from "@/lib/export/cobranzas-excel";

export default async function RendicionesPage({
  searchParams,
}: {
  searchParams?: Promise<{ desde?: string; hasta?: string }>;
}) {
  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);
  const canApprove = rol === "admin" || rol === "gerente";
  const canReverse = rol === "gerente";

  const p = searchParams ? await searchParams : undefined;
  const desde = p?.desde?.trim();
  const hasta = p?.hasta?.trim();

  const supabase = await createClient();
  let query = supabase
    .from("rendiciones_cuentas")
    .select("*, clientes(razon_social)")
    .order("fecha_rendicion", { ascending: false });

  if (desde) {
    query = query.gte("fecha_rendicion", `${desde}T00:00:00`);
  }
  if (hasta) {
    query = query.lte("fecha_rendicion", `${hasta}T23:59:59.999Z`);
  }

  const { data } = await query;
  const items = data ?? [];

  const excelRows: CobranzaExcelRow[] = items.map((r) => {
    const estadoObj = RENDICION_ESTADOS.find((e) => e.value === r.estado);
    return {
      id: r.id,
      fecha_rendicion: r.fecha_rendicion,
      cliente: joinOne(r.clientes)?.razon_social ?? "—",
      estado: estadoObj?.label ?? r.estado ?? "—",
      tasa_cambio: Number(r.tasa_cambio) || 1,
      total_efectivo: Number(r.total_efectivo_recaudado) || 0,
      total_transferencias: Number(r.total_transferencias_recaudado) || 0,
      total_recaudado_usd: Number(r.total_recaudado_usd) || 0,
      total_recaudado_bs: Number(r.total_recaudado_bs) || 0,
    };
  });

  const totalEfectivo = excelRows.reduce((s, r) => s + r.total_efectivo, 0);
  const totalTransferencias = excelRows.reduce((s, r) => s + r.total_transferencias, 0);
  const totalUsd = excelRows.reduce((s, r) => s + r.total_recaudado_usd, 0);

  return (
    <div className="space-y-6">
      <PageHeader
        title="Cobranzas"
        description="Registro de órdenes por liquidar y opciones de pago."
        action={
          <div className="flex flex-wrap items-center gap-2">
            <ExportCobranzasExcelButton
              items={excelRows}
              filtros={{ desde, hasta }}
            />
            <Button href="/rendiciones/nuevo">Nueva cobranza</Button>
          </div>
        }
      />

      <CobranzasFiltros defaultDesde={desde} defaultHasta={hasta} />

      <div className="flex flex-wrap items-center justify-between gap-4 text-xs text-lt-text-muted">
        <span>
          Registros: <strong className="text-lt-text">{formatNumber(items.length)}</strong>
        </span>
        <div className="flex flex-wrap items-center gap-4">
          <span>
            Efectivo: <strong className="text-lt-text">{formatCurrency(totalEfectivo)}</strong>
          </span>
          <span>
            Transferencias:{" "}
            <strong className="text-lt-text">{formatCurrency(totalTransferencias)}</strong>
          </span>
          {totalUsd > 0 ? (
            <span>
              Total: <strong className="text-lt-primary">{formatCurrency(totalUsd)}</strong>
            </span>
          ) : null}
        </div>
      </div>
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
                <Badge tone={r.estado === "reversada" ? "danger" : "default"}>
                  {RENDICION_ESTADOS.find((e) => e.value === r.estado)?.label ??
                    r.estado}
                </Badge>
              ),
              ...(canApprove
                ? {
                    acciones:
                      r.estado === "revision" ? (
                        <AprobarRendicionButton rendicionId={r.id} />
                      ) : r.estado === "aprobada" && canReverse ? (
                        <ReversarRendicionButton
                          rendicionId={r.id}
                          cliente={joinOne(r.clientes)?.razon_social ?? "este cliente"}
                        />
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
