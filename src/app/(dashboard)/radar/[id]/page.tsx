import { redirect } from "next/navigation";
import Link from "next/link";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import {
  retornaOrdenesDistribucionSegunIdRadarAction,
  retornaRadarDetalleReporteAction,
} from "@/lib/actions/radar";
import { PageHeader } from "@/components/layout/page-header";
import { RadarOrdenesResumen } from "../radar-ordenes-resumen";
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
  const [resumen, reporte] = await Promise.all([
    retornaOrdenesDistribucionSegunIdRadarAction(id),
    retornaRadarDetalleReporteAction(id),
  ]);

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

      <section className="space-y-3">
        <h2 className="text-base font-semibold text-lt-text">
          Órdenes del radar
        </h2>
        {!resumen.ok ? (
          <p className="lt-alert-error">{resumen.error}</p>
        ) : (
          <RadarOrdenesResumen
            ordenes={resumen.ordenes}
            radarId={id}
            modoDespachador={modoDespachador}
          />
        )}
      </section>

      {reporte.ok ? (
        <>
          <section className="space-y-3 border-t border-lt-border pt-8">
            <h2 className="text-base font-semibold text-lt-text">
              Clientes a visitar
            </h2>
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
      ) : null}
    </div>
  );
}
