"use server";

import { revalidatePath } from "next/cache";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import type { DescuentoClienteProducto } from "@/types/database";

export interface DescuentoConProducto extends DescuentoClienteProducto {
  producto_nombre: string;
  producto_codigo: string;
  precio_lista1: number;
}

export async function obtenerDescuentosClienteAction(
  clienteId: string
): Promise<
  | { ok: true; descuentos: DescuentoConProducto[] }
  | { ok: false; error: string }
> {
  if (!clienteId) {
    return { ok: false, error: "ID de cliente no proporcionado." };
  }

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("descuentos_cliente_producto")
    .select(`
      id,
      cliente_id,
      producto_id,
      porcentaje_descuento,
      precio_pactado_usd,
      activo,
      created_at,
      updated_at,
      productos (
        id,
        nombre,
        codigo_producto,
        precio_lista1
      )
    `)
    .eq("cliente_id", clienteId)
    .eq("activo", true)
    .order("created_at", { ascending: false });

  if (error) {
    return { ok: false, error: error.message };
  }

  const descuentos: DescuentoConProducto[] = (data ?? []).map((item: any) => ({
    id: item.id,
    cliente_id: item.cliente_id,
    producto_id: item.producto_id,
    porcentaje_descuento: Number(item.porcentaje_descuento || 0),
    precio_pactado_usd: item.precio_pactado_usd !== null ? Number(item.precio_pactado_usd) : null,
    activo: item.activo,
    created_at: item.created_at,
    updated_at: item.updated_at,
    producto_nombre: item.productos?.nombre || "Producto desconocido",
    producto_codigo: item.productos?.codigo_producto || item.productos?.id || "",
    precio_lista1: Number(item.productos?.precio_lista1 || 0),
  }));

  return { ok: true, descuentos };
}

export async function guardarDescuentoClienteAction(input: {
  cliente_id: string;
  producto_id: string;
  porcentaje_descuento: number;
  precio_pactado_usd?: number | null;
}): Promise<{ ok: true; id: string } | { ok: false; error: string }> {
  if (!input.cliente_id) {
    return { ok: false, error: "Selecciona un cliente válido." };
  }
  if (!input.producto_id) {
    return { ok: false, error: "Selecciona un producto válido." };
  }
  if (
    input.porcentaje_descuento < 0 ||
    input.porcentaje_descuento > 100
  ) {
    return { ok: false, error: "El porcentaje debe estar entre 0% y 100%." };
  }

  const admin = await createAdminClient();
  const { data, error } = await admin
    .from("descuentos_cliente_producto")
    .upsert(
      {
        cliente_id: input.cliente_id,
        producto_id: input.producto_id,
        porcentaje_descuento: input.porcentaje_descuento,
        precio_pactado_usd: input.precio_pactado_usd || null,
        activo: true,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "cliente_id,producto_id" }
    )
    .select("id")
    .single();

  if (error) {
    return { ok: false, error: error.message };
  }

  revalidatePath("/clientes");
  revalidatePath("/ordenes/nuevo");
  return { ok: true, id: data.id };
}

export async function eliminarDescuentoClienteAction(
  id: string,
  clienteId: string
): Promise<{ ok: true } | { ok: false; error: string }> {
  if (!id) {
    return { ok: false, error: "ID de descuento no proporcionado." };
  }

  const admin = await createAdminClient();
  const { error } = await admin
    .from("descuentos_cliente_producto")
    .delete()
    .eq("id", id);

  if (error) {
    return { ok: false, error: error.message };
  }

  revalidatePath("/clientes");
  revalidatePath("/ordenes/nuevo");
  return { ok: true };
}
