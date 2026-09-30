"use server";

import { revalidatePath } from "next/cache";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { callDbProcedure, rpcErrorMessage } from "@/lib/actions/db-rpc";
import { createClient } from "@/lib/supabase/server";
import {
  ROLES_MOVIMIENTOS_ESPECIALES,
  type MovimientoInventario,
  type MovimientoTipo,
} from "@/lib/inventario/movimientos-especiales";

const UUID_RE =
  /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi;

export type MovimientoEspecialInput = {
  tipo: MovimientoTipo;
  concepto: string;
  inventario: MovimientoInventario;
  camionId: string | null;
  clienteId: string | null;
  observaciones: string;
  detalles: Array<{ producto_id: string; cantidad: number; costo_unitario: number }>;
};

/** `registrar_movimiento_inventario_especial` (§6): entradas/salidas fuera de compras y distribución. */
export async function registrarMovimientoEspecialAction(
  input: MovimientoEspecialInput,
): Promise<{ ok: true; movimientoId: string | null } | { ok: false; error: string }> {
  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);
  if (!rol || !(ROLES_MOVIMIENTOS_ESPECIALES as readonly string[]).includes(rol)) {
    return { ok: false, error: "Solo admin o gerente pueden registrar movimientos especiales." };
  }

  const concepto = input.concepto.trim().toUpperCase();
  if (!concepto) return { ok: false, error: "Indica el concepto del movimiento." };
  if (input.inventario === "MOVIL" && !input.camionId) {
    return { ok: false, error: "Selecciona el camión." };
  }

  const detalles = input.detalles.filter((d) => d.producto_id && d.cantidad > 0);
  if (!detalles.length) {
    return { ok: false, error: "Agrega al menos un producto con cantidad mayor a 0." };
  }
  if (detalles.some((d) => !(d.costo_unitario >= 0))) {
    return { ok: false, error: "El costo unitario no puede ser negativo." };
  }

  const response = await callDbProcedure<{ movimiento_id?: string }>(
    "registrar_movimiento_inventario_especial",
    {
      p_tipo_movimiento: input.tipo,
      p_concepto: concepto,
      p_tipo_inventario_afectado: input.inventario,
      p_id_referencia_movil: input.inventario === "MOVIL" ? input.camionId : null,
      p_id_cliente: input.clienteId || null,
      p_observaciones: input.observaciones.trim() || null,
      p_detalles: detalles,
    },
  );

  if (!response.success) {
    return {
      ok: false,
      error: await nombresEnMensaje(
        rpcErrorMessage(response, "No se pudo registrar el movimiento."),
      ),
    };
  }

  revalidatePath("/inventario-movimientos");
  revalidatePath("/inventario-almacen");
  revalidatePath("/inventario-movil");
  revalidatePath("/autoventas");
  return { ok: true, movimientoId: response.data?.movimiento_id ?? null };
}

/** El SP identifica los productos por UUID en sus errores; se muestran por nombre. */
async function nombresEnMensaje(mensaje: string): Promise<string> {
  const ids = [...new Set(mensaje.match(UUID_RE) ?? [])];
  if (!ids.length) return mensaje;
  const supabase = await createClient();
  const { data } = await supabase.from("productos").select("id, nombre").in("id", ids);
  let salida = mensaje;
  for (const p of data ?? []) {
    salida = salida.split(p.id).join(`«${p.nombre}»`);
  }
  return salida;
}
