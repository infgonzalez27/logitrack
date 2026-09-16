import Link from "next/link";
import { redirect } from "next/navigation";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import {
  listarSaldosContenedores,
  listarTiposContenedoresConsulta,
} from "@/lib/data/contenedores";
import { formatDate, formatNumber } from "@/lib/format";
import { PageHeader } from "@/components/layout/page-header";
import { PrintButton } from "@/components/print/print-button";
import { Card } from "@/components/ui/card";
import { DataTable } from "@/components/ui/data-table";
import { ContenedoresFiltros } from "./contenedores-filtros";

export default async function ConsultaContenedoresPage({
  searchParams,
}: {
  searchParams: Promise<{
    q?: string;
    contenedor?: string;
    todos?: string;
  }>;
}) {
  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);
  if (
    rol !== "admin" &&
    rol !== "gerente" &&
    rol !== "vendedor" &&
    rol !== "cobrador" &&
    rol !== "despachador"
  ) {
    redirect("/");
  }

  const { q = "", contenedor = "", todos } = await searchParams;
  const soloConSaldo = todos !== "1";

  const [tipos, saldos] = await Promise.all([
    listarTiposContenedoresConsulta(),
    listarSaldosContenedores({
      q,
      contenedorId: contenedor.trim() || undefined,
      soloConSaldo,
    }),
  ]);

  const totalPendiente = saldos.reduce((s, r) => s + r.saldo_pendiente, 0);

  return (
    <div className="lt-print-document space-y-6">
      <PageHeader
        title="Consulta de contenedores"
        description="Saldos de vacíos por cliente según el asiento en base de datos."
        action={<PrintButton label="Imprimir" />}
      />

      <Card className="lt-no-print space-y-1 p-4">
        <ContenedoresFiltros
          defaultQ={q}
          defaultContenedorId={contenedor}
          defaultSoloConSaldo={soloConSaldo}
          tipos={tipos.map((t) => ({ value: t.id, label: t.label }))}
        />
      </Card>

      <p className="text-sm text-lt-text-muted">
        {formatNumber(saldos.length)} registro
        {saldos.length === 1 ? "" : "s"} · Saldo total pendiente:{" "}
        <span className="font-semibold text-lt-text">
          {formatNumber(totalPendiente)}
        </span>
      </p>

      <Card>
        <DataTable
          emptyMessage="No hay saldos de contenedores con esos filtros."
          columns={[
            { key: "cliente", label: "Cliente" },
            { key: "rif", label: "RIF/NIT" },
            { key: "contenedor", label: "Contenedor" },
            { key: "saldo", label: "Saldo pendiente" },
            { key: "actualizado", label: "Actualizado" },
            { key: "acciones", label: "" },
          ]}
          rows={saldos.map((row) => ({
            id: row.id,
            cells: {
              cliente: row.cliente_razon,
              rif: row.cliente_rif,
              contenedor: row.contenedor_codigo
                ? `${row.contenedor_codigo} — ${row.contenedor_nombre}`
                : row.contenedor_nombre,
              saldo: (
                <span className="font-medium tabular-nums">
                  {formatNumber(row.saldo_pendiente)}
                </span>
              ),
              actualizado: formatDate(row.updated_at),
              acciones: (
                <Link
                  href={`/contenedores/${row.cliente_id}`}
                  className="lt-no-print text-sm font-medium text-lt-primary underline-offset-2 hover:underline"
                >
                  Ver movimientos
                </Link>
              ),
            },
          }))}
        />
      </Card>
    </div>
  );
}
