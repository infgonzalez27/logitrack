"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import type { OrdenEstado } from "@/types/database";

export type LineaOrdenInput = {
  producto_id: string;
  cantidad_solicitada: number;
  valor_unitario_recaudar: number;
  secuencia_entrega?: number;
};

export async function createOrdenAction(input: {
  cliente_id: string;
  camion_id: string;
  chofer_id: string;
  factura_origen_numero: string;
  lineas: LineaOrdenInput[];
}) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!input.lineas.length) {
    return { error: "Agrega al menos una línea de producto." };
  }

  const pesoLineas = await Promise.all(
    input.lineas.map(async (linea) => {
      const { data: producto } = await supabase
        .from("productos")
        .select("peso_unitario_kg")
        .eq("id", linea.producto_id)
        .single();
      return (
        (producto?.peso_unitario_kg ?? 0) * linea.cantidad_solicitada
      );
    }),
  );

  const peso_total_calculado = pesoLineas.reduce((a, b) => a + b, 0);

  const { data: orden, error: ordenError } = await supabase
    .from("ordenes_distribucion")
    .insert({
      cliente_id: input.cliente_id,
      camion_id: input.camion_id,
      chofer_id: input.chofer_id,
      factura_origen_numero: input.factura_origen_numero,
      estado: "borrador",
      peso_total_calculado,
      creado_por: user?.id ?? null,
    })
    .select("id")
    .single();

  if (ordenError || !orden) {
    return { error: ordenError?.message ?? "No se pudo crear la orden." };
  }

  const detalle = input.lineas.map((linea, index) => ({
    orden_id: orden.id,
    producto_id: linea.producto_id,
    cantidad_solicitada: linea.cantidad_solicitada,
    cantidad_despachada: 0,
    valor_unitario_recaudar: linea.valor_unitario_recaudar,
    subtotal_recaudar:
      linea.cantidad_solicitada * linea.valor_unitario_recaudar,
    secuencia_entrega: linea.secuencia_entrega ?? index + 1,
    estado_entrega: "pendiente" as const,
  }));

  const { error: detalleError } = await supabase
    .from("detalle_distribucion")
    .insert(detalle);

  if (detalleError) {
    await supabase.from("ordenes_distribucion").delete().eq("id", orden.id);
    return { error: detalleError.message };
  }

  revalidatePath("/ordenes");
  redirect(`/ordenes/${orden.id}`);
}

export async function updateOrdenEstadoAction(
  ordenId: string,
  estado: OrdenEstado,
) {
  const supabase = await createClient();
  const payload: Record<string, unknown> = { estado };

  if (estado === "en_transito") {
    payload.fecha_despacho = new Date().toISOString();
  }

  const { error } = await supabase
    .from("ordenes_distribucion")
    .update(payload)
    .eq("id", ordenId);

  if (error) return { error: error.message };

  revalidatePath("/ordenes");
  revalidatePath(`/ordenes/${ordenId}`);
  return { success: true };
}
