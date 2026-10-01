import { redirect } from "next/navigation";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { decodeCargaTicket } from "@/lib/autoventas/carga-ticket";
import { getVaciosRetiradosPorOrden } from "@/lib/autoventas/vacios-por-orden";
import { resolveUserEmpresa } from "@/lib/supabase/central";
import { CargaCamionReporte } from "@/components/print/carga-camion-reporte";
import { CargaPrintControls } from "./carga-print-controls";

export default async function CargaCamionImprimirPage({
  searchParams,
}: {
  searchParams: Promise<{ d?: string }>;
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

  const { d } = await searchParams;
  const data = decodeCargaTicket(d);
  const [empresa, vaciosPorOrden] = await Promise.all([
    profile ? resolveUserEmpresa(profile.id) : null,
    data?.camionId ? getVaciosRetiradosPorOrden(data.camionId, data.fecha) : null,
  ]);

  return (
    <div className="lt-carta-page mx-auto max-w-4xl space-y-4 px-2 py-4">
      <CargaPrintControls descarga={data?.tipo === "descarga"} />
      {data ? (
        <CargaCamionReporte
          {...data}
          empresaNombre={empresa?.nombre_empresa ?? null}
          vaciosPorOrden={vaciosPorOrden}
        />
      ) : (
        <p className="lt-alert-error">
          No se encontró el comprobante a imprimir. Vuelve a AutoVentas.
        </p>
      )}
    </div>
  );
}
