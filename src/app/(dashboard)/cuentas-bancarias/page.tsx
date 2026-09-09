import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { listarCuentasBancariasEmpresaAction } from "@/lib/actions/cuentas-bancarias";
import { PageHeader } from "@/components/layout/page-header";
import { CuentasBancariasClient } from "./cuentas-bancarias-client";

export default async function CuentasBancariasPage() {
  const [profile, cuentasResult] = await Promise.all([
    getCurrentProfile(),
    listarCuentasBancariasEmpresaAction(false),
  ]);
  const rol = getRoleNameFromProfile(profile);
  const puedeGestionar = rol === "admin" || rol === "gerente";

  return (
    <div className="mx-auto max-w-3xl space-y-6">
      <PageHeader
        title="Cuentas bancarias"
        description="Cuentas destino de la empresa para rendición de cuentas. Solo registrar y modificar."
      />
      {!cuentasResult.ok ? (
        <p className="lt-alert-error">{cuentasResult.error}</p>
      ) : null}
      <CuentasBancariasClient
        cuentasIniciales={cuentasResult.ok ? cuentasResult.cuentas : []}
        puedeGestionar={puedeGestionar}
      />
    </div>
  );
}
