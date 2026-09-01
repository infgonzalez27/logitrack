import { redirect } from "next/navigation";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import {
  retornaRadarDespachadorAction,
  retornaRadarDetalleReporteAction,
} from "@/lib/actions/radar";
import { PageHeader } from "@/components/layout/page-header";
import type { RadarDetalleReporte, RadarOrden } from "@/types/database";
import { RadarEntregaForm } from "../../../radar-entrega-form";

function ordenFromReporte(
  reporte: RadarDetalleReporte,
  ordenId: string,
): RadarOrden | null {
  const raw = reporte.ordenes?.find(
    (o) => String(o.orden_id ?? o.id ?? "") === ordenId,
  );
  if (!raw) return null;

  return {
    orden_id: ordenId,
    correlativo: Number(raw.correlativo ?? 0),
    estado: String(raw.estado ?? "en_transito"),
    fecha_despacho: raw.fecha_despacho ?? null,
    tasa_cambio: null,
    total_recaudar_bs: null,
    total_recaudar_usd: null,
    cliente: {
      id: String((raw.cliente as { id?: string } | undefined)?.id ?? ""),
      razon_social: raw.cliente?.razon_social ?? "Cliente",
      rif_nit: raw.cliente?.rif_nit ?? "",
      direccion_fiscal: raw.cliente?.direccion_fiscal ?? null,
      telefono: raw.cliente?.telefono ?? null,
      movil1: raw.cliente?.movil1 ?? null,
      nombre_ruta: raw.cliente?.nombre_ruta ?? null,
    },
    detalles: raw.detalles ?? [],
    saldo_contenedores: [],
  };
}

export default async function RadarEntregaConRadarPage({
  params,
}: {
  params: Promise<{ id: string; ordenId: string }>;
}) {
  const { id, ordenId } = await params;
  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);

  if (rol !== "despachador") {
    redirect(`/radar/${id}`);
  }

  const radarResult = await retornaRadarDespachadorAction();
  let orden: RadarOrden | undefined;

  if (radarResult.ok) {
    orden = radarResult.ordenes.find((o) => o.orden_id === ordenId);
  }

  if (!orden) {
    const reporteResult = await retornaRadarDetalleReporteAction(id);
    if (reporteResult.ok) {
      const mapped = ordenFromReporte(reporteResult.reporte, ordenId);
      if (mapped) orden = mapped;
    }
  }

  if (!orden) {
    return (
      <div className="mx-auto max-w-3xl space-y-6">
        <PageHeader title="Entrega" description="Registro de entrega en ruta." />
        <p className="lt-alert-error">
          No se encontró la orden en este radar.
        </p>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-3xl space-y-6">
      <PageHeader
        title="Detalle de entrega"
        description="Registra productos entregados y envases retirados."
      />
      <RadarEntregaForm orden={orden} backHref={`/radar/${id}`} />
    </div>
  );
}
