import { notFound, redirect } from "next/navigation";
import Link from "next/link";
import { getCurrentProfile, getSessionUser } from "@/lib/auth";
import { canCreateOrden } from "@/lib/auth/orden-permissions";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { obtenerClienteParaEditarAction } from "@/lib/actions/clientes";
import { solicitaAbonosOrdenDistribucionAction } from "@/lib/actions/rendiciones";
import { formatCurrency, formatDateOnly, formatNumber } from "@/lib/format";
import { PageHeader } from "@/components/layout/page-header";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { VisitaClienteAcciones } from "./visita-cliente-acciones";

export default async function ClienteVisitaPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const [profile, user] = await Promise.all([
    getCurrentProfile(),
    getSessionUser(),
  ]);
  const rol = getRoleNameFromProfile(profile);

  if (
    rol !== "vendedor" &&
    rol !== "gerente" &&
    rol !== "admin" &&
    rol !== "cobrador"
  ) {
    redirect("/");
  }

  const clienteResult = await obtenerClienteParaEditarAction(id);
  if (!clienteResult.ok) notFound();

  const cliente = clienteResult.cliente;
  if (
    rol === "vendedor" &&
    user?.id &&
    cliente.vendedor_id &&
    cliente.vendedor_id !== user.id
  ) {
    redirect("/visita");
  }

  const abonos = await solicitaAbonosOrdenDistribucionAction(id);
  const ordenes = abonos.ok ? abonos.data.ordenes : [];
  const saldoFavor = abonos.ok ? abonos.data.saldo_favor : 0;

  return (
    <div className="mx-auto max-w-4xl space-y-6">
      <PageHeader
        title={cliente.razon_social}
        description={`${cliente.rif_nit} · Órdenes por liquidar y acciones de visita`}
        action={
          <Link
            href="/visita"
            className="text-sm font-medium text-lt-primary hover:underline"
          >
            ← Cambiar cliente
          </Link>
        }
      />

      <VisitaClienteAcciones
        clienteId={id}
        puedeCrearOrden={canCreateOrden(rol)}
      />

      {!abonos.ok ? (
        <p className="lt-alert-error">{abonos.error}</p>
      ) : null}

      {abonos.ok && saldoFavor > 0 ? (
        <p className="rounded-xl border border-lt-border bg-lt-surface-muted px-4 py-3 text-sm text-lt-text">
          Saldo a favor del cliente:{" "}
          <strong>{formatCurrency(saldoFavor)}</strong>
        </p>
      ) : null}

      <Card className="overflow-hidden p-0">
        <div className="border-b border-lt-border px-4 py-3">
          <h2 className="text-base font-semibold text-lt-text">
            Órdenes por liquidar
          </h2>
          <p className="text-sm text-lt-text-muted">
            Pendientes de cobro / liquidación de este cliente.
          </p>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full min-w-[36rem] text-left text-sm">
            <thead className="border-b border-lt-border bg-lt-surface-muted text-lt-text-muted">
              <tr>
                <th className="px-4 py-3 font-medium">Orden</th>
                <th className="px-4 py-3 font-medium">Fecha despacho</th>
                <th className="px-4 py-3 font-medium text-right">
                  Total orden
                </th>
                <th className="px-4 py-3 font-medium text-right">Abonado</th>
                <th className="px-4 py-3 font-medium text-right">
                  Saldo pendiente
                </th>
                <th className="px-4 py-3 font-medium"> </th>
              </tr>
            </thead>
            <tbody>
              {!ordenes.length ? (
                <tr>
                  <td
                    colSpan={6}
                    className="px-4 py-8 text-center text-lt-text-muted"
                  >
                    Este cliente no tiene órdenes por liquidar.
                  </td>
                </tr>
              ) : (
                ordenes.map((o) => (
                  <tr
                    key={o.id}
                    className="border-b border-lt-border-light last:border-0"
                  >
                    <td className="px-4 py-3 font-semibold text-lt-text">
                      #{o.correlativo}
                    </td>
                    <td className="px-4 py-3 text-lt-text-muted">
                      {o.fecha_despacho
                        ? formatDateOnly(o.fecha_despacho)
                        : "—"}
                    </td>
                    <td className="px-4 py-3 text-right tabular-nums">
                      {formatCurrency(Number(o.monto_total_orden ?? 0))}
                    </td>
                    <td className="px-4 py-3 text-right tabular-nums">
                      {formatCurrency(Number(o.abonos_acumulados ?? 0))}
                    </td>
                    <td className="px-4 py-3 text-right tabular-nums">
                      <Badge tone="warning">
                        {formatCurrency(Number(o.saldo_pendiente ?? 0))}
                      </Badge>
                    </td>
                    <td className="px-4 py-3 text-right">
                      <Link
                        href={`/ordenes/${o.id}`}
                        className="text-sm font-medium text-lt-primary hover:underline"
                      >
                        Ver
                      </Link>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
        {ordenes.length ? (
          <p className="border-t border-lt-border px-4 py-3 text-sm text-lt-text-muted">
            {formatNumber(ordenes.length)} orden
            {ordenes.length === 1 ? "" : "es"} pendiente
            {ordenes.length === 1 ? "" : "s"}
          </p>
        ) : null}
      </Card>
    </div>
  );
}
