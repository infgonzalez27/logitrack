import { redirect } from "next/navigation";
import { getCurrentProfile, getSessionUser } from "@/lib/auth";
import { canCreateOrden } from "@/lib/auth/orden-permissions";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { listarProductosAction } from "@/lib/actions/productos";
import { retornaUltimaTasaCambioAction } from "@/lib/actions/tasa-cambio";
import { createClient } from "@/lib/supabase/server";
import { VentaDirectaForm } from "./venta-directa-form";

export default async function VentaDirectaPage() {
  const [profile, user] = await Promise.all([getCurrentProfile(), getSessionUser()]);
  const rol = getRoleNameFromProfile(profile);
  if (!canCreateOrden(rol)) redirect("/ordenes");

  const supabase = await createClient();
  let clientesQuery = supabase
    .from("clientes")
    .select("id, razon_social, rif_nit")
    .eq("activo", true)
    .order("razon_social");
  if (rol === "vendedor" && user?.id) {
    clientesQuery = clientesQuery.eq("vendedor_id", user.id);
  }

  const [{ data: clientes }, productosResult, tasaResult] = await Promise.all([
    clientesQuery,
    listarProductosAction(),
    retornaUltimaTasaCambioAction(),
  ]);

  return (
    <VentaDirectaForm
      clientes={(clientes ?? []).map((c) => ({
        value: c.id,
        label: c.razon_social,
        hint: c.rif_nit ?? null,
      }))}
      productos={productosResult.ok ? productosResult.productos : []}
      productosError={productosResult.ok ? null : productosResult.error}
      tasaActual={tasaResult.ok ? tasaResult.tasa : null}
    />
  );
}
