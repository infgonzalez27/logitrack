import { redirect } from "next/navigation";
import Link from "next/link";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { retornaRadarDetalleReporteAction } from "@/lib/actions/radar";
import { createClient } from "@/lib/supabase/server";
import { PageHeader } from "@/components/layout/page-header";
import { RadarGerenciaActions } from "../radar-gerencia-actions";
import { RadarParadasView } from "../radar-paradas-view";
import { RadarRegenerarButton } from "../radar-regenerar-button";
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
  const puedeRegenerar =
    rol === "admin" || rol === "gerente" || rol === "vendedor";
  const reporte = await retornaRadarDetalleReporteAction(id);

  const supabase = await createClient();
  const { data: radarRow } = await supabase
    .from("radars")
    .select("status_radar, carga_inventario_movil")
    .eq("id", id)
    .maybeSingle();

  const radarAprobado = Boolean(
    radarRow?.status_radar === true ||
      (reporte.ok && reporte.reporte.radar.status_radar === true),
  );
  const cargaInventarioMovil = Boolean(radarRow?.carga_inventario_movil);

  const correlativo = reporte.ok ? reporte.reporte.radar.correlativo : null;
  const fechaDespacho = reporte.ok
    ? reporte.reporte.radar.fecha_despacho
    : null;

  return (
    <div className="mx-auto max-w-4xl space-y-8">
      <PageHeader
        title={
          correlativo != null ? `Radar # ${correlativo}` : "Detalle del radar"
        }
        description={
          fechaDespacho
            ? `Fecha de despacho ${fechaDespacho} · Carga y paradas`
            : "Órdenes y paradas vinculadas a este radar."
        }
        action={
          <div className="flex flex-wrap items-center gap-3 print:hidden">
            {puedeRegenerar ? (
              <RadarRegenerarButton
                radarId={id}
                yaAprobado={radarAprobado}
                cargaInventarioMovil={cargaInventarioMovil}
              />
            ) : null}
            <Link
              href="/radar"
              className="text-sm font-medium text-lt-primary hover:underline"
            >
              ← Volver al listado
            </Link>
          </div>
        }
      />

      {reporte.ok ? (
        <>
          <section className="space-y-3 print:hidden">
            <RadarParadasView
              reporte={reporte.reporte}
              radarId={id}
              modoDespachador={modoDespachador}
            />
          </section>
          <section className="border-t border-lt-border pt-8 print:border-0 print:pt-0">
            <h2 className="mb-4 text-base font-semibold text-lt-text print:hidden">
              Reporte de carga
            </h2>
            <RadarReporteView reporte={reporte.reporte} />
          </section>
        </>
      ) : (
        <p className="lt-alert-error print:hidden">{reporte.error}</p>
      )}

      {puedeAprobar ? (
        <section className="space-y-3 border-t border-lt-border pt-8 print:hidden">
          <h2 className="text-base font-semibold text-lt-text">
            Aprobación gerencial
          </h2>
          <p className="text-sm text-lt-text-muted">
            Al aprobar: se acreditan vacíos retirados, se restituye al almacén
            la mercancía no despachada y las órdenes de vuelta pasan a anuladas.
            El SP no evalúa entrega completa/parcial; eso ya quedó en las
            cantidades registradas por el despachador.
          </p>
          <RadarGerenciaActions
            radarId={id}
            yaAprobado={radarAprobado}
            cargaInventarioMovil={cargaInventarioMovil}
          />
        </section>
      ) : null}
    </div>
  );
}
