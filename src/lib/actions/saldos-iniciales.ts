"use server";

import { revalidatePath } from "next/cache";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { callDbProcedure, rpcErrorMessage } from "@/lib/actions/db-rpc";
import { createClient } from "@/lib/supabase/server";
import { joinOne } from "@/lib/supabase/join";

export type SaldoInicialItem = {
  id: string;
  correlativo: number;
  factura_origen_numero: string;
  fecha_factura: string | null;
  total_recaudar_usd: number;
  estado: string;
  cliente_razon_social: string;
  cliente_rif: string | null;
};

type SaldoInicialRpcData = {
  orden_id: string;
  correlativo: number;
  factura_origen_numero: string;
  total_recaudar_usd: number;
};

async function puedeCargarSaldos(): Promise<boolean> {
  const rol = getRoleNameFromProfile(await getCurrentProfile());
  return rol === "admin" || rol === "gerente";
}

export async function registrarSaldoInicialAction(input: {
  cliente_id: string;
  total_recaudar_usd: number;
  factura_origen_numero: string;
  fecha_factura: string;
}): Promise<
  { ok: true; data: SaldoInicialRpcData } | { ok: false; error: string }
> {
  if (!(await puedeCargarSaldos())) {
    return { ok: false, error: "Solo admin o gerente pueden cargar cuentas iniciales." };
  }

  const res = await callDbProcedure<SaldoInicialRpcData>(
    "registra_saldo_inicial_cliente",
    {
      p_cliente_id: input.cliente_id,
      p_total_recaudar_usd: input.total_recaudar_usd,
      p_factura_origen_numero: input.factura_origen_numero,
      p_fecha_factura: input.fecha_factura || null,
    },
  );

  if (!res.success || !res.data) {
    return { ok: false, error: rpcErrorMessage(res, "No se pudo cargar la cuenta inicial.") };
  }

  revalidatePath("/rendiciones/saldos-iniciales");
  revalidatePath("/rendiciones/por-liquidar");
  return { ok: true, data: res.data };
}

export async function listarSaldosInicialesAction(): Promise<
  { ok: true; items: SaldoInicialItem[] } | { ok: false; error: string }
> {
  if (!(await puedeCargarSaldos())) {
    return { ok: false, error: "Solo admin o gerente pueden ver las cuentas iniciales." };
  }

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("ordenes_distribucion")
    .select(
      "id, correlativo, factura_origen_numero, fecha_despacho, total_recaudar_usd, estado, clientes(razon_social, rif_nit)",
    )
    .eq("es_saldo_inicial", true)
    .order("correlativo", { ascending: false })
    .limit(200);

  if (error) return { ok: false, error: error.message };

  return {
    ok: true,
    items: (data ?? []).map((row) => {
      const cliente = joinOne(
        row.clientes as
          | { razon_social: string; rif_nit: string | null }
          | { razon_social: string; rif_nit: string | null }[]
          | null,
      );
      return {
        id: row.id,
        correlativo: row.correlativo,
        factura_origen_numero: row.factura_origen_numero,
        fecha_factura: row.fecha_despacho,
        total_recaudar_usd: Number(row.total_recaudar_usd ?? 0),
        estado: row.estado,
        cliente_razon_social: cliente?.razon_social ?? "Sin cliente",
        cliente_rif: cliente?.rif_nit ?? null,
      };
    }),
  };
}
