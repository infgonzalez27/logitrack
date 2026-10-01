"use server";

import { revalidatePath } from "next/cache";
import { getCurrentProfile, getSessionUser } from "@/lib/auth";
import { canCreateOrden } from "@/lib/auth/orden-permissions";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { callDbProcedure, rpcErrorMessage } from "@/lib/actions/db-rpc";
import {
  parseEnvasesResumen,
  type EnvaseResumenVenta,
} from "@/lib/contenedores/envases-venta";

export type VentaDirectaLineaInput = {
  producto_id: string;
  cantidad: number;
  valor_unitario_usd: number;
};

export type VentaDirectaResultado = {
  orden_id: string;
  correlativo: number | null;
  total_recaudar_usd: number;
  contenedores: EnvaseResumenVenta[];
};

export type VentaDirectaRetiroInput = {
  contenedor_id: string;
  cantidad_retirada: number;
};

/** `crear_venta_directa_almacen` (§2.1.1): venta en mostrador que descuenta del almacén. */
export async function crearVentaDirectaAlmacenAction(input: {
  cliente_id: string;
  lineas: VentaDirectaLineaInput[];
  tasa_cambio?: number | null;
  retirados?: VentaDirectaRetiroInput[];
}): Promise<{ ok: true; venta: VentaDirectaResultado } | { ok: false; error: string }> {
  const [profile, user] = await Promise.all([getCurrentProfile(), getSessionUser()]);
  const rol = getRoleNameFromProfile(profile);
  if (!user || !canCreateOrden(rol)) {
    return { ok: false, error: "No tienes permiso para registrar ventas directas." };
  }

  const clienteId = input.cliente_id?.trim();
  if (!clienteId) return { ok: false, error: "Selecciona un cliente." };

  const lineas = input.lineas.filter((l) => l.producto_id);
  if (!lineas.length) return { ok: false, error: "Agrega al menos un producto." };
  for (const l of lineas) {
    if (!Number.isInteger(l.cantidad) || l.cantidad <= 0) {
      return { ok: false, error: "Las cantidades deben ser enteras y mayores a 0." };
    }
    if (!Number.isFinite(l.valor_unitario_usd) || l.valor_unitario_usd < 0) {
      return { ok: false, error: "El precio unitario no puede ser negativo." };
    }
  }

  const tasa =
    input.tasa_cambio != null && Number.isFinite(input.tasa_cambio) && input.tasa_cambio > 0
      ? input.tasa_cambio
      : null;

  const retirados = (input.retirados ?? []).filter(
    (r) => r.contenedor_id && r.cantidad_retirada > 0,
  );
  for (const r of retirados) {
    if (!Number.isInteger(r.cantidad_retirada)) {
      return { ok: false, error: "Los envases retirados deben ser cantidades enteras." };
    }
  }

  const params: Record<string, unknown> = {
    p_cliente_id: clienteId,
    p_vendedor_id: user.id,
    p_tipo_venta: "credito",
    p_tasa_cambio: tasa,
    p_productos_json: lineas.map((l) => ({
      producto_id: l.producto_id,
      cantidad: l.cantidad,
      valor_unitario_usd: l.valor_unitario_usd,
    })),
  };
  // Sin retirados se omite el parámetro: así la llamada también funciona con la versión de 5 argumentos.
  if (retirados.length) params.p_contenedores_json = retirados;

  const response = await callDbProcedure<{
    orden_id?: string;
    correlativo?: number;
    total_recaudar_usd?: number;
    contenedores?: unknown;
  }>("crear_venta_directa_almacen", params);

  if (!response.success || !response.data?.orden_id) {
    const mensaje = rpcErrorMessage(response, "No se pudo registrar la venta.");
    if (/could not find the function/i.test(mensaje)) {
      return {
        ok: false,
        error: retirados.length
          ? "El retiro de envases en venta directa aún no está disponible en la base de datos de esta empresa."
          : "La venta directa aún no está disponible en la base de datos de esta empresa.",
      };
    }
    return { ok: false, error: mensaje };
  }

  revalidatePath("/ordenes");
  revalidatePath("/inventario-almacen");
  revalidatePath("/rendiciones/por-liquidar");
  return {
    ok: true,
    venta: {
      orden_id: response.data.orden_id,
      correlativo: response.data.correlativo ?? null,
      total_recaudar_usd: Number(response.data.total_recaudar_usd ?? 0),
      contenedores: parseEnvasesResumen(response.data.contenedores),
    },
  };
}
