"use server";

import { revalidatePath } from "next/cache";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { callDbProcedure, rpcErrorMessage } from "@/lib/actions/db-rpc";

export type ItemMovimientoContenedorInput = {
  contenedor_id: string;
  cantidad_retirada: number;
  cantidad_entregada?: number;
};

export type RegistrarMovimientoContenedoresClienteInput = {
  cliente_id: string;
  movimientos: ItemMovimientoContenedorInput[];
  observaciones?: string | null;
};

export async function registrarMovimientoContenedoresAClientesAction(
  input: RegistrarMovimientoContenedoresClienteInput,
): Promise<{ ok: true; message: string; data?: unknown } | { ok: false; error: string }> {
  const profile = await getCurrentProfile();
  if (!profile) {
    return { ok: false, error: "Debes iniciar sesión para registrar movimientos de contenedores." };
  }

  const rol = getRoleNameFromProfile(profile);
  const rolesPermitidos = ["admin", "gerente", "vendedor", "despachador", "cobrador", "chofer"];
  if (!rol || !rolesPermitidos.includes(rol)) {
    return { ok: false, error: "No tienes permisos para registrar retiro de contenedores." };
  }

  const clienteId = input.cliente_id?.trim();
  if (!clienteId) {
    return { ok: false, error: "Debes seleccionar un cliente." };
  }

  const limpios = (input.movimientos ?? [])
    .map((m) => ({
      contenedor_id: String(m.contenedor_id ?? "").trim(),
      cantidad_retirada: Math.max(0, Math.floor(Number(m.cantidad_retirada) || 0)),
      cantidad_entregada: Math.max(0, Math.floor(Number(m.cantidad_entregada) || 0)),
    }))
    .filter((m) => m.contenedor_id && (m.cantidad_retirada > 0 || m.cantidad_entregada > 0));

  if (!limpios.length) {
    return { ok: false, error: "Indica al menos una cantidad mayor a 0 para retirar o ajustar." };
  }

  const res = await callDbProcedure<unknown>(
    "registrar_movimiento_contenedores_a_clientes",
    {
      p_cliente_id: clienteId,
      p_movimientos: limpios,
      p_observaciones: input.observaciones?.trim() || null,
      p_creado_por: profile.id,
    },
  );

  if (!res.success) {
    return {
      ok: false,
      error: rpcErrorMessage(res, "No se pudo registrar el retiro de contenedores."),
    };
  }

  revalidatePath("/contenedores");
  revalidatePath(`/contenedores/${clienteId}`);

  return {
    ok: true,
    message: "Retiro de contenedores registrado exitosamente.",
    data: res.data,
  };
}
