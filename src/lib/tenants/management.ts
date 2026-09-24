/**
 * Cliente mínimo de la Supabase Management API (solo servidor).
 * Env: SUPABASE_ACCESS_TOKEN
 */

export async function managementFetch(
  pathName: string,
  init?: RequestInit,
): Promise<Response> {
  const token = process.env.SUPABASE_ACCESS_TOKEN;
  if (!token) {
    throw new Error(
      "Falta SUPABASE_ACCESS_TOKEN. El aprovisionamiento de tenants lo configura el admin/Cursor (Management API).",
    );
  }

  return fetch(`https://api.supabase.com/v1${pathName}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      ...(init?.headers ?? {}),
    },
    cache: "no-store",
  });
}

/** Ejecuta SQL como `postgres` en el proyecto (sin RLS). */
export async function runProjectSql(projectRef: string, query: string): Promise<unknown> {
  const res = await managementFetch(`/projects/${projectRef}/database/query`, {
    method: "POST",
    body: JSON.stringify({ query }),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`SQL en ${projectRef} falló: ${res.status} ${text}`);
  }

  return res.json();
}

type ApiKey = { name?: string; api_key?: string };

export async function getProjectApiKeys(projectRef: string): Promise<ApiKey[]> {
  const res = await managementFetch(`/projects/${projectRef}/api-keys?reveal=true`);
  if (!res.ok) {
    throw new Error(
      `No se pudieron leer las API keys de ${projectRef}: ${res.status}`,
    );
  }
  return (await res.json()) as ApiKey[];
}

const serviceKeyCache = new Map<string, string>();

export async function getTenantServiceKey(projectRef: string): Promise<string> {
  const cached = serviceKeyCache.get(projectRef);
  if (cached) return cached;

  const keys = await getProjectApiKeys(projectRef);
  const serviceKey = keys.find((k) => k.name === "service_role")?.api_key;
  if (!serviceKey) {
    throw new Error(`El proyecto ${projectRef} no tiene service_role key disponible.`);
  }

  serviceKeyCache.set(projectRef, serviceKey);
  return serviceKey;
}

export function projectRefFromUrl(supabaseUrl: string): string {
  return new URL(supabaseUrl).host.split(".")[0];
}
