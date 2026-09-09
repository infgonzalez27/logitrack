"use server";

import { revalidatePath } from "next/cache";
import { getCurrentProfile } from "@/lib/auth";
import { callDbProcedure, rpcErrorMessage } from "@/lib/actions/db-rpc";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { createClient } from "@/lib/supabase/server";
import type { Cliente } from "@/types/database";

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function isUuid(value: string): boolean {
  return UUID_RE.test(value.trim());
}

export type ClienteEditarInput = {
  id: string;
  rif_nit: string;
  razon_social: string;
  direccion_fiscal: string;
  telefono: string | null;
  movil1: string | null;
  correo_e: string | null;
  vendedor_id: string | null;
  despachador_id: string | null;
  id_ruta: string | null;
  activo: boolean;
  limite_credito: number | null;
  max_facturas_vencidas: number | null;
  permiso_despacho_manual: boolean;
  excepcion_despacho_gerencia: boolean;
};

export async function obtenerClienteParaEditarAction(
  id: string,
): Promise<
  { ok: true; cliente: ClienteEditarInput } | { ok: false; error: string }
> {
  const clienteId = id?.trim();
  if (!clienteId || !isUuid(clienteId)) {
    return { ok: false, error: "ID de cliente inválido." };
  }

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("clientes")
    .select(
      "id, rif_nit, razon_social, direccion_fiscal, telefono, movil1, correo_e, vendedor_id, despachador_id, id_ruta, activo, limite_credito, max_facturas_vencidas, permiso_despacho_manual, excepcion_despacho_gerencia",
    )
    .eq("id", clienteId)
    .single();

  if (error || !data) {
    return { ok: false, error: "Cliente no encontrado." };
  }

  const row = data as Cliente;
  return {
    ok: true,
    cliente: {
      id: row.id,
      rif_nit: row.rif_nit,
      razon_social: row.razon_social,
      direccion_fiscal: row.direccion_fiscal,
      telefono: row.telefono,
      movil1: row.movil1,
      correo_e: row.correo_e,
      vendedor_id: row.vendedor_id ?? null,
      despachador_id: row.despachador_id ?? null,
      id_ruta: row.id_ruta ?? null,
      activo: row.activo,
      limite_credito:
        row.limite_credito != null ? Number(row.limite_credito) : null,
      max_facturas_vencidas:
        row.max_facturas_vencidas != null
          ? Number(row.max_facturas_vencidas)
          : null,
      permiso_despacho_manual: row.permiso_despacho_manual ?? true,
      excepcion_despacho_gerencia: row.excepcion_despacho_gerencia ?? false,
    },
  };
}

/** INTEGRACION-RPC §2.15 — `actualiza_registro_cliente_segun_uuid` */
export async function actualizarClienteAction(
  input: ClienteEditarInput,
): Promise<{ ok: true } | { ok: false; error: string; code?: string }> {
  const id = input.id?.trim();
  if (!id || !isUuid(id)) {
    return { ok: false, error: "ID de cliente inválido." };
  }

  const rif = input.rif_nit?.trim();
  const razon = input.razon_social?.trim();
  const direccion = input.direccion_fiscal?.trim();
  if (!rif) return { ok: false, error: "El RIF/NIT es requerido." };
  if (!razon) return { ok: false, error: "La razón social es requerida." };
  if (!direccion) {
    return { ok: false, error: "La dirección fiscal es requerida." };
  }

  const vendedorId = input.vendedor_id?.trim() || null;
  const despachadorId = input.despachador_id?.trim() || null;
  const idRuta = input.id_ruta?.trim() || null;

  if (vendedorId && !isUuid(vendedorId)) {
    return { ok: false, error: "Vendedor inválido." };
  }
  if (despachadorId && !isUuid(despachadorId)) {
    return { ok: false, error: "Despachador inválido." };
  }
  if (idRuta && !isUuid(idRuta)) {
    return { ok: false, error: "Ruta inválida." };
  }
  if (!despachadorId) {
    return { ok: false, error: "El despachador es obligatorio." };
  }
  if (!idRuta) {
    return { ok: false, error: "La ruta es obligatoria." };
  }

  const limiteCredito =
    input.limite_credito == null || Number.isNaN(Number(input.limite_credito))
      ? 0
      : Math.max(0, Number(input.limite_credito));
  const maxFacturas =
    input.max_facturas_vencidas == null ||
    Number.isNaN(Number(input.max_facturas_vencidas))
      ? 0
      : Math.max(0, Math.floor(Number(input.max_facturas_vencidas)));

  const response = await callDbProcedure<Cliente>(
    "actualiza_registro_cliente_segun_uuid",
    {
      p_id: id,
      p_rif_nit: rif,
      p_razon_social: razon,
      p_direccion_fiscal: direccion,
      p_telefono: input.telefono?.trim() || null,
      p_movil1: input.movil1?.trim() || null,
      p_correo_e: input.correo_e?.trim() || null,
      p_vendedor_id: vendedorId,
      p_despachador_id: despachadorId,
      p_id_ruta: idRuta,
      p_activo: !!input.activo,
      p_limite_credito: limiteCredito,
      p_max_facturas_vencidas: maxFacturas,
      p_permiso_despacho_manual: !!input.permiso_despacho_manual,
    },
  );

  if (!response.success || !response.data) {
    return {
      ok: false,
      error: rpcErrorMessage(response, "No se pudo actualizar el cliente."),
      code: response.error?.code,
    };
  }

  revalidatePath("/clientes");
  revalidatePath(`/clientes/${id}`);
  revalidatePath("/ordenes");
  revalidatePath("/radar");
  return { ok: true };
}

/** INTEGRACION-RPC §2.23 — `otorgar_excepcion_despacho_gerencia` */
export async function otorgarExcepcionDespachoGerenciaAction(
  clienteId: string,
): Promise<{ ok: true } | { ok: false; error: string; code?: string }> {
  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);
  if (rol !== "gerente" && rol !== "admin") {
    return {
      ok: false,
      error: "Solo gerencia o admin pueden otorgar la excepción.",
      code: "ACCESO_DENEGADO",
    };
  }

  const id = clienteId?.trim();
  if (!id || !isUuid(id)) {
    return { ok: false, error: "Cliente inválido.", code: "PARAMETRO_INVALIDO" };
  }

  const response = await callDbProcedure<{
    cliente_id: string;
    excepcion_despacho_gerencia: boolean;
  }>("otorgar_excepcion_despacho_gerencia", {
    p_cliente_id: id,
  });

  if (!response.success) {
    return {
      ok: false,
      error: rpcErrorMessage(
        response,
        "No se pudo otorgar la excepción de despacho.",
      ),
      code: response.error?.code,
    };
  }

  revalidatePath(`/clientes/${id}`);
  revalidatePath("/clientes");
  revalidatePath("/radar");
  revalidatePath("/ordenes");
  return { ok: true };
}
