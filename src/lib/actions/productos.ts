"use server";

import { revalidatePath } from "next/cache";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import type {
  ActualizarProductoRpcInput,
  ProductoListaRpc,
} from "@/types/database";

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function isUuid(value: string): boolean {
  return UUID_RE.test(value.trim());
}

type ProductoTablaRow = {
  id: string;
  nombre: string;
  codigo_producto: string | null;
  codigo_barras: string | null;
  precio_lista1: number | null;
  precio_lista2: number | null;
  precio_lista3: number | null;
};

function mapProductoTablaRow(
  row: ProductoTablaRow,
  stock: number,
): ProductoListaRpc {
  return {
    id: row.id,
    nombre: row.nombre,
    codigo_producto: row.codigo_producto,
    codigo_barras: row.codigo_barras,
    precio: row.precio_lista1 ?? 0,
    precio_lista1: row.precio_lista1 ?? 0,
    precio_lista2: row.precio_lista2 ?? 0,
    precio_lista3: row.precio_lista3 ?? 0,
    stock_disponible: stock,
  };
}

async function cargarStockPorProducto(
  ids: string[],
): Promise<Map<string, number>> {
  if (!ids.length) return new Map();

  const { data } = await createAdminClient()
    .from("inventario_almacen")
    .select("producto_id, stock_disponible")
    .in("producto_id", ids);

  return new Map(
    (data ?? []).map((row) => [row.producto_id, row.stock_disponible]),
  );
}

/** Búsqueda parcial por código de producto, nombre o código de barras. */
async function buscarProductosEnTabla(
  termino: string,
): Promise<
  { ok: true; productos: ProductoListaRpc[] } | { ok: false; error: string }
> {
  const q = termino.trim();
  if (q.length < 2) {
    return { ok: true, productos: [] };
  }

  const pattern = `%${q}%`;
  const { data: rows, error } = await createAdminClient()
    .from("productos")
    .select(
      "id, nombre, codigo_producto, codigo_barras, precio_lista1, precio_lista2, precio_lista3",
    )
    .or(
      `codigo_producto.ilike.${pattern},nombre.ilike.${pattern},codigo_barras.ilike.${pattern}`,
    )
    .order("nombre")
    .limit(200);

  if (error) {
    return { ok: false, error: error.message };
  }

  const productoRows = (rows ?? []) as ProductoTablaRow[];
  const stockPorId = await cargarStockPorProducto(productoRows.map((r) => r.id));

  return {
    ok: true,
    productos: productoRows.map((row) =>
      mapProductoTablaRow(row, stockPorId.get(row.id) ?? 0),
    ),
  };
}

async function listarProductosDesdeRpc(
  parametro: string,
): Promise<
  { ok: true; productos: ProductoListaRpc[] } | { ok: false; error: string }
> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc(
    "retorna_lista_productos_segun_parametros",
    { p_parametro: parametro },
  );

  if (error) {
    return { ok: false, error: error.message };
  }

  return enriquecerProductosLista((data ?? []) as ProductoListaRpc[]);
}

/** El SP aún no devuelve codigo_producto; lo completamos desde la tabla productos. */
async function enriquecerProductosLista(
  productos: ProductoListaRpc[],
): Promise<{ ok: true; productos: ProductoListaRpc[] } | { ok: false; error: string }> {
  const ids = productos.map((p) => p.id);
  if (!ids.length) {
    return { ok: true, productos: [] };
  }

  const { data, error } = await createAdminClient()
    .from("productos")
    .select(
      "id, codigo_producto, codigo_barras, precio_lista1, precio_lista2, precio_lista3",
    )
    .in("id", ids);

  if (error) {
    return { ok: false, error: error.message };
  }

  const porId = new Map((data ?? []).map((row) => [row.id, row as ProductoTablaRow]));

  return {
    ok: true,
    productos: productos.map((p) => {
      const row = porId.get(p.id);
      if (!row) return p;

      return {
        ...p,
        codigo_producto: p.codigo_producto ?? row.codigo_producto,
        codigo_barras: p.codigo_barras ?? row.codigo_barras,
        precio_lista1: p.precio_lista1 ?? row.precio_lista1 ?? p.precio,
        precio_lista2: p.precio_lista2 ?? row.precio_lista2 ?? 0,
        precio_lista3: p.precio_lista3 ?? row.precio_lista3 ?? 0,
      };
    }),
  };
}

export async function buscarProductosOrdenAction(
  parametro: string,
): Promise<
  | { ok: true; productos: ProductoListaRpc[] }
  | { ok: false; error: string }
> {
  const p = parametro.trim();

  if (!p) {
    return { ok: false, error: "Ingresa un nombre o código de producto para buscar." };
  }

  if (p.length < 2) {
    return {
      ok: false,
      error: "El parámetro de búsqueda debe tener al menos 2 caracteres.",
    };
  }

  return buscarProductosEnTabla(p);
}

export async function listarProductosAction(
  parametro?: string,
): Promise<
  | { ok: true; productos: ProductoListaRpc[] }
  | { ok: false; error: string }
> {
  const q = parametro?.trim() ?? "";

  if (!q) {
    return listarProductosDesdeRpc("");
  }

  return buscarProductosEnTabla(q);
}

export async function obtenerProductoParaEditarAction(
  id: string,
): Promise<
  | { ok: true; producto: ActualizarProductoRpcInput & { stock_disponible?: number } }
  | { ok: false; error: string }
> {
  const productoId = id?.trim();
  if (!productoId || !isUuid(productoId)) {
    return { ok: false, error: "ID de producto inválido." };
  }

  const admin = createAdminClient();
  const { data, error } = await admin
    .from("productos")
    .select(
      "id, nombre, codigo_producto, codigo_barras, precio_lista1, precio_lista2, precio_lista3",
    )
    .eq("id", productoId)
    .single();

  if (error || !data) {
    return { ok: false, error: "Producto no encontrado." };
  }

  const { data: inventario } = await admin
    .from("inventario_almacen")
    .select("stock_disponible")
    .eq("producto_id", productoId)
    .maybeSingle();

  return {
    ok: true,
    producto: {
      id: data.id,
      codigo_producto: data.codigo_producto ?? "",
      nombre: data.nombre,
      codigo_barras: data.codigo_barras ?? "",
      precio_lista1: data.precio_lista1 ?? 0,
      precio_lista2: data.precio_lista2 ?? 0,
      precio_lista3: data.precio_lista3 ?? 0,
      stock_disponible: inventario?.stock_disponible,
    },
  };
}

function validateActualizarProductoInput(
  input: ActualizarProductoRpcInput,
): string | null {
  if (!input.id?.trim()) {
    return "ID de producto requerido.";
  }
  if (!isUuid(input.id)) {
    return "ID de producto inválido.";
  }
  if (!input.nombre?.trim()) {
    return "El nombre del producto es requerido.";
  }
  if (!input.codigo_producto?.trim()) {
    return "El código de producto es requerido.";
  }

  for (const [label, value] of [
    ["precio lista 1", input.precio_lista1],
    ["precio lista 2", input.precio_lista2],
    ["precio lista 3", input.precio_lista3],
  ] as const) {
    if (!Number.isFinite(value) || value < 0) {
      return `El ${label} no puede ser negativo.`;
    }
  }

  return null;
}

export async function actualizarProductoAction(
  input: ActualizarProductoRpcInput,
): Promise<{ ok: true } | { ok: false; error: string }> {
  const validationError = validateActualizarProductoInput(input);
  if (validationError) {
    return { ok: false, error: validationError };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc(
    "actualizar_registro_productos_segun_id",
    {
      p_id: input.id.trim(),
      p_codigo_producto: input.codigo_producto.trim(),
      p_nombre: input.nombre.trim(),
      p_codigo_barras: input.codigo_barras.trim(),
      p_precio_lista1: input.precio_lista1,
      p_precio_lista2: input.precio_lista2,
      p_precio_lista3: input.precio_lista3,
    },
  );

  if (error) {
    return { ok: false, error: error.message };
  }

  if (!data) {
    return { ok: false, error: "No se encontró un producto con ese ID." };
  }

  revalidatePath("/productos");
  revalidatePath(`/productos/${input.id.trim()}`);
  return { ok: true };
}
