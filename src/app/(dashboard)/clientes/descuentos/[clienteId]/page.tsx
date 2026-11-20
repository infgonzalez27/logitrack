import { notFound, redirect } from "next/navigation";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { createClient } from "@/lib/supabase/server";
import { obtenerTodosDescuentosClienteAction } from "@/lib/actions/descuentos";
import { listarProductosAction } from "@/lib/actions/productos";
import { PageHeader } from "@/components/layout/page-header";
import { Button } from "@/components/ui/button";
import { DescuentosClienteDetalleClient } from "./descuentos-cliente-detalle-client";

export default async function DescuentoClienteDetallePage({
  params,
}: {
  params: Promise<{ clienteId: string }>;
}) {
  const profile = await getCurrentProfile();
  if (getRoleNameFromProfile(profile) !== "gerente") {
    redirect("/clientes");
  }

  const { clienteId } = await params;
  const supabase = await createClient();

  const [{ data: cliente }, resDescuentos, resProductos] = await Promise.all([
    supabase
      .from("clientes")
      .select("id, razon_social, rif_nit")
      .eq("id", clienteId)
      .single(),
    obtenerTodosDescuentosClienteAction(clienteId),
    listarProductosAction(""),
  ]);

  if (!cliente) {
    notFound();
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title={`Descuentos — ${cliente.razon_social}`}
        description={
          cliente.rif_nit
            ? `RIF/NIT: ${cliente.rif_nit} · Gestión de porcentajes y estado por producto`
            : "Gestión de porcentajes y estado por producto"
        }
        action={
          <Button href="/clientes/descuentos" variant="secondary">
            Volver al listado
          </Button>
        }
      />

      {!resDescuentos.ok ? (
        <div className="rounded-xl border border-rose-500/30 bg-rose-500/10 p-4 text-sm text-rose-700 dark:text-rose-400">
          {resDescuentos.error}
        </div>
      ) : (
        <DescuentosClienteDetalleClient
          clienteId={cliente.id}
          descuentosIniciales={resDescuentos.descuentos}
          productos={resProductos.ok ? resProductos.productos : []}
        />
      )}
    </div>
  );
}
