import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { retornaListaRutasAction } from "@/lib/actions/rutas";
import { PageHeader } from "@/components/layout/page-header";
import { RutasClient } from "./rutas-client";

export default async function RutasPage() {
  const [profile, rutasResult] = await Promise.all([
    getCurrentProfile(),
    retornaListaRutasAction(),
  ]);
  const rol = getRoleNameFromProfile(profile);
  const puedeGestionar = rol === "admin" || rol === "gerente";

  return (
    <div className="mx-auto max-w-3xl space-y-6">
      <PageHeader
        title="Rutas"
        description="Rutas de despacho para asignar a clientes."
      />
      {!rutasResult.ok ? (
        <p className="lt-alert-error">{rutasResult.error}</p>
      ) : null}
      <RutasClient
        rutasIniciales={rutasResult.ok ? rutasResult.rutas : []}
        puedeGestionar={puedeGestionar}
      />
    </div>
  );
}
