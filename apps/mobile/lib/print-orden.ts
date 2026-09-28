import {
  buildOrdenTicketText,
  type OrdenTicketData,
} from "./ticket";
import {
  fetchEstadoCuentaVacios,
  resolveDespachadorNombre,
  type OrdenDetalle,
} from "./ordenes";

/** Arma el texto ESC/POS de una orden (líneas + vacíos). */
export async function buildTicketForOrden(
  orden: OrdenDetalle,
): Promise<{ text: string; totalUsd: number; data: OrdenTicketData }> {
  const [despachadorNombre, vacios] = await Promise.all([
    resolveDespachadorNombre(orden.despachador_id),
    fetchEstadoCuentaVacios(orden),
  ]);

  const detalle = [...(orden.detalle_distribucion ?? [])].sort(
    (a, b) => (a.secuencia_entrega ?? 0) - (b.secuencia_entrega ?? 0),
  );

  const lineas = detalle.map((l) => {
    const unitarioUsd = Number(
      l.valor_unitario_usd != null && Number(l.valor_unitario_usd) > 0
        ? l.valor_unitario_usd
        : 0,
    );
    const subtotalUsd = Number(
      l.subtotal_recaudar_usd != null && Number(l.subtotal_recaudar_usd) > 0
        ? l.subtotal_recaudar_usd
        : unitarioUsd * Number(l.cantidad_solicitada ?? 0),
    );
    return {
      id: l.id,
      secuencia: l.secuencia_entrega ?? "·",
      codigo: l.productos?.codigo_producto ?? "-",
      producto: l.productos?.nombre ?? "Producto",
      cantidad: Number(l.cantidad_solicitada),
      unitario: unitarioUsd,
      subtotal: subtotalUsd,
    };
  });

  const total =
    orden.total_recaudar_usd != null && Number(orden.total_recaudar_usd) > 0
      ? Number(orden.total_recaudar_usd)
      : lineas.reduce((s, l) => s + l.subtotal, 0);

  const data: OrdenTicketData = {
    correlativo: orden.correlativo,
    facturaOrigen: orden.factura_origen_numero ?? "-",
    estado: orden.estado,
    creadaAt: orden.created_at,
    clienteNombre: orden.clientes?.razon_social ?? "-",
    clienteRif: orden.clientes?.rif_nit ?? "-",
    clienteDireccion: orden.clientes?.direccion_fiscal ?? "-",
    camionLabel: orden.camiones
      ? `${orden.camiones.placa}${orden.camiones.modelo ? ` · ${orden.camiones.modelo}` : ""}`
      : "-",
    despachadorNombre,
    pesoKg: Number(orden.peso_total_calculado ?? 0),
    lineas,
    totalRecaudar: total,
    estadoCuentaVacios: vacios.lineas,
    estadoCuentaProvisional: vacios.provisional,
  };

  return {
    text: buildOrdenTicketText(data),
    totalUsd: total,
    data,
  };
}
