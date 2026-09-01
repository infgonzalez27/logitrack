import { redirect } from "next/navigation";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { retornaRadarDespachadorAction } from "@/lib/actions/radar";
import { PageHeader } from "@/components/layout/page-header";
import { RadarEntregaForm } from "../../radar-entrega-form";

export default async function RadarEntregaPage({
  params,
}: {
  params: Promise<{ ordenId: string }>;
}) {
  const { ordenId } = await params;
  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);

  if (rol !== "despachador") {
    redirect("/radar");
  }

  const result = await retornaRadarDespachadorAction();
  if (!result.ok) {
    return (
      <div className="mx-auto max-w-3xl space-y-6">
        <PageHeader title="Entrega" description="Registro de entrega en ruta." />
        <p className="lt-alert-error">{result.error}</p>
      </div>
    );
  }

  const orden = result.ordenes.find((o) => o.orden_id === ordenId);
  if (!orden) {
    return (
      <div className="mx-auto max-w-3xl space-y-6">
        <PageHeader title="Entrega" description="Registro de entrega en ruta." />
        <p className="lt-alert-error">
          No se encontró la orden en tu radar o ya no está en tránsito.
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
      <RadarEntregaForm orden={orden} backHref="/radar" />
    </div>
  );
}
