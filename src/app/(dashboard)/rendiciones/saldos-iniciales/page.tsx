import { redirect } from "next/navigation";
import Link from "next/link";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import {
  esEstadoOrdenValido,
  labelOrdenEstadoValue,
} from "@/lib/auth/orden-permissions";
import { listarSaldosInicialesAction } from "@/lib/actions/saldos-iniciales";
import { createClient } from "@/lib/supabase/server";
import { formatCurrency, formatDateOnly, formatNumber } from "@/lib/format";
import { PageHeader } from "@/components/layout/page-header";
import { Badge, ordenEstadoTone } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { SaldoInicialForm } from "./saldo-inicial-form";

export default async function SaldosInicialesPage() {
  const rol = getRoleNameFromProfile(await getCurrentProfile());
  if (rol !== "admin" && rol !== "gerente") redirect("/");

  const supabase = await createClient();
  const [{ data: clientes }, { data: contenedores }, saldos] = await Promise.all([
    supabase
      .from("clientes")
      .select("id, razon_social, rif_nit")
      .eq("activo", true)
      .order("razon_social"),
    supabase.from("tipos_contenedores").select("id, codigo, nombre").order("codigo"),
    listarSaldosInicialesAction(),
  ]);

  const items = saldos.ok ? saldos.items : [];
  const vacios = saldos.ok ? saldos.vacios : [];
  const pendientes = items.filter((i) => i.estado !== "anulada");
  const total = pendientes.reduce((s, i) => s + i.total_recaudar_usd, 0);

  return (
    <div className="mx-auto max-w-5xl space-y-6">
      <PageHeader
        title="Cuentas por cobrar iniciales"
        description="Carga la deuda previa y los vacíos que ya tiene un cliente, sin crear una orden. La deuda queda por liquidar y se cobra con una cobranza normal."
      />

      <SaldoInicialForm
        clientes={(clientes ?? []).map((c) => ({
          value: c.id,
          label: c.razon_social,
          hint: c.rif_nit ?? null,
        }))}
        contenedores={(contenedores ?? []).map((t) => ({
          value: t.id,
          label: `${t.nombre} (${t.codigo})`,
        }))}
      />

      <Card title="Cuentas iniciales cargadas">
        {!saldos.ok ? <p className="lt-alert-error">{saldos.error}</p> : null}
        {!items.length ? (
          <p className="text-sm text-lt-text-muted">
            Todavía no hay cuentas iniciales cargadas.
          </p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-lt-border text-left text-lt-text-muted">
                  <th className="py-2 pr-3 font-medium">Nº</th>
                  <th className="py-2 pr-3 font-medium">Cliente</th>
                  <th className="py-2 pr-3 font-medium">Factura</th>
                  <th className="py-2 pr-3 font-medium">Fecha</th>
                  <th className="py-2 pr-3 text-right font-medium">Deuda USD</th>
                  <th className="py-2 font-medium">Estado</th>
                </tr>
              </thead>
              <tbody>
                {items.map((i) => (
                  <tr key={i.id} className="border-b border-lt-border-light">
                    <td className="py-2 pr-3 tabular-nums">
                      <Link
                        href={`/ordenes/${i.id}`}
                        className="font-medium text-lt-primary hover:underline"
                      >
                        #{i.correlativo}
                      </Link>
                    </td>
                    <td className="py-2 pr-3">
                      <span className="block text-lt-text">{i.cliente_razon_social}</span>
                      {i.cliente_rif ? (
                        <span className="block text-xs text-lt-text-muted">{i.cliente_rif}</span>
                      ) : null}
                    </td>
                    <td className="py-2 pr-3">{i.factura_origen_numero}</td>
                    <td className="py-2 pr-3">{formatDateOnly(i.fecha_factura)}</td>
                    <td className="py-2 pr-3 text-right tabular-nums">
                      {formatCurrency(i.total_recaudar_usd)}
                    </td>
                    <td className="py-2">
                      <Badge tone={ordenEstadoTone(i.estado)}>
                        {esEstadoOrdenValido(i.estado)
                          ? labelOrdenEstadoValue(i.estado)
                          : i.estado}
                      </Badge>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        {pendientes.length ? (
          <p className="mt-4 text-sm text-lt-text-muted">
            {formatNumber(pendientes.length)} documento
            {pendientes.length === 1 ? "" : "s"} · Total cargado{" "}
            <span className="font-semibold text-lt-text">{formatCurrency(total)}</span>
          </p>
        ) : null}
      </Card>

      <Card title="Vacíos iniciales cargados">
        {!vacios.length ? (
          <p className="text-sm text-lt-text-muted">
            Todavía no hay vacíos iniciales cargados.
          </p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-lt-border text-left text-lt-text-muted">
                  <th className="py-2 pr-3 font-medium">Cliente</th>
                  <th className="py-2 pr-3 font-medium">Contenedor</th>
                  <th className="py-2 pr-3 font-medium">Fecha</th>
                  <th className="py-2 text-right font-medium">Vacíos</th>
                </tr>
              </thead>
              <tbody>
                {vacios.map((v) => (
                  <tr key={v.id} className="border-b border-lt-border-light">
                    <td className="py-2 pr-3">
                      <span className="block text-lt-text">{v.cliente_razon_social}</span>
                      {v.cliente_rif ? (
                        <span className="block text-xs text-lt-text-muted">{v.cliente_rif}</span>
                      ) : null}
                    </td>
                    <td className="py-2 pr-3">{v.contenedor}</td>
                    <td className="py-2 pr-3">{formatDateOnly(v.fecha)}</td>
                    <td className="py-2 text-right tabular-nums">{formatNumber(v.cantidad)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        <p className="mt-4 text-xs text-lt-text-muted">
          El saldo total de vacíos por cliente se consulta en Cobranzas →
          «Consulta de contenedores».
        </p>
      </Card>
    </div>
  );
}
