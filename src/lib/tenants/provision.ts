/**
 * Aprovisionamiento de tenant lt_* (panel Superadmin):
 * 1) Crea proyecto Supabase vía Management API
 * 2) Inyecta supabase/schema_base.sql en la DB nueva
 * 3) bootstrapTenant: confianza en JWT de Central + catálogos/buckets
 * 4) Devuelve URL + anon key para el catálogo Central
 *
 * Env:
 * - SUPABASE_ACCESS_TOKEN
 * - SUPABASE_ORG_ID
 * - SUPABASE_TENANT_REGION (default us-east-1)
 */

import fs from "fs";
import path from "path";
import { bootstrapTenant } from "@/lib/tenants/bootstrap";
import {
  getProjectApiKeys,
  managementFetch,
  runProjectSql,
} from "@/lib/tenants/management";

export type ProvisionTenantResult = {
  projectRef: string;
  projectName: string;
  supabaseUrl: string;
  supabaseAnonKey: string;
  dbPass: string;
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
 * Aplica el molde public schema al proyecto tenant recién creado.
 * Usa la Management API: el host del pooler (aws-0/aws-1) varía por proyecto
 * y el pooler puede tardar en reconocer un proyecto recién creado.
 */
export async function applySchemaBase(projectRef: string): Promise<void> {
  const sqlScriptPath = path.join(process.cwd(), "supabase", "schema_base.sql");
  if (!fs.existsSync(sqlScriptPath)) {
    throw new Error(
      "Falta supabase/schema_base.sql en el deploy. Genera el dump y súbelo al repo.",
    );
  }

  try {
    await runProjectSql(projectRef, fs.readFileSync(sqlScriptPath, "utf8"));
  } catch (err) {
    throw new Error(
      `Error clonando tablas en ${projectRef}: ${err instanceof Error ? err.message : String(err)}`,
    );
  }
}

/**
 * Crea el proyecto Supabase `lt_[codigo]`, inyecta schema_base.sql y
 * devuelve URL + anon key (+ dbPass por si hace falta reintentar el SQL).
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
  const dbPass = crypto.randomUUID().replace(/-/g, "") + "Aa1!";

  const createRes = await managementFetch("/projects", {
    method: "POST",
    body: JSON.stringify({
      name: projectName,
      organization_id: orgId,
      region,
      db_pass: dbPass,
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

  const keys = await getProjectApiKeys(projectRef);
  const anon =
    keys.find((k) => k.name === "anon")?.api_key ||
    keys.find((k) => (k.name ?? "").includes("anon"))?.api_key;

  if (!anon) {
    throw new Error(
      `Proyecto ${projectName} creado, pero no hay anon key disponible.`,
    );
  }

  await applySchemaBase(projectRef);
  await bootstrapTenant(projectRef);

  return {
    projectRef,
    projectName,
    supabaseUrl: `https://${projectRef}.supabase.co`,
    supabaseAnonKey: anon,
    dbPass,
  };
}
