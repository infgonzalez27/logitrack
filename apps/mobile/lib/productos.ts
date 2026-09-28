import { supabase } from "./supabase";

export type ProductoLista = {
  id: string;
  nombre: string;
  codigo_producto: string | null;
  codigo_barras: string | null;
  precio: number;
  precio_lista1?: number;
  precio_lista?: number;
  porcentaje_descuento?: number;
  precio_final_usd?: number;
  stock_disponible: number;
  imagen_path?: string | null;
};

export type ProductoMaestro = {
  id: string;
  codigo_producto: string | null;
  codigo_barras: string | null;
  nombre: string;
  descripcion: string | null;
  precio_lista1: number;
  precio_lista2: number;
  precio_lista3: number;
  contenedor_id: string | null;
  unidades_por_contenedor: number | null;
  imagen_path: string | null;
};

export function precioNeto(p: ProductoLista): number {
  return Number(p.precio_final_usd ?? p.precio ?? p.precio_lista1 ?? 0);
}

export async function listarProductos(
  parametro: string,
  clienteId?: string,
): Promise<{ ok: true; productos: ProductoLista[] } | { ok: false; error: string }> {
  const { data, error } = await supabase.rpc(
    "retorna_lista_productos_segun_parametros",
    {
      p_parametro: parametro || ".F.",
      p_cliente_id: clienteId || null,
    },
  );

  if (error) return { ok: false, error: error.message };

  const rows = (Array.isArray(data) ? data : []) as ProductoLista[];
  const ids = rows.map((r) => r.id).filter(Boolean);
  if (!ids.length) return { ok: true, productos: [] };

  const { data: extra } = await supabase
    .from("productos")
    .select("id, codigo_producto, codigo_barras, precio_lista1, imagen_path")
    .in("id", ids);

  const byId = new Map((extra ?? []).map((r) => [r.id, r]));

  return {
    ok: true,
    productos: rows.map((p) => {
      const row = byId.get(p.id);
      return {
        ...p,
        codigo_producto: p.codigo_producto ?? row?.codigo_producto ?? null,
        codigo_barras: p.codigo_barras ?? row?.codigo_barras ?? null,
        precio_lista1: p.precio_lista ?? p.precio_lista1 ?? row?.precio_lista1 ?? p.precio,
        precio_lista: p.precio_lista ?? p.precio_lista1 ?? row?.precio_lista1 ?? p.precio,
        porcentaje_descuento: Number(p.porcentaje_descuento ?? 0),
        precio_final_usd: p.precio_final_usd ?? p.precio,
        imagen_path: p.imagen_path ?? row?.imagen_path ?? null,
        stock_disponible: Number(p.stock_disponible ?? 0),
        precio: Number(p.precio ?? 0),
      };
    }),
  };
}

/** Catálogo maestros: listado con búsqueda (RPC + enriquecimiento). */
export async function listProductosMaestros(
  parametro = "",
): Promise<
  { ok: true; productos: ProductoMaestro[] } | { ok: false; error: string }
> {
  const res = await listarProductos(parametro || ".F.");
  if (!res.ok) return res;

  return {
    ok: true,
    productos: res.productos.map((p) => ({
      id: p.id,
      codigo_producto: p.codigo_producto,
      codigo_barras: p.codigo_barras,
      nombre: p.nombre,
      descripcion: null,
      precio_lista1: Number(p.precio_lista1 ?? p.precio ?? 0),
      precio_lista2: 0,
      precio_lista3: 0,
      contenedor_id: null,
      unidades_por_contenedor: null,
      imagen_path: p.imagen_path ?? null,
    })),
  };
}

export async function getProducto(
  id: string,
): Promise<{ ok: true; producto: ProductoMaestro } | { ok: false; error: string }> {
  const { data, error } = await supabase
    .from("productos")
    .select(
      "id, codigo_producto, codigo_barras, nombre, descripcion, precio_lista1, precio_lista2, precio_lista3, contenedor_id, unidades_por_contenedor, imagen_path",
    )
    .eq("id", id)
    .maybeSingle();

  if (error) return { ok: false, error: error.message };
  if (!data) return { ok: false, error: "Producto no encontrado." };

  return {
    ok: true,
    producto: {
      id: data.id,
      codigo_producto: data.codigo_producto ?? null,
      codigo_barras: data.codigo_barras ?? null,
      nombre: data.nombre,
      descripcion: data.descripcion ?? null,
      precio_lista1: Number(data.precio_lista1 ?? 0),
      precio_lista2: Number(data.precio_lista2 ?? 0),
      precio_lista3: Number(data.precio_lista3 ?? 0),
      contenedor_id: data.contenedor_id ?? null,
      unidades_por_contenedor:
        data.unidades_por_contenedor != null
          ? Number(data.unidades_por_contenedor)
          : null,
      imagen_path: data.imagen_path ?? null,
    },
  };
}

export async function createProducto(input: {
  codigo_producto?: string;
  nombre: string;
  codigo_barras?: string | null;
  descripcion?: string | null;
  precio_lista1?: number;
}): Promise<{ ok: true; id: string } | { ok: false; error: string }> {
  const nombre = input.nombre.trim();
  if (!nombre) return { ok: false, error: "El nombre del producto es requerido." };

  const codigoProducto =
    input.codigo_producto?.trim() || `PROD-${Date.now()}`;

  const { data, error } = await supabase.rpc(
    "registra_nuevo_producto_retorna_id",
    {
      p_codigo_producto: codigoProducto,
      p_nombre: nombre,
      p_codigo_barras: input.codigo_barras?.trim() || null,
      p_descripcion: input.descripcion?.trim() || null,
      p_cant_unidad_medida: null,
      p_precio_lista1: input.precio_lista1 ?? 0,
      p_precio_lista2: 0,
      p_precio_lista3: 0,
      p_contenedor_id: null,
      p_unidades_por_contenedor: 1,
      p_imagen_path: null,
    },
  );

  if (error) return { ok: false, error: error.message };
  if (!data) return { ok: false, error: "No se pudo registrar el producto." };
  return { ok: true, id: String(data) };
}

export async function updateProducto(input: {
  id: string;
  codigo_producto: string;
  nombre: string;
  codigo_barras?: string | null;
  precio_lista1: number;
  precio_lista2?: number;
  precio_lista3?: number;
  descripcion?: string | null;
}): Promise<{ ok: true } | { ok: false; error: string }> {
  const nombre = input.nombre.trim();
  const codigo = input.codigo_producto.trim();
  if (!nombre) return { ok: false, error: "El nombre del producto es requerido." };
  if (!codigo) return { ok: false, error: "El código de producto es requerido." };

  const { data, error } = await supabase.rpc(
    "actualizar_registro_productos_segun_id",
    {
      p_id: input.id,
      p_codigo_producto: codigo,
      p_nombre: nombre,
      p_codigo_barras: input.codigo_barras?.trim() || null,
      p_precio_lista1: input.precio_lista1 ?? 0,
      p_precio_lista2: input.precio_lista2 ?? 0,
      p_precio_lista3: input.precio_lista3 ?? 0,
      p_descripcion: input.descripcion?.trim() || null,
      p_cant_unidad_medida: null,
      p_contenedor_id: null,
      p_unidades_por_contenedor: 1,
      p_imagen_path: null,
    },
  );

  if (error) return { ok: false, error: error.message };
  if (!data) return { ok: false, error: "No se encontró un producto con ese ID." };
  return { ok: true };
}
