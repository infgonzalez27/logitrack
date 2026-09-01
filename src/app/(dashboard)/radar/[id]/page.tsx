import { redirect } from "next/navigation";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { retornaRadarDetalleReporteAction } from "@/lib/actions/radar";
import { PageHeader } from "@/components/layout/page-header";
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

  const result = await retornaRadarDetalleReporteAction(id);
  if (!result.ok) {
    return (
      <div className="mx-auto max-w-4xl space-y-6">
        <PageHeader title="Radar" description="Detalle del radar." />
        <p className="lt-alert-error">{result.error}</p>
      </div>
    );
  }

  const modoDespachador = rol === "despachador";

  return (
    <div className="mx-auto max-w-4xl space-y-8">
      <PageHeader
        title="Clientes a visitar"
        description="Paradas del radar agrupadas por cliente."
      />
      <RadarParadasView
        reporte={result.reporte}
        radarId={id}
        modoDespachador={modoDespachador}
      />
      {!modoDespachador ? (
        <section className="border-t border-lt-border pt-8">
          <h2 className="mb-4 text-base font-semibold text-lt-text">
            Reporte completo
          </h2>
          <RadarReporteView reporte={result.reporte} />
        </section>
      ) : null}
    </div>
  );
}
