import { redirect } from "next/navigation";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { obtenerClientesConDescuentosAction } from "@/lib/actions/descuentos";
import { PageHeader } from "@/components/layout/page-header";
import { Button } from "@/components/ui/button";
import { DescuentosClientesListaClient } from "./descuentos-clientes-lista-client";

export default async function DescuentosClientesPage() {
  const profile = await getCurrentProfile();
  if (getRoleNameFromProfile(profile) !== "gerente") {
    redirect("/clientes");
  }

  const res = await obtenerClientesConDescuentosAction();

  return (
    <div className="space-y-6">
      <PageHeader
        title="Descuentos por cliente"
        description="Consulta directa y control global de descuentos"
        action={
          <Button href="/clientes" variant="secondary">
            Volver a clientes
          </Button>
        }
      />

      {!res.ok ? (
        <div className="rounded-xl border border-rose-500/30 bg-rose-500/10 p-4 text-sm text-rose-700 dark:text-rose-400">
          {res.error}
        </div>
      ) : (
        <DescuentosClientesListaClient
          clientes={res.clientes}
          hayAlgunDescuentoActivo={res.hayAlgunDescuentoActivo}
        />
      )}
    </div>
  );
}
