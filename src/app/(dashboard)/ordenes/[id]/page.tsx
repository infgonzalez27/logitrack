import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { joinOne } from "@/lib/supabase/join";
import { labelOrdenEstado, labelEstadoEntrega } from "@/lib/constants";
import { formatDate, formatCurrency, formatNumber } from "@/lib/format";
import { PageHeader } from "@/components/layout/page-header";
import { DataTable } from "@/components/ui/data-table";
import { Badge, ordenEstadoTone } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { OrdenEstadoActions } from "./orden-estado-actions";
import type { OrdenEstado } from "@/types/database";

export default async function OrdenDetallePage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();

  const { data: orden } = await supabase
    .from("ordenes_distribucion")
    .select(
      `
      *,
      clientes(razon_social, rif_nit, direccion_fiscal),
      camiones(placa, modelo),
      choferes(perfil_id, cedula_licencia, perfiles_usuario(nombre_completo)),
      detalle_distribucion(*, productos(nombre, unidad_medida))
    `,
    )
    .eq("id", id)
    .single();

  if (!orden) notFound();

  const cliente = joinOne(orden.clientes);
  const camion = joinOne(orden.camiones);
  const chofer = joinOne(orden.choferes);
  const perfilChofer = joinOne(chofer?.perfiles_usuario);

  const detalle = [...(orden.detalle_distribucion ?? [])].sort(
    (a, b) => (a.secuencia_entrega ?? 0) - (b.secuencia_entrega ?? 0),
  );

  const totalRecaudar = detalle.reduce(
    (sum, linea) => sum + linea.subtotal_recaudar,
    0,
  );

  return (
    <div className="space-y-6">
      <PageHeader
        title={`Orden #${orden.correlativo}`}
        description={`Factura origen: ${orden.factura_origen_numero}`}
        action={
          <OrdenEstadoActions
            ordenId={orden.id}
            estadoActual={orden.estado as OrdenEstado}
          />
        }
      />

      <div className="grid gap-4 lg:grid-cols-3">
        <Card title="Estado">
          <Badge tone={ordenEstadoTone(orden.estado)}>
            {labelOrdenEstado(orden.estado as OrdenEstado)}
          </Badge>
          <dl className="mt-4 space-y-2 text-sm">
            <div className="flex justify-between gap-4">
              <dt className="text-zinc-500">Creada</dt>
              <dd>{formatDate(orden.created_at)}</dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt className="text-zinc-500">Despacho</dt>
              <dd>{formatDate(orden.fecha_despacho)}</dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt className="text-zinc-500">Peso total</dt>
              <dd>{formatNumber(orden.peso_total_calculado)} kg</dd>
            </div>
          </dl>
        </Card>

        <Card title="Cliente">
          <p className="font-medium">{cliente?.razon_social}</p>
          <p className="text-sm text-zinc-500">{cliente?.rif_nit}</p>
          <p className="mt-2 text-sm">{cliente?.direccion_fiscal}</p>
        </Card>

        <Card title="Logística">
          <dl className="space-y-2 text-sm">
            <div>
              <dt className="text-zinc-500">Camión</dt>
              <dd className="font-medium">
                {camion?.placa} — {camion?.modelo}
              </dd>
            </div>
            <div>
              <dt className="text-zinc-500">Chofer</dt>
              <dd className="font-medium">
                {perfilChofer?.nombre_completo ?? "—"}
              </dd>
            </div>
          </dl>
        </Card>
      </div>

      <Card title="Detalle de distribución">
        <DataTable
          columns={[
            { key: "sec", label: "Sec." },
            { key: "producto", label: "Producto" },
            { key: "solicitada", label: "Solicitada" },
            { key: "despachada", label: "Despachada" },
            { key: "unitario", label: "Unit. recaudar" },
            { key: "subtotal", label: "Subtotal" },
            { key: "entrega", label: "Estado entrega" },
          ]}
          rows={detalle.map((linea) => ({
            id: linea.id,
            cells: {
              sec: linea.secuencia_entrega ?? "—",
              producto: joinOne(linea.productos)?.nombre ?? "—",
              solicitada: formatNumber(linea.cantidad_solicitada),
              despachada: formatNumber(linea.cantidad_despachada),
              unitario: formatCurrency(linea.valor_unitario_recaudar),
              subtotal: formatCurrency(linea.subtotal_recaudar),
              entrega: labelEstadoEntrega(linea.estado_entrega),
            },
          }))}
        />
        <p className="mt-4 text-right text-sm font-medium">
          Total a recaudar: {formatCurrency(totalRecaudar)}
        </p>
      </Card>
    </div>
  );
}
