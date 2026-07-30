import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { retornaUltimaTasaCambioAction } from "@/lib/actions/tasa-cambio";
import { PageHeader } from "@/components/layout/page-header";
import { TasasCambioClient } from "./tasas-cambio-client";

export default async function TasasCambioPage() {
  const [profile, ultimaResult] = await Promise.all([
    getCurrentProfile(),
    retornaUltimaTasaCambioAction(),
  ]);
  const rol = getRoleNameFromProfile(profile);
  const puedeGestionar = rol === "admin" || rol === "gerente";

  return (
    <div className="mx-auto max-w-3xl space-y-6">
      <PageHeader
        title="Tasas de cambio"
        description="Tasa BCV (Bs/USD) por fecha. Obligatoria al crear órdenes de distribución."
      />
      {!ultimaResult.ok ? (
        <p className="lt-alert-error">{ultimaResult.error}</p>
      ) : null}
      <TasasCambioClient
        ultimaInicial={ultimaResult.ok ? ultimaResult.tasa : null}
        puedeGestionar={puedeGestionar}
      />
    </div>
  );
}
