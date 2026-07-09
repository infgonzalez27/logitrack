"use server";

import { revalidatePath } from "next/cache";
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

export async function buscarProductosOrdenAction(
  parametro: string,
): Promise<
  | { ok: true; productos: ProductoListaRpc[] }
  | { ok: false; error: string }
> {
  const p = parametro.trim();

  if (!p) {
    return { ok: false, error: "Ingresa un nombre o código de barras para buscar." };
  }

  if (p.length < 2) {
    return {
      ok: false,
      error: "El parámetro de búsqueda debe tener al menos 2 caracteres.",
    };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc(
    "retorna_lista_productos_segun_parametros",
    { p_parametro: p },
  );

  if (error) {
    return { ok: false, error: error.message };
  }

  return { ok: true, productos: (data ?? []) as ProductoListaRpc[] };
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
  return { ok: true };
}
