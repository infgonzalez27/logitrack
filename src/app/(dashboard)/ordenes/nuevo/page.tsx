import { redirect } from "next/navigation";
import { getCurrentProfile, getSessionUser } from "@/lib/auth";
import { canCreateOrden } from "@/lib/auth/orden-permissions";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { listarCamionesParaOrdenAction } from "@/lib/actions/entities";
import { listarProductosAction } from "@/lib/actions/productos";
import { retornaUsuariosDespachadoresAction } from "@/lib/actions/rutas";
import { retornaUltimaTasaCambioAction } from "@/lib/actions/tasa-cambio";
import { createClient } from "@/lib/supabase/server";
import { NuevaOrdenForm } from "./nueva-orden-form";

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export default async function NuevaOrdenPage({
  searchParams,
}: {
  searchParams: Promise<{ cliente_id?: string; volver?: string }>;
}) {
  const [profile, user] = await Promise.all([
    getCurrentProfile(),
    getSessionUser(),
  ]);
  const rol = getRoleNameFromProfile(profile);
  if (!canCreateOrden(rol)) redirect("/ordenes");

  const sp = await searchParams;
  const clienteIdPrefill =
    sp.cliente_id && UUID_RE.test(sp.cliente_id.trim())
      ? sp.cliente_id.trim()
      : null;
  const volverHref =
    sp.volver && sp.volver.startsWith("/") ? sp.volver : null;

  const supabase = await createClient();

  let clientesQuery = supabase
    .from("clientes")
    .select("id, razon_social, vendedor_id, despachador_id")
    .eq("activo", true)
    .order("razon_social");

  if (rol === "vendedor" && user?.id) {
    clientesQuery = clientesQuery.eq("vendedor_id", user.id);
  }

  const [
    { data: clientes },
    camionesResult,
    despachadoresResult,
    productosResult,
    tasaResult,
  ] = await Promise.all([
    clientesQuery,
    listarCamionesParaOrdenAction(),
    retornaUsuariosDespachadoresAction(),
    listarProductosAction(),
    retornaUltimaTasaCambioAction(),
  ]);

  const camiones = camionesResult.ok ? camionesResult.camiones : [];
  const productos = productosResult.ok ? productosResult.productos : [];
  const despachadorNombrePorId = new Map(
    (despachadoresResult.ok ? despachadoresResult.despachadores : []).map(
      (d) => [d.id, d.nombre_completo],
    ),
  );

  const clienteOptions = (clientes ?? []).map((c) => ({
    value: c.id,
    label: c.razon_social,
    despachador_id: c.despachador_id ?? null,
    despachador_nombre: c.despachador_id
      ? (despachadorNombrePorId.get(c.despachador_id) ?? null)
      : null,
  }));

  const initialClienteId =
    clienteIdPrefill &&
    clienteOptions.some((c) => c.value === clienteIdPrefill)
      ? clienteIdPrefill
      : "";

  return (
    <NuevaOrdenForm
      clientes={clienteOptions}
      camiones={camiones.map((c) => ({
        value: c.id,
        label: c.placa,
      }))}
      camionesError={camionesResult.ok ? null : camionesResult.error}
      productos={productos}
      productosError={productosResult.ok ? null : productosResult.error}
      tasaActual={tasaResult.ok ? tasaResult.tasa : null}
      initialClienteId={initialClienteId || undefined}
      lockCliente={Boolean(initialClienteId)}
      volverHref={volverHref}
    />
  );
}
