import { createClient } from "@/lib/supabase/server";
import { PageHeader } from "@/components/layout/page-header";
import { NuevaRendicionForm } from "./nueva-rendicion-form";

export default async function NuevaRendicionPage() {
  const supabase = await createClient();
  const { data: clientes } = await supabase
    .from("clientes")
    .select("id, razon_social, rif_nit")
    .eq("activo", true)
    .order("razon_social");

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <PageHeader
        title="Rendición de cuentas"
        description="Cliente → formas de pago (con captura) → órdenes por liquidar."
      />
      <NuevaRendicionForm
        clientes={(clientes ?? []).map((c) => ({
          value: c.id,
          label: c.razon_social,
          codigo: c.rif_nit ?? "",
        }))}
      />
    </div>
  );
}
