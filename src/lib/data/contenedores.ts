import { createClient } from "@/lib/supabase/server";
import { joinOne } from "@/lib/supabase/join";

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

export async function obtenerClienteContenedoresResumen(
  clienteId: string,
): Promise<{
  cliente: { id: string; razon_social: string; rif_nit: string } | null;
  saldos: SaldoContenedorConsulta[];
  movimientos: MovimientoContenedorConsulta[];
}> {
  const supabase = await createClient();
  const [{ data: cliente }, saldos, { data: movs }] = await Promise.all([
    supabase
      .from("clientes")
      .select("id, razon_social, rif_nit")
      .eq("id", clienteId)
      .maybeSingle(),
    listarSaldosContenedores({
      clienteId,
      soloConSaldo: false,
    }),
    supabase
      .from("movimientos_contenedores")
      .select(
        "id, orden_id, contenedor_id, cantidad_entregada, cantidad_retirada, created_at, tipos_contenedores(codigo, nombre), ordenes_distribucion(correlativo)",
      )
      .eq("cliente_id", clienteId)
      .order("created_at", { ascending: false })
      .limit(100),
  ]);

  const movimientos: MovimientoContenedorConsulta[] = (movs ?? []).map((m) => {
    const tipo = joinOne(m.tipos_contenedores);
    const orden = joinOne(m.ordenes_distribucion);
    const codigo = tipo?.codigo ? String(tipo.codigo).trim() : "";
    const nombre = String(tipo?.nombre ?? m.contenedor_id).trim();
    return {
      id: String(m.id),
      orden_id: m.orden_id ? String(m.orden_id) : null,
      orden_correlativo:
        orden?.correlativo != null ? Number(orden.correlativo) : null,
      contenedor_id: String(m.contenedor_id),
      contenedor_nombre: codigo ? `${codigo} — ${nombre}` : nombre,
      cantidad_entregada: Number(m.cantidad_entregada) || 0,
      cantidad_retirada: Number(m.cantidad_retirada) || 0,
      created_at: String(m.created_at),
    };
  });

  return {
    cliente: cliente
      ? {
          id: String(cliente.id),
          razon_social: String(cliente.razon_social ?? "—"),
          rif_nit: String(cliente.rif_nit ?? "—"),
        }
      : null,
    saldos,
    movimientos,
  };
}
