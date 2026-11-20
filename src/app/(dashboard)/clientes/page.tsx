import { createClient } from "@/lib/supabase/server";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { PageHeader } from "@/components/layout/page-header";
import { Button } from "@/components/ui/button";
import { ClientesListaClient } from "./clientes-lista-client";
import type { Cliente } from "@/types/database";

export default async function ClientesPage({
  searchParams,
}: {
  searchParams?: Promise<{ q?: string }>;
}) {
  const [profile, resolvedParams] = await Promise.all([
    getCurrentProfile(),
    searchParams ? searchParams : Promise.resolve({} as { q?: string }),
  ]);
  const isGerente = getRoleNameFromProfile(profile) === "gerente";
  const initialQuery =
    typeof resolvedParams.q === "string" ? resolvedParams.q : "";

  const supabase = await createClient();
  const { data: clientes } = await supabase
    .from("clientes")
    .select("*")
    .order("razon_social");

  return (
    <div className="space-y-6">
      <PageHeader
        title="Clientes"
        description="Módulo 1 — Entidades maestras"
        action={
          <div className="flex flex-wrap items-center gap-2">
            {isGerente ? (
              <Button href="/clientes/descuentos" variant="secondary">
                Descuentos
              </Button>
            ) : null}
            <Button href="/clientes/nuevo">Nuevo cliente</Button>
          </div>
        }
      />
      <ClientesListaClient
        clientes={(clientes ?? []) as Cliente[]}
        initialQuery={initialQuery}
      />
    </div>
  );
}
