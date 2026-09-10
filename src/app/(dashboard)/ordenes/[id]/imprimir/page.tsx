import { notFound } from "next/navigation";
import { getCurrentProfile, getSessionUser } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { getOrdenDistribucionDetalle } from "@/lib/data/ordenes";
import { getNombresPerfilByIds } from "@/lib/data/perfiles";
import { retornaEstadoCuentaVaciosOrden } from "@/lib/ordenes/estado-cuenta-vacios";
import { joinOne } from "@/lib/supabase/join";
import { OrdenTicket } from "@/components/print/orden-ticket";
import { OrdenPrintControls } from "./orden-print-controls";
import type { OrdenEstado } from "@/types/database";

export default async function OrdenImprimirPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{
    de_vuelta?: string;
    estado_cuenta?: string;
    volver?: string;
  }>;
}) {
  const { id } = await params;
  const {
    de_vuelta,
    estado_cuenta,
    volver: volverParam,
  } = await searchParams;
  const esDeVuelta = de_vuelta === "1" || de_vuelta === "true";
  const pedirEstadoCuenta =
    estado_cuenta === "1" ||
    estado_cuenta === "true" ||
    esDeVuelta;

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
    const unitarioUsd = Number(
      linea.valor_unitario_usd != null && Number(linea.valor_unitario_usd) > 0
        ? linea.valor_unitario_usd
        : 0,
    );
    const subtotalUsd = Number(
      linea.subtotal_recaudar_usd != null &&
        Number(linea.subtotal_recaudar_usd) > 0
        ? linea.subtotal_recaudar_usd
        : unitarioUsd * Number(linea.cantidad_solicitada ?? 0),
    );
    return {
      id: linea.id,
      secuencia: linea.secuencia_entrega ?? "—",
      codigo: producto?.codigo_producto ?? "—",
      producto: producto?.nombre ?? "—",
      cantidad: linea.cantidad_solicitada,
      unitario: unitarioUsd,
      subtotal: subtotalUsd,
    };
  });

  const totalRecaudar = lineas.reduce((sum, linea) => sum + linea.subtotal, 0);

  const estadoCuenta = pedirEstadoCuenta
    ? await retornaEstadoCuentaVaciosOrden({
        clienteId: orden.cliente_id,
        radarId: orden.radar_id ?? null,
        detalle,
      })
    : null;

  const volverHref =
    volverParam && volverParam.startsWith("/")
      ? volverParam
      : `/ordenes/${orden.id}`;

  return (
    <div className="lt-ticket-page mx-auto max-w-[22rem] space-y-4 px-2 py-4">
      <OrdenPrintControls
        volverHref={volverHref}
        volverLabel={
          volverParam?.startsWith("/radar")
            ? "Volver al radar"
            : "Volver a la orden"
        }
      />

      {esDeVuelta ? (
        <p className="rounded-xl border border-lt-warning-border bg-lt-warning-bg px-3 py-2 text-center text-sm font-semibold text-lt-warning-text print:border-black print:bg-transparent print:text-black">
          ORDEN DEVUELTA — revisar saldo de vacíos
        </p>
      ) : null}

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
        estadoCuentaVacios={estadoCuenta?.lineas}
        estadoCuentaProvisional={estadoCuenta?.provisional}
      />
    </div>
  );
}
