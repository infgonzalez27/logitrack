import { redirect } from "next/navigation";
import Link from "next/link";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { retornaOrdenesPorLiquidarAction } from "@/lib/actions/rendiciones";
import { PageHeader } from "@/components/layout/page-header";
import { PrintButton } from "@/components/print/print-button";
import { PorLiquidarLista } from "./por-liquidar-lista";

export default async function OrdenesPorLiquidarPage() {
  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);

  if (
    rol !== "admin" &&
    rol !== "gerente" &&
    rol !== "vendedor" &&
    rol !== "cobrador"
  ) {
    redirect("/");
  }

  const result = await retornaOrdenesPorLiquidarAction();
  const items = result.ok ? result.items : [];

  return (
    <div className="lt-print-document mx-auto max-w-5xl space-y-6">
      <PageHeader
        title="Órdenes por liquidar"
        description="Cartera por cliente (días vencidos y montos desde el SP)."
        action={
          <div className="flex flex-wrap gap-2">
            <PrintButton label="Imprimir" />
            <Link
              href="/rendiciones/nuevo"
              className="lt-no-print inline-flex items-center justify-center rounded-xl bg-lt-primary px-4 py-2 text-sm font-medium text-white hover:opacity-90"
            >
              Nueva cobranza
            </Link>
          </div>
        }
      />

      {!result.ok ? (
        <p className="lt-alert-error">{result.error}</p>
      ) : null}

      <PorLiquidarLista items={items} />
    </div>
  );
}
