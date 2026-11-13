/**
 * Cliente mínimo de la Supabase Management API (solo servidor).
 * Env:
 * - SUPABASE_ACCESS_TOKEN (admite un token o varios separados por coma: sbp_1,sbp_2)
 * - SUPABASE_ACCESS_TOKEN_<PROJECT_REF> (opcional, token específico para un proyecto tenant)
 */

function resolveCandidateTokens(pathName: string): string[] {
  const tokens: string[] = [];

  const projMatch = pathName.match(/^\/projects\/([a-z0-9-]+)(?:\/|$)/i);
  if (projMatch) {
    const refUpper = projMatch[1].toUpperCase();
    const refLower = projMatch[1].toLowerCase();
    const specificToken =
      process.env[`SUPABASE_ACCESS_TOKEN_${refUpper}`] ||
      process.env[`SUPABASE_ACCESS_TOKEN_${refLower}`];
    if (specificToken?.trim()) {
      tokens.push(specificToken.trim());
    }
  }

  const rawMain = process.env.SUPABASE_ACCESS_TOKEN ?? "";
  for (const part of rawMain.split(",")) {
    const t = part.trim();
    if (t && !tokens.includes(t)) {
      tokens.push(t);
    }
  }

  const rawExtra = process.env.SUPABASE_TENANT_ACCESS_TOKEN ?? "";
  for (const part of rawExtra.split(",")) {
    const t = part.trim();
    if (t && !tokens.includes(t)) {
      tokens.push(t);
    }
  }

  return tokens;
}

export async function managementFetch(
  pathName: string,
  init?: RequestInit,
): Promise<Response> {
  const tokens = resolveCandidateTokens(pathName);
  if (tokens.length === 0) {
    throw new Error(
      "Falta SUPABASE_ACCESS_TOKEN. El aprovisionamiento de tenants lo configura el admin/Cursor (Management API).",
    );
  }

  let lastRes: Response | null = null;
  for (let i = 0; i < tokens.length; i++) {
    const token = tokens[i];
    const res = await fetch(`https://api.supabase.com/v1${pathName}`, {
      ...init,
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
        ...(init?.headers ?? {}),
      },
      cache: "no-store",
    });

    lastRes = res;
    // Si hay más tokens configurados y este dio 401/403 (otra cuenta de Supabase), probar el siguiente
    if ((res.status === 401 || res.status === 403) && i < tokens.length - 1) {
      continue;
    }
    return res;
  }

  return lastRes!;
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

  const refClean = projectRef.trim().toLowerCase();
  const envKey =
    process.env[`TENANT_SERVICE_ROLE_KEY_${refClean.toUpperCase()}`] ||
    process.env[`SUPABASE_SERVICE_ROLE_KEY_${refClean.toUpperCase()}`] ||
    process.env[`TENANT_SERVICE_KEY_${refClean.toUpperCase()}`] ||
    process.env[`TENANT_SERVICE_ROLE_KEY_${refClean}`] ||
    process.env[`SUPABASE_SERVICE_ROLE_KEY_${refClean}`];

  if (envKey) {
    serviceKeyCache.set(projectRef, envKey);
    return envKey;
  }

  let keys: ApiKey[];
  try {
    keys = await getProjectApiKeys(projectRef);
  } catch (err) {
    throw new Error(
      `No se pudo obtener la service_role key de ${projectRef}. Si el SUPABASE_ACCESS_TOKEN no tiene permisos de organización sobre este tenant, puedes definir TENANT_SERVICE_ROLE_KEY_${refClean.toUpperCase()} en .env.local. Detalle: ${err instanceof Error ? err.message : String(err)}`,
    );
  }

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
