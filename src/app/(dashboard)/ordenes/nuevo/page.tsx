import { redirect } from "next/navigation";
import { getCurrentProfile } from "@/lib/auth";
import { canCreateOrden } from "@/lib/auth/orden-permissions";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { listarChoferesParaOrdenAction } from "@/lib/actions/usuarios";
import { listarProductosAction } from "@/lib/actions/productos";
import { createClient } from "@/lib/supabase/server";
import { NuevaOrdenForm } from "./nueva-orden-form";

export default async function NuevaOrdenPage() {
  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);
  if (!canCreateOrden(rol)) redirect("/ordenes");

  const supabase = await createClient();

  const [
    { data: clientes },
    { data: camiones },
    choferesResult,
    productosResult,
  ] = await Promise.all([
    supabase.from("clientes").select("id, razon_social").eq("activo", true).order("razon_social"),
    supabase.from("camiones").select("id, placa").neq("estado", "inactivo").order("placa"),
    listarChoferesParaOrdenAction(),
    listarProductosAction(),
  ]);

  const choferes = choferesResult.ok ? choferesResult.choferes : [];
  const productos = productosResult.ok ? productosResult.productos : [];

  return (
    <NuevaOrdenForm
      clientes={(clientes ?? []).map((c) => ({
        value: c.id,
        label: c.razon_social,
      }))}
      camiones={(camiones ?? []).map((c) => ({
        value: c.id,
        label: c.placa,
      }))}
      choferes={choferes.map((c) => ({
        value: c.id,
        label: c.nombre_completo,
      }))}
      choferesError={choferesResult.ok ? null : choferesResult.error}
      choferesAviso={choferesResult.ok ? choferesResult.aviso : null}
      productos={productos}
      productosError={productosResult.ok ? null : productosResult.error}
    />
  );
}
