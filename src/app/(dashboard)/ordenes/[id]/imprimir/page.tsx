import { notFound } from "next/navigation";
import { getCurrentProfile, getSessionUser } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { getOrdenDistribucionDetalle } from "@/lib/data/ordenes";
import { getNombresPerfilByIds } from "@/lib/data/perfiles";
import { joinOne } from "@/lib/supabase/join";
import { OrdenTicket } from "@/components/print/orden-ticket";
import { OrdenPrintControls } from "./orden-print-controls";
import type { OrdenEstado } from "@/types/database";

export default async function OrdenImprimirPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const [user, profile] = await Promise.all([
    getSessionUser(),
    getCurrentProfile(),
  ]);
  const rol = getRoleNameFromProfile(profile);

  const orden = await getOrdenDistribucionDetalle(id, {
    userId: user?.id,
    rol,
  });

  if (!orden) notFound();

  const cliente = joinOne(orden.clientes);
  const camion = joinOne(orden.camiones);
  const perfilIds = [orden.despachador_id, orden.chofer_id].filter(
    (id): id is string => !!id,
  );
  const nombresPerfil = perfilIds.length
    ? await getNombresPerfilByIds(perfilIds)
    : {};
  const choferNombre =
    (orden.despachador_id
      ? nombresPerfil[orden.despachador_id]
      : null) ??
    (orden.chofer_id ? nombresPerfil[orden.chofer_id] : null) ??
    "—";

  const detalle = [...(orden.detalle_distribucion ?? [])].sort(
    (a, b) => (a.secuencia_entrega ?? 0) - (b.secuencia_entrega ?? 0),
  );

  const lineas = detalle.map((linea) => {
    const producto = joinOne(linea.productos);
    return {
      id: linea.id,
      secuencia: linea.secuencia_entrega ?? "—",
      codigo: producto?.codigo_producto ?? "—",
      producto: producto?.nombre ?? "—",
      cantidad: linea.cantidad_solicitada,
      unitario: linea.valor_unitario_recaudar,
      subtotal: linea.subtotal_recaudar,
    };
  });

  const totalRecaudar = lineas.reduce((sum, linea) => sum + linea.subtotal, 0);

  return (
    <div className="lt-ticket-page mx-auto max-w-[22rem] space-y-4 px-2 py-4">
      <OrdenPrintControls volverHref={`/ordenes/${orden.id}`} />

      <OrdenTicket
        correlativo={orden.correlativo}
        facturaOrigen={orden.factura_origen_numero}
        estado={orden.estado as OrdenEstado}
        creadaAt={orden.created_at}
        clienteNombre={cliente?.razon_social ?? "—"}
        clienteRif={cliente?.rif_nit ?? "—"}
        clienteDireccion={cliente?.direccion_fiscal ?? "—"}
        camionLabel={camion ? `${camion.placa} — ${camion.modelo}` : "—"}
        choferNombre={choferNombre}
        pesoKg={orden.peso_total_calculado}
        lineas={lineas}
        totalRecaudar={totalRecaudar}
      />
    </div>
  );
}
