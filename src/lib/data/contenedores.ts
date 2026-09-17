import { createClient } from "@/lib/supabase/server";
import { joinOne } from "@/lib/supabase/join";
import { callDbProcedure } from "@/lib/actions/db-rpc";
import type { HistoricoContenedoresData } from "@/types/database";

export type SaldoContenedorConsulta = {
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

export type MovimientoContenedorConsulta = {
  id: string;
  orden_id: string | null;
  orden_correlativo: number | null;
  factura_origen_numero: string | null;
  contenedor_id: string;
  contenedor_nombre: string;
  cantidad_entregada: number;
  cantidad_retirada: number;
  created_at: string;
};

export type TipoContenedorOption = {
  id: string;
  label: string;
};

export type HistoricoContenedoresConsulta = {
  cliente: { id: string; razon_social: string; rif_nit: string } | null;
  saldos: SaldoContenedorConsulta[];
  historico: HistoricoContenedoresData | null;
  historicoError: string | null;
};

export async function listarTiposContenedoresConsulta(): Promise<
  TipoContenedorOption[]
> {
  const supabase = await createClient();
  const { data } = await supabase
    .from("tipos_contenedores")
    .select("id, codigo, nombre")
    .order("nombre");

  return (data ?? []).map((t) => ({
    id: String(t.id),
    label:
      t.codigo && String(t.codigo).trim()
        ? `${t.codigo} — ${t.nombre}`
        : String(t.nombre ?? t.id),
  }));
}

export async function listarSaldosContenedores(input?: {
  q?: string;
  contenedorId?: string;
  clienteId?: string;
  soloConSaldo?: boolean;
}): Promise<SaldoContenedorConsulta[]> {
  const supabase = await createClient();
  let query = supabase
    .from("saldo_contenedores_clientes")
    .select(
      "cliente_id, contenedor_id, saldo_pendiente, updated_at, clientes(razon_social, rif_nit), tipos_contenedores(codigo, nombre)",
    )
    .order("saldo_pendiente", { ascending: false });

  if (input?.soloConSaldo !== false) {
    query = query.neq("saldo_pendiente", 0);
  }
  if (input?.contenedorId) {
    query = query.eq("contenedor_id", input.contenedorId);
  }
  if (input?.clienteId) {
    query = query.eq("cliente_id", input.clienteId);
  }

  const { data, error } = await query;
  if (error || !data) return [];

  const q = input?.q?.trim().toLowerCase() ?? "";
  const rows: SaldoContenedorConsulta[] = [];

  for (const row of data) {
    const cliente = joinOne(row.clientes);
    const tipo = joinOne(row.tipos_contenedores);
    const razon = String(cliente?.razon_social ?? "").trim();
    const rif = String(cliente?.rif_nit ?? "").trim();
    if (
      q &&
      !razon.toLowerCase().includes(q) &&
      !rif.toLowerCase().includes(q)
    ) {
      continue;
    }
    const contenedorId = String(row.contenedor_id);
    const clienteId = String(row.cliente_id);
    rows.push({
      id: `${clienteId}:${contenedorId}`,
      cliente_id: clienteId,
      cliente_razon: razon || "—",
      cliente_rif: rif || "—",
      contenedor_id: contenedorId,
      contenedor_nombre: String(tipo?.nombre ?? contenedorId.slice(0, 8)),
      contenedor_codigo: tipo?.codigo ? String(tipo.codigo) : null,
      saldo_pendiente: Number(row.saldo_pendiente) || 0,
      updated_at: row.updated_at ? String(row.updated_at) : null,
    });
  }

  return rows.sort((a, b) => {
    const byCliente = a.cliente_razon.localeCompare(b.cliente_razon, "es");
    if (byCliente !== 0) return byCliente;
    return a.contenedor_nombre.localeCompare(b.contenedor_nombre, "es");
  });
}

/** Historial vía `retorna_movimientos_contenedores_segun_cliente_id_rango_fechas`. */
export async function obtenerHistoricoContenedoresCliente(
  clienteId: string,
  fechaInicial?: string,
  fechaLimite?: string,
): Promise<{
  data: HistoricoContenedoresData | null;
  error: string | null;
}> {
  const response = await callDbProcedure<HistoricoContenedoresData>(
    "retorna_movimientos_contenedores_segun_cliente_id_rango_fechas",
    {
      p_cliente_id: clienteId,
      p_fecha_inicial: fechaInicial || null,
      p_fecha_limite: fechaLimite || null,
    },
  );

  if (!response.success || !response.data) {
    return {
      data: null,
      error:
        response.error?.message ||
        response.message ||
        "No se pudo consultar el historial de contenedores.",
    };
  }

  return { data: response.data, error: null };
}

export async function obtenerClienteContenedoresResumen(
  clienteId: string,
  opts?: { fechaInicial?: string; fechaLimite?: string },
): Promise<HistoricoContenedoresConsulta> {
  const supabase = await createClient();
  const [{ data: cliente }, saldos, historicoResult] = await Promise.all([
    supabase
      .from("clientes")
      .select("id, razon_social, rif_nit")
      .eq("id", clienteId)
      .maybeSingle(),
    listarSaldosContenedores({
      clienteId,
      soloConSaldo: false,
    }),
    obtenerHistoricoContenedoresCliente(
      clienteId,
      opts?.fechaInicial,
      opts?.fechaLimite,
    ),
  ]);

  return {
    cliente: cliente
      ? {
          id: String(cliente.id),
          razon_social: String(cliente.razon_social ?? "—"),
          rif_nit: String(cliente.rif_nit ?? "—"),
        }
      : null,
    saldos,
    historico: historicoResult.data,
    historicoError: historicoResult.error,
  };
}
