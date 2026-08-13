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
  const puedeEditar = rol === "admin" || rol === "gerente";

  return (
    <div className="mx-auto max-w-3xl space-y-6">
      <PageHeader
        title="Rutas"
        description="Consulta y edición de nombre/descripción. No se permiten altas desde la aplicación."
      />
      {!rutasResult.ok ? (
        <p className="lt-alert-error">{rutasResult.error}</p>
      ) : (
        <p className="text-sm text-lt-text-muted">
          {rutasResult.total_registros} ruta
          {rutasResult.total_registros === 1 ? "" : "s"}
        </p>
      )}
      <RutasClient
        rutasIniciales={rutasResult.ok ? rutasResult.rutas : []}
        puedeEditar={puedeEditar}
      />
    </div>
  );
}
