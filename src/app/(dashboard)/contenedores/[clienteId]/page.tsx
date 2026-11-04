import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import {
  listarTiposContenedoresConsulta,
  obtenerClienteContenedoresResumen,
} from "@/lib/data/contenedores";
import { formatDate, formatNumber } from "@/lib/format";
import { PageHeader } from "@/components/layout/page-header";
import { PrintButton } from "@/components/print/print-button";
import { Card } from "@/components/ui/card";
import { DataTable } from "@/components/ui/data-table";
import { ContenedoresHistoricoFiltros } from "./contenedores-historico-filtros";
import {
  ModalRetirarContenedores,
  type TipoContenedorInput,
} from "../modal-retirar-contenedores";

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

  const [resumen, catalogoTipos] = await Promise.all([
    obtenerClienteContenedoresResumen(clienteId, {
      fechaInicial: desde?.trim() || undefined,
      fechaLimite: hasta?.trim() || undefined,
    }),
    listarTiposContenedoresConsulta(),
  ]);

  if (!resumen.cliente) notFound();

  const totalPendiente = resumen.saldos.reduce(
    (s, r) => s + r.saldo_pendiente,
    0,
  );
  const hist = resumen.historico;
  const movimientos = hist?.movimientos ?? [];

  // Mapear opciones de tipos de contenedor combinando catálogo y saldos actuales
  const saldosMap = new Map<string, number>();
  for (const s of resumen.saldos) {
    saldosMap.set(s.contenedor_id, s.saldo_pendiente);
  }

  const tiposParaModal: TipoContenedorInput[] = catalogoTipos.map((t) => ({
    id: t.id,
    label: t.label,
    saldoActual: saldosMap.get(t.id) ?? 0,
  }));

  return (
    <div className="lt-print-document space-y-6">
      <PageHeader
        title={resumen.cliente.razon_social}
        description={`RIF/NIT ${resumen.cliente.rif_nit} · Estado de cuenta de vacíos`}
        action={
          <div className="flex flex-wrap gap-2">
            <ModalRetirarContenedores
              clienteId={resumen.cliente.id}
              clienteNombre={resumen.cliente.razon_social}
              tipos={tiposParaModal}
            />
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
        Saldo neto actual:{" "}
        <span
          className={`font-semibold ${
            totalPendiente < 0
              ? "text-emerald-700"
              : totalPendiente > 0
                ? "text-red-700"
                : "text-lt-text"
          }`}
        >
          {totalPendiente < 0
            ? `${formatNumber(Math.abs(totalPendiente))} a favor del cliente`
            : formatNumber(totalPendiente)}
        </span>
      </p>

      <Card>
        <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-lt-text-subtle">
          Saldos actuales por contenedor
        </h2>
        <DataTable
          emptyMessage="Este cliente no tiene saldos de contenedores."
          columns={[
            { key: "contenedor", label: "Contenedor" },
            { key: "saldo", label: "Saldo" },
            { key: "actualizado", label: "Actualizado" },
          ]}
          rows={resumen.saldos.map((row) => {
            const esAFavor = row.saldo_pendiente < 0;
            return {
              id: row.id,
              cells: {
                contenedor: row.contenedor_codigo
                  ? `${row.contenedor_codigo} — ${row.contenedor_nombre}`
                  : row.contenedor_nombre,
                saldo: (
                  <span
                    className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-bold tabular-nums ${
                      esAFavor
                        ? "bg-emerald-100 text-emerald-800"
                        : row.saldo_pendiente === 0
                          ? "bg-gray-100 text-gray-800"
                          : "bg-red-100 text-red-800"
                    }`}
                  >
                    {esAFavor
                      ? `${formatNumber(Math.abs(row.saldo_pendiente))} a favor`
                      : formatNumber(row.saldo_pendiente)}
                  </span>
                ),
                actualizado: row.updated_at
                  ? formatDate(row.updated_at)
                  : "—",
              },
            };
          })}
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
              <p
                className={`text-lg font-semibold tabular-nums ${
                  hist.saldo_final < 0 ? "text-emerald-700" : ""
                }`}
              >
                {hist.saldo_final < 0
                  ? `${formatNumber(Math.abs(hist.saldo_final))} (a favor)`
                  : formatNumber(hist.saldo_final)}
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
            { key: "origen", label: "Origen / Tipo" },
            { key: "contenedor", label: "Contenedor" },
            { key: "entregada", label: "Entregados" },
            { key: "retirada", label: "Retirados" },
            { key: "observaciones", label: "Detalles" },
          ]}
          rows={movimientos.map((m) => {
            const codigo = m.codigo_contenedor?.trim() || "";
            const nombre = (m.nombre_contenedor || m.contenedor_id).trim();
            const esDirecto = m.es_movimiento_directo || !m.orden_id;

            return {
              id: String(m.id),
              cells: {
                fecha: formatDate(m.fecha_movimiento),
                origen: esDirecto ? (
                  <span className="inline-flex items-center rounded-md bg-amber-50 px-2 py-0.5 text-xs font-semibold text-amber-800 border border-amber-200">
                    Retiro directo
                  </span>
                ) : m.correlativo_orden != null ? (
                  <span className="text-xs font-medium text-lt-text">
                    Orden #{m.correlativo_orden}
                  </span>
                ) : (
                  <span className="text-xs text-lt-text-muted">
                    {m.factura_origen_numero || "Orden"}
                  </span>
                ),
                contenedor: codigo ? `${codigo} — ${nombre}` : nombre,
                entregada: (
                  <span className="tabular-nums">
                    {formatNumber(m.cantidad_entregada)}
                  </span>
                ),
                retirada: (
                  <span className="tabular-nums font-semibold text-lt-text">
                    {formatNumber(m.cantidad_retirada)}
                  </span>
                ),
                observaciones: (
                  <div className="space-y-0.5 text-xs">
                    {m.saldo_anterior != null && m.saldo_actual != null ? (
                      <p className="text-lt-text-muted">
                        Saldo: {m.saldo_anterior} →{" "}
                        <span className="font-semibold text-lt-text">
                          {m.saldo_actual}
                        </span>
                        {m.saldo_actual < 0 && (
                          <span className="text-emerald-700 ml-1">
                            (a favor)
                          </span>
                        )}
                      </p>
                    ) : null}
                    {m.observaciones ? (
                      <p className="italic text-lt-text-subtle">
                        {m.observaciones}
                      </p>
                    ) : null}
                  </div>
                ),
              },
            };
          })}
        />
      </Card>
    </div>
  );
}
