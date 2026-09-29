import { supabase } from "./supabase";
import type { AppProfile } from "./auth";
import {
  isRpcSuccess,
  rpcFailMessage,
  unwrapRpcData,
} from "./rpc";

export type ClienteListaItem = {
  id: string;
  razon_social: string;
  rif_nit: string;
  despachador_id: string | null;
  id_ruta: string | null;
  vendedor_id: string | null;
};

export type ClienteVisita = ClienteListaItem & {
  direccion_fiscal: string | null;
  telefono: string | null;
  movil1: string | null;
};

export type OrdenAbono = {
  id: string;
  correlativo: number;
  fecha_despacho: string | null;
  dias_vencidos: number | null;
  saldo_pendiente: number;
  monto_total_orden: number | null;
  abonos_acumulados: number | null;
};

export type AbonosCliente = {
  cliente_id: string;
  saldo_favor: number;
  saldo_favor_bs: number | null;
  ordenes: OrdenAbono[];
};

export async function listClientesForProfile(
  profile: AppProfile,
  query?: string,
): Promise<
  { ok: true; clientes: ClienteListaItem[] } | { ok: false; error: string }
> {
  let q = supabase
    .from("clientes")
    .select("id, razon_social, rif_nit, despachador_id, id_ruta, vendedor_id")
    .eq("activo", true)
    .order("razon_social")
    .limit(200);

  if (profile.rol === "vendedor") {
    q = q.eq("vendedor_id", profile.id);
  }

  const term = query?.trim();
  if (term) {
    q = q.or(
      `razon_social.ilike.%${term}%,rif_nit.ilike.%${term}%`,
    );
  }

  const { data, error } = await q;
  if (error) return { ok: false, error: error.message };
  return { ok: true, clientes: (data ?? []) as ClienteListaItem[] };
}

/** Typeahead: busca en el servidor por razón social o RIF, sin traer la cartera completa. */
export async function buscarClientesForProfile(
  profile: AppProfile,
  texto: string,
  limite = 20,
): Promise<
  { ok: true; clientes: ClienteListaItem[] } | { ok: false; error: string }
> {
  const term = texto.replace(/[%,()*\\]/g, " ").trim();
  if (term.length < 2) return { ok: true, clientes: [] };

  let q = supabase
    .from("clientes")
    .select("id, razon_social, rif_nit, despachador_id, id_ruta, vendedor_id")
    .eq("activo", true)
    .or(`razon_social.ilike.%${term}%,rif_nit.ilike.%${term}%`)
    .order("razon_social")
    .limit(limite);

  if (profile.rol === "vendedor") {
    q = q.eq("vendedor_id", profile.id);
  }

  const { data, error } = await q;
  if (error) return { ok: false, error: error.message };
  return { ok: true, clientes: (data ?? []) as ClienteListaItem[] };
}

export async function getClienteVisita(
  clienteId: string,
  profile: AppProfile,
): Promise<
  { ok: true; cliente: ClienteVisita } | { ok: false; error: string }
> {
  const { data, error } = await supabase
    .from("clientes")
    .select(
      "id, razon_social, rif_nit, despachador_id, id_ruta, vendedor_id, direccion_fiscal, telefono, movil1",
    )
    .eq("id", clienteId)
    .maybeSingle();

  if (error) return { ok: false, error: error.message };
  if (!data) return { ok: false, error: "Cliente no encontrado." };

  if (
    profile.rol === "vendedor" &&
    data.vendedor_id &&
    data.vendedor_id !== profile.id
  ) {
    return { ok: false, error: "Este cliente no está en tu cartera." };
  }

  return { ok: true, cliente: data as ClienteVisita };
}

export async function solicitaAbonosCliente(
  clienteId: string,
): Promise<{ ok: true; abonos: AbonosCliente } | { ok: false; error: string }> {
  const { data, error } = await supabase.rpc(
    "solicita_abonos_orden_distribucion",
    { p_cliente_id: clienteId },
  );

  if (error) return { ok: false, error: error.message };

  const raw = unwrapRpcData<Record<string, unknown>>(data) ?? (data as Record<string, unknown>);
  if (!raw || typeof raw !== "object") {
    return { ok: false, error: "Respuesta inválida del servidor." };
  }

  const ordenesRaw = Array.isArray(raw.ordenes) ? raw.ordenes : [];
  const ordenes: OrdenAbono[] = ordenesRaw.map((o: Record<string, unknown>) => ({
    id: String(o.id ?? o.orden_id ?? ""),
    correlativo: Number(o.correlativo) || 0,
    fecha_despacho: (o.fecha_despacho as string) ?? null,
    dias_vencidos:
      o.dias_vencidos != null ? Number(o.dias_vencidos) : null,
    saldo_pendiente: Number(o.saldo_pendiente) || 0,
    monto_total_orden:
      o.monto_total_orden != null ? Number(o.monto_total_orden) : null,
    abonos_acumulados:
      o.abonos_acumulados != null ? Number(o.abonos_acumulados) : null,
  }));

  return {
    ok: true,
    abonos: {
      cliente_id: String(raw.cliente_id ?? clienteId),
      saldo_favor: Number(raw.saldo_favor) || 0,
      saldo_favor_bs:
        raw.saldo_favor_bs != null ? Number(raw.saldo_favor_bs) : null,
      ordenes,
    },
  };
}

export type ClienteEditar = {
  id: string;
  rif_nit: string;
  razon_social: string;
  direccion_fiscal: string;
  telefono: string | null;
  vendedor_id: string | null;
  despachador_id: string | null;
  id_ruta: string | null;
  activo: boolean;
};

export type CatalogOption = { id: string; label: string };

export async function getClienteEditar(
  id: string,
): Promise<{ ok: true; cliente: ClienteEditar } | { ok: false; error: string }> {
  const { data, error } = await supabase
    .from("clientes")
    .select(
      "id, rif_nit, razon_social, direccion_fiscal, telefono, vendedor_id, despachador_id, id_ruta, activo",
    )
    .eq("id", id)
    .maybeSingle();

  if (error) return { ok: false, error: error.message };
  if (!data) return { ok: false, error: "Cliente no encontrado." };
  return { ok: true, cliente: data as ClienteEditar };
}

export async function createCliente(input: {
  rif_nit: string;
  razon_social: string;
  direccion_fiscal: string;
  telefono?: string | null;
  vendedor_id?: string | null;
  despachador_id?: string | null;
  id_ruta?: string | null;
  activo?: boolean;
}): Promise<{ ok: true; id: string } | { ok: false; error: string }> {
  const rif = input.rif_nit.trim();
  const razon = input.razon_social.trim();
  const direccion = input.direccion_fiscal.trim();
  if (!rif) return { ok: false, error: "El RIF/NIT es requerido." };
  if (!razon) return { ok: false, error: "La razón social es requerida." };
  if (!direccion) return { ok: false, error: "La dirección fiscal es requerida." };

  const { data, error } = await supabase
    .from("clientes")
    .insert({
      rif_nit: rif,
      razon_social: razon,
      direccion_fiscal: direccion,
      telefono: input.telefono?.trim() || null,
      vendedor_id: input.vendedor_id?.trim() || null,
      despachador_id: input.despachador_id?.trim() || null,
      id_ruta: input.id_ruta?.trim() || null,
      activo: input.activo ?? true,
      limite_credito: 0,
      max_facturas_vencidas: 0,
      permiso_despacho_manual: false,
    })
    .select("id")
    .single();

  if (error) return { ok: false, error: error.message };
  return { ok: true, id: data.id as string };
}

export async function updateCliente(input: {
  id: string;
  rif_nit: string;
  razon_social: string;
  direccion_fiscal: string;
  telefono?: string | null;
  vendedor_id?: string | null;
  despachador_id?: string | null;
  id_ruta?: string | null;
  activo: boolean;
}): Promise<{ ok: true } | { ok: false; error: string }> {
  const rif = input.rif_nit.trim();
  const razon = input.razon_social.trim();
  const direccion = input.direccion_fiscal.trim();
  if (!rif) return { ok: false, error: "El RIF/NIT es requerido." };
  if (!razon) return { ok: false, error: "La razón social es requerida." };
  if (!direccion) return { ok: false, error: "La dirección fiscal es requerida." };
  if (!input.despachador_id?.trim()) {
    return { ok: false, error: "El despachador es obligatorio." };
  }
  if (!input.id_ruta?.trim()) {
    return { ok: false, error: "La ruta es obligatoria." };
  }

  const { data, error } = await supabase.rpc(
    "actualiza_registro_cliente_segun_uuid",
    {
      p_id: input.id,
      p_rif_nit: rif,
      p_razon_social: razon,
      p_direccion_fiscal: direccion,
      p_telefono: input.telefono?.trim() || null,
      p_movil1: null,
      p_correo_e: null,
      p_vendedor_id: input.vendedor_id?.trim() || null,
      p_despachador_id: input.despachador_id.trim(),
      p_id_ruta: input.id_ruta.trim(),
      p_activo: !!input.activo,
      p_limite_credito: 0,
      p_max_facturas_vencidas: 0,
      p_permiso_despacho_manual: false,
    },
  );

  if (error) return { ok: false, error: error.message };
  if (!isRpcSuccess(data)) {
    return {
      ok: false,
      error: rpcFailMessage(data, "No se pudo actualizar el cliente."),
    };
  }
  return { ok: true };
}

export async function listVendedoresOptions(): Promise<
  { ok: true; options: CatalogOption[] } | { ok: false; error: string }
> {
  const { data, error } = await supabase.rpc(
    "retorna_lista_usuarios_segun_parametros",
    { p_nombre: "", p_rol: "vendedor" },
  );
  if (error) return { ok: false, error: error.message };
  const rows =
    unwrapRpcData<{ id: string; nombre_completo: string }[]>(data) ??
    (Array.isArray(data) ? data : []);
  return {
    ok: true,
    options: (rows as { id: string; nombre_completo: string }[]).map((u) => ({
      id: u.id,
      label: u.nombre_completo || u.id,
    })),
  };
}

export async function listDespachadoresOptions(): Promise<
  { ok: true; options: CatalogOption[] } | { ok: false; error: string }
> {
  const { data, error } = await supabase.rpc("retorna_usuarios_despachadores");
  if (error) return { ok: false, error: error.message };
  if (!isRpcSuccess(data)) {
    return {
      ok: false,
      error: rpcFailMessage(data, "No se pudieron consultar despachadores."),
    };
  }
  const rows =
    unwrapRpcData<{ id: string; nombre_completo: string }[]>(data) ?? [];
  return {
    ok: true,
    options: (Array.isArray(rows) ? rows : []).map((u) => ({
      id: u.id,
      label: u.nombre_completo || u.id,
    })),
  };
}
