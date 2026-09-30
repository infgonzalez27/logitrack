import { supabase } from "./supabase";
import { isRpcSuccess, rpcFailMessage } from "./rpc";

export type MovimientoTipo = "ENTRADA" | "SALIDA";
export type MovimientoInventario = "ALMACEN" | "MOVIL";

export const MOVIMIENTO_CONCEPTOS: { value: string; label: string }[] = [
  { value: "OBSEQUIO", label: "Obsequio" },
  { value: "CONSUMO_INTERNO", label: "Consumo interno" },
  { value: "EVENTOS", label: "Eventos" },
  { value: "MERMA", label: "Merma / daño" },
  { value: "AJUSTE", label: "Ajuste" },
];

export function labelConcepto(value: string): string {
  return MOVIMIENTO_CONCEPTOS.find((c) => c.value === value)?.label ?? value;
}

export function puedeMovimientosEspeciales(rol: string | null | undefined): boolean {
  return rol === "admin" || rol === "gerente";
}

export type MovimientoEspecialItem = {
  id: string;
  fecha: string;
  tipo: MovimientoTipo;
  concepto: string;
  inventario: MovimientoInventario;
  camion: string | null;
  cliente: string | null;
  observaciones: string | null;
  lineas: Array<{ producto: string; cantidad: number; costo_unitario: number }>;
  costo_total: number;
};

type MovimientoRow = {
  id: string;
  fecha_movimiento: string;
  tipo_movimiento: MovimientoTipo;
  concepto: string;
  tipo_inventario_afectado: MovimientoInventario;
  id_referencia_movil: string | null;
  id_cliente: string | null;
  observaciones: string | null;
  movimientos_inventario_detalle: Array<{
    id_producto: string;
    cantidad: number;
    costo_unitario: number;
  }>;
};

async function mapaNombres(
  tabla: "productos" | "camiones" | "clientes",
  columna: "nombre" | "placa" | "razon_social",
  ids: string[],
): Promise<Map<string, string>> {
  const unicos = [...new Set(ids.filter(Boolean))];
  if (!unicos.length) return new Map();
  const { data } = await supabase.from(tabla).select(`id, ${columna}`).in("id", unicos);
  return new Map(
    ((data ?? []) as unknown as Array<Record<string, string>>).map((r) => [r.id, r[columna]]),
  );
}

export async function listMovimientosEspeciales(): Promise<
  { ok: true; items: MovimientoEspecialItem[] } | { ok: false; error: string }
> {
  const { data, error } = await supabase
    .from("movimientos_inventario")
    .select(
      "id, fecha_movimiento, tipo_movimiento, concepto, tipo_inventario_afectado, id_referencia_movil, id_cliente, observaciones, movimientos_inventario_detalle(id_producto, cantidad, costo_unitario)",
    )
    .order("fecha_movimiento", { ascending: false })
    .limit(100);
  if (error) return { ok: false, error: error.message };

  const rows = (data ?? []) as MovimientoRow[];
  const [productos, camiones, clientes] = await Promise.all([
    mapaNombres(
      "productos",
      "nombre",
      rows.flatMap((r) => r.movimientos_inventario_detalle.map((d) => d.id_producto)),
    ),
    mapaNombres("camiones", "placa", rows.map((r) => r.id_referencia_movil ?? "")),
    mapaNombres("clientes", "razon_social", rows.map((r) => r.id_cliente ?? "")),
  ]);

  return {
    ok: true,
    items: rows.map((r) => {
      const lineas = r.movimientos_inventario_detalle.map((d) => ({
        producto: productos.get(d.id_producto) ?? "Producto",
        cantidad: Number(d.cantidad) || 0,
        costo_unitario: Number(d.costo_unitario) || 0,
      }));
      return {
        id: r.id,
        fecha: r.fecha_movimiento,
        tipo: r.tipo_movimiento,
        concepto: r.concepto,
        inventario: r.tipo_inventario_afectado,
        camion: r.id_referencia_movil ? camiones.get(r.id_referencia_movil) ?? "—" : null,
        cliente: r.id_cliente ? clientes.get(r.id_cliente) ?? "—" : null,
        observaciones: r.observaciones,
        lineas,
        costo_total: lineas.reduce((s, l) => s + l.cantidad * l.costo_unitario, 0),
      };
    }),
  };
}

export type DatosMovimiento = {
  productos: Array<{ id: string; nombre: string; codigo: string | null }>;
  camiones: Array<{ id: string; placa: string }>;
  stockAlmacen: Record<string, number>;
  stockMovil: Record<string, Record<string, number>>;
  ultimoCosto: Record<string, number>;
};

export async function cargarDatosMovimiento(): Promise<
  { ok: true; datos: DatosMovimiento } | { ok: false; error: string }
> {
  const [productos, camiones, almacen, movil, compras] = await Promise.all([
    supabase.from("productos").select("id, nombre, codigo_producto").order("nombre"),
    supabase.from("camiones").select("id, placa").neq("estado", "inactivo").order("placa"),
    supabase.from("inventario_almacen").select("producto_id, stock_disponible"),
    supabase
      .from("inventario_movil")
      .select("camion_id, producto_id, cantidad_cargada, cantidad_entregada"),
    supabase
      .from("detalle_facturas_compras")
      .select("producto_id, precio_unitario_compra, facturas_compras(fecha_emision, created_at)")
      .limit(5000),
  ]);
  const fallo = productos.error ?? camiones.error;
  if (fallo) return { ok: false, error: fallo.message };

  const ultimoCosto: Record<string, number> = {};
  const fechaCosto: Record<string, string> = {};
  for (const d of (compras.data ?? []) as Array<{
    producto_id: string | null;
    precio_unitario_compra: number | null;
    facturas_compras:
      | { fecha_emision?: string | null; created_at?: string | null }
      | Array<{ fecha_emision?: string | null; created_at?: string | null }>
      | null;
  }>) {
    const f = Array.isArray(d.facturas_compras) ? d.facturas_compras[0] : d.facturas_compras;
    const fecha = String(f?.fecha_emision ?? f?.created_at ?? "");
    if (!d.producto_id) continue;
    if (!fechaCosto[d.producto_id] || fecha > fechaCosto[d.producto_id]) {
      fechaCosto[d.producto_id] = fecha;
      ultimoCosto[d.producto_id] = Number(d.precio_unitario_compra) || 0;
    }
  }

  const stockAlmacen: Record<string, number> = {};
  for (const r of almacen.data ?? []) {
    if (r.producto_id) stockAlmacen[r.producto_id] = Number(r.stock_disponible) || 0;
  }

  const stockMovil: Record<string, Record<string, number>> = {};
  for (const r of movil.data ?? []) {
    if (!r.camion_id || !r.producto_id) continue;
    (stockMovil[r.camion_id] ??= {})[r.producto_id] = Math.max(
      0,
      (Number(r.cantidad_cargada) || 0) - (Number(r.cantidad_entregada) || 0),
    );
  }

  return {
    ok: true,
    datos: {
      productos: (productos.data ?? []).map((p) => ({
        id: p.id,
        nombre: p.nombre,
        codigo: p.codigo_producto ?? null,
      })),
      camiones: (camiones.data ?? []).map((c) => ({ id: c.id, placa: c.placa })),
      stockAlmacen,
      stockMovil,
      ultimoCosto,
    },
  };
}

const UUID_RE =
  /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi;

/** `registrar_movimiento_inventario_especial` (§6). */
export async function registrarMovimientoEspecial(input: {
  tipo: MovimientoTipo;
  concepto: string;
  inventario: MovimientoInventario;
  camionId: string | null;
  clienteId: string | null;
  observaciones: string;
  detalles: Array<{ producto_id: string; cantidad: number; costo_unitario: number }>;
  nombresProducto: Record<string, string>;
}): Promise<{ ok: true } | { ok: false; error: string }> {
  const { data, error } = await supabase.rpc("registrar_movimiento_inventario_especial", {
    p_tipo_movimiento: input.tipo,
    p_concepto: input.concepto.trim().toUpperCase(),
    p_tipo_inventario_afectado: input.inventario,
    p_id_referencia_movil: input.inventario === "MOVIL" ? input.camionId : null,
    p_id_cliente: input.clienteId || null,
    p_observaciones: input.observaciones.trim() || null,
    p_detalles: input.detalles,
  });

  const mensaje = error
    ? error.message
    : !isRpcSuccess(data)
      ? rpcFailMessage(data, "No se pudo registrar el movimiento.")
      : null;
  if (!mensaje) return { ok: true };
  return {
    ok: false,
    error: mensaje.replace(UUID_RE, (id) =>
      input.nombresProducto[id] ? `«${input.nombresProducto[id]}»` : id,
    ),
  };
}
