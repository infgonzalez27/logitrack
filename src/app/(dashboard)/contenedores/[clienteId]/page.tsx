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

export default async function ContenedoresClientePage({
  params,
}: {
  params: Promise<{ clienteId: string }>;
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
  const resumen = await obtenerClienteContenedoresResumen(clienteId);
  if (!resumen.cliente) notFound();

  const totalPendiente = resumen.saldos.reduce(
    (s, r) => s + r.saldo_pendiente,
    0,
  );

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
        Saldo total pendiente:{" "}
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
              actualizado: formatDate(row.updated_at),
            },
          }))}
        />
      </Card>

      <Card>
        <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-lt-text-subtle">
          Movimientos recientes
        </h2>
        <DataTable
          emptyMessage="Sin movimientos registrados para este cliente."
          columns={[
            { key: "fecha", label: "Fecha" },
            { key: "orden", label: "Orden" },
            { key: "contenedor", label: "Contenedor" },
            { key: "entregado", label: "Entregado" },
            { key: "retirado", label: "Retirado" },
          ]}
          rows={resumen.movimientos.map((m) => ({
            id: m.id,
            cells: {
              fecha: formatDate(m.created_at),
              orden:
                m.orden_correlativo != null ? (
                  m.orden_id ? (
                    <Link
                      href={`/ordenes/${m.orden_id}`}
                      className="lt-no-print font-medium text-lt-primary underline-offset-2 hover:underline"
                    >
                      #{m.orden_correlativo}
                    </Link>
                  ) : (
                    `#${m.orden_correlativo}`
                  )
                ) : (
                  "—"
                ),
              contenedor: m.contenedor_nombre,
              entregado: formatNumber(m.cantidad_entregada),
              retirado: formatNumber(m.cantidad_retirada),
            },
          }))}
        />
      </Card>
    </div>
  );
}
