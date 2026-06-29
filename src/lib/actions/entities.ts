"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

type ActionResult = { error?: string; success?: boolean };

async function getUserId() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  return { supabase, userId: user?.id ?? null };
}

export async function createClienteAction(
  _prev: ActionResult | null,
  formData: FormData,
): Promise<ActionResult> {
  const { supabase } = await getUserId();
  const { error } = await supabase.from("clientes").insert({
    rif_nit: String(formData.get("rif_nit")).trim(),
    razon_social: String(formData.get("razon_social")).trim(),
    direccion_fiscal: String(formData.get("direccion_fiscal")).trim(),
    telefono: String(formData.get("telefono") || "") || null,
    movil1: String(formData.get("movil1") || "") || null,
    correo_e: String(formData.get("correo_e") || "") || null,
    activo: true,
  });

  if (error) return { error: error.message };
  revalidatePath("/clientes");
  return { success: true };
}

export async function createProveedorAction(
  _prev: ActionResult | null,
  formData: FormData,
): Promise<ActionResult> {
  const { supabase } = await getUserId();
  const { error } = await supabase.from("proveedores").insert({
    rif_nit: String(formData.get("rif_nit")).trim(),
    razon_social: String(formData.get("razon_social")).trim(),
    direccion_fiscal: String(formData.get("direccion_fiscal") || "") || null,
    telefono: String(formData.get("telefono") || "") || null,
    correo_e: String(formData.get("correo_e") || "") || null,
    activo: true,
  });

  if (error) return { error: error.message };
  revalidatePath("/proveedores");
  return { success: true };
}

export async function createCamionAction(
  _prev: ActionResult | null,
  formData: FormData,
): Promise<ActionResult> {
  const { supabase } = await getUserId();
  const { error } = await supabase.from("camiones").insert({
    placa: String(formData.get("placa")).trim(),
    modelo: String(formData.get("modelo")).trim(),
    capacidad_kg: Number(formData.get("capacidad_kg")),
    volumen_m3: formData.get("volumen_m3")
      ? Number(formData.get("volumen_m3"))
      : null,
    estado: "disponible",
  });

  if (error) return { error: error.message };
  revalidatePath("/camiones");
  return { success: true };
}

export async function createProductoAction(
  _prev: ActionResult | null,
  formData: FormData,
): Promise<ActionResult> {
  const { supabase } = await getUserId();
  const { error } = await supabase.from("productos").insert({
    codigo_barras: String(formData.get("codigo_barras") || "") || null,
    nombre: String(formData.get("nombre")).trim(),
    descripcion: String(formData.get("descripcion") || "") || null,
    unidad_medida: String(formData.get("unidad_medida") || "unidades"),
    peso_unitario_kg: Number(formData.get("peso_unitario_kg") || 0),
    cant_unidad_medida: Number(formData.get("cant_unidad_medida") || 0),
  });

  if (error) return { error: error.message };
  revalidatePath("/productos");
  return { success: true };
}

export async function createInventarioAlmacenAction(
  _prev: ActionResult | null,
  formData: FormData,
): Promise<ActionResult> {
  const { supabase } = await getUserId();
  const { error } = await supabase.from("inventario_almacen").insert({
    producto_id: String(formData.get("producto_id")),
    stock_disponible: Number(formData.get("stock_disponible") || 0),
    stock_comprometido: 0,
    ubicacion_pasillo: String(formData.get("ubicacion_pasillo") || "") || null,
  });

  if (error) return { error: error.message };
  revalidatePath("/inventario-almacen");
  return { success: true };
}

export async function createInventarioMovilAction(
  _prev: ActionResult | null,
  formData: FormData,
): Promise<ActionResult> {
  const { supabase } = await getUserId();
  const { error } = await supabase.from("inventario_movil").insert({
    camion_id: String(formData.get("camion_id")),
    producto_id: String(formData.get("producto_id")),
    cantidad_cargada: Number(formData.get("cantidad_cargada") || 0),
    cantidad_entregada: 0,
    cantidad_devolucion: 0,
  });

  if (error) return { error: error.message };
  revalidatePath("/inventario-movil");
  return { success: true };
}

export async function createRendicionAction(
  _prev: ActionResult | null,
  formData: FormData,
): Promise<ActionResult> {
  const { supabase } = await getUserId();
  const { error } = await supabase.from("rendiciones_cuentas").insert({
    cliente_id: String(formData.get("cliente_id")),
    observaciones: String(formData.get("observaciones") || "") || null,
    estado: "revision",
  });

  if (error) return { error: error.message };
  revalidatePath("/rendiciones");
  return { success: true };
}

export async function createFacturaCompraAction(
  _prev: ActionResult | null,
  formData: FormData,
): Promise<ActionResult> {
  const { supabase } = await getUserId();
  const subtotal = Number(formData.get("monto_subtotal"));
  const impuesto = Number(formData.get("monto_impuesto") || 0);
  const { error } = await supabase.from("facturas_compras").insert({
    proveedor_id: String(formData.get("proveedor_id")),
    numero_factura: String(formData.get("numero_factura")).trim(),
    fecha_emision: String(formData.get("fecha_emision")),
    fecha_vencimiento: String(formData.get("fecha_vencimiento") || "") || null,
    monto_subtotal: subtotal,
    monto_impuesto: impuesto,
    monto_total: subtotal + impuesto,
    estado_pago: "pendiente",
  });

  if (error) return { error: error.message };
  revalidatePath("/facturas-compras");
  return { success: true };
}

export async function createPagoProveedorAction(
  _prev: ActionResult | null,
  formData: FormData,
): Promise<ActionResult> {
  const { supabase, userId } = await getUserId();
  const { error } = await supabase.from("pagos_proveedores").insert({
    proveedor_id: String(formData.get("proveedor_id")),
    monto_total_pagado: Number(formData.get("monto_total_pagado")),
    glosa_concepto: String(formData.get("glosa_concepto") || "") || null,
    ejecutado_por: userId,
  });

  if (error) return { error: error.message };
  revalidatePath("/pagos-proveedores");
  return { success: true };
}
