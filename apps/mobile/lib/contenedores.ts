import { supabase } from "./supabase";
import { isRpcSuccess, rpcFailMessage, unwrapRpcData } from "./rpc";

function joinOne<T>(value: T | T[] | null | undefined): T | null {
  if (value == null) return null;
  return Array.isArray(value) ? (value[0] ?? null) : value;
}

export type SaldoContenedorRow = {
  id: string;
  cliente_id: string;
  cliente_razon: string;
  cliente_rif: string;
  contenedor_id: string;
  contenedor_nombre: string;
  contenedor_codigo: string | null;
  saldo_pendiente: number;
  updated_at: string | null;
};

export type MovimientoContenedorRow = {
  id: string;
  fecha_movimiento: string;
  orden_id: string | null;
  correlativo_orden: number | null;
  factura_origen_numero: string | null;
  contenedor_id: string;
  codigo_contenedor: string | null;
  nombre_contenedor: string | null;
  cantidad_entregada: number;
  cantidad_retirada: number;
};

export type HistoricoContenedores = {
  cliente_id: string;
  rif_nit: string;
  razon_social: string;
  fecha_inicial: string;
  fecha_limite: string;
  saldo_anterior: number;
  total_entregados: number;
  total_retirados: number;
  saldo_final: number;
  movimientos: MovimientoContenedorRow[];
};

export type ClienteContenedoresResumen = {
  cliente: { id: string; razon_social: string; rif_nit: string } | null;
  saldos: SaldoContenedorRow[];
  historico: HistoricoContenedores | null;
  historicoError: string | null;
};

/** Agrupa saldos por cliente para la lista (una fila por cliente). */
export type ClienteSaldoContenedoresResumen = {
  cliente_id: string;
  cliente_razon: string;
  cliente_rif: string;
  total_saldo: number;
  tipos: number;
};

function mapSaldoRow(row: {
  cliente_id: string;
  contenedor_id: string;
  saldo_pendiente: number | null;
  updated_at: string | null;
  clientes: unknown;
  tipos_contenedores: unknown;
}): SaldoContenedorRow {
  const cliente = joinOne(
    row.clientes as
      | { razon_social: string; rif_nit: string | null }
      | { razon_social: string; rif_nit: string | null }[]
      | null,
  );
  const tipo = joinOne(
    row.tipos_contenedores as
      | { codigo: string | null; nombre: string }
      | { codigo: string | null; nombre: string }[]
      | null,
  );
  const clienteId = String(row.cliente_id);
  const contenedorId = String(row.contenedor_id);
  return {
    id: `${clienteId}:${contenedorId}`,
    cliente_id: clienteId,
    cliente_razon: String(cliente?.razon_social ?? "").trim() || "—",
    cliente_rif: String(cliente?.rif_nit ?? "").trim() || "—",
    contenedor_id: contenedorId,
    contenedor_nombre: String(tipo?.nombre ?? contenedorId.slice(0, 8)),
    contenedor_codigo: tipo?.codigo ? String(tipo.codigo) : null,
    saldo_pendiente: Number(row.saldo_pendiente) || 0,
    updated_at: row.updated_at ? String(row.updated_at) : null,
  };
}

export async function listarSaldosContenedores(input?: {
  q?: string;
  soloConSaldo?: boolean;
}): Promise<
  { ok: true; rows: SaldoContenedorRow[] } | { ok: false; error: string }
> {
  let query = supabase
    .from("saldo_contenedores_clientes")
    .select(
      "cliente_id, contenedor_id, saldo_pendiente, updated_at, clientes(razon_social, rif_nit), tipos_contenedores(codigo, nombre)",
    )
    .order("saldo_pendiente", { ascending: false });

  if (input?.soloConSaldo !== false) {
    query = query.neq("saldo_pendiente", 0);
  }

  const { data, error } = await query;
  if (error) return { ok: false, error: error.message };

  const q = input?.q?.trim().toLowerCase() ?? "";
  const rows: SaldoContenedorRow[] = [];

  for (const row of data ?? []) {
    const mapped = mapSaldoRow(row);
    if (
      q &&
      !mapped.cliente_razon.toLowerCase().includes(q) &&
      !mapped.cliente_rif.toLowerCase().includes(q)
    ) {
      continue;
    }
    rows.push(mapped);
  }

  rows.sort((a, b) => {
    const byCliente = a.cliente_razon.localeCompare(b.cliente_razon, "es");
    if (byCliente !== 0) return byCliente;
    return a.contenedor_nombre.localeCompare(b.contenedor_nombre, "es");
  });

  return { ok: true, rows };
}

export type SaldoEnvaseCliente = {
  contenedor_id: string;
  nombre: string;
  codigo: string | null;
  saldo: number;
};

/** Todos los tipos de contenedor con el saldo actual del cliente (0 si no tiene). */
export async function obtenerSaldosEnvasesCliente(
  clienteId: string,
): Promise<
  { ok: true; envases: SaldoEnvaseCliente[] } | { ok: false; error: string }
> {
  const [tiposRes, saldosRes] = await Promise.all([
    supabase.from("tipos_contenedores").select("id, codigo, nombre").order("nombre"),
    supabase
      .from("saldo_contenedores_clientes")
      .select("contenedor_id, saldo_pendiente")
      .eq("cliente_id", clienteId),
  ]);
  if (tiposRes.error) return { ok: false, error: tiposRes.error.message };
  if (saldosRes.error) return { ok: false, error: saldosRes.error.message };

  const saldos = new Map<string, number>();
  for (const s of saldosRes.data ?? []) {
    saldos.set(String(s.contenedor_id), Number(s.saldo_pendiente) || 0);
  }

  return {
    ok: true,
    envases: (tiposRes.data ?? []).map((t) => ({
      contenedor_id: String(t.id),
      nombre: String(t.nombre ?? ""),
      codigo: t.codigo ? String(t.codigo) : null,
      saldo: saldos.get(String(t.id)) ?? 0,
    })),
  };
}

export function agruparSaldosPorCliente(
  rows: SaldoContenedorRow[],
): ClienteSaldoContenedoresResumen[] {
  const map = new Map<string, ClienteSaldoContenedoresResumen>();
  for (const r of rows) {
    const prev = map.get(r.cliente_id) ?? {
      cliente_id: r.cliente_id,
      cliente_razon: r.cliente_razon,
      cliente_rif: r.cliente_rif,
      total_saldo: 0,
      tipos: 0,
    };
    prev.total_saldo += r.saldo_pendiente;
    prev.tipos += 1;
    map.set(r.cliente_id, prev);
  }
  return [...map.values()].sort((a, b) =>
    a.cliente_razon.localeCompare(b.cliente_razon, "es"),
  );
}

export async function obtenerHistoricoContenedoresCliente(
  clienteId: string,
  fechaInicial?: string,
  fechaLimite?: string,
): Promise<
  { ok: true; data: HistoricoContenedores } | { ok: false; error: string }
> {
  const { data, error } = await supabase.rpc(
    "retorna_movimientos_contenedores_segun_cliente_id_rango_fechas",
    {
      p_cliente_id: clienteId,
      p_fecha_inicial: fechaInicial || null,
      p_fecha_limite: fechaLimite || null,
    },
  );

  if (error) return { ok: false, error: error.message };
  if (!isRpcSuccess(data)) {
    return {
      ok: false,
      error: rpcFailMessage(
        data,
        "No se pudo consultar el historial de contenedores.",
      ),
    };
  }

  const raw = unwrapRpcData<Record<string, unknown>>(data);
  if (!raw) return { ok: false, error: "Historial vacío." };

  const movs = Array.isArray(raw.movimientos) ? raw.movimientos : [];

  return {
    ok: true,
    data: {
      cliente_id: String(raw.cliente_id ?? clienteId),
      rif_nit: String(raw.rif_nit ?? ""),
      razon_social: String(raw.razon_social ?? ""),
      fecha_inicial: String(raw.fecha_inicial ?? ""),
      fecha_limite: String(raw.fecha_limite ?? ""),
      saldo_anterior: Number(raw.saldo_anterior) || 0,
      total_entregados: Number(raw.total_entregados) || 0,
      total_retirados: Number(raw.total_retirados) || 0,
      saldo_final: Number(raw.saldo_final) || 0,
      movimientos: movs.map((m) => {
        const row = m as Record<string, unknown>;
        return {
          id: String(row.id ?? ""),
          fecha_movimiento: String(row.fecha_movimiento ?? ""),
          orden_id: row.orden_id ? String(row.orden_id) : null,
          correlativo_orden:
            row.correlativo_orden != null
              ? Number(row.correlativo_orden)
              : null,
          factura_origen_numero: row.factura_origen_numero
            ? String(row.factura_origen_numero)
            : null,
          contenedor_id: String(row.contenedor_id ?? ""),
          codigo_contenedor: row.codigo_contenedor
            ? String(row.codigo_contenedor)
            : null,
          nombre_contenedor: row.nombre_contenedor
            ? String(row.nombre_contenedor)
            : null,
          cantidad_entregada: Number(row.cantidad_entregada) || 0,
          cantidad_retirada: Number(row.cantidad_retirada) || 0,
        };
      }),
    },
  };
}

export async function obtenerClienteContenedoresResumen(
  clienteId: string,
): Promise<
  | { ok: true; resumen: ClienteContenedoresResumen }
  | { ok: false; error: string }
> {
  const [clienteRes, saldosRes, historicoRes] = await Promise.all([
    supabase
      .from("clientes")
      .select("id, razon_social, rif_nit")
      .eq("id", clienteId)
      .maybeSingle(),
    supabase
      .from("saldo_contenedores_clientes")
      .select(
        "cliente_id, contenedor_id, saldo_pendiente, updated_at, clientes(razon_social, rif_nit), tipos_contenedores(codigo, nombre)",
      )
      .eq("cliente_id", clienteId)
      .order("saldo_pendiente", { ascending: false }),
    obtenerHistoricoContenedoresCliente(clienteId),
  ]);

  if (clienteRes.error) return { ok: false, error: clienteRes.error.message };
  if (saldosRes.error) return { ok: false, error: saldosRes.error.message };

  const cliente = clienteRes.data;
  const saldos = (saldosRes.data ?? []).map(mapSaldoRow);

  return {
    ok: true,
    resumen: {
      cliente: cliente
        ? {
            id: String(cliente.id),
            razon_social: String(cliente.razon_social ?? "—"),
            rif_nit: String(cliente.rif_nit ?? "—"),
          }
        : null,
      saldos,
      historico: historicoRes.ok ? historicoRes.data : null,
      historicoError: historicoRes.ok ? null : historicoRes.error,
    },
  };
}
