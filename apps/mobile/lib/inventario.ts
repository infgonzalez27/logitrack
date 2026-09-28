import { supabase } from "./supabase";
import { joinOne } from "./join";

export type InventarioAlmacenItem = {
  id: string;
  producto_id: string;
  producto_nombre: string;
  codigo_barras: string | null;
  stock_disponible: number;
  stock_comprometido: number;
  ubicacion_pasillo: string | null;
  updated_at: string | null;
};

export type InventarioMovilItem = {
  id: string;
  camion_id: string;
  camion_placa: string;
  producto_id: string;
  producto_nombre: string;
  cantidad_cargada: number;
  cantidad_entregada: number;
  cantidad_devolucion: number;
  updated_at: string | null;
};

export type ProductoOption = { id: string; nombre: string };

export async function listInventarioAlmacen(): Promise<
  | { ok: true; items: InventarioAlmacenItem[] }
  | { ok: false; error: string }
> {
  const { data, error } = await supabase
    .from("inventario_almacen")
    .select("*, productos(nombre, codigo_barras)")
    .order("updated_at", { ascending: false });

  if (error) return { ok: false, error: error.message };

  return {
    ok: true,
    items: (data ?? []).map((row) => {
      const prod = joinOne(
        row.productos as
          | { nombre?: string; codigo_barras?: string | null }
          | { nombre?: string; codigo_barras?: string | null }[]
          | null,
      );
      return {
        id: row.id,
        producto_id: row.producto_id,
        producto_nombre: prod?.nombre ?? "—",
        codigo_barras: prod?.codigo_barras ?? null,
        stock_disponible: Number(row.stock_disponible ?? 0),
        stock_comprometido: Number(row.stock_comprometido ?? 0),
        ubicacion_pasillo: row.ubicacion_pasillo ?? null,
        updated_at: row.updated_at ?? null,
      };
    }),
  };
}

export async function listProductosOptions(): Promise<
  { ok: true; productos: ProductoOption[] } | { ok: false; error: string }
> {
  const { data, error } = await supabase
    .from("productos")
    .select("id, nombre")
    .order("nombre");
  if (error) return { ok: false, error: error.message };
  return {
    ok: true,
    productos: (data ?? []).map((p) => ({ id: p.id, nombre: p.nombre })),
  };
}

/** Upsert stock almacén (producto_id UNIQUE), igual que web createInventarioAlmacenAction. */
export async function upsertInventarioAlmacen(input: {
  producto_id: string;
  stock_disponible: number;
  ubicacion_pasillo?: string | null;
}): Promise<{ ok: true } | { ok: false; error: string }> {
  const productoId = input.producto_id.trim();
  if (!productoId) return { ok: false, error: "Selecciona un producto." };

  const { error } = await supabase.from("inventario_almacen").upsert(
    {
      producto_id: productoId,
      stock_disponible: Number(input.stock_disponible) || 0,
      ubicacion_pasillo: input.ubicacion_pasillo?.trim() || null,
      updated_at: new Date().toISOString(),
    },
    { onConflict: "producto_id" },
  );

  if (error) return { ok: false, error: error.message };
  return { ok: true };
}

export async function listInventarioMovil(camionId?: string | null): Promise<
  | { ok: true; items: InventarioMovilItem[] }
  | { ok: false; error: string }
> {
  let query = supabase
    .from("inventario_movil")
    .select("*, camiones(placa), productos(nombre)")
    .order("updated_at", { ascending: false });

  if (camionId?.trim()) {
    query = query.eq("camion_id", camionId.trim());
  }

  const { data, error } = await query;
  if (error) return { ok: false, error: error.message };

  return {
    ok: true,
    items: (data ?? []).map((row) => {
      const camion = joinOne(
        row.camiones as { placa?: string } | { placa?: string }[] | null,
      );
      const prod = joinOne(
        row.productos as { nombre?: string } | { nombre?: string }[] | null,
      );
      return {
        id: row.id,
        camion_id: row.camion_id,
        camion_placa: camion?.placa ?? "—",
        producto_id: row.producto_id,
        producto_nombre: prod?.nombre ?? "—",
        cantidad_cargada: Number(row.cantidad_cargada ?? 0),
        cantidad_entregada: Number(row.cantidad_entregada ?? 0),
        cantidad_devolucion: Number(row.cantidad_devolucion ?? 0),
        updated_at: row.updated_at ?? null,
      };
    }),
  };
}
