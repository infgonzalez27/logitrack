import { redirect } from "next/navigation";
import { getCurrentProfile, getSessionUser } from "@/lib/auth";
import { canCreateOrden } from "@/lib/auth/orden-permissions";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { listarCamionesParaOrdenAction } from "@/lib/actions/entities";
import { listarChoferesParaOrdenAction } from "@/lib/actions/usuarios";
import { listarProductosAction } from "@/lib/actions/productos";
import { createClient } from "@/lib/supabase/server";
import { NuevaOrdenForm } from "./nueva-orden-form";

export default async function NuevaOrdenPage() {
  const [profile, user] = await Promise.all([
    getCurrentProfile(),
    getSessionUser(),
  ]);
  const rol = getRoleNameFromProfile(profile);
  if (!canCreateOrden(rol)) redirect("/ordenes");

  const supabase = await createClient();

  let clientesQuery = supabase
    .from("clientes")
    .select("id, razon_social, vendedor_id")
    .eq("activo", true)
    .order("razon_social");

  // Cartera: vendedor solo ve clientes asignados (DB-016)
  if (rol === "vendedor" && user?.id) {
    clientesQuery = clientesQuery.eq("vendedor_id", user.id);
  }

  const [
    { data: clientes },
    camionesResult,
    choferesResult,
    productosResult,
  ] = await Promise.all([
    clientesQuery,
    listarCamionesParaOrdenAction(),
    listarChoferesParaOrdenAction(),
    listarProductosAction(),
  ]);

  const camiones = camionesResult.ok ? camionesResult.camiones : [];
  const choferes = choferesResult.ok ? choferesResult.choferes : [];
  const productos = productosResult.ok ? productosResult.productos : [];

  return (
    <NuevaOrdenForm
      clientes={(clientes ?? []).map((c) => ({
        value: c.id,
        label: c.razon_social,
      }))}
      camiones={camiones.map((c) => ({
        value: c.id,
        label: c.placa,
      }))}
      camionesError={camionesResult.ok ? null : camionesResult.error}
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
