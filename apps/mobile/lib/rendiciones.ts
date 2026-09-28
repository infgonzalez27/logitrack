import { supabase } from "./supabase";
import {
  convertirBsAUsd,
  convertirUsdABs,
  esFormaPagoEnBs,
} from "./moneda";
import { isRpcSuccess, rpcFailMessage, unwrapRpcData } from "./rpc";
import { retornaUltimaTasa } from "./catalogos";

export type Fpago = {
  fpago_id: string;
  fpago_concepto: string;
  fpago_info: boolean;
};

export type CuentaBancaria = {
  id: string;
  banco: string;
  numero_cuenta: string | null;
  titular: string | null;
  activa: boolean;
};

export type OrdenParaRendicion = {
  id: string;
  correlativo: number;
  fecha_despacho: string | null;
  dias_vencidos: number;
  saldo_pendiente: number;
  saldo_pendiente_bs: number | null;
  tasa_orden: number | null;
};

export type AbonosCliente = {
  cliente_id: string;
  saldo_favor: number;
  saldo_favor_bs: number | null;
  tasa_oficial_actual: number | null;
  ordenes: OrdenParaRendicion[];
};

export type PagoInput = {
  fpago_id: string;
  monto: number;
  en_bs: boolean;
  cuenta_bancaria_id?: string | null;
  referencia_bancaria?: string | null;
  fpago_info: boolean;
};

export async function listarFormasPago(): Promise<
  { ok: true; formas: Fpago[] } | { ok: false; error: string }
> {
  const { data, error } = await supabase.rpc("consulta_registros_formas_pago");
  if (error) return { ok: false, error: error.message };
  if (!isRpcSuccess(data)) {
    return {
      ok: false,
      error: rpcFailMessage(data, "No se pudieron cargar las formas de pago."),
    };
  }
  const rows = unwrapRpcData<Record<string, unknown>[]>(data) ?? [];
  const formas: Fpago[] = (Array.isArray(rows) ? rows : []).map((r) => ({
    fpago_id: String(r.fpago_id ?? r.id ?? ""),
    fpago_concepto: String(r.fpago_concepto ?? r.concepto ?? ""),
    fpago_info: Boolean(r.fpago_info),
  }));
  return { ok: true, formas: formas.filter((f) => f.fpago_id) };
}

export async function listarCuentasBancarias(): Promise<
  { ok: true; cuentas: CuentaBancaria[] } | { ok: false; error: string }
> {
  const { data, error } = await supabase.rpc(
    "retorna_cuentas_bancarias_empresa",
    { p_solo_activas: true },
  );
  if (error) {
    const fallback = await supabase
      .from("cuentas_bancarias_empresa")
      .select("id, banco, numero_cuenta, titular, activa")
      .eq("activa", true)
      .order("banco");
    if (fallback.error) return { ok: false, error: fallback.error.message };
    return {
      ok: true,
      cuentas: (fallback.data ?? []).map((c) => ({
        id: c.id,
        banco: c.banco,
        numero_cuenta: c.numero_cuenta,
        titular: c.titular,
        activa: c.activa,
      })),
    };
  }
  if (!isRpcSuccess(data)) {
    return {
      ok: false,
      error: rpcFailMessage(data, "No se pudieron cargar las cuentas."),
    };
  }
  const rows = unwrapRpcData<Record<string, unknown>[]>(data) ?? [];
  return {
    ok: true,
    cuentas: (Array.isArray(rows) ? rows : []).map((c) => ({
      id: String(c.id ?? ""),
      banco: String(c.banco ?? c.nombre_banco ?? ""),
      numero_cuenta: (c.numero_cuenta as string) ?? null,
      titular: (c.titular as string) ?? null,
      activa: c.activa !== false,
    })).filter((c) => c.id),
  };
}

export async function solicitaAbonosCliente(
  clienteId: string,
): Promise<{ ok: true; abonos: AbonosCliente } | { ok: false; error: string }> {
  const { data, error } = await supabase.rpc(
    "solicita_abonos_orden_distribucion",
    { p_cliente_id: clienteId },
  );
  if (error) return { ok: false, error: error.message };
  if (!isRpcSuccess(data)) {
    return {
      ok: false,
      error: rpcFailMessage(data, "No se pudieron cargar los saldos."),
    };
  }

  const raw =
    unwrapRpcData<Record<string, unknown>>(data) ??
    (data as Record<string, unknown>);
  if (!raw || typeof raw !== "object") {
    return { ok: false, error: "Respuesta inválida del servidor." };
  }

  const tasaOficial =
    raw.tasa_oficial_actual != null && Number(raw.tasa_oficial_actual) > 0
      ? Number(raw.tasa_oficial_actual)
      : null;

  const ordenesRaw = Array.isArray(raw.ordenes) ? raw.ordenes : [];
  const ordenes: OrdenParaRendicion[] = ordenesRaw.map((o) => {
    const row = o as Record<string, unknown>;
    const saldo = Number(row.saldo_pendiente) || 0;
    const tasaOrden =
      row.tasa_orden != null && Number(row.tasa_orden) > 0
        ? Number(row.tasa_orden)
        : tasaOficial;
    let saldoBs =
      row.saldo_pendiente_bs != null ? Number(row.saldo_pendiente_bs) : null;
    if ((saldoBs == null || saldoBs <= 0) && saldo > 0 && tasaOrden != null) {
      saldoBs = convertirUsdABs(saldo, tasaOrden);
    }
    return {
      id: String(row.orden_id ?? row.id ?? ""),
      correlativo: Number(row.correlativo) || 0,
      fecha_despacho: (row.fecha_despacho as string) ?? null,
      dias_vencidos: Math.max(0, Number(row.dias_vencidos) || 0),
      saldo_pendiente: saldo,
      saldo_pendiente_bs: saldoBs,
      tasa_orden: tasaOrden,
    };
  });

  return {
    ok: true,
    abonos: {
      cliente_id: String(raw.cliente_id ?? clienteId),
      saldo_favor: Number(raw.saldo_favor) || 0,
      saldo_favor_bs:
        raw.saldo_favor_bs != null ? Number(raw.saldo_favor_bs) : null,
      tasa_oficial_actual: tasaOficial,
      ordenes: ordenes.filter((o) => o.id && o.saldo_pendiente > 0),
    },
  };
}

export async function registrarRendicion(input: {
  clienteId: string;
  userId: string;
  observaciones?: string;
  tasaCambio?: number | null;
  ordenes: Array<{
    orden_id: string;
    monto_recaudado: number;
    monto_recaudado_bs?: number | null;
  }>;
  pagos: PagoInput[];
  formas: Fpago[];
}): Promise<
  | {
      ok: true;
      rendicionId: string;
      saldoFavorUsado: number;
      saldoFavorGenerado: number;
    }
  | { ok: false; error: string }
> {
  if (!input.ordenes.length) {
    return { ok: false, error: "Agrega al menos una orden a la Rendición." };
  }
  if (!input.pagos.length) {
    return { ok: false, error: "Agrega al menos una forma de pago." };
  }

  for (const pago of input.pagos) {
    if (!(pago.monto > 0)) {
      return { ok: false, error: "Cada pago debe tener monto mayor a 0." };
    }
    if (pago.fpago_info) {
      if (!pago.referencia_bancaria?.trim()) {
        return { ok: false, error: "La referencia bancaria es obligatoria." };
      }
      if (!pago.cuenta_bancaria_id?.trim()) {
        return {
          ok: false,
          error: "Selecciona la cuenta bancaria de la empresa.",
        };
      }
    }
  }

  let tasaDia =
    input.tasaCambio != null && input.tasaCambio > 0
      ? input.tasaCambio
      : null;
  if (tasaDia == null) {
    const ultima = await retornaUltimaTasa();
    if (ultima.ok) tasaDia = ultima.tasa;
  }

  const formasById = new Map(input.formas.map((f) => [f.fpago_id, f]));
  const necesitaTasa = input.pagos.some((p) => {
    if (p.en_bs) return true;
    const forma = formasById.get(p.fpago_id);
    return forma ? esFormaPagoEnBs(forma.fpago_concepto) : false;
  });

  if (necesitaTasa && (tasaDia == null || tasaDia <= 0)) {
    return {
      ok: false,
      error:
        "No hay tasa del día para convertir pagos en bolívares. Regístrala en la web (BCV).",
    };
  }

  const { data, error } = await supabase.rpc("registrar_rendicion_cuentas", {
    p_cliente_id: input.clienteId,
    p_observaciones: input.observaciones?.trim() || null,
    p_creado_por: input.userId,
    p_tasa_cambio: tasaDia,
    p_ordenes: input.ordenes.map((o) => {
      const usd = o.monto_recaudado;
      const bs =
        o.monto_recaudado_bs != null
          ? o.monto_recaudado_bs
          : tasaDia != null
            ? convertirUsdABs(usd, tasaDia)
            : null;
      return {
        orden_id: o.orden_id,
        monto_recaudado: usd,
        monto_recaudado_bs: bs,
      };
    }),
    p_pagos: input.pagos.map((p) => {
      const forma = formasById.get(p.fpago_id);
      const enBs =
        p.en_bs ||
        (!!forma && esFormaPagoEnBs(forma.fpago_concepto));
      let montoUsd: number;
      let montoBs: number;
      if (enBs) {
        montoBs = p.monto;
        montoUsd =
          tasaDia != null ? convertirBsAUsd(montoBs, tasaDia) : p.monto;
      } else {
        montoUsd = p.monto;
        montoBs =
          tasaDia != null ? convertirUsdABs(montoUsd, tasaDia) : 0;
      }
      return {
        fpago_id: p.fpago_id,
        monto: montoUsd,
        monto_usd: montoUsd,
        monto_bs: montoBs,
        cuenta_bancaria_id: p.fpago_info
          ? p.cuenta_bancaria_id?.trim() || null
          : null,
        referencia_bancaria: p.fpago_info
          ? p.referencia_bancaria?.trim() || null
          : null,
        cuenta_bancaria: null,
        capture_url: null,
      };
    }),
  });

  if (error) return { ok: false, error: error.message };
  if (!isRpcSuccess(data)) {
    return {
      ok: false,
      error: rpcFailMessage(data, "No se pudo registrar la Rendición."),
    };
  }

  const payload =
    unwrapRpcData<Record<string, unknown>>(data) ??
    (data as Record<string, unknown>);
  const rendicionId = String(
    payload?.rendicion_id ??
      (data as { rendicion_id?: string }).rendicion_id ??
      "",
  );
  if (!rendicionId) {
    return { ok: false, error: "Rendición creada sin ID de respuesta." };
  }

  return {
    ok: true,
    rendicionId,
    saldoFavorUsado: Number(payload?.saldo_favor_usado) || 0,
    saldoFavorGenerado: Number(payload?.saldo_favor_generado) || 0,
  };
}

function joinOne<T>(value: T | T[] | null | undefined): T | null {
  if (value == null) return null;
  return Array.isArray(value) ? (value[0] ?? null) : value;
}

export type OrdenPorLiquidarCliente = {
  cliente_id: string;
  razon_social: string;
  rif_nit: string;
  dias_vencidos: number;
  cant_ordenes: number;
  monto_por_liquidar: number;
};

/** Alias usado por pantallas de campo. */
export type OrdenPorLiquidar = OrdenPorLiquidarCliente;

export type RendicionListaItem = {
  id: string;
  cliente_id: string;
  cliente_razon: string;
  fecha_rendicion: string;
  total_efectivo_recaudado: number;
  total_transferencias_recaudado: number;
  total_recaudado_usd: number | null;
  estado: string;
  observaciones: string | null;
};

export type RendicionDetalle = RendicionListaItem & {
  tasa_cambio: number | null;
  auditado_por: string | null;
  ordenes: Array<{
    id: string;
    orden_id: string;
    correlativo: number | null;
    recaudado: number;
    recaudado_bs: number | null;
  }>;
  pagos: Array<{
    id: string;
    fpago_concepto: string | null;
    monto: number;
    monto_usd: number | null;
    monto_bs: number | null;
    referencia_bancaria: string | null;
  }>;
};

export type ReporteFormaPagoMovimiento = {
  rendicion_id: string;
  fecha_rendicion: string;
  tasa_cambio: number | null;
  cliente_id: string;
  cliente_nombre: string;
  cliente_rif: string;
  fpago_id: string;
  fpago_concepto: string;
  es_bancario: boolean;
  referencia_bancaria: string | null;
  cuenta_bancaria: string | null;
  monto_bs: number | null;
  monto_usd: number | null;
};

export type ReporteFormasPagoData = {
  fecha_desde: string;
  fecha_hasta: string;
  solo_bancarios: boolean;
  total_registros: number;
  monto_total_bs: number;
  monto_total_usd: number;
  movimientos: ReporteFormaPagoMovimiento[];
};

export async function listRendiciones(): Promise<
  { ok: true; items: RendicionListaItem[] } | { ok: false; error: string }
> {
  const { data, error } = await supabase
    .from("rendiciones_cuentas")
    .select(
      "id, cliente_id, fecha_rendicion, total_efectivo_recaudado, total_transferencias_recaudado, total_recaudado_usd, estado, observaciones, clientes(razon_social)",
    )
    .order("fecha_rendicion", { ascending: false })
    .limit(100);

  if (error) return { ok: false, error: error.message };

  const items: RendicionListaItem[] = (data ?? []).map((r) => {
    const cliente = joinOne(
      r.clientes as { razon_social: string } | { razon_social: string }[] | null,
    );
    return {
      id: r.id,
      cliente_id: r.cliente_id,
      cliente_razon: cliente?.razon_social ?? "â€”",
      fecha_rendicion: r.fecha_rendicion,
      total_efectivo_recaudado: Number(r.total_efectivo_recaudado) || 0,
      total_transferencias_recaudado:
        Number(r.total_transferencias_recaudado) || 0,
      total_recaudado_usd:
        r.total_recaudado_usd != null ? Number(r.total_recaudado_usd) : null,
      estado: String(r.estado ?? ""),
      observaciones: r.observaciones ?? null,
    };
  });

  return { ok: true, items };
}

export async function getRendicionDetalle(
  id: string,
): Promise<
  { ok: true; rendicion: RendicionDetalle } | { ok: false; error: string }
> {
  const { data, error } = await supabase
    .from("rendiciones_cuentas")
    .select(
      `
      id, cliente_id, fecha_rendicion, tasa_cambio,
      total_efectivo_recaudado, total_transferencias_recaudado,
      total_recaudado_usd, estado, observaciones, auditado_por,
      clientes(razon_social),
      detalle_rendicion_ordenes(
        id, orden_distribucion_id, recaudado, recaudado_bs,
        ordenes_distribucion(correlativo)
      ),
      detalle_rendicion_fpagos(
        id, monto, monto_usd, monto_bs, referencia_bancaria,
        fpagos(fpago_concepto)
      )
    `,
    )
    .eq("id", id)
    .maybeSingle();

  if (error) return { ok: false, error: error.message };
  if (!data) return { ok: false, error: "Rendición no encontrada." };

  const cliente = joinOne(
    data.clientes as { razon_social: string } | { razon_social: string }[] | null,
  );

  const ordenesRaw = Array.isArray(data.detalle_rendicion_ordenes)
    ? data.detalle_rendicion_ordenes
    : [];
  const pagosRaw = Array.isArray(data.detalle_rendicion_fpagos)
    ? data.detalle_rendicion_fpagos
    : [];

  return {
    ok: true,
    rendicion: {
      id: data.id,
      cliente_id: data.cliente_id,
      cliente_razon: cliente?.razon_social ?? "â€”",
      fecha_rendicion: data.fecha_rendicion,
      tasa_cambio: data.tasa_cambio != null ? Number(data.tasa_cambio) : null,
      total_efectivo_recaudado: Number(data.total_efectivo_recaudado) || 0,
      total_transferencias_recaudado:
        Number(data.total_transferencias_recaudado) || 0,
      total_recaudado_usd:
        data.total_recaudado_usd != null
          ? Number(data.total_recaudado_usd)
          : null,
      estado: String(data.estado ?? ""),
      observaciones: data.observaciones ?? null,
      auditado_por: data.auditado_por ?? null,
      ordenes: ordenesRaw.map((o) => {
        const ord = joinOne(
          o.ordenes_distribucion as
            | { correlativo: number }
            | { correlativo: number }[]
            | null,
        );
        return {
          id: String(o.id),
          orden_id: String(o.orden_distribucion_id),
          correlativo: ord?.correlativo ?? null,
          recaudado: Number(o.recaudado) || 0,
          recaudado_bs:
            o.recaudado_bs != null ? Number(o.recaudado_bs) : null,
        };
      }),
      pagos: pagosRaw.map((p) => {
        const forma = joinOne(
          p.fpagos as
            | { fpago_concepto: string }
            | { fpago_concepto: string }[]
            | null,
        );
        return {
          id: String(p.id),
          fpago_concepto: forma?.fpago_concepto ?? null,
          monto: Number(p.monto) || 0,
          monto_usd: p.monto_usd != null ? Number(p.monto_usd) : null,
          monto_bs: p.monto_bs != null ? Number(p.monto_bs) : null,
          referencia_bancaria: p.referencia_bancaria ?? null,
        };
      }),
    },
  };
}

export async function aprobarRendicion(
  rendicionId: string,
  userId: string,
): Promise<{ ok: true } | { ok: false; error: string }> {
  const id = rendicionId?.trim();
  if (!id) return { ok: false, error: "ID de Rendición inválido." };

  const { data: actual, error: fetchError } = await supabase
    .from("rendiciones_cuentas")
    .select("id, estado")
    .eq("id", id)
    .maybeSingle();

  if (fetchError) return { ok: false, error: fetchError.message };
  if (!actual) return { ok: false, error: "Rendición no encontrada." };
  if (actual.estado === "aprobada") {
    return { ok: false, error: "La Rendición ya está aprobada." };
  }

  const { error } = await supabase
    .from("rendiciones_cuentas")
    .update({
      estado: "aprobada",
      auditado_por: userId,
    })
    .eq("id", id);

  if (error) return { ok: false, error: error.message };
  return { ok: true };
}

export async function retornaOrdenesPorLiquidar(): Promise<
  | { ok: true; items: OrdenPorLiquidarCliente[] }
  | { ok: false; error: string }
> {
  const { data, error } = await supabase.rpc("retorna_ordenes_por_liquidar");

  if (!error && isRpcSuccess(data)) {
    const rows = unwrapRpcData<unknown[]>(data);
    const list = Array.isArray(rows) ? rows : rows ? [rows] : [];
    const items: OrdenPorLiquidarCliente[] = [];

    for (const raw of list) {
      if (!raw || typeof raw !== "object") continue;
      const r = raw as Record<string, unknown>;
      const clienteId = typeof r.cliente_id === "string" ? r.cliente_id : null;
      if (!clienteId) continue;
      items.push({
        cliente_id: clienteId,
        razon_social: String(r.razon_social ?? "—"),
        rif_nit: String(r.rif_nit ?? "—"),
        dias_vencidos: Math.max(0, Number(r.dias_vencidos ?? 0)),
        cant_ordenes: Math.max(0, Number(r.cant_ordenes ?? 0)),
        monto_por_liquidar: Number(r.monto_por_liquidar ?? 0),
      });
    }

    items.sort((a, b) => b.monto_por_liquidar - a.monto_por_liquidar);
    return { ok: true, items };
  }

  // Fallback local (mismo criterio que web) si el SP falla.
  const local = await retornaOrdenesPorLiquidarLocal();
  if (local.ok) return local;

  return {
    ok: false,
    error:
      error?.message ||
      rpcFailMessage(data, "No se pudieron cargar las órdenes por liquidar."),
  };
}

/** Fallback local solo si falla el SP — sin inventar días vencidos. */
async function retornaOrdenesPorLiquidarLocal(): Promise<
  | { ok: true; items: OrdenPorLiquidarCliente[] }
  | { ok: false; error: string }
> {
  const { data: ordenes, error } = await supabase
    .from("ordenes_distribucion")
    .select(
      `
      id,
      cliente_id,
      total_recaudar_usd,
      clientes(razon_social, rif_nit),
      detalle_distribucion(subtotal_recaudar_usd)
    `,
    )
    .eq("estado", "por_liquidar");

  if (error) return { ok: false, error: error.message };

  type Det = { subtotal_recaudar_usd: number | null };
  type Row = {
    id: string;
    cliente_id: string;
    total_recaudar_usd: number | null;
    clientes:
      | { razon_social: string; rif_nit?: string | null }
      | { razon_social: string; rif_nit?: string | null }[]
      | null;
    detalle_distribucion: Det[] | Det | null;
  };

  const rows = (ordenes ?? []) as Row[];
  const ordenIds = rows.map((o) => o.id);
  const abonosMap = new Map<string, number>();

  if (ordenIds.length) {
    const { data: abonos } = await supabase
      .from("detalle_rendicion_ordenes")
      .select("orden_distribucion_id, recaudado, rendiciones_cuentas(estado)")
      .in("orden_distribucion_id", ordenIds);

    for (const a of abonos ?? []) {
      const rc = Array.isArray(a.rendiciones_cuentas)
        ? a.rendiciones_cuentas[0]
        : a.rendiciones_cuentas;
      if ((rc as { estado?: string } | null)?.estado !== "aprobada") continue;
      const key = a.orden_distribucion_id as string;
      abonosMap.set(key, (abonosMap.get(key) ?? 0) + Number(a.recaudado ?? 0));
    }
  }

  const byCliente = new Map<
    string,
    {
      razon_social: string;
      rif_nit: string;
      cant_ordenes: number;
      monto_por_liquidar: number;
    }
  >();

  for (const od of rows) {
    const cliente = Array.isArray(od.clientes) ? od.clientes[0] : od.clientes;
    const dets = Array.isArray(od.detalle_distribucion)
      ? od.detalle_distribucion
      : od.detalle_distribucion
        ? [od.detalle_distribucion]
        : [];
    const sumUsd = dets.reduce(
      (s, d) => s + Number(d.subtotal_recaudar_usd ?? 0),
      0,
    );
    const montoOrden =
      od.total_recaudar_usd != null && Number(od.total_recaudar_usd) > 0
        ? Number(od.total_recaudar_usd)
        : sumUsd;
    const saldo = Math.max(0, montoOrden - (abonosMap.get(od.id) ?? 0));
    const prev = byCliente.get(od.cliente_id) ?? {
      razon_social: cliente?.razon_social ?? "—",
      rif_nit: cliente?.rif_nit ?? "—",
      cant_ordenes: 0,
      monto_por_liquidar: 0,
    };
    prev.cant_ordenes += 1;
    prev.monto_por_liquidar += Math.round(saldo * 100) / 100;
    byCliente.set(od.cliente_id, prev);
  }

  const items = [...byCliente.entries()].map(([cliente_id, v]) => ({
    cliente_id,
    razon_social: v.razon_social,
    rif_nit: v.rif_nit,
    dias_vencidos: 0,
    cant_ordenes: v.cant_ordenes,
    monto_por_liquidar: Math.round(v.monto_por_liquidar * 100) / 100,
  }));

  items.sort((a, b) => b.monto_por_liquidar - a.monto_por_liquidar);
  return { ok: true, items };
}

export async function reporteFormasPago(input?: {
  fechaDesde?: string | null;
  fechaHasta?: string | null;
  soloBancarios?: boolean;
}): Promise<
  { ok: true; data: ReporteFormasPagoData } | { ok: false; error: string }
> {
  const { data, error } = await supabase.rpc("reporte_formas_pago_rendicion", {
    p_fecha_desde: input?.fechaDesde?.trim() || null,
    p_fecha_hasta: input?.fechaHasta?.trim() || null,
    p_solo_bancarios: input?.soloBancarios === true,
  });

  if (error) return { ok: false, error: error.message };
  if (!isRpcSuccess(data)) {
    return {
      ok: false,
      error: rpcFailMessage(data, "No se pudo generar el reporte."),
    };
  }

  const raw = unwrapRpcData<Record<string, unknown>>(data);
  if (!raw) return { ok: false, error: "Reporte vacío." };

  const movimientosRaw = Array.isArray(raw.movimientos) ? raw.movimientos : [];

  return {
    ok: true,
    data: {
      fecha_desde: String(raw.fecha_desde ?? ""),
      fecha_hasta: String(raw.fecha_hasta ?? ""),
      solo_bancarios: Boolean(raw.solo_bancarios),
      total_registros: Number(raw.total_registros ?? 0),
      monto_total_bs: Number(raw.monto_total_bs ?? 0),
      monto_total_usd: Number(raw.monto_total_usd ?? 0),
      movimientos: movimientosRaw.map((m) => {
        const row = m as Record<string, unknown>;
        return {
          rendicion_id: String(row.rendicion_id ?? ""),
          fecha_rendicion: String(row.fecha_rendicion ?? ""),
          tasa_cambio:
            row.tasa_cambio != null ? Number(row.tasa_cambio) : null,
          cliente_id: String(row.cliente_id ?? ""),
          cliente_nombre: String(row.cliente_nombre ?? "â€”"),
          cliente_rif: String(row.cliente_rif ?? "â€”"),
          fpago_id: String(row.fpago_id ?? ""),
          fpago_concepto: String(row.fpago_concepto ?? "â€”"),
          es_bancario: Boolean(row.es_bancario),
          referencia_bancaria: row.referencia_bancaria
            ? String(row.referencia_bancaria)
            : null,
          cuenta_bancaria: row.cuenta_bancaria
            ? String(row.cuenta_bancaria)
            : null,
          monto_bs: row.monto_bs != null ? Number(row.monto_bs) : null,
          monto_usd: row.monto_usd != null ? Number(row.monto_usd) : null,
        };
      }),
    },
  };
}

