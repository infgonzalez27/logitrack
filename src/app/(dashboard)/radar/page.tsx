import { redirect } from "next/navigation";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { retornaRadarDespachadorAction } from "@/lib/actions/radar";
import { PageHeader } from "@/components/layout/page-header";
import { RadarClient } from "./radar-client";

export default async function RadarPage() {
  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);
  if (rol !== "despachador") redirect("/");

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
