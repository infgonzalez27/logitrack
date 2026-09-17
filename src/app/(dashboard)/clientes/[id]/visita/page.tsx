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
import { Button } from "@/components/ui/button";
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
        puedeRendir={ordenes.some((o) => Number(o.saldo_pendiente ?? 0) > 0)}
      />

      {!abonos.ok ? (
        <p className="lt-alert-error">{abonos.error}</p>
      ) : null}

      {abonos.ok ? (
        <p
          className={`rounded-xl border px-4 py-3 text-sm ${
            saldoFavor > 0
              ? "border-emerald-200 bg-emerald-50 text-emerald-950"
              : "border-lt-border bg-lt-surface-muted text-lt-text"
          }`}
        >
          Saldo a favor acumulado a la fecha:{" "}
          <strong>{formatCurrency(saldoFavor)}</strong>
          {abonos.data.saldo_favor_bs != null
            ? ` · ${formatNumber(abonos.data.saldo_favor_bs)} Bs`
            : null}
        </p>
      ) : null}

      <section className="space-y-4">
        <div>
          <h2 className="text-base font-semibold text-lt-text">
            Órdenes por liquidar
          </h2>
          <p className="text-sm text-lt-text-muted">
            Pendientes de cobro / liquidación de este cliente.
          </p>
        </div>

        {!ordenes.length ? (
          <Card className="px-4 py-8 text-center text-sm text-lt-text-muted">
            Este cliente no tiene órdenes por liquidar.
          </Card>
        ) : (
          <div className="grid gap-4 sm:grid-cols-2">
            {ordenes.map((o) => (
              <article
                key={o.id}
                className="flex flex-col rounded-2xl border border-lt-border bg-lt-surface p-4 shadow-sm"
              >
                <h3 className="text-lg font-bold text-lt-text">
                  Orden: #{o.correlativo}
                </h3>
                <dl className="mt-3 flex-1 space-y-2 text-sm">
                  <div className="flex items-start justify-between gap-3">
                    <dt className="text-lt-text-muted">Fecha despacho:</dt>
                    <dd className="text-right font-medium text-lt-text">
                      {o.fecha_despacho
                        ? formatDateOnly(o.fecha_despacho)
                        : "—"}
                    </dd>
                  </div>
                  <div className="flex items-start justify-between gap-3">
                    <dt className="text-lt-text-muted">Días vencidos:</dt>
                    <dd className="text-right font-medium tabular-nums text-lt-text">
                      {formatNumber(o.dias_vencidos ?? 0)}
                    </dd>
                  </div>
                  <div className="flex items-start justify-between gap-3">
                    <dt className="text-lt-text-muted">Total orden:</dt>
                    <dd className="text-right tabular-nums text-lt-text">
                      {formatCurrency(Number(o.monto_total_orden ?? 0))}
                    </dd>
                  </div>
                  <div className="flex items-start justify-between gap-3">
                    <dt className="text-lt-text-muted">Abonado:</dt>
                    <dd className="text-right tabular-nums text-lt-text">
                      {formatCurrency(Number(o.abonos_acumulados ?? 0))}
                    </dd>
                  </div>
                  <div className="flex items-start justify-between gap-3">
                    <dt className="text-lt-text-muted">Saldo pendiente:</dt>
                    <dd className="text-right">
                      <Badge tone="warning">
                        {formatCurrency(Number(o.saldo_pendiente ?? 0))}
                      </Badge>
                    </dd>
                  </div>
                </dl>
                <div className="mt-4 flex justify-end">
                  <Button href={`/ordenes/${o.id}`}>Ver detalle</Button>
                </div>
              </article>
            ))}
          </div>
        )}

        {ordenes.length ? (
          <p className="text-sm text-lt-text-muted">
            Total de órdenes en vista: {formatNumber(ordenes.length)}
          </p>
        ) : null}
      </section>
    </div>
  );
}
