import "react-native-url-polyfill/auto";
import AsyncStorage from "@react-native-async-storage/async-storage";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { joinOne } from "./join";

const DEFAULT_SUPABASE_URL = "https://egwryptydgxdnjvwtrfq.supabase.co";
const DEFAULT_SUPABASE_ANON_KEY =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVnd3J5cHR5ZGd4ZG5qdnd0cmZxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI3Mzg3NDQsImV4cCI6MjA5ODMxNDc0NH0.fTPvtapUAyg9CV3L4aLkPMsylhoySkIWqLM-FzRrlhs";

const url = process.env.EXPO_PUBLIC_SUPABASE_URL || DEFAULT_SUPABASE_URL;
const anonKey = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY || DEFAULT_SUPABASE_ANON_KEY;

/** BD Central: sesión, cuentas y a qué empresa pertenece cada usuario. */
const central = createClient(
  url || "https://placeholder.supabase.co",
  anonKey || "placeholder",
  {
    auth: {
      storage: AsyncStorage,
      autoRefreshToken: true,
      persistSession: true,
      detectSessionInUrl: false,
    },
  },
);

export type EmpresaActual = { id: string; codigo: string; nombre: string };

let dataClient: SupabaseClient = central;
let empresaActual: EmpresaActual | null = null;
let resueltoPara: string | null = null;

function sameHost(a: string, b: string): boolean {
  try {
    return new URL(a).host === new URL(b).host;
  } catch {
    return a === b;
  }
}

type EmpresaRow = {
  id: string;
  codigo_empresa: string | null;
  nombre_empresa: string | null;
  activo: boolean;
  supabase_url: string | null;
  supabase_anon_key: string | null;
};

/**
 * Busca en Central la empresa del usuario y apunta los datos a su BD (lt_*).
 * El tenant acepta el JWT de Central (Third-Party Auth), así que RLS y
 * auth.uid() funcionan con la misma sesión.
 */
export async function resolveEmpresa(
  userId: string,
): Promise<{ ok: true; empresa: EmpresaActual | null } | { ok: false; error: string }> {
  if (resueltoPara === userId) return { ok: true, empresa: empresaActual };

  // Un admin con perfil en Central es el superadmin: se queda en Central aunque tenga empresas asignadas.
  const { data: perfilCentral } = await central
    .from("perfiles_usuario")
    .select("roles(nombre)")
    .eq("id", userId)
    .maybeSingle();
  const esSuperadmin =
    joinOne(
      perfilCentral?.roles as { nombre?: string } | { nombre?: string }[] | null | undefined,
    )?.nombre === "admin";

  const { data, error } = esSuperadmin
    ? { data: null, error: null }
    : await central
        .from("usuarios_empresas")
        .select("empresas(id, codigo_empresa, nombre_empresa, activo, supabase_url, supabase_anon_key)")
        .eq("user_id", userId)
        .order("created_at", { ascending: true })
        .limit(1)
        .maybeSingle();
  if (error) {
    return { ok: false, error: `No se pudo leer tu empresa: ${error.message}` };
  }

  const empresa = joinOne(data?.empresas as EmpresaRow | EmpresaRow[] | null | undefined);
  if (empresa && !empresa.activo) {
    return { ok: false, error: "Tu empresa está inactiva. Contacta al administrador." };
  }

  if (
    empresa?.supabase_url &&
    empresa.supabase_anon_key &&
    !sameHost(empresa.supabase_url, url)
  ) {
    dataClient = createClient(empresa.supabase_url, empresa.supabase_anon_key, {
      accessToken: async () =>
        (await central.auth.getSession()).data.session?.access_token ?? null,
    });
  } else {
    dataClient = central;
  }

  empresaActual = empresa
    ? {
        id: empresa.id,
        codigo: empresa.codigo_empresa ?? "",
        nombre: empresa.nombre_empresa ?? "",
      }
    : null;
  resueltoPara = userId;
  return { ok: true, empresa: empresaActual };
}

export function getEmpresaActual(): EmpresaActual | null {
  return empresaActual;
}

export function clearEmpresa(): void {
  dataClient = central;
  empresaActual = null;
  resueltoPara = null;
}

/** `auth` siempre va a Central; from/rpc/storage a la BD de la empresa. */
export const supabase = new Proxy(central, {
  get(target, prop) {
    if (prop === "auth") return target.auth;
    const client = dataClient;
    const value = Reflect.get(client, prop, client);
    return typeof value === "function" ? value.bind(client) : value;
  },
}) as SupabaseClient;
