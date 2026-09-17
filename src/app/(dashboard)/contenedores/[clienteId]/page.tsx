import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { obtenerClienteContenedoresResumen } from "@/lib/data/contenedores";
import { formatDate, formatNumber } from "@/lib/format";
import { PageHeader } from "@/components/layout/page-header";
import { PrintButton } from "@/components/print/print-button";
import { Card } from "@/components/ui/card";
import { DataTable } from "@/components/ui/data-table";
import { ContenedoresHistoricoFiltros } from "./contenedores-historico-filtros";

export default async function ContenedoresClientePage({
  params,
  searchParams,
}: {
  params: Promise<{ clienteId: string }>;
  searchParams: Promise<{ desde?: string; hasta?: string }>;
}) {
  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);
  if (
    rol !== "admin" &&
    rol !== "gerente" &&
    rol !== "vendedor" &&
    rol !== "cobrador" &&
    rol !== "despachador"
  ) {
    redirect("/");
  }

  const { clienteId } = await params;
  const { desde, hasta } = await searchParams;
  const resumen = await obtenerClienteContenedoresResumen(clienteId, {
    fechaInicial: desde?.trim() || undefined,
    fechaLimite: hasta?.trim() || undefined,
  });
  if (!resumen.cliente) notFound();

  const totalPendiente = resumen.saldos.reduce(
    (s, r) => s + r.saldo_pendiente,
    0,
  );
  const hist = resumen.historico;
  const movimientos = hist?.movimientos ?? [];

  return (
    <div className="lt-print-document space-y-6">
      <PageHeader
        title={resumen.cliente.razon_social}
        description={`RIF/NIT ${resumen.cliente.rif_nit} · Estado de cuenta de vacíos`}
        action={
          <div className="flex flex-wrap gap-2">
            <PrintButton label="Imprimir" />
            <Link
              href="/contenedores"
              className="lt-no-print inline-flex items-center justify-center rounded-xl border border-lt-border bg-lt-surface px-4 py-2 text-sm font-medium text-lt-text hover:bg-lt-primary-muted"
            >
              Volver a consulta
            </Link>
          </div>
        }
      />

      <p className="text-sm text-lt-text-muted">
        Saldo total pendiente (actual):{" "}
        <span className="font-semibold text-lt-text">
          {formatNumber(totalPendiente)}
        </span>
      </p>

      <Card>
        <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-lt-text-subtle">
          Saldos actuales
        </h2>
        <DataTable
          emptyMessage="Este cliente no tiene saldos de contenedores."
          columns={[
            { key: "contenedor", label: "Contenedor" },
            { key: "saldo", label: "Saldo pendiente" },
            { key: "actualizado", label: "Actualizado" },
          ]}
          rows={resumen.saldos.map((row) => ({
            id: row.id,
            cells: {
              contenedor: row.contenedor_codigo
                ? `${row.contenedor_codigo} — ${row.contenedor_nombre}`
                : row.contenedor_nombre,
              saldo: (
                <span className="font-medium tabular-nums">
                  {formatNumber(row.saldo_pendiente)}
                </span>
              ),
              actualizado: row.updated_at
                ? formatDate(row.updated_at)
                : "—",
            },
          }))}
        />
      </Card>

      <Card className="lt-no-print space-y-3 p-4">
        <h2 className="text-sm font-semibold uppercase tracking-wide text-lt-text-subtle">
          Historial por rango de fechas
        </h2>
        <ContenedoresHistoricoFiltros
          defaultDesde={desde ?? hist?.fecha_inicial ?? ""}
          defaultHasta={hasta ?? hist?.fecha_limite ?? ""}
        />
        {resumen.historicoError ? (
          <p className="lt-alert-error">{resumen.historicoError}</p>
        ) : hist ? (
          <div className="grid gap-3 sm:grid-cols-4">
            <div className="rounded-xl bg-lt-surface-muted px-3 py-2">
              <p className="text-xs text-lt-text-muted">Saldo anterior</p>
              <p className="text-lg font-semibold tabular-nums">
                {formatNumber(hist.saldo_anterior)}
              </p>
            </div>
            <div className="rounded-xl bg-lt-surface-muted px-3 py-2">
              <p className="text-xs text-lt-text-muted">Entregados</p>
              <p className="text-lg font-semibold tabular-nums">
                {formatNumber(hist.total_entregados)}
              </p>
            </div>
            <div className="rounded-xl bg-lt-surface-muted px-3 py-2">
              <p className="text-xs text-lt-text-muted">Retirados</p>
              <p className="text-lg font-semibold tabular-nums">
                {formatNumber(hist.total_retirados)}
              </p>
            </div>
            <div className="rounded-xl bg-lt-surface-muted px-3 py-2">
              <p className="text-xs text-lt-text-muted">Saldo final (rango)</p>
              <p className="text-lg font-semibold tabular-nums">
                {formatNumber(hist.saldo_final)}
              </p>
            </div>
          </div>
        ) : null}
      </Card>

      <Card>
        <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-lt-text-subtle">
          Movimientos del período
        </h2>
        <DataTable
          emptyMessage="Sin movimientos en el rango seleccionado."
          columns={[
            { key: "fecha", label: "Fecha" },
            { key: "orden", label: "Orden" },
            { key: "contenedor", label: "Contenedor" },
            { key: "entregada", label: "Entregados" },
            { key: "retirada", label: "Retirados" },
          ]}
          rows={movimientos.map((m) => {
            const codigo = m.codigo_contenedor?.trim() || "";
            const nombre = (m.nombre_contenedor || m.contenedor_id).trim();
            return {
              id: String(m.id),
              cells: {
                fecha: formatDate(m.fecha_movimiento),
                orden:
                  m.correlativo_orden != null
                    ? `#${m.correlativo_orden}`
                    : m.factura_origen_numero || "—",
                contenedor: codigo ? `${codigo} — ${nombre}` : nombre,
                entregada: (
                  <span className="tabular-nums">
                    {formatNumber(m.cantidad_entregada)}
                  </span>
                ),
                retirada: (
                  <span className="tabular-nums">
                    {formatNumber(m.cantidad_retirada)}
                  </span>
                ),
              },
            };
          })}
        />
      </Card>
    </div>
  );
}
