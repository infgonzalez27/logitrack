"use server";

import { revalidatePath } from "next/cache";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import type { CamionListaRpc } from "@/types/database";

type ActionResult = { error?: string; success?: boolean };

export type CamionOrdenOption = {
  id: string;
  placa: string;
};

function mapCamionesParaOrden(
  rows: Array<{ id: string; placa: string; estado?: string }>,
): CamionOrdenOption[] {
  return rows
    .filter((c) => c.estado !== "inactivo")
    .map((c) => ({ id: c.id, placa: c.placa }))
    .sort((a, b) => a.placa.localeCompare(b.placa, "es"));
}

/** Camiones para emitir órdenes: RPC (evita RLS de SELECT directo en `camiones`). */
export async function listarCamionesParaOrdenAction(): Promise<
  | { ok: true; camiones: CamionOrdenOption[] }
  | { ok: false; error: string }
> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("retorna_lista_camiones");

  if (!error) {
    const camiones = mapCamionesParaOrden((data ?? []) as CamionListaRpc[]);
    if (camiones.length > 0) {
      return { ok: true, camiones };
    }
  }

  // Fallback: vendedor no tiene SELECT en `camiones`; el listado de emisión sí debe verlos.
  const { data: rows, error: adminError } = await createAdminClient()
    .from("camiones")
    .select("id, placa, estado")
    .neq("estado", "inactivo")
    .order("placa");

  if (adminError) {
    return {
      ok: false,
      error: error?.message ?? adminError.message,
    };
  }

  return { ok: true, camiones: mapCamionesParaOrden(rows ?? []) };
}

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
  const vendedorId = String(formData.get("vendedor_id") || "").trim();
  const despachadorId = String(formData.get("despachador_id") || "").trim();
  const idRuta = String(formData.get("id_ruta") || "").trim();
  const limiteRaw = Number(formData.get("limite_credito") ?? 0);
  const maxFacturasRaw = Number(formData.get("max_facturas_vencidas") ?? 0);
  const permisoRaw = String(formData.get("permiso_despacho_manual") || "false");
  const limiteCredito =
    Number.isFinite(limiteRaw) && limiteRaw >= 0 ? limiteRaw : 0;
  const maxFacturas =
    Number.isFinite(maxFacturasRaw) && maxFacturasRaw >= 0
      ? Math.floor(maxFacturasRaw)
      : 0;

  const { error } = await supabase.from("clientes").insert({
    rif_nit: String(formData.get("rif_nit")).trim(),
    razon_social: String(formData.get("razon_social")).trim(),
    direccion_fiscal: String(formData.get("direccion_fiscal")).trim(),
    telefono: String(formData.get("telefono") || "") || null,
    movil1: String(formData.get("movil1") || "") || null,
    correo_e: String(formData.get("correo_e") || "") || null,
    vendedor_id: vendedorId || null,
    despachador_id: despachadorId || null,
    id_ruta: idRuta || null,
    limite_credito: limiteCredito,
    max_facturas_vencidas: maxFacturas,
    permiso_despacho_manual: permisoRaw === "true",
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
  const codigoProducto =
    String(formData.get("codigo_producto") || "").trim() ||
    `PROD-${Date.now()}`;
  const nombre = String(formData.get("nombre") || "").trim();
  if (!nombre) return { error: "El nombre del producto es requerido." };

  const codigoBarras =
    String(formData.get("codigo_barras") || "").trim() || null;
  const descripcion =
    String(formData.get("descripcion") || "").trim() || null;
  const cantRaw = formData.get("cant_unidad_medida");
  const cantUnidadMedida =
    cantRaw != null && String(cantRaw).trim() !== ""
      ? Number(cantRaw)
      : null;
  const contenedorRaw = String(formData.get("contenedor_id") || "").trim();
  const unidadesRaw = Number(formData.get("unidades_por_contenedor") || 1);
  const unidadesPorContenedor =
    Number.isFinite(unidadesRaw) && unidadesRaw > 0 ? unidadesRaw : 1;
  const imagenPath =
    String(formData.get("imagen_path") || "").trim() || null;

  const { data, error } = await supabase.rpc(
    "registra_nuevo_producto_retorna_id",
    {
      p_codigo_producto: codigoProducto,
      p_nombre: nombre,
      p_codigo_barras: codigoBarras,
      p_descripcion: descripcion,
      p_cant_unidad_medida:
        cantUnidadMedida != null && Number.isFinite(cantUnidadMedida)
          ? cantUnidadMedida
          : null,
      p_precio_lista1: 0,
      p_precio_lista2: 0,
      p_precio_lista3: 0,
      p_contenedor_id: contenedorRaw || null,
      p_unidades_por_contenedor: contenedorRaw
        ? unidadesPorContenedor
        : 1,
      p_imagen_path: imagenPath,
    },
  );

  if (error) return { error: error.message };
  if (!data) return { error: "No se pudo registrar el producto." };

  revalidatePath("/productos");
  return { success: true };
}

export async function createInventarioAlmacenAction(
  _prev: ActionResult | null,
  formData: FormData,
): Promise<ActionResult> {
  const { supabase } = await getUserId();
  const productoId = String(formData.get("producto_id") || "").trim();
  const stockDisponible = Number(formData.get("stock_disponible") || 0);
  const ubicacionPasillo =
    String(formData.get("ubicacion_pasillo") || "").trim() || null;

  if (!productoId) {
    return { error: "Selecciona un producto." };
  }

  // `producto_id` es UNIQUE (1 fila por producto): insert o update.
  const { error } = await supabase.from("inventario_almacen").upsert(
    {
      producto_id: productoId,
      stock_disponible: stockDisponible,
      ubicacion_pasillo: ubicacionPasillo,
      updated_at: new Date().toISOString(),
    },
    { onConflict: "producto_id", defaultToNull: false },
  );

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
