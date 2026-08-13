"use server";

import { revalidatePath } from "next/cache";
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
      "id, rif_nit, razon_social, direccion_fiscal, telefono, movil1, correo_e, vendedor_id, despachador_id, id_ruta, activo",
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
    },
  };
}

export async function actualizarClienteAction(
  input: ClienteEditarInput,
): Promise<{ ok: true } | { ok: false; error: string }> {
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

  const supabase = await createClient();
  const { error } = await supabase
    .from("clientes")
    .update({
      rif_nit: rif,
      razon_social: razon,
      direccion_fiscal: direccion,
      telefono: input.telefono?.trim() || null,
      movil1: input.movil1?.trim() || null,
      correo_e: input.correo_e?.trim() || null,
      vendedor_id: vendedorId,
      despachador_id: despachadorId,
      id_ruta: idRuta,
      activo: !!input.activo,
    })
    .eq("id", id);

  if (error) {
    return { ok: false, error: error.message };
  }

  revalidatePath("/clientes");
  revalidatePath(`/clientes/${id}`);
  revalidatePath("/ordenes");
  return { ok: true };
}
