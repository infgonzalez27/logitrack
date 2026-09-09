import { redirect } from "next/navigation";
import Link from "next/link";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { retornaRadarDetalleReporteAction } from "@/lib/actions/radar";
import { PageHeader } from "@/components/layout/page-header";
import { RadarAprobarButton } from "../radar-aprobar-button";
import { RadarParadasView } from "../radar-paradas-view";
import { RadarReporteView } from "../radar-reporte-view";

export default async function RadarDetallePage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);

  if (
    rol !== "despachador" &&
    rol !== "gerente" &&
    rol !== "vendedor" &&
    rol !== "admin"
  ) {
    redirect("/");
  }

  const modoDespachador = rol === "despachador";
  const puedeAprobar = rol === "gerente" || rol === "admin";
  const reporte = await retornaRadarDetalleReporteAction(id);

  const radarAprobado = Boolean(
    reporte.ok &&
      (reporte.reporte.radar.aprobado === true ||
        (reporte.reporte.radar as { aprobado?: boolean }).aprobado),
  );

  return (
    <div className="mx-auto max-w-4xl space-y-8">
      <PageHeader
        title="Detalle del radar"
        description="Órdenes y paradas vinculadas a este radar."
        action={
          <Link
            href="/radar"
            className="text-sm font-medium text-lt-primary hover:underline"
          >
            ← Volver al listado
          </Link>
        }
      />

      {reporte.ok ? (
        <>
          <section className="space-y-3">
            <RadarParadasView
              reporte={reporte.reporte}
              radarId={id}
              modoDespachador={modoDespachador}
            />
          </section>
          {!modoDespachador ? (
            <section className="border-t border-lt-border pt-8">
              <h2 className="mb-4 text-base font-semibold text-lt-text">
                Reporte completo
              </h2>
              <RadarReporteView reporte={reporte.reporte} />
            </section>
          ) : null}
        </>
      ) : (
        <p className="lt-alert-error">{reporte.error}</p>
      )}

      {puedeAprobar ? (
        <section className="space-y-3 border-t border-lt-border pt-8">
          <h2 className="text-base font-semibold text-lt-text">
            Aprobación gerencial
          </h2>
          <p className="text-sm text-lt-text-muted">
            Al aprobar: se acreditan vacíos retirados, se restituye al almacén
            la mercancía no despachada y las órdenes de vuelta pasan a anuladas.
            El SP no evalúa entrega completa/parcial; eso ya quedó en las
            cantidades registradas por el despachador.
          </p>
          <RadarAprobarButton radarId={id} yaAprobado={radarAprobado} />
        </section>
      ) : null}
    </div>
  );
}
