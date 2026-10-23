import { createClient } from "@/lib/supabase/server";
import {
  listarEntidadesBancariasAction,
  listarFormasPagoAction,
  retornaCuentasBancariasEmpresaAction,
} from "@/lib/actions/rendiciones";
import {
  ensureTasaCambioDelDia,
  retornaUltimaTasaCambioAction,
} from "@/lib/actions/tasa-cambio";
import { NuevaRendicionForm } from "./nueva-rendicion-form";

export default async function NuevaRendicionPage({
  searchParams,
}: {
  searchParams: Promise<{ cliente_id?: string; volver?: string }>;
}) {
  const { cliente_id: clienteIdParam, volver } = await searchParams;
  await ensureTasaCambioDelDia();
  const supabase = await createClient();
  const [
    { data: clientes },
    formasResult,
    cuentasResult,
    entidadesResult,
    tasaResult,
  ] = await Promise.all([
    supabase
      .from("clientes")
      .select("id, razon_social, rif_nit")
      .eq("activo", true)
      .order("razon_social"),
    listarFormasPagoAction(),
    retornaCuentasBancariasEmpresaAction(true),
    listarEntidadesBancariasAction(true),
    retornaUltimaTasaCambioAction(),
  ]);

  const volverHref =
    volver && volver.startsWith("/") ? volver : "/rendiciones";

  return (
    <div className="mx-auto max-w-6xl space-y-4">
      <NuevaRendicionForm
        clientes={(clientes ?? []).map((c) => ({
          value: c.id,
          label: c.razon_social,
          codigo: c.rif_nit ?? "",
        }))}
        formasPago={formasResult.ok ? formasResult.formas : []}
        formasError={formasResult.ok ? null : formasResult.error}
        cuentasBancarias={cuentasResult.ok ? cuentasResult.cuentas : []}
        cuentasError={cuentasResult.ok ? null : cuentasResult.error}
        entidadesBancarias={entidadesResult.ok ? entidadesResult.entidades : []}
        tasaDelDia={tasaResult.ok ? tasaResult.tasa : null}
        tasaError={tasaResult.ok ? null : tasaResult.error}
        initialClienteId={clienteIdParam?.trim() || undefined}
        volverHref={volverHref}
      />
    </div>
  );
}
