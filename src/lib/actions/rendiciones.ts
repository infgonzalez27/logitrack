"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { getCurrentProfile, getSessionUser } from "@/lib/auth";
import { getRoleNameFromProfile, type RolNombre } from "@/lib/auth/roles";
import { listarCuentasBancariasEmpresaAction } from "@/lib/actions/cuentas-bancarias";
import { callDbProcedure, rpcErrorMessage } from "@/lib/actions/db-rpc";
import { retornaUltimaTasaCambioAction } from "@/lib/actions/tasa-cambio";
import { createClient } from "@/lib/supabase/server";
import {
  convertirBsAUsd,
  convertirUsdABs,
  esFormaPagoEnBs,
} from "@/lib/rendiciones/moneda";
import type { CuentaBancariaEmpresa, Fpago, OrdenPorLiquidarCliente } from "@/types/database";

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function isUuid(value: string): boolean {
  return UUID_RE.test(value.trim());
}

const ROLES_REGISTRAR: RolNombre[] = [
  "admin",
  "gerente",
  "vendedor",
  "cobrador",
];

const ROLES_APROBAR: RolNombre[] = ["admin", "gerente"];

/** Orden pendiente del cliente — §2.24 `solicita_abonos_orden_distribucion`. */
export type OrdenParaRendicion = {
  id: string;
  correlativo: number;
  fecha_despacho: string | null;
  tasa_orden: number | null;
  /** Saldo pendiente USD (monto a cobrar restante). */
  total_recaudar: number;
  total_recaudar_bs: number | null;
  monto_total_orden: number;
  monto_total_orden_bs: number | null;
  abonos_acumulados: number;
  abonos_acumulados_bs: number | null;
  saldo_pendiente: number;
  saldo_pendiente_bs: number | null;
};

export type AbonosClienteResult = {
  cliente_id: string;
  saldo_favor: number;
  saldo_favor_bs: number | null;
  tasa_oficial_actual: number | null;
  ordenes: OrdenParaRendicion[];
};

export type OrdenRendicionInput = {
  orden_id: string;
  /** Recaudado en USD. */
  monto_recaudado: number;
  /** Recaudado en Bs (opcional; DB lo deriva si falta). */
  monto_recaudado_bs?: number | null;
};

export type PagoRendicionInput = {
  fpago_id: string;
  /** Monto ingresado (Bs o USD según `en_bs`). */
  monto: number;
  en_bs?: boolean;
  monto_bs?: number | null;
  monto_usd?: number | null;
  cuenta_bancaria_id?: string | null;
  referencia_bancaria?: string | null;
  /** Texto legado; preferir `cuenta_bancaria_id`. */
  cuenta_bancaria?: string | null;
  capture_url?: string | null;
  fpago_info?: boolean;
};

/** DB-011 — catálogo desde tabla `fpagos`. */
export async function listarFormasPagoAction(): Promise<
  | { ok: true; formas: Fpago[] }
  | { ok: false; error: string }
> {
  const response = await callDbProcedure<Fpago[]>(
    "consulta_registros_formas_pago",
  );

  if (!response.success) {
    return {
      ok: false,
      error: rpcErrorMessage(response, "No se pudieron cargar las formas de pago."),
    };
  }

  const formas = Array.isArray(response.data) ? response.data : [];
  return { ok: true, formas };
}

/** §2.29 — cuentas destino de la empresa (activas para combo de rendición). */
export async function retornaCuentasBancariasEmpresaAction(
  soloActivas = true,
): Promise<
  | { ok: true; cuentas: CuentaBancariaEmpresa[] }
  | { ok: false; error: string }
> {
  return listarCuentasBancariasEmpresaAction(soloActivas);
}

type AbonosOrdenRpc = {
  orden_id: string;
  correlativo: number;
  fecha_despacho?: string | null;
  tasa_orden?: number | null;
  monto_total_orden?: number | null;
  monto_total_orden_bs?: number | null;
  abonos_acumulados?: number | null;
  abonos_acumulados_bs?: number | null;
  saldo_pendiente?: number | null;
  saldo_pendiente_bs?: number | null;
};

type AbonosClienteRpc = {
  cliente_id: string;
  saldo_favor?: number | null;
  saldo_favor_bs?: number | null;
  tasa_oficial_actual?: number | null;
  ordenes?: AbonosOrdenRpc[] | null;
};

function mapAbonosClienteRpc(raw: AbonosClienteRpc): AbonosClienteResult {
  const ordenes: OrdenParaRendicion[] = (raw.ordenes ?? []).map((o) => {
    const saldoPendiente = Number(o.saldo_pendiente ?? 0);
    const saldoPendienteBs =
      o.saldo_pendiente_bs != null ? Number(o.saldo_pendiente_bs) : null;
    return {
      id: o.orden_id,
      correlativo: Number(o.correlativo),
      fecha_despacho: o.fecha_despacho ?? null,
      tasa_orden: o.tasa_orden != null ? Number(o.tasa_orden) : null,
      total_recaudar: saldoPendiente,
      total_recaudar_bs: saldoPendienteBs,
      monto_total_orden: Number(o.monto_total_orden ?? 0),
      monto_total_orden_bs:
        o.monto_total_orden_bs != null ? Number(o.monto_total_orden_bs) : null,
      abonos_acumulados: Number(o.abonos_acumulados ?? 0),
      abonos_acumulados_bs:
        o.abonos_acumulados_bs != null ? Number(o.abonos_acumulados_bs) : null,
      saldo_pendiente: saldoPendiente,
      saldo_pendiente_bs: saldoPendienteBs,
    };
  });

  return {
    cliente_id: raw.cliente_id,
    saldo_favor: Number(raw.saldo_favor ?? 0),
    saldo_favor_bs:
      raw.saldo_favor_bs != null ? Number(raw.saldo_favor_bs) : null,
    tasa_oficial_actual:
      raw.tasa_oficial_actual != null
        ? Number(raw.tasa_oficial_actual)
        : null,
    ordenes,
  };
}

/**
 * Fallback local: evita `od.subtotal_recaudar` (columna inexistente en cabecera).
 * Usa `total_recaudar_usd` / `total_recaudar_bs` de `ordenes_distribucion`.
 */
async function solicitaAbonosOrdenDistribucionLocal(
  clienteId: string,
): Promise<
  { ok: true; data: AbonosClienteResult } | { ok: false; error: string }
> {
  const supabase = await createClient();
  const ultimaTasa = await retornaUltimaTasaCambioAction();
  const tasaOficial =
    ultimaTasa.ok && ultimaTasa.tasa && Number(ultimaTasa.tasa.tasa_cambio) > 0
      ? Number(ultimaTasa.tasa.tasa_cambio)
      : 1;

  const { data: cliente, error: clienteError } = await supabase
    .from("clientes")
    .select("id, saldo_favor")
    .eq("id", clienteId)
    .maybeSingle();

  if (clienteError) {
    // Columna saldo_favor puede no existir aún en algunos entornos.
    const { data: clienteBasico, error: basicoError } = await supabase
      .from("clientes")
      .select("id")
      .eq("id", clienteId)
      .maybeSingle();
    if (basicoError || !clienteBasico) {
      return {
        ok: false,
        error: clienteError.message || "El cliente especificado no existe.",
      };
    }
    // continuar con saldo 0
  } else if (!cliente) {
    return { ok: false, error: "El cliente especificado no existe." };
  }

  const saldoFavor = Number(
    (cliente as { saldo_favor?: number | null } | null)?.saldo_favor ?? 0,
  );

  const { data: ordenesRaw, error: ordenesError } = await supabase
    .from("ordenes_distribucion")
    .select(
      `
      id,
      correlativo,
      fecha_despacho,
      tasa_cambio,
      total_recaudar_usd,
      total_recaudar_bs,
      created_at,
      estado,
      detalle_distribucion(subtotal_recaudar, subtotal_recaudar_usd)
    `,
    )
    .eq("cliente_id", clienteId)
    // Tras radar quedan en `despachada`; `por_liquidar` tras "Aprobar despacho".
    .in("estado", ["despachada", "por_liquidar"])
    .order("created_at", { ascending: true });

  if (ordenesError) {
    return { ok: false, error: ordenesError.message };
  }

  const ordenIds = (ordenesRaw ?? []).map((o) => o.id);
  const abonosByOrden = new Map<
    string,
    { usd: number; bs: number }
  >();

  if (ordenIds.length > 0) {
    const { data: detalles, error: detalleError } = await supabase
      .from("detalle_rendicion_ordenes")
      .select(
        "orden_distribucion_id, recaudado, recaudado_bs, rendiciones_cuentas!inner(estado, tasa_cambio)",
      )
      .in("orden_distribucion_id", ordenIds)
      .eq("rendiciones_cuentas.estado", "aprobada");

    if (detalleError) {
      // Si aún no existe recaudado_bs / join, intentar sin filtro estricto
      const { data: detallesSimple, error: simpleError } = await supabase
        .from("detalle_rendicion_ordenes")
        .select("orden_distribucion_id, recaudado, rendicion_id")
        .in("orden_distribucion_id", ordenIds);

      if (simpleError) {
        return { ok: false, error: detalleError.message };
      }

      const rendicionIds = [
        ...new Set(
          (detallesSimple ?? [])
            .map((d) => d.rendicion_id)
            .filter((x): x is string => !!x),
        ),
      ];
      const aprobadas = new Set<string>();
      if (rendicionIds.length) {
        const { data: rends } = await supabase
          .from("rendiciones_cuentas")
          .select("id, estado")
          .in("id", rendicionIds)
          .eq("estado", "aprobada");
        for (const r of rends ?? []) aprobadas.add(r.id);
      }

      for (const d of detallesSimple ?? []) {
        if (!aprobadas.has(d.rendicion_id)) continue;
        const key = d.orden_distribucion_id;
        const prev = abonosByOrden.get(key) ?? { usd: 0, bs: 0 };
        const usd = Number(d.recaudado ?? 0);
        prev.usd += usd;
        prev.bs += usd * tasaOficial;
        abonosByOrden.set(key, prev);
      }
    } else {
      for (const d of detalles ?? []) {
        const key = d.orden_distribucion_id as string;
        const prev = abonosByOrden.get(key) ?? { usd: 0, bs: 0 };
        const usd = Number(d.recaudado ?? 0);
        const bs =
          d.recaudado_bs != null
            ? Number(d.recaudado_bs)
            : usd * tasaOficial;
        prev.usd += usd;
        prev.bs += bs;
        abonosByOrden.set(key, prev);
      }
    }
  }

  const ordenes: OrdenParaRendicion[] = (ordenesRaw ?? []).map((od) => {
    const tasaOrden =
      od.tasa_cambio != null && Number(od.tasa_cambio) > 0
        ? Number(od.tasa_cambio)
        : tasaOficial;

    const lineas = Array.isArray(od.detalle_distribucion)
      ? od.detalle_distribucion
      : od.detalle_distribucion
        ? [od.detalle_distribucion]
        : [];
    const sumUsdLineas = lineas.reduce(
      (s, l) => s + Number(l.subtotal_recaudar_usd ?? 0),
      0,
    );
    const sumBsLineas = lineas.reduce(
      (s, l) => s + Number(l.subtotal_recaudar ?? 0),
      0,
    );

    const totalUsd =
      od.total_recaudar_usd != null && Number(od.total_recaudar_usd) > 0
        ? Number(od.total_recaudar_usd)
        : sumUsdLineas > 0
          ? sumUsdLineas
          : sumBsLineas > 0 && tasaOrden > 0
            ? Math.round((sumBsLineas / tasaOrden) * 100) / 100
            : 0;
    const totalBs =
      od.total_recaudar_bs != null && Number(od.total_recaudar_bs) > 0
        ? Number(od.total_recaudar_bs)
        : sumBsLineas > 0
          ? sumBsLineas
          : totalUsd * tasaOrden;

    const abonos = abonosByOrden.get(od.id) ?? { usd: 0, bs: 0 };
    const saldoPendiente = Math.max(0, totalUsd - abonos.usd);
    const saldoPendienteBs = Math.max(0, totalBs - abonos.bs);

    return {
      id: od.id,
      correlativo: od.correlativo,
      fecha_despacho: od.fecha_despacho ?? null,
      tasa_orden: tasaOrden,
      total_recaudar: saldoPendiente,
      total_recaudar_bs: saldoPendienteBs,
      monto_total_orden: totalUsd,
      monto_total_orden_bs: totalBs,
      abonos_acumulados: abonos.usd,
      abonos_acumulados_bs: abonos.bs,
      saldo_pendiente: saldoPendiente,
      saldo_pendiente_bs: saldoPendienteBs,
    };
  });

  return {
    ok: true,
    data: {
      cliente_id: clienteId,
      saldo_favor: saldoFavor,
      saldo_favor_bs: saldoFavor * tasaOficial,
      tasa_oficial_actual: tasaOficial,
      ordenes,
    },
  };
}

/** §2.24 — saldo a favor + órdenes por liquidar / despachadas con abonos. */
export async function solicitaAbonosOrdenDistribucionAction(
  clienteId: string,
): Promise<
  { ok: true; data: AbonosClienteResult } | { ok: false; error: string }
> {
  const id = clienteId?.trim();
  if (!id || !isUuid(id)) {
    return { ok: false, error: "Cliente inválido." };
  }

  // Preferir consulta local: el SP aún puede fallar por columnas viejas
  // (`od.subtotal_recaudar`) y solo listaba `por_liquidar`.
  const local = await solicitaAbonosOrdenDistribucionLocal(id);
  if (local.ok) {
    return local;
  }

  const response = await callDbProcedure<AbonosClienteRpc>(
    "solicita_abonos_orden_distribucion",
    { p_cliente_id: id },
  );

  if (response.success && response.data) {
    return { ok: true, data: mapAbonosClienteRpc(response.data) };
  }

  return {
    ok: false,
    error:
      local.error ||
      rpcErrorMessage(
        response,
        "No se pudieron cargar las órdenes del cliente.",
      ),
  };
}

/** @deprecated Preferir `solicitaAbonosOrdenDistribucionAction`. */
export async function listarOrdenesParaRendicionAction(
  clienteId: string,
): Promise<
  | { ok: true; ordenes: OrdenParaRendicion[] }
  | { ok: false; error: string }
> {
  const result = await solicitaAbonosOrdenDistribucionAction(clienteId);
  if (!result.ok) return result;
  return { ok: true, ordenes: result.data.ordenes };
}

/** Sube captura de pago a Storage (bucket `rendiciones-captures`). */
export async function uploadCaptureRendicionAction(
  formData: FormData,
): Promise<{ ok: true; url: string } | { ok: false; error: string }> {
  const user = await getSessionUser();
  if (!user) {
    return { ok: false, error: "No autenticado." };
  }

  const file = formData.get("file");
  if (!(file instanceof File) || file.size === 0) {
    return { ok: false, error: "Selecciona una imagen." };
  }

  if (file.size > 5 * 1024 * 1024) {
    return { ok: false, error: "La imagen no puede superar 5 MB." };
  }

  const ext = file.name.split(".").pop()?.toLowerCase() || "jpg";
  const path = `${user.id}/${Date.now()}.${ext}`;
  const supabase = await createClient();
  const { error } = await supabase.storage
    .from("rendiciones-captures")
    .upload(path, file, {
      cacheControl: "3600",
      upsert: false,
      contentType: file.type || "image/jpeg",
    });

  if (error) {
    return {
      ok: false,
      error:
        error.message.includes("Bucket not found")
          ? "Falta el bucket de Storage `rendiciones-captures`."
          : error.message,
    };
  }

  const { data } = supabase.storage
    .from("rendiciones-captures")
    .getPublicUrl(path);

  return { ok: true, url: data.publicUrl };
}

export async function registrarRendicionCuentasAction(input: {
  cliente_id: string;
  observaciones?: string;
  tasa_cambio?: number | null;
  ordenes: OrdenRendicionInput[];
  pagos: PagoRendicionInput[];
}) {
  const user = await getSessionUser();
  if (!user) {
    return { error: "No autenticado." };
  }

  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);
  if (!rol || !ROLES_REGISTRAR.includes(rol)) {
    return { error: "No tienes permiso para registrar rendiciones." };
  }

  const clienteId = input.cliente_id?.trim();
  if (!clienteId || !isUuid(clienteId)) {
    return { error: "Selecciona un cliente." };
  }

  if (!input.ordenes?.length) {
    return { error: "Agrega al menos una orden a la rendición." };
  }

  if (!input.pagos?.length) {
    return { error: "Agrega al menos una forma de pago." };
  }

  for (let i = 0; i < input.ordenes.length; i++) {
    const orden = input.ordenes[i];
    if (!orden.orden_id || !isUuid(orden.orden_id)) {
      return { error: `Orden #${i + 1}: ID inválido.` };
    }
    if (!Number.isFinite(orden.monto_recaudado) || orden.monto_recaudado <= 0) {
      return { error: `Orden #${i + 1}: el monto recaudado debe ser mayor a 0.` };
    }
  }

  for (let i = 0; i < input.pagos.length; i++) {
    const pago = input.pagos[i];
    if (!pago.fpago_id || !isUuid(pago.fpago_id)) {
      return { error: `Pago #${i + 1}: forma de pago inválida.` };
    }
    if (!Number.isFinite(pago.monto) || pago.monto <= 0) {
      return { error: `Pago #${i + 1}: el monto debe ser mayor a 0.` };
    }
    if (pago.fpago_info === true) {
      if (!pago.referencia_bancaria?.trim()) {
        return {
          error: `Pago #${i + 1}: la referencia bancaria es obligatoria.`,
        };
      }
      if (!pago.cuenta_bancaria_id?.trim() || !isUuid(pago.cuenta_bancaria_id)) {
        return {
          error: `Pago #${i + 1}: selecciona la cuenta bancaria de la empresa.`,
        };
      }
    }
  }

  const formasCatalogo = await listarFormasPagoAction();
  const formasById = new Map(
    (formasCatalogo.ok ? formasCatalogo.formas : []).map((f) => [
      f.fpago_id,
      f,
    ]),
  );

  let tasaDia =
    input.tasa_cambio != null &&
    Number.isFinite(input.tasa_cambio) &&
    input.tasa_cambio > 0
      ? Number(input.tasa_cambio)
      : null;

  if (tasaDia == null) {
    const ultima = await retornaUltimaTasaCambioAction();
    if (ultima.ok && ultima.tasa && Number(ultima.tasa.tasa_cambio) > 0) {
      tasaDia = Number(ultima.tasa.tasa_cambio);
    }
  }

  const necesitaTasa = input.pagos.some((pago) => {
    if (pago.en_bs === true) return true;
    if (pago.en_bs === false) return false;
    const forma = formasById.get(pago.fpago_id.trim());
    return forma ? esFormaPagoEnBs(forma.fpago_concepto) : false;
  });

  if (necesitaTasa && (tasaDia == null || tasaDia <= 0)) {
    return {
      error:
        "No hay tasa del día para convertir pagos en bolívares. Regístrala en Tasas de cambio (BCV).",
      code: "EXCEPCION_TASA_NO_ENCONTRADA",
    };
  }

  const response = await callDbProcedure<{
    rendicion_id: string;
    total_ordenes: number;
    total_pagos: number;
    saldo_favor_generado: number;
    tasa_cambio?: number;
  }>("registrar_rendicion_cuentas", {
    p_cliente_id: clienteId,
    p_observaciones: input.observaciones?.trim() || null,
    p_creado_por: user.id,
    p_tasa_cambio: tasaDia,
    p_ordenes: input.ordenes.map((o) => {
      const usd = o.monto_recaudado;
      const bs =
        o.monto_recaudado_bs != null && Number.isFinite(o.monto_recaudado_bs)
          ? Number(o.monto_recaudado_bs)
          : tasaDia != null
            ? convertirUsdABs(usd, tasaDia)
            : null;
      return {
        orden_id: o.orden_id.trim(),
        monto_recaudado: usd,
        monto_recaudado_bs: bs,
      };
    }),
    p_pagos: input.pagos.map((p) => {
      const forma = formasById.get(p.fpago_id.trim());
      const enBs =
        p.en_bs === true ||
        (p.en_bs !== false &&
          !!forma &&
          esFormaPagoEnBs(forma.fpago_concepto));

      let montoUsd: number;
      let montoBs: number;

      if (enBs) {
        montoBs = p.monto_bs ?? p.monto;
        montoUsd =
          p.monto_usd ??
          (tasaDia != null ? convertirBsAUsd(montoBs, tasaDia) : p.monto);
      } else {
        montoUsd = p.monto_usd ?? p.monto;
        montoBs =
          p.monto_bs ??
          (tasaDia != null ? convertirUsdABs(montoUsd, tasaDia) : 0);
      }

      const cuentaId = p.cuenta_bancaria_id?.trim() || null;

      return {
        fpago_id: p.fpago_id.trim(),
        monto: montoUsd,
        monto_usd: montoUsd,
        monto_bs: montoBs,
        cuenta_bancaria_id: cuentaId,
        referencia_bancaria: p.fpago_info
          ? p.referencia_bancaria?.trim() || null
          : null,
        cuenta_bancaria: p.cuenta_bancaria?.trim() || null,
        capture_url: p.capture_url?.trim() || null,
      };
    }),
  });

  if (!response.success) {
    return {
      error: rpcErrorMessage(response, "No se pudo registrar la rendición."),
      code: response.error?.code,
    };
  }

  const rendicionId = response.data?.rendicion_id;
  revalidatePath("/rendiciones");
  revalidatePath("/ordenes");

  if (rendicionId) {
    redirect(`/rendiciones?ok=${encodeURIComponent(rendicionId)}`);
  }

  return {
    success: true,
    data: response.data,
  };
}

/** Aprueba rendición → trigger DB auto-liquida órdenes asociadas. */
export async function aprobarRendicionAction(rendicionId: string) {
  const id = rendicionId?.trim();
  if (!id || !isUuid(id)) {
    return { error: "ID de rendición inválido." };
  }

  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);
  if (!rol || !ROLES_APROBAR.includes(rol)) {
    return { error: "Solo gerente o admin pueden aprobar recaudaciones." };
  }

  const supabase = await createClient();
  const { data: actual, error: fetchError } = await supabase
    .from("rendiciones_cuentas")
    .select("id, estado")
    .eq("id", id)
    .single();

  if (fetchError || !actual) {
    return { error: "Rendición no encontrada." };
  }

  if (actual.estado === "aprobada") {
    return { error: "La rendición ya está aprobada." };
  }

  const user = await getSessionUser();
  const { error } = await supabase
    .from("rendiciones_cuentas")
    .update({
      estado: "aprobada",
      auditado_por: user?.id ?? null,
    })
    .eq("id", id);

  if (error) {
    return { error: error.message };
  }

  revalidatePath("/rendiciones");
  revalidatePath("/ordenes");
  return { success: true };
}

function mapOrdenPorLiquidar(raw: unknown): OrdenPorLiquidarCliente | null {
  if (!raw || typeof raw !== "object") return null;
  const r = raw as Record<string, unknown>;
  const clienteId =
    typeof r.cliente_id === "string"
      ? r.cliente_id
      : typeof r.id === "string"
        ? r.id
        : null;
  if (!clienteId) return null;
  return {
    cliente_id: clienteId,
    razon_social: String(r.razon_social ?? "—"),
    rif_nit: typeof r.rif_nit === "string" ? r.rif_nit : null,
    dias_vencidos: Number(r.dias_vencidos ?? 0),
    cant_ordenes: Number(r.cant_ordenes ?? 0),
    monto_por_liquidar: Number(r.monto_por_liquidar ?? 0),
  };
}

/** Fallback local si el RPC falla por columnas inexistentes (`subtotal_recaudar`). */
async function retornaOrdenesPorLiquidarLocal(): Promise<OrdenPorLiquidarCliente[]> {
  const supabase = await createClient();
  const { data: ordenes, error } = await supabase
    .from("ordenes_distribucion")
    .select(
      `
      id,
      cliente_id,
      fecha_despacho,
      total_recaudar_usd,
      total_recaudar_bs,
      clientes(razon_social, rif_nit),
      detalle_distribucion(subtotal_recaudar_usd, subtotal_recaudar)
    `,
    )
    .eq("estado", "por_liquidar");

  if (error) {
    console.error("[retornaOrdenesPorLiquidarLocal]", error.message);
    return [];
  }

  type Det = {
    subtotal_recaudar_usd: number | null;
    subtotal_recaudar: number | null;
  };
  type Row = {
    id: string;
    cliente_id: string;
    fecha_despacho: string | null;
    total_recaudar_usd: number | null;
    total_recaudar_bs: number | null;
    clientes:
      | { razon_social: string; rif_nit: string | null }
      | { razon_social: string; rif_nit: string | null }[]
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
      if (!rc || (rc as { estado?: string }).estado !== "aprobada") continue;
      const oid = a.orden_distribucion_id as string;
      abonosMap.set(
        oid,
        (abonosMap.get(oid) ?? 0) + Number(a.recaudado ?? 0),
      );
    }
  }

  const hoy = new Date();
  hoy.setHours(0, 0, 0, 0);

  type Agg = {
    cliente_id: string;
    razon_social: string;
    rif_nit: string | null;
    minFecha: Date | null;
    cant_ordenes: number;
    monto_por_liquidar: number;
  };
  const byCliente = new Map<string, Agg>();

  for (const od of rows) {
    const cliente =
      Array.isArray(od.clientes) ? od.clientes[0] : od.clientes;
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
        : sumUsd > 0
          ? sumUsd
          : Number(od.total_recaudar_bs ?? 0);
    const saldo = Math.max(0, montoOrden - (abonosMap.get(od.id) ?? 0));

    let fecha: Date | null = null;
    if (od.fecha_despacho) {
      const iso = String(od.fecha_despacho).slice(0, 10);
      const [y, m, d] = iso.split("-").map(Number);
      if (y && m && d) fecha = new Date(y, m - 1, d);
    }

    let agg = byCliente.get(od.cliente_id);
    if (!agg) {
      agg = {
        cliente_id: od.cliente_id,
        razon_social: cliente?.razon_social ?? "—",
        rif_nit: cliente?.rif_nit ?? null,
        minFecha: fecha,
        cant_ordenes: 0,
        monto_por_liquidar: 0,
      };
      byCliente.set(od.cliente_id, agg);
    }
    agg.cant_ordenes += 1;
    agg.monto_por_liquidar += saldo;
    if (fecha && (!agg.minFecha || fecha < agg.minFecha)) {
      agg.minFecha = fecha;
    }
  }

  const items: OrdenPorLiquidarCliente[] = [...byCliente.values()].map(
    (a) => {
      let dias = 0;
      if (a.minFecha) {
        dias = Math.max(
          0,
          Math.floor(
            (hoy.getTime() - a.minFecha.getTime()) / (1000 * 60 * 60 * 24),
          ),
        );
      }
      return {
        cliente_id: a.cliente_id,
        razon_social: a.razon_social,
        rif_nit: a.rif_nit,
        dias_vencidos: dias,
        cant_ordenes: a.cant_ordenes,
        monto_por_liquidar: Math.round(a.monto_por_liquidar * 100) / 100,
      };
    },
  );

  items.sort((a, b) => b.dias_vencidos - a.dias_vencidos);
  return items;
}

/** INTEGRACION-RPC §2.32 — cartera de órdenes por liquidar agrupada por cliente. */
export async function retornaOrdenesPorLiquidarAction(): Promise<
  | { ok: true; items: OrdenPorLiquidarCliente[] }
  | { ok: false; error: string; code?: string }
> {
  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);
  if (
    rol !== "admin" &&
    rol !== "gerente" &&
    rol !== "vendedor" &&
    rol !== "cobrador"
  ) {
    return { ok: false, error: "No tienes acceso a órdenes por liquidar." };
  }

  const response = await callDbProcedure<unknown>("retorna_ordenes_por_liquidar");

  if (response.success) {
    const rows = Array.isArray(response.data)
      ? response.data
      : response.data
        ? [response.data]
        : [];
    const items = rows
      .map(mapOrdenPorLiquidar)
      .filter((x): x is OrdenPorLiquidarCliente => x != null);
    return { ok: true, items };
  }

  const local = await retornaOrdenesPorLiquidarLocal();
  if (local.length || response.error?.code === "NETWORK_OR_API_ERROR") {
    return { ok: true, items: local };
  }

  // Si el RPC falló por columna inexistente, el local suele devolver [] o datos.
  return { ok: true, items: local };
}

