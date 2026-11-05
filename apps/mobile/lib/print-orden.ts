import * as Print from "expo-print";
import {
  buildOrdenTicketText,
  type OrdenTicketData,
} from "./ticket";
import {
  fetchEstadoCuentaVacios,
  getOrdenDetalle,
  resolveDespachadorNombre,
  type OrdenDetalle,
} from "./ordenes";
import { getEmpresaActual } from "./supabase";
import { printToPreferredPrinter } from "./bluetooth-print";

function escapeHtml(text: string): string {
  return String(text ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

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
    empresaNombre: getEmpresaActual()?.nombre,
    empresaCodigo: getEmpresaActual()?.codigo,
  };

  return {
    text: buildOrdenTicketText(data),
    totalUsd: total,
    data,
  };
}

/** Imprime el ticket de una orden en la impresora Bluetooth preferida. */
export async function imprimirTicketOrden(
  ordenOId: string | OrdenDetalle,
): Promise<{ ok: true } | { ok: false; error: string; sinImpresora?: boolean }> {
  let orden: OrdenDetalle;
  if (typeof ordenOId === "string") {
    const res = await getOrdenDetalle(ordenOId);
    if (!res.ok) return { ok: false, error: res.error };
    orden = res.orden;
  } else {
    orden = ordenOId;
  }
  const ticket = await buildTicketForOrden(orden);
  return printToPreferredPrinter(ticket.text, {
    codigoEmpresa: getEmpresaActual()?.codigo,
  });
}

/** Construye una hoja HTML limpia lista para Impresora Wi-Fi / Red del sistema. */
export async function buildHtmlForOrden(orden: OrdenDetalle): Promise<string> {
  const { data } = await buildTicketForOrden(orden);
  const filasHtml = data.lineas
    .map(
      (l) => `
      <tr>
        <td>${escapeHtml(String(l.codigo))}</td>
        <td>${escapeHtml(l.producto)}</td>
        <td style="text-align:center;">${l.cantidad}</td>
        <td style="text-align:right;">$${l.unitario.toFixed(2)}</td>
        <td style="text-align:right;font-weight:bold;">$${l.subtotal.toFixed(2)}</td>
      </tr>`,
    )
    .join("");

  const vaciosHtml =
    data.estadoCuentaVacios && data.estadoCuentaVacios.length > 0
      ? `
      <h3 style="margin-top:16px;font-size:13px;">Estado de Cuenta de Envases / Contenedores</h3>
      <table>
        <thead>
          <tr>
            <th>Contenedor</th>
            <th style="text-align:center;">Saldo Ant.</th>
            <th style="text-align:center;">Entregado</th>
            <th style="text-align:center;">Retirado</th>
            <th style="text-align:center;">Saldo Nuevo</th>
          </tr>
        </thead>
        <tbody>
          ${data.estadoCuentaVacios
            .map(
              (v) => `
            <tr>
              <td>${escapeHtml(v.nombre)}</td>
              <td style="text-align:center;">${v.saldo_anterior}</td>
              <td style="text-align:center;">+${v.entregado}</td>
              <td style="text-align:center;">-${v.retirado}</td>
              <td style="text-align:center;font-weight:bold;">${v.saldo_nuevo}</td>
            </tr>`,
            )
            .join("")}
        </tbody>
      </table>`
      : "";

  return `
  <!DOCTYPE html>
  <html lang="es">
  <head>
    <meta charset="utf-8" />
    <style>
      body { font-family: Arial, Helvetica, sans-serif; font-size: 12px; color: #111; padding: 16px; }
      h1 { font-size: 18px; margin: 0 0 4px 0; color: #0B3A5C; }
      .meta { margin-bottom: 12px; line-height: 1.4; }
      table { width: 100%; border-collapse: collapse; margin-top: 8px; }
      th, td { border: 1px solid #cbd5e1; padding: 6px 8px; font-size: 11px; text-align: left; }
      th { background: #f1f5f9; font-weight: bold; }
      .total { text-align: right; font-size: 15px; font-weight: bold; margin-top: 12px; }
    </style>
  </head>
  <body>
    <h1>${escapeHtml(data.empresaNombre ?? "LogiTrack")} — Orden #${data.correlativo}</h1>
    <div class="meta">
      <div><strong>Cliente:</strong> ${escapeHtml(data.clienteNombre)} (${escapeHtml(data.clienteRif)})</div>
      <div><strong>Dirección:</strong> ${escapeHtml(data.clienteDireccion)}</div>
      <div><strong>Camión:</strong> ${escapeHtml(data.camionLabel)} · <strong>Despachador:</strong> ${escapeHtml(data.despachadorNombre)}</div>
      <div><strong>Estado:</strong> ${escapeHtml(data.estado.toUpperCase())} · <strong>Peso:</strong> ${data.pesoKg.toFixed(2)} kg</div>
    </div>
    <table>
      <thead>
        <tr>
          <th>Código</th>
          <th>Producto</th>
          <th style="text-align:center;">Cant.</th>
          <th style="text-align:right;">Unit.</th>
          <th style="text-align:right;">Subtotal</th>
        </tr>
      </thead>
      <tbody>${filasHtml}</tbody>
    </table>
    <div class="total">Total a Recaudar: $${data.totalRecaudar.toFixed(2)}</div>
    ${vaciosHtml}
  </body>
  </html>`;
}

/** Abre el diálogo nativo de impresión Wi-Fi / Red del sistema Android/iOS. */
export async function imprimirOrdenWifi(
  ordenOId: string | OrdenDetalle,
): Promise<{ ok: true } | { ok: false; error: string }> {
  try {
    let orden: OrdenDetalle;
    if (typeof ordenOId === "string") {
      const res = await getOrdenDetalle(ordenOId);
      if (!res.ok) return { ok: false, error: res.error };
      orden = res.orden;
    } else {
      orden = ordenOId;
    }
    const html = await buildHtmlForOrden(orden);
    await Print.printAsync({ html });
    return { ok: true };
  } catch (err) {
    const msg =
      err instanceof Error ? err.message : "No se pudo imprimir por Wi-Fi.";
    return { ok: false, error: msg };
  }
}
