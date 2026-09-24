import { cache } from "react";
import { createClient as createSupabaseClient } from "@supabase/supabase-js";
import { createCentralClient, resolveUserEmpresa } from "@/lib/supabase/central";
import { projectRefFromUrl } from "@/lib/tenants/management";
import type { Empresa } from "@/types/database";

export type CurrentTenant = {
  empresaId: string;
  projectRef: string;
  url: string;
  anonKey: string;
};

function centralUrl(): string {
  return (
    process.env.NEXT_PUBLIC_CENTRAL_SUPABASE_URL ||
    process.env.NEXT_PUBLIC_SUPABASE_URL!
  );
}

function sameSupabaseHost(a: string, b: string): boolean {
  try {
    return new URL(a).host === new URL(b).host;
  } catch {
    return a === b;
  }
}

/** null = la empresa no tiene proyecto propio y sus datos viven en Central. */
export function tenantFromEmpresa(
  empresa: Pick<Empresa, "id" | "activo" | "supabase_url" | "supabase_anon_key"> | null | undefined,
): CurrentTenant | null {
  if (
    !empresa?.activo ||
    !empresa.supabase_url ||
    !empresa.supabase_anon_key ||
    sameSupabaseHost(empresa.supabase_url, centralUrl())
  ) {
    return null;
  }

  return {
    empresaId: empresa.id,
    projectRef: projectRefFromUrl(empresa.supabase_url),
    url: empresa.supabase_url,
    anonKey: empresa.supabase_anon_key,
  };
}

/**
 * Tenant lt_* del usuario en sesión según usuarios_empresas (BD Central).
 * null = el usuario trabaja sobre la BD Central (superadmin o sin empresa).
 */
export const getTenantForCurrentUser = cache(
  async (): Promise<CurrentTenant | null> => {
    const central = await createCentralClient();
    const {
      data: { user },
    } = await central.auth.getUser();
    if (!user) return null;

    return tenantFromEmpresa(await resolveUserEmpresa(user.id));
  },
);

/** Cliente de datos del tenant autenticado con el JWT de Central (Third-Party Auth). */
export function createTenantDataClient(
  tenant: CurrentTenant,
  accessToken: () => Promise<string | null>,
) {
  return createSupabaseClient(tenant.url, tenant.anonKey, { accessToken });
}

/**
 * Cliente cuyos datos (from/rpc/storage) van al tenant y cuyo `auth`
 * sigue siendo el de Central, donde viven la sesión y las cuentas.
 */
export function withCentralAuth<T extends object>(dataClient: T, auth: unknown): T {
  return new Proxy(dataClient, {
    get(target, prop) {
      if (prop === "auth") return auth;
      const value = Reflect.get(target, prop, target);
      return typeof value === "function" ? value.bind(target) : value;
    },
  });
}
