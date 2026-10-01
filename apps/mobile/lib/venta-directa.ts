import { normalizeRolNombre } from "./auth";
import { parseEnvasesResumen, type EnvaseResumenVenta } from "./envases-venta";
import { supabase } from "./supabase";

export type LineaVentaDirecta = {
  producto_id: string;
  cantidad: number;
  valor_unitario_usd: number;
};

export type VentaDirectaResultado = {
  ordenId: string;
  correlativo: number | null;
  totalUsd: number;
  contenedores: EnvaseResumenVenta[];
};

export function puedeVentaDirecta(rol: string | null | undefined): boolean {
  const r = normalizeRolNombre(rol);
  return r === "admin" || r === "gerente" || r === "vendedor";
}

/** `crear_venta_directa_almacen` (§2.1.1): venta en mostrador que descuenta del almacén. */
export async function crearVentaDirectaAlmacen(input: {
  vendedorId: string;
  clienteId: string;
  tasaCambio: number | null;
  lineas: LineaVentaDirecta[];
  retirados?: Array<{ contenedor_id: string; cantidad_retirada: number }>;
}): Promise<{ ok: true; venta: VentaDirectaResultado } | { ok: false; error: string }> {
  const retirados = (input.retirados ?? []).filter((r) => r.cantidad_retirada > 0);
  const params: Record<string, unknown> = {
    p_cliente_id: input.clienteId,
    p_vendedor_id: input.vendedorId,
    p_tipo_venta: "credito",
    p_tasa_cambio: input.tasaCambio && input.tasaCambio > 0 ? input.tasaCambio : null,
    p_productos_json: input.lineas,
  };
  // Sin retirados se omite el parámetro: así la llamada también funciona con la versión de 5 argumentos.
  if (retirados.length) params.p_contenedores_json = retirados;

  const { data, error } = await supabase.rpc("crear_venta_directa_almacen", params);

  if (error) {
    if (/could not find the function/i.test(error.message)) {
      return {
        ok: false,
        error: retirados.length
          ? "El retiro de envases en venta directa aún no está disponible en la base de datos de esta empresa."
          : "La venta directa aún no está disponible en la base de datos de esta empresa.",
      };
    }
    return { ok: false, error: error.message };
  }

  const env = data as {
    success?: boolean;
    message?: string;
    error?: { message?: string } | null;
    data?: {
      orden_id?: string;
      correlativo?: number;
      total_recaudar_usd?: number;
      contenedores?: unknown;
    } | null;
  } | null;

  if (!env?.success || !env.data?.orden_id) {
    return {
      ok: false,
      error: env?.error?.message ?? env?.message ?? "No se pudo registrar la venta.",
    };
  }

  return {
    ok: true,
    venta: {
      ordenId: env.data.orden_id,
      correlativo: env.data.correlativo ?? null,
      totalUsd: Number(env.data.total_recaudar_usd ?? 0),
      contenedores: parseEnvasesResumen(env.data.contenedores),
    },
  };
}
