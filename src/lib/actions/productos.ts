"use server";

import { revalidatePath } from "next/cache";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import type {
  ActualizarProductoRpcInput,
  ProductoListaRpc,
  RegistrarProductoRpcInput,
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
  contenedor_id?: string | null;
  unidades_por_contenedor?: number | null;
  imagen_path?: string | null;
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
    contenedor_id: row.contenedor_id ?? null,
    unidades_por_contenedor: row.unidades_por_contenedor ?? null,
    imagen_path: row.imagen_path ?? null,
  };
}

async function cargarStockPorProducto(
  ids: string[],
): Promise<Map<string, number>> {
  if (!ids.length) return new Map();

  const supabase = await createClient();
  const { data } = await supabase
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
  const supabase = await createClient();
  const { data: rows, error } = await supabase
    .from("productos")
    .select(
      "id, nombre, codigo_producto, codigo_barras, precio_lista1, precio_lista2, precio_lista3, contenedor_id, unidades_por_contenedor, imagen_path",
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
  clienteId?: string,
): Promise<
  { ok: true; productos: ProductoListaRpc[] } | { ok: false; error: string }
> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc(
    "retorna_lista_productos_segun_parametros",
    {
      p_parametro: parametro,
      p_cliente_id: clienteId || null,
    },
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

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("productos")
    .select(
      "id, codigo_producto, codigo_barras, precio_lista1, precio_lista2, precio_lista3, contenedor_id, unidades_por_contenedor, imagen_path",
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
        // No pisar `precio` (puede venir con descuento del RPC).
        precio_lista1:
          p.precio_lista ?? p.precio_lista1 ?? row.precio_lista1 ?? p.precio,
        precio_lista2: p.precio_lista2 ?? row.precio_lista2 ?? 0,
        precio_lista3: p.precio_lista3 ?? row.precio_lista3 ?? 0,
        precio_lista:
          p.precio_lista ?? p.precio_lista1 ?? row.precio_lista1 ?? p.precio,
        porcentaje_descuento: p.porcentaje_descuento ?? 0,
        precio_final_usd: p.precio_final_usd ?? p.precio,
        contenedor_id: p.contenedor_id ?? row.contenedor_id ?? null,
        unidades_por_contenedor:
          p.unidades_por_contenedor ?? row.unidades_por_contenedor ?? null,
        imagen_path: p.imagen_path ?? row.imagen_path ?? null,
      };
    }),
  };
}

export async function buscarProductosOrdenAction(
  parametro: string,
  clienteId?: string,
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

  if (clienteId) {
    return listarProductosDesdeRpc(p, clienteId);
  }

  return buscarProductosEnTabla(p);
}

export async function listarProductosAction(
  parametro?: string,
  clienteId?: string,
): Promise<
  | { ok: true; productos: ProductoListaRpc[] }
  | { ok: false; error: string }
> {
  const q = parametro?.trim() ?? "";

  if (clienteId) {
    return listarProductosDesdeRpc(q || ".F.", clienteId);
  }

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

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("productos")
    .select(
      "id, nombre, codigo_producto, codigo_barras, precio_lista1, precio_lista2, precio_lista3, contenedor_id, unidades_por_contenedor, imagen_path",
    )
    .eq("id", productoId)
    .single();

  if (error || !data) {
    return { ok: false, error: "Producto no encontrado." };
  }

  const { data: inventario } = await supabase
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
      contenedor_id: data.contenedor_id ?? null,
      unidades_por_contenedor: data.unidades_por_contenedor ?? 1,
      imagen_path: data.imagen_path ?? null,
      stock_disponible: inventario?.stock_disponible,
    },
  };
}

export async function registrarProductoAction(
  input: RegistrarProductoRpcInput,
): Promise<{ ok: true; id: string } | { ok: false; error: string }> {
  if (!input.nombre?.trim()) {
    return { ok: false, error: "El nombre del producto es requerido." };
  }
  if (!input.codigo_producto?.trim()) {
    return { ok: false, error: "El código de producto es requerido." };
  }

  const contenedorId = input.contenedor_id?.trim() || null;
  const supabase = await createClient();
  const { data, error } = await supabase.rpc(
    "registra_nuevo_producto_retorna_id",
    {
      p_codigo_producto: input.codigo_producto.trim(),
      p_nombre: input.nombre.trim(),
      p_codigo_barras: input.codigo_barras?.trim() || null,
      p_descripcion: input.descripcion?.trim() || null,
      p_cant_unidad_medida: input.cant_unidad_medida ?? null,
      p_precio_lista1: input.precio_lista1 ?? 0,
      p_precio_lista2: input.precio_lista2 ?? 0,
      p_precio_lista3: input.precio_lista3 ?? 0,
      p_contenedor_id: contenedorId,
      p_unidades_por_contenedor: contenedorId
        ? Math.max(1, Number(input.unidades_por_contenedor) || 1)
        : 1,
      p_imagen_path: input.imagen_path?.trim() || null,
    },
  );

  if (error) {
    return { ok: false, error: error.message };
  }

  if (!data) {
    return { ok: false, error: "No se pudo registrar el producto." };
  }

  revalidatePath("/productos");
  return { ok: true, id: String(data) };
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
    ["precio lista 1", input.precio_lista1 ?? 0],
    ["precio lista 2", input.precio_lista2 ?? 0],
    ["precio lista 3", input.precio_lista3 ?? 0],
  ] as const) {
    if (!Number.isFinite(value) || value < 0) {
      return `El ${label} no puede ser negativo.`;
    }
  }

  if (input.contenedor_id?.trim() && !isUuid(input.contenedor_id)) {
    return "Contenedor / empaque inválido.";
  }

  if (
    input.unidades_por_contenedor != null &&
    (!Number.isFinite(input.unidades_por_contenedor) ||
      input.unidades_por_contenedor < 1)
  ) {
    return "Unidades por contenedor debe ser al menos 1.";
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

  const contenedorId = input.contenedor_id?.trim() || null;
  const supabase = await createClient();
  const { data, error } = await supabase.rpc(
    "actualizar_registro_productos_segun_id",
    {
      p_id: input.id.trim(),
      p_codigo_producto: input.codigo_producto.trim(),
      p_nombre: input.nombre.trim(),
      p_codigo_barras: input.codigo_barras?.trim() || null,
      p_precio_lista1: input.precio_lista1 ?? 0,
      p_precio_lista2: input.precio_lista2 ?? 0,
      p_precio_lista3: input.precio_lista3 ?? 0,
      p_descripcion: input.descripcion?.trim() || null,
      p_cant_unidad_medida: input.cant_unidad_medida ?? null,
      p_contenedor_id: contenedorId,
      p_unidades_por_contenedor: contenedorId
        ? Math.max(1, Number(input.unidades_por_contenedor) || 1)
        : 1,
      p_imagen_path: input.imagen_path?.trim() || null,
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

/**
 * Sube una imagen de producto al bucket "productos" y actualiza la columna imagen_path en la tabla productos.
 * Soporta archivos WebP, JPG y PNG de hasta 5 MB.
 */
export async function subirImagenProductoAction(
  productId: string,
  formData: FormData,
): Promise<{ ok: true; imagen_path: string } | { ok: false; error: string }> {
  if (!productId || !isUuid(productId)) {
    return { ok: false, error: "ID de producto inválido." };
  }

  const file = formData.get("file");
  if (!file || !(file instanceof File)) {
    return { ok: false, error: "Debes seleccionar un archivo de imagen." };
  }

  const MAX_FILE_SIZE_BYTES = 5 * 1024 * 1024; // 5 MB
  if (file.size > MAX_FILE_SIZE_BYTES) {
    return {
      ok: false,
      error: "El archivo supera el tamaño máximo permitido de 5 MB.",
    };
  }

  const mime = file.type || "application/octet-stream";
  const allowedMimes = new Set([
    "image/webp",
    "image/jpeg",
    "image/jpg",
    "image/png",
  ]);
  if (!allowedMimes.has(mime)) {
    return {
      ok: false,
      error: "Tipo de archivo no permitido. Solo se aceptan WebP, JPG y PNG.",
    };
  }

  let ext = "webp";
  if (mime === "image/jpeg" || mime === "image/jpg") ext = "jpg";
  else if (mime === "image/png") ext = "png";
  else if (file.name.includes(".")) {
    ext = file.name.split(".").pop()?.toLowerCase() || "webp";
  }

  const fileName = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}.${ext}`;
  const relativeImagePath = `/productos/${fileName}`;

  try {
    const admin = await createAdminClient();
    const arrayBuffer = await file.arrayBuffer();
    const buffer = Buffer.from(arrayBuffer);

    // 1. Subir al bucket 'productos'
    const { error: uploadError } = await admin.storage
      .from("productos")
      .upload(fileName, buffer, {
        contentType: mime,
        upsert: true,
      });

    if (uploadError) {
      return {
        ok: false,
        error: `Error al subir al bucket 'productos': ${uploadError.message}`,
      };
    }

    // 2. Actualizar campo imagen_path en la tabla productos
    const { error: updateError } = await admin
      .from("productos")
      .update({ imagen_path: relativeImagePath })
      .eq("id", productId);

    if (updateError) {
      return {
        ok: false,
        error: `Imagen subida pero falló la actualización del producto: ${updateError.message}`,
      };
    }

    revalidatePath("/productos");
    revalidatePath(`/productos/${productId}`);

    return { ok: true, imagen_path: relativeImagePath };
  } catch (err) {
    const message =
      err instanceof Error ? err.message : "Error inesperado al subir imagen.";
    return { ok: false, error: message };
  }
}

