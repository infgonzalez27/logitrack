"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { getCurrentProfile, getSessionUser } from "@/lib/auth";
import { getRoleNameFromProfile, type RolNombre } from "@/lib/auth/roles";
import { callDbProcedure, rpcErrorMessage } from "@/lib/actions/db-rpc";
import { createClient } from "@/lib/supabase/server";
import type { Fpago } from "@/types/database";

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

export type OrdenParaRendicion = {
  id: string;
  correlativo: number;
  estado: string;
  factura_origen_numero: string;
  total_recaudar: number;
};

export type OrdenRendicionInput = {
  orden_id: string;
  monto_recaudado: number;
};

export type PagoRendicionInput = {
  fpago_id: string;
  monto: number;
  referencia_bancaria?: string | null;
  cuenta_bancaria?: string | null;
  capture_url?: string | null;
  /** Solo para validar en servidor si el front ya conoce fpago_info. */
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

export async function listarOrdenesParaRendicionAction(
  clienteId: string,
): Promise<
  | { ok: true; ordenes: OrdenParaRendicion[] }
  | { ok: false; error: string }
> {
  const id = clienteId?.trim();
  if (!id || !isUuid(id)) {
    return { ok: false, error: "Cliente inválido." };
  }

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("ordenes_distribucion")
    .select(
      `
      id,
      correlativo,
      estado,
      factura_origen_numero,
      detalle_distribucion(subtotal_recaudar)
    `,
    )
    .eq("cliente_id", id)
    .eq("estado", "por_liquidar")
    .order("correlativo", { ascending: false });

  if (error) {
    return { ok: false, error: error.message };
  }

  const ordenes: OrdenParaRendicion[] = (data ?? []).map((orden) => {
    const lineas = Array.isArray(orden.detalle_distribucion)
      ? orden.detalle_distribucion
      : orden.detalle_distribucion
        ? [orden.detalle_distribucion]
        : [];
    const total = lineas.reduce(
      (sum, linea) => sum + Number(linea.subtotal_recaudar ?? 0),
      0,
    );
    return {
      id: orden.id,
      correlativo: orden.correlativo,
      estado: orden.estado,
      factura_origen_numero: orden.factura_origen_numero,
      total_recaudar: total,
    };
  });

  return { ok: true, ordenes };
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
      if (!pago.cuenta_bancaria?.trim()) {
        return {
          error: `Pago #${i + 1}: la cuenta bancaria es obligatoria.`,
        };
      }
    }
  }

  // DB-008 / DB-010 — p_pagos con fpago_id
  const response = await callDbProcedure<{
    rendicion_id: string;
    total_ordenes: number;
    total_pagos: number;
    saldo_favor_generado: number;
  }>("registrar_rendicion_cuentas", {
    p_cliente_id: clienteId,
    p_observaciones: input.observaciones?.trim() || null,
    p_creado_por: user.id,
    p_ordenes: input.ordenes.map((o) => ({
      orden_id: o.orden_id.trim(),
      monto_recaudado: o.monto_recaudado,
    })),
    p_pagos: input.pagos.map((p) => ({
      fpago_id: p.fpago_id.trim(),
      monto: p.monto,
      referencia_bancaria: p.fpago_info
        ? p.referencia_bancaria?.trim() || null
        : null,
      cuenta_bancaria: p.fpago_info
        ? p.cuenta_bancaria?.trim() || null
        : null,
      capture_url: p.capture_url?.trim() || null,
    })),
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
