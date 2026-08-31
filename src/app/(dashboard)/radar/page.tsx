import { redirect } from "next/navigation";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { retornaRadarDespachadorAction } from "@/lib/actions/radar";
import { retornaUsuariosDespachadoresAction } from "@/lib/actions/rutas";
import { PageHeader } from "@/components/layout/page-header";
import { RadarClient } from "./radar-client";
import { RadarCrearForm } from "./radar-crear-form";

export default async function RadarPage() {
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

  if (rol === "despachador") {
    const result = await retornaRadarDespachadorAction();
    return (
      <div className="mx-auto max-w-3xl space-y-6">
        <PageHeader
          title="Radar"
          description="Despachos en ruta de tus clientes. Registra entregas y retiro de envases."
        />
        {!result.ok ? (
          <p className="lt-alert-error">{result.error}</p>
        ) : (
          <RadarClient ordenes={result.ordenes} />
        )}
      </div>
    );
  }

  const despachadores = await retornaUsuariosDespachadoresAction();

  return (
    <div className="mx-auto max-w-4xl space-y-6">
      <PageHeader
        title="Radar"
        description="Crea o abre el radar por fecha de entrega y despachador. Las órdenes se agrupan con esas dos claves."
      />
      {!despachadores.ok ? (
        <p className="lt-alert-error">{despachadores.error}</p>
      ) : (
        <RadarCrearForm despachadores={despachadores.despachadores} />
      )}
    </div>
  );
}
