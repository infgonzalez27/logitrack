import { redirect } from "next/navigation";
import { getCurrentProfile, getSessionUser } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { createClient } from "@/lib/supabase/server";
import { PageHeader } from "@/components/layout/page-header";
import { VisitaClientePicker } from "./visita-cliente-picker";

export default async function VisitaPage() {
  const [profile, user] = await Promise.all([
    getCurrentProfile(),
    getSessionUser(),
  ]);
  const rol = getRoleNameFromProfile(profile);

  if (
    rol !== "vendedor" &&
    rol !== "gerente" &&
    rol !== "admin" &&
    rol !== "cobrador"
  ) {
    redirect("/");
  }

  const supabase = await createClient();
  let query = supabase
    .from("clientes")
    .select("id, razon_social, rif_nit")
    .eq("activo", true)
    .order("razon_social");

  if (rol === "vendedor" && user?.id) {
    query = query.eq("vendedor_id", user.id);
  }

  const { data: clientes } = await query;

  return (
    <div className="mx-auto max-w-xl space-y-6">
      <PageHeader
        title="Visita / cartera"
        description="Primero selecciona el cliente. Luego verás sus órdenes por liquidar y las acciones disponibles."
      />
      <VisitaClientePicker
        clientes={(clientes ?? []).map((c) => ({
          value: c.id,
          label: `${c.razon_social}${c.rif_nit ? ` · ${c.rif_nit}` : ""}`,
        }))}
      />
    </div>
  );
}
