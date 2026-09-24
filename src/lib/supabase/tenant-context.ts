import { cache } from "react";
import { createCentralClient, resolveUserEmpresa } from "@/lib/supabase/central";
import { projectRefFromUrl } from "@/lib/tenants/management";

export type CurrentTenant = {
  empresaId: string;
  projectRef: string;
  url: string;
  anonKey: string;
};

function sameSupabaseHost(a: string, b: string): boolean {
  try {
    return new URL(a).host === new URL(b).host;
  } catch {
    return a === b;
  }
}

/**
 * Tenant lt_* del usuario en sesión según usuarios_empresas (BD Central).
 * null = el usuario trabaja sobre la BD Central (superadmin o sin empresa).
 */
export const getTenantForCurrentUser = cache(
  async (): Promise<CurrentTenant | null> => {
    const centralUrl =
      process.env.NEXT_PUBLIC_CENTRAL_SUPABASE_URL ||
      process.env.NEXT_PUBLIC_SUPABASE_URL!;

    const central = await createCentralClient();
    const {
      data: { user },
    } = await central.auth.getUser();
    if (!user) return null;

    const empresa = await resolveUserEmpresa(user.id);
    if (
      !empresa?.activo ||
      !empresa.supabase_url ||
      !empresa.supabase_anon_key ||
      sameSupabaseHost(empresa.supabase_url, centralUrl)
    ) {
      return null;
    }

    return {
      empresaId: empresa.id,
      projectRef: projectRefFromUrl(empresa.supabase_url),
      url: empresa.supabase_url,
      anonKey: empresa.supabase_anon_key,
    };
  },
);

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
