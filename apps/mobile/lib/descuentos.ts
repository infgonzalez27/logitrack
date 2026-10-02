import { supabase } from "./supabase";

export type DescuentoConProducto = {
  id: string;
  cliente_id: string;
  producto_id: string;
  porcentaje_descuento: number;
  precio_pactado_usd: number | null;
  activo: boolean;
  producto_nombre: string;
  producto_codigo: string;
  precio_lista1: number;
};

export async function obtenerDescuentosCliente(
  clienteId: string,
): Promise<
  { ok: true; descuentos: DescuentoConProducto[] } | { ok: false; error: string }
> {
  if (!clienteId) return { ok: false, error: "ID de cliente no proporcionado." };

  const { data, error } = await supabase
    .from("descuentos_cliente_producto")
    .select(
      `
      id,
      cliente_id,
      producto_id,
      porcentaje_descuento,
      precio_pactado_usd,
      activo,
      productos (
        id,
        nombre,
        codigo_producto,
        precio_lista1
      )
    `,
    )
    .eq("cliente_id", clienteId)
    .eq("activo", true)
    .order("created_at", { ascending: false });

  if (error) return { ok: false, error: error.message };

  const descuentos: DescuentoConProducto[] = (data ?? []).map(
    (item: Record<string, unknown>) => {
      const prod = item.productos as
        | {
            nombre?: string;
            codigo_producto?: string;
            id?: string;
            precio_lista1?: number;
          }
        | {
            nombre?: string;
            codigo_producto?: string;
            id?: string;
            precio_lista1?: number;
          }[]
        | null;
      const p = Array.isArray(prod) ? prod[0] : prod;
      return {
        id: String(item.id),
        cliente_id: String(item.cliente_id),
        producto_id: String(item.producto_id),
        porcentaje_descuento: Number(item.porcentaje_descuento || 0),
        precio_pactado_usd:
          item.precio_pactado_usd != null
            ? Number(item.precio_pactado_usd)
            : null,
        activo: !!item.activo,
        producto_nombre: p?.nombre || "Producto desconocido",
        producto_codigo: p?.codigo_producto || p?.id || "",
        precio_lista1: Number(p?.precio_lista1 || 0),
      };
    },
  );

  return { ok: true, descuentos };
}

export async function guardarDescuentoCliente(input: {
  cliente_id: string;
  producto_id: string;
  porcentaje_descuento: number;
  precio_pactado_usd?: number | null;
}): Promise<{ ok: true; id: string } | { ok: false; error: string }> {
  if (!input.cliente_id) return { ok: false, error: "Selecciona un cliente válido." };
  if (!input.producto_id) {
    return { ok: false, error: "Selecciona un producto válido." };
  }
  if (input.porcentaje_descuento < 0 || input.porcentaje_descuento > 100) {
    return { ok: false, error: "El porcentaje debe estar entre 0% y 100%." };
  }

  const { data, error } = await supabase
    .from("descuentos_cliente_producto")
    .upsert(
      {
        cliente_id: input.cliente_id,
        producto_id: input.producto_id,
        porcentaje_descuento: input.porcentaje_descuento,
        precio_pactado_usd: input.precio_pactado_usd ?? null,
        activo: true,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "cliente_id,producto_id" },
    )
    .select("id")
    .single();

  if (error) return { ok: false, error: error.message };
  return { ok: true, id: data.id as string };
}

export async function eliminarDescuentoCliente(
  id: string,
): Promise<{ ok: true } | { ok: false; error: string }> {
  if (!id) return { ok: false, error: "ID de descuento no proporcionado." };

  const { error } = await supabase
    .from("descuentos_cliente_producto")
    .delete()
    .eq("id", id);

  if (error) return { ok: false, error: error.message };
  return { ok: true };
}

export async function consultarDescuentoRPC(
  clienteId: string,
  productoId: string,
): Promise<{
  ok: true;
  data: {
    producto_id: string;
    cliente_id: string;
    aplica_descuento: boolean;
    precio_lista_usd: number;
    precio_final_usd: number;
    porcentaje_descuento: number;
    monto_descuento_usd: number;
  };
} | { ok: false; error: string }> {
  const { data, error } = await supabase.rpc("consultar_descuento_producto_cliente", {
    p_cliente_id: clienteId,
    p_producto_id: productoId,
  });

  if (error) return { ok: false, error: error.message };
  if (data && typeof data === "object" && data.success && data.data) {
    return { ok: true, data: data.data };
  }
  return { ok: false, error: "Error consultando descuento" };
}
