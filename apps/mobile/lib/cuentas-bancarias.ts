import { supabase } from "./supabase";
import { isRpcSuccess, rpcFailMessage, unwrapRpcData } from "./rpc";

export type CuentaBancariaEmpresa = {
  id: string;
  cuenta_bancaria: string;
  entidad_bancaria: string;
  status_cuenta: boolean;
  created_at?: string | null;
};

function mapCuenta(raw: Record<string, unknown>): CuentaBancariaEmpresa | null {
  const id = String(raw.id ?? "");
  if (!id) return null;
  return {
    id,
    cuenta_bancaria: String(
      raw.cuenta_bancaria ?? raw.numero_cuenta ?? "",
    ),
    entidad_bancaria: String(
      raw.entidad_bancaria ?? raw.banco ?? raw.nombre_banco ?? "",
    ),
    status_cuenta:
      raw.status_cuenta === undefined
        ? raw.activa !== false
        : Boolean(raw.status_cuenta),
    created_at: (raw.created_at as string) ?? null,
  };
}

export async function listarCuentasBancariasEmpresa(
  soloActivas = false,
): Promise<
  | { ok: true; cuentas: CuentaBancariaEmpresa[] }
  | { ok: false; error: string }
> {
  const { data, error } = await supabase.rpc(
    "retorna_cuentas_bancarias_empresa",
    { p_solo_activas: soloActivas },
  );

  if (error) {
    let q = supabase
      .from("cuentas_bancarias_empresa")
      .select("id, cuenta_bancaria, entidad_bancaria, status_cuenta, created_at")
      .order("entidad_bancaria");
    if (soloActivas) q = q.eq("status_cuenta", true);
    const fallback = await q;
    if (fallback.error) return { ok: false, error: fallback.error.message };
    return {
      ok: true,
      cuentas: (fallback.data ?? [])
        .map((c) => mapCuenta(c as Record<string, unknown>))
        .filter((c): c is CuentaBancariaEmpresa => c != null),
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
    cuentas: (Array.isArray(rows) ? rows : [])
      .map((c) => mapCuenta(c))
      .filter((c): c is CuentaBancariaEmpresa => c != null),
  };
}

export async function crearCuentaBancariaEmpresa(input: {
  cuenta_bancaria: string;
  entidad_bancaria: string;
}): Promise<
  | { ok: true; cuenta: CuentaBancariaEmpresa }
  | { ok: false; error: string }
> {
  const cuenta = input.cuenta_bancaria.trim();
  const entidad = input.entidad_bancaria.trim();
  if (!cuenta) return { ok: false, error: "El número de cuenta es requerido." };
  if (!entidad) return { ok: false, error: "La entidad bancaria es requerida." };

  const { data, error } = await supabase.rpc("crear_cuenta_bancaria_empresa", {
    p_cuenta_bancaria: cuenta,
    p_entidad_bancaria: entidad,
  });

  if (error) {
    const insert = await supabase
      .from("cuentas_bancarias_empresa")
      .insert({
        cuenta_bancaria: cuenta,
        entidad_bancaria: entidad,
        status_cuenta: true,
      })
      .select("id, cuenta_bancaria, entidad_bancaria, status_cuenta, created_at")
      .single();
    if (insert.error) return { ok: false, error: insert.error.message };
    const mapped = mapCuenta(insert.data as Record<string, unknown>);
    if (!mapped) return { ok: false, error: "No se pudo registrar la cuenta." };
    return { ok: true, cuenta: mapped };
  }

  if (!isRpcSuccess(data)) {
    return {
      ok: false,
      error: rpcFailMessage(data, "No se pudo registrar la cuenta."),
    };
  }

  const row = unwrapRpcData<Record<string, unknown>>(data);
  const mapped = row ? mapCuenta(row) : null;
  if (!mapped) {
    return {
      ok: true,
      cuenta: {
        id: "",
        cuenta_bancaria: cuenta,
        entidad_bancaria: entidad,
        status_cuenta: true,
      },
    };
  }
  return { ok: true, cuenta: mapped };
}

export async function actualizarCuentaBancariaEmpresa(input: {
  id: string;
  cuenta_bancaria?: string | null;
  entidad_bancaria?: string | null;
  status_cuenta?: boolean | null;
}): Promise<
  | { ok: true; cuenta: CuentaBancariaEmpresa }
  | { ok: false; error: string }
> {
  const id = input.id.trim();
  if (!id) return { ok: false, error: "Cuenta inválida." };

  const { data, error } = await supabase.rpc(
    "actualizar_cuenta_bancaria_empresa",
    {
      p_id: id,
      p_cuenta_bancaria: input.cuenta_bancaria?.trim() || null,
      p_entidad_bancaria: input.entidad_bancaria?.trim() || null,
      p_status_cuenta:
        input.status_cuenta === undefined ? null : input.status_cuenta,
    },
  );

  if (error) {
    const patch: Record<string, unknown> = {};
    if (input.cuenta_bancaria != null) {
      patch.cuenta_bancaria = input.cuenta_bancaria.trim();
    }
    if (input.entidad_bancaria != null) {
      patch.entidad_bancaria = input.entidad_bancaria.trim();
    }
    if (input.status_cuenta !== undefined && input.status_cuenta !== null) {
      patch.status_cuenta = input.status_cuenta;
    }
    const upd = await supabase
      .from("cuentas_bancarias_empresa")
      .update(patch)
      .eq("id", id)
      .select("id, cuenta_bancaria, entidad_bancaria, status_cuenta, created_at")
      .single();
    if (upd.error) return { ok: false, error: upd.error.message };
    const mapped = mapCuenta(upd.data as Record<string, unknown>);
    if (!mapped) return { ok: false, error: "No se pudo actualizar." };
    return { ok: true, cuenta: mapped };
  }

  if (!isRpcSuccess(data)) {
    return {
      ok: false,
      error: rpcFailMessage(data, "No se pudo actualizar la cuenta."),
    };
  }

  const row = unwrapRpcData<Record<string, unknown>>(data);
  const mapped = row ? mapCuenta(row) : null;
  if (!mapped) return { ok: false, error: "No se pudo actualizar la cuenta." };
  return { ok: true, cuenta: mapped };
}

export async function toggleCuentaActiva(
  cuenta: CuentaBancariaEmpresa,
): Promise<
  | { ok: true; cuenta: CuentaBancariaEmpresa }
  | { ok: false; error: string }
> {
  return actualizarCuentaBancariaEmpresa({
    id: cuenta.id,
    status_cuenta: !cuenta.status_cuenta,
  });
}
