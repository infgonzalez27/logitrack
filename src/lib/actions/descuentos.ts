"use server";

import { revalidatePath } from "next/cache";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { joinOne } from "@/lib/supabase/join";
import type { DescuentoClienteProducto } from "@/types/database";

export interface DescuentoConProducto extends DescuentoClienteProducto {
  producto_nombre: string;
  producto_codigo: string;
  precio_lista1: number;
}

export interface ClienteConDescuentosResumen {
  cliente_id: string;
  razon_social: string;
  rif_nit: string | null;
  total_productos: number;
  productos_activos: number;
  productos_inactivos: number;
}

async function requireGerente(): Promise<
  { ok: true } | { ok: false; error: string }
> {
  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);
  if (rol !== "gerente") {
    return {
      ok: false,
      error: "Solo el rol gerente puede gestionar el módulo de descuentos.",
    };
  }
  return { ok: true };
}

function mapDescuentosConProducto(data: any[]): DescuentoConProducto[] {
  return data.map((item) => ({
    id: item.id,
    cliente_id: item.cliente_id,
    producto_id: item.producto_id,
    porcentaje_descuento: Number(item.porcentaje_descuento || 0),
    precio_pactado_usd:
      item.precio_pactado_usd !== null ? Number(item.precio_pactado_usd) : null,
    activo: Boolean(item.activo),
    created_at: item.created_at,
    updated_at: item.updated_at,
    producto_nombre: item.productos?.nombre || "Producto desconocido",
    producto_codigo:
      item.productos?.codigo_producto || item.productos?.id || "",
    precio_lista1: Number(item.productos?.precio_lista1 || 0),
  }));
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

  return { ok: true, descuentos: mapDescuentosConProducto(data ?? []) };
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
  revalidatePath("/clientes/descuentos");
  revalidatePath(`/clientes/descuentos/${input.cliente_id}`);
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
  revalidatePath("/clientes/descuentos");
  if (clienteId) {
    revalidatePath(`/clientes/descuentos/${clienteId}`);
  }
  revalidatePath("/ordenes/nuevo");
  return { ok: true };
}

export async function obtenerClientesConDescuentosAction(): Promise<
  | {
      ok: true;
      clientes: ClienteConDescuentosResumen[];
      hayAlgunDescuentoActivo: boolean;
    }
  | { ok: false; error: string }
> {
  const auth = await requireGerente();
  if (!auth.ok) return auth;

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("descuentos_cliente_producto")
    .select("id, cliente_id, activo, clientes(id, razon_social, rif_nit)");

  if (error) {
    return { ok: false, error: error.message };
  }

  const map = new Map<string, ClienteConDescuentosResumen>();
  let hayAlgunDescuentoActivo = false;

  for (const row of data ?? []) {
    const activo = Boolean(row.activo);
    if (activo) hayAlgunDescuentoActivo = true;

    const cli = joinOne(row.clientes);
    const existing = map.get(row.cliente_id);
    if (existing) {
      existing.total_productos += 1;
      if (activo) existing.productos_activos += 1;
      else existing.productos_inactivos += 1;
    } else {
      map.set(row.cliente_id, {
        cliente_id: row.cliente_id,
        razon_social: cli?.razon_social ?? "Cliente desconocido",
        rif_nit: cli?.rif_nit ?? null,
        total_productos: 1,
        productos_activos: activo ? 1 : 0,
        productos_inactivos: activo ? 0 : 1,
      });
    }
  }

  const clientes = Array.from(map.values()).sort((a, b) =>
    a.razon_social.localeCompare(b.razon_social, "es")
  );

  return { ok: true, clientes, hayAlgunDescuentoActivo };
}

export async function toggleTodosDescuentosAction(
  activar: boolean
): Promise<{ ok: true } | { ok: false; error: string }> {
  const auth = await requireGerente();
  if (!auth.ok) return auth;

  const admin = await createAdminClient();
  const { error } = await admin
    .from("descuentos_cliente_producto")
    .update({
      activo: activar,
      updated_at: new Date().toISOString(),
    })
    .neq("activo", activar);

  if (error) {
    return { ok: false, error: error.message };
  }

  revalidatePath("/clientes");
  revalidatePath("/clientes/descuentos");
  revalidatePath("/ordenes/nuevo");
  return { ok: true };
}

export async function obtenerTodosDescuentosClienteAction(
  clienteId: string
): Promise<
  | { ok: true; descuentos: DescuentoConProducto[] }
  | { ok: false; error: string }
> {
  const auth = await requireGerente();
  if (!auth.ok) return auth;

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
    .order("created_at", { ascending: false });

  if (error) {
    return { ok: false, error: error.message };
  }

  return { ok: true, descuentos: mapDescuentosConProducto(data ?? []) };
}

export async function actualizarPorcentajeDescuentoAction(input: {
  id: string;
  cliente_id: string;
  porcentaje_descuento: number;
}): Promise<{ ok: true } | { ok: false; error: string }> {
  const auth = await requireGerente();
  if (!auth.ok) return auth;

  if (!input.id || !input.cliente_id) {
    return { ok: false, error: "Identificador de descuento inválido." };
  }
  if (
    Number.isNaN(input.porcentaje_descuento) ||
    input.porcentaje_descuento < 0 ||
    input.porcentaje_descuento > 100
  ) {
    return { ok: false, error: "El porcentaje debe estar entre 0% y 100%." };
  }

  const admin = await createAdminClient();
  const { error } = await admin
    .from("descuentos_cliente_producto")
    .update({
      porcentaje_descuento: input.porcentaje_descuento,
      updated_at: new Date().toISOString(),
    })
    .eq("id", input.id)
    .eq("cliente_id", input.cliente_id);

  if (error) {
    return { ok: false, error: error.message };
  }

  revalidatePath("/clientes");
  revalidatePath("/clientes/descuentos");
  revalidatePath(`/clientes/descuentos/${input.cliente_id}`);
  revalidatePath("/ordenes/nuevo");
  return { ok: true };
}

export async function toggleDescuentoProductoAction(input: {
  id: string;
  cliente_id: string;
  activo: boolean;
}): Promise<{ ok: true } | { ok: false; error: string }> {
  const auth = await requireGerente();
  if (!auth.ok) return auth;

  if (!input.id || !input.cliente_id) {
    return { ok: false, error: "Identificador de descuento inválido." };
  }

  const admin = await createAdminClient();
  const { error } = await admin
    .from("descuentos_cliente_producto")
    .update({
      activo: input.activo,
      updated_at: new Date().toISOString(),
    })
    .eq("id", input.id)
    .eq("cliente_id", input.cliente_id);

  if (error) {
    return { ok: false, error: error.message };
  }

  revalidatePath("/clientes");
  revalidatePath("/clientes/descuentos");
  revalidatePath(`/clientes/descuentos/${input.cliente_id}`);
  revalidatePath("/ordenes/nuevo");
  return { ok: true };
}
