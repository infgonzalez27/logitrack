import { createClient } from "@/lib/supabase/server";
import { PageHeader } from "@/components/layout/page-header";
import { Button } from "@/components/ui/button";
import { ClientesListaClient } from "./clientes-lista-client";
import type { Cliente } from "@/types/database";

export default async function ClientesPage() {
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
        action={<Button href="/clientes/nuevo">Nuevo cliente</Button>}
      />
      <ClientesListaClient clientes={(clientes ?? []) as Cliente[]} />
    </div>
  );
}
