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

export type VaciosInicialesItem = {
  id: string;
  fecha: string | null;
  cantidad: number;
  contenedor: string;
  cliente_razon_social: string;
  cliente_rif: string | null;
};

type SaldoInicialRpcData = {
  orden_id: string | null;
  correlativo: number | null;
  factura_origen_numero: string | null;
  total_recaudar_usd: number;
  cantidad_contenedores: number;
  saldo_contenedores: number | null;
};

type ClienteJoin =
  | { razon_social: string; rif_nit: string | null }
  | { razon_social: string; rif_nit: string | null }[]
  | null;

async function puedeCargarSaldos(): Promise<boolean> {
  const rol = getRoleNameFromProfile(await getCurrentProfile());
  return rol === "admin" || rol === "gerente";
}

export async function registrarSaldoInicialAction(input: {
  cliente_id: string;
  total_recaudar_usd: number;
  factura_origen_numero: string;
  fecha_factura: string;
  cantidad_contenedores: number;
  contenedor_id: string | null;
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
      p_factura_origen_numero: input.factura_origen_numero || null,
      p_fecha_factura: input.fecha_factura || null,
      p_cantidad_contenedores: input.cantidad_contenedores,
      p_contenedor_id: input.contenedor_id || null,
    },
  );

  if (!res.success || !res.data) {
    return { ok: false, error: rpcErrorMessage(res, "No se pudo cargar la cuenta inicial.") };
  }

  revalidatePath("/rendiciones/saldos-iniciales");
  revalidatePath("/rendiciones/por-liquidar");
  revalidatePath("/contenedores");
  return { ok: true, data: res.data };
}

export async function listarSaldosInicialesAction(): Promise<
  | { ok: true; items: SaldoInicialItem[]; vacios: VaciosInicialesItem[] }
  | { ok: false; error: string }
> {
  if (!(await puedeCargarSaldos())) {
    return { ok: false, error: "Solo admin o gerente pueden ver las cuentas iniciales." };
  }

  const supabase = await createClient();
  const [ordenes, movimientos] = await Promise.all([
    supabase
      .from("ordenes_distribucion")
      .select(
        "id, correlativo, factura_origen_numero, fecha_despacho, total_recaudar_usd, estado, clientes(razon_social, rif_nit)",
      )
      .eq("es_saldo_inicial", true)
      .order("correlativo", { ascending: false })
      .limit(200),
    // Los vacíos iniciales son los únicos movimientos de envases sin orden.
    supabase
      .from("movimientos_contenedores")
      .select(
        "id, created_at, cantidad_entregada, clientes(razon_social, rif_nit), tipos_contenedores(codigo, nombre)",
      )
      .is("orden_id", null)
      .order("created_at", { ascending: false })
      .limit(200),
  ]);

  if (ordenes.error) return { ok: false, error: ordenes.error.message };
  if (movimientos.error) return { ok: false, error: movimientos.error.message };

  return {
    ok: true,
    items: (ordenes.data ?? []).map((row) => {
      const cliente = joinOne(row.clientes as ClienteJoin);
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
    vacios: (movimientos.data ?? []).map((row) => {
      const cliente = joinOne(row.clientes as ClienteJoin);
      const tipo = joinOne(
        row.tipos_contenedores as
          | { codigo: string; nombre: string }
          | { codigo: string; nombre: string }[]
          | null,
      );
      return {
        id: row.id,
        fecha: row.created_at,
        cantidad: Number(row.cantidad_entregada ?? 0),
        contenedor: tipo ? `${tipo.nombre} (${tipo.codigo})` : "—",
        cliente_razon_social: cliente?.razon_social ?? "Sin cliente",
        cliente_rif: cliente?.rif_nit ?? null,
      };
    }),
  };
}
