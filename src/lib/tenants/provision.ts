/**
 * Aprovisionamiento de tenant lt_* (lo que el panel Superadmin dispara;
 * URL y anon key no las escribe el usuario — salen del proyecto creado).
 *
 * Requiere en el servidor:
 * - SUPABASE_ACCESS_TOKEN (Management API)
 * - SUPABASE_ORG_ID
 * Región opcional: SUPABASE_TENANT_REGION (default us-east-1)
 */

export type ProvisionTenantResult = {
  projectRef: string;
  projectName: string;
  supabaseUrl: string;
  supabaseAnonKey: string;
};

function normalizeCodigo(codigo: string): string {
  return codigo
    .trim()
    .toLowerCase()
    .replace(/^lt_/, "")
    .replace(/[^a-z0-9_-]/g, "");
}

export function tenantProjectName(codigo: string): string {
  return `lt_${normalizeCodigo(codigo)}`;
}

async function managementFetch(
  path: string,
  init?: RequestInit,
): Promise<Response> {
  const token = process.env.SUPABASE_ACCESS_TOKEN;
  if (!token) {
    throw new Error(
      "Falta SUPABASE_ACCESS_TOKEN. El aprovisionamiento de tenants lo configura el admin/Cursor (Management API).",
    );
  }

  return fetch(`https://api.supabase.com/v1${path}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      ...(init?.headers ?? {}),
    },
  });
}

async function waitUntilActive(projectRef: string, attempts = 40): Promise<void> {
  for (let i = 0; i < attempts; i++) {
    const res = await managementFetch(`/projects/${projectRef}`);
    if (!res.ok) {
      throw new Error(`No se pudo consultar el proyecto ${projectRef}: ${res.status}`);
    }
    const body = (await res.json()) as { status?: string };
    if (body.status === "ACTIVE_HEALTHY" || body.status === "ACTIVE_UNHEALTHY") {
      return;
    }
    await new Promise((r) => setTimeout(r, 5000));
  }
  throw new Error(
    `Timeout esperando que el proyecto ${projectRef} quede activo.`,
  );
}

/**
 * Crea el proyecto Supabase `lt_[codigo]` y devuelve URL + anon key.
 * El clon de esquema (dump/restore o db push) sigue el procedimiento
 * docs/procedimiento_duplicacion_tenant.md — puede ejecutarlo Cursor tras el alta.
 */
export async function provisionTenantProject(
  codigoEmpresa: string,
): Promise<ProvisionTenantResult> {
  const codigo = normalizeCodigo(codigoEmpresa);
  if (!codigo) {
    throw new Error("Código de empresa inválido.");
  }

  const orgId = process.env.SUPABASE_ORG_ID;
  if (!orgId) {
    throw new Error(
      "Falta SUPABASE_ORG_ID. Configúralo para crear proyectos lt_* desde el panel.",
    );
  }

  const region = process.env.SUPABASE_TENANT_REGION || "us-east-1";
  const projectName = tenantProjectName(codigo);

  const createRes = await managementFetch("/projects", {
    method: "POST",
    body: JSON.stringify({
      name: projectName,
      organization_id: orgId,
      region,
      db_pass: crypto.randomUUID().replace(/-/g, "") + "Aa1!",
    }),
  });

  if (!createRes.ok) {
    const text = await createRes.text();
    throw new Error(
      `No se pudo crear el proyecto ${projectName}: ${createRes.status} ${text}`,
    );
  }

  const created = (await createRes.json()) as { id?: string; ref?: string };
  const projectRef = created.ref || created.id;
  if (!projectRef) {
    throw new Error("La API de Supabase no devolvió el ref del proyecto.");
  }

  await waitUntilActive(projectRef);

  const keysRes = await managementFetch(`/projects/${projectRef}/api-keys`);
  if (!keysRes.ok) {
    throw new Error(
      `Proyecto ${projectName} creado, pero no se pudieron leer las API keys.`,
    );
  }

  const keys = (await keysRes.json()) as Array<{
    name?: string;
    api_key?: string;
  }>;
  const anon =
    keys.find((k) => k.name === "anon")?.api_key ||
    keys.find((k) => (k.name ?? "").includes("anon"))?.api_key;

  if (!anon) {
    throw new Error(
      `Proyecto ${projectName} creado, pero no hay anon key disponible.`,
    );
  }

  return {
    projectRef,
    projectName,
    supabaseUrl: `https://${projectRef}.supabase.co`,
    supabaseAnonKey: anon,
  };
}
