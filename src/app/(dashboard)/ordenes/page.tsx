import Link from "next/link";
import { getCurrentProfile, getSessionUser } from "@/lib/auth";
import { canCreateOrden } from "@/lib/auth/orden-permissions";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { listarOrdenesDistribucion } from "@/lib/data/ordenes";
import { getNombresPerfilByIds } from "@/lib/data/perfiles";
import { labelOrdenEstado, ORDEN_ESTADOS } from "@/lib/constants";
import { formatDate, formatNumber } from "@/lib/format";
import { PageHeader } from "@/components/layout/page-header";
import { Button } from "@/components/ui/button";
import { DataTable } from "@/components/ui/data-table";
import { Badge, ordenEstadoTone } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import type { OrdenEstado } from "@/types/database";

export default async function OrdenesPage({
  searchParams,
}: {
  searchParams: Promise<{ estado?: string }>;
}) {
  const { estado: estadoParam } = await searchParams;
  const estadoFiltro =
    estadoParam &&
    ORDEN_ESTADOS.some((e) => e.value === estadoParam)
      ? (estadoParam as OrdenEstado)
      : "todos";

  const [user, profile] = await Promise.all([
    getSessionUser(),
    getCurrentProfile(),
  ]);
  const rol = getRoleNameFromProfile(profile);
  const puedeCrear = canCreateOrden(rol);

  const ordenes = await listarOrdenesDistribucion({
    userId: user?.id,
    rol,
    estado: estadoFiltro,
  });

  const nombresChofer = await getNombresPerfilByIds(
    ordenes.map((o) => o.chofer_id).filter(Boolean) as string[],
  );

  return (
    <div className="space-y-6">
      <PageHeader
        title="Órdenes de distribución"
        description="Despacho maestro-detalle"
        action={
          puedeCrear ? (
            <Button href="/ordenes/nuevo">Nueva orden</Button>
          ) : undefined
        }
      />

      <div className="lt-no-print flex flex-wrap gap-2">
        <Link
          href="/ordenes"
          className={`rounded-xl px-3 py-1.5 text-sm ${
            estadoFiltro === "todos"
              ? "bg-lt-primary text-white"
              : "border border-lt-border bg-lt-surface text-lt-text"
          }`}
        >
          Todas
        </Link>
        {ORDEN_ESTADOS.filter((e) => e.value !== "lista_para_carga").map(
          (e) => (
            <Link
              key={e.value}
              href={`/ordenes?estado=${e.value}`}
              className={`rounded-xl px-3 py-1.5 text-sm ${
                estadoFiltro === e.value
                  ? "bg-lt-primary text-white"
                  : "border border-lt-border bg-lt-surface text-lt-text"
              }`}
            >
              {e.label}
            </Link>
          ),
        )}
      </div>

      <Card>
        <DataTable
          columns={[
            { key: "correlativo", label: "#" },
            { key: "factura", label: "Factura origen" },
            { key: "cliente", label: "Cliente" },
            { key: "chofer", label: "Chofer" },
            { key: "estado", label: "Estado" },
            { key: "tasa", label: "Tasa" },
            { key: "total_bs", label: "Total Bs" },
            { key: "fecha", label: "Despacho" },
            { key: "acciones", label: "" },
          ]}
          rows={ordenes.map((o) => ({
            id: o.id,
            cells: {
              correlativo: `#${o.correlativo}`,
              factura: o.factura_origen_numero,
              cliente: o.cliente_razon_social ?? "—",
              chofer: o.chofer_id
                ? (nombresChofer[o.chofer_id] ?? "—")
                : "—",
              estado: (
                <Badge tone={ordenEstadoTone(o.estado)}>
                  {labelOrdenEstado(o.estado)}
                </Badge>
              ),
              tasa:
                o.tasa_cambio != null ? formatNumber(Number(o.tasa_cambio)) : "—",
              total_bs:
                o.total_recaudar_bs != null
                  ? formatNumber(Number(o.total_recaudar_bs))
                  : "—",
              fecha: formatDate(o.fecha_despacho),
              acciones: (
                <div className="flex flex-wrap gap-3">
                  <Link
                    href={`/ordenes/${o.id}`}
                    className="text-sm font-medium text-lt-primary underline hover:text-lt-primary-hover"
                  >
                    Ver
                  </Link>
                  <Link
                    href={`/ordenes/${o.id}/imprimir`}
                    className="lt-no-print text-sm font-medium text-lt-primary underline hover:text-lt-primary-hover"
                  >
                    Imprimir ticket
                  </Link>
                </div>
              ),
            },
          }))}
          emptyMessage="No hay órdenes para este filtro."
        />
      </Card>
    </div>
  );
}
