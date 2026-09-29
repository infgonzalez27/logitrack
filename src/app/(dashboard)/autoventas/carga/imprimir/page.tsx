import { redirect } from "next/navigation";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { decodeCargaTicket } from "@/lib/autoventas/carga-ticket";
import { CargaCamionTicket } from "@/components/print/carga-camion-ticket";
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

  return (
    <div className="lt-ticket-page mx-auto max-w-[22rem] space-y-4 px-2 py-4">
      <CargaPrintControls />
      {data ? (
        <CargaCamionTicket {...data} />
      ) : (
        <p className="lt-alert-error">
          No se encontró la carga a imprimir. Vuelve a AutoVentas.
        </p>
      )}
    </div>
  );
}
