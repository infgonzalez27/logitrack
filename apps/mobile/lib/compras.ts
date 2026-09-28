import { supabase } from "./supabase";
import { joinOne } from "./join";
import { getSessionUserId } from "./auth";

export type ProveedorOption = { id: string; razon_social: string };

export type FacturaCompraItem = {
  id: string;
  numero_factura: string;
  proveedor_nombre: string;
  fecha_emision: string;
  monto_total: number;
  estado_pago: string;
};

export type PagoProveedorItem = {
  id: string;
  proveedor_nombre: string;
  fecha_pago: string;
  monto_total_pagado: number;
  glosa_concepto: string | null;
};

export async function listProveedoresActivos(): Promise<
  { ok: true; proveedores: ProveedorOption[] } | { ok: false; error: string }
> {
  const { data, error } = await supabase
    .from("proveedores")
    .select("id, razon_social")
    .eq("activo", true)
    .order("razon_social");
  if (error) return { ok: false, error: error.message };
  return {
    ok: true,
    proveedores: (data ?? []).map((p) => ({
      id: p.id,
      razon_social: p.razon_social,
    })),
  };
}

export async function listFacturasCompras(): Promise<
  { ok: true; facturas: FacturaCompraItem[] } | { ok: false; error: string }
> {
  const { data, error } = await supabase
    .from("facturas_compras")
    .select("*, proveedores(razon_social)")
    .order("fecha_emision", { ascending: false });

  if (error) return { ok: false, error: error.message };

  return {
    ok: true,
    facturas: (data ?? []).map((f) => {
      const prov = joinOne(
        f.proveedores as
          | { razon_social?: string }
          | { razon_social?: string }[]
          | null,
      );
      return {
        id: f.id,
        numero_factura: f.numero_factura,
        proveedor_nombre: prov?.razon_social ?? "—",
        fecha_emision: f.fecha_emision,
        monto_total: Number(f.monto_total ?? 0),
        estado_pago: f.estado_pago ?? "pendiente",
      };
    }),
  };
}

export async function createFacturaCompra(input: {
  proveedor_id: string;
  numero_factura: string;
  fecha_emision: string;
  fecha_vencimiento?: string | null;
  monto_subtotal: number;
  monto_impuesto?: number;
}): Promise<{ ok: true } | { ok: false; error: string }> {
  const proveedorId = input.proveedor_id.trim();
  const numero = input.numero_factura.trim();
  const fecha = input.fecha_emision.trim();
  const subtotal = Number(input.monto_subtotal);
  const impuesto = Number(input.monto_impuesto ?? 0) || 0;

  if (!proveedorId) return { ok: false, error: "Selecciona un proveedor." };
  if (!numero) return { ok: false, error: "Indica el número de factura." };
  if (!fecha) return { ok: false, error: "Indica la fecha de emisión." };
  if (!Number.isFinite(subtotal) || subtotal < 0) {
    return { ok: false, error: "Subtotal inválido." };
  }

  const { error } = await supabase.from("facturas_compras").insert({
    proveedor_id: proveedorId,
    numero_factura: numero,
    fecha_emision: fecha,
    fecha_vencimiento: input.fecha_vencimiento?.trim() || null,
    monto_subtotal: subtotal,
    monto_impuesto: impuesto,
    monto_total: subtotal + impuesto,
    estado_pago: "pendiente",
  });

  if (error) return { ok: false, error: error.message };
  return { ok: true };
}

export async function listPagosProveedores(): Promise<
  { ok: true; pagos: PagoProveedorItem[] } | { ok: false; error: string }
> {
  const { data, error } = await supabase
    .from("pagos_proveedores")
    .select("*, proveedores(razon_social)")
    .order("fecha_pago", { ascending: false });

  if (error) return { ok: false, error: error.message };

  return {
    ok: true,
    pagos: (data ?? []).map((p) => {
      const prov = joinOne(
        p.proveedores as
          | { razon_social?: string }
          | { razon_social?: string }[]
          | null,
      );
      return {
        id: p.id,
        proveedor_nombre: prov?.razon_social ?? "—",
        fecha_pago: p.fecha_pago,
        monto_total_pagado: Number(p.monto_total_pagado ?? 0),
        glosa_concepto: p.glosa_concepto ?? null,
      };
    }),
  };
}

export async function createPagoProveedor(input: {
  proveedor_id: string;
  monto_total_pagado: number;
  glosa_concepto?: string | null;
}): Promise<{ ok: true } | { ok: false; error: string }> {
  const proveedorId = input.proveedor_id.trim();
  const monto = Number(input.monto_total_pagado);

  if (!proveedorId) return { ok: false, error: "Selecciona un proveedor." };
  if (!Number.isFinite(monto) || monto <= 0) {
    return { ok: false, error: "El monto debe ser mayor a 0." };
  }

  const userId = await getSessionUserId();
  const { error } = await supabase.from("pagos_proveedores").insert({
    proveedor_id: proveedorId,
    monto_total_pagado: monto,
    glosa_concepto: input.glosa_concepto?.trim() || null,
    ejecutado_por: userId,
  });

  if (error) return { ok: false, error: error.message };
  return { ok: true };
}
