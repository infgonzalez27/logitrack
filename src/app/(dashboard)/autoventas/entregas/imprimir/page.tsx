import { redirect } from "next/navigation";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { resolveUserEmpresa } from "@/lib/supabase/central";
import { obtenerReporteEntregasAction } from "@/lib/actions/reporte-entregas";
import { EntregasReporte } from "@/components/print/entregas-reporte";
import { CargaPrintControls } from "../../carga/imprimir/carga-print-controls";

export default async function EntregasReporteImprimirPage({
  searchParams,
}: {
  searchParams: Promise<{ camionId?: string; fecha?: string }>;
}) {
  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);
  if (
    rol !== "admin" &&
    rol !== "gerente" &&
    rol !== "vendedor" &&
    rol !== "despachador"
  ) {
    redirect("/");
  }

  const { camionId, fecha } = await searchParams;
  if (!camionId) {
    return (
      <div className="lt-carta-page mx-auto max-w-4xl space-y-4 px-2 py-4">
        <p className="lt-alert-error">Falta el ID del camión.</p>
      </div>
    );
  }

  const [empresa, data] = await Promise.all([
    profile ? resolveUserEmpresa(profile.id) : null,
    obtenerReporteEntregasAction(camionId, fecha),
  ]);

  return (
    <div className="lt-carta-page mx-auto max-w-4xl space-y-4 px-2 py-4">
      <CargaPrintControls descarga={false} />
      {data ? (
        <EntregasReporte data={data} empresaNombre={empresa?.nombre_empresa ?? null} />
      ) : (
        <p className="lt-alert-error">
          No se encontró información de entregas para este camión.
        </p>
      )}
    </div>
  );
}
