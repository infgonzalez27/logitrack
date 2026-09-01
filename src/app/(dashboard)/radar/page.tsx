import { redirect } from "next/navigation";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { retornaRadarDespachadorAction } from "@/lib/actions/radar";
import { retornaUsuariosDespachadoresAction } from "@/lib/actions/rutas";
import { listarRadares } from "@/lib/data/radares";
import { PageHeader } from "@/components/layout/page-header";
import { RadarCrearForm } from "./radar-crear-form";
import { RadarLista } from "./radar-lista";
import { RadarParadasDespachador } from "./radar-paradas-despachador";

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
          description="Paradas de tu ruta. Selecciona un cliente para registrar la entrega."
        />
        {!result.ok ? (
          <p className="lt-alert-error">{result.error}</p>
        ) : (
          <RadarParadasDespachador ordenes={result.ordenes} />
        )}
      </div>
    );
  }

  const [radares, despachadores] = await Promise.all([
    listarRadares(),
    retornaUsuariosDespachadoresAction(),
  ]);

  return (
    <div className="mx-auto max-w-4xl space-y-6">
      <PageHeader
        title="Radar"
        description="Listado de radares por fecha de entrega y despachador."
      />
      {!despachadores.ok ? (
        <p className="lt-alert-error">{despachadores.error}</p>
      ) : (
        <RadarCrearForm despachadores={despachadores.despachadores} />
      )}
      <div>
        <h2 className="mb-3 text-base font-semibold text-lt-text">
          Radares recientes
        </h2>
        <RadarLista radares={radares} />
      </div>
    </div>
  );
}
