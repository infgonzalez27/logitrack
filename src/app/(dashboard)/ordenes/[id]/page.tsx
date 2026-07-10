import { notFound } from "next/navigation";
import { getCurrentProfile, getSessionUser } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { getNombresPerfilByIds } from "@/lib/data/perfiles";
import { createClient } from "@/lib/supabase/server";
import { joinOne } from "@/lib/supabase/join";
import { labelOrdenEstado, labelEstadoEntrega } from "@/lib/constants";
import { formatDate, formatCurrency, formatNumber } from "@/lib/format";
import { PageHeader } from "@/components/layout/page-header";
import { DataTable } from "@/components/ui/data-table";
import { Badge, ordenEstadoTone } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { PrintButton } from "@/components/print/print-button";
import { PrintDocumentHeader } from "@/components/print/print-document-header";
import { OrdenEstadoActions } from "./orden-estado-actions";
import type { OrdenEstado } from "@/types/database";

export default async function OrdenDetallePage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();
  const [user, profile] = await Promise.all([
    getSessionUser(),
    getCurrentProfile(),
  ]);
  const rol = getRoleNameFromProfile(profile);

  const { data: orden } = await supabase
    .from("ordenes_distribucion")
    .select(
      `
      *,
      clientes(razon_social, rif_nit, direccion_fiscal),
      camiones(placa, modelo),
      choferes(perfil_id, cedula_licencia, perfiles_usuario(nombre_completo)),
      detalle_distribucion(*, productos(nombre, unidad_medida, codigo_producto))
    `,
    )
    .eq("id", id)
    .single();

  if (!orden) notFound();

  const cliente = joinOne(orden.clientes);
  const camion = joinOne(orden.camiones);
  const chofer = joinOne(orden.choferes);
  const perfilChofer = joinOne(chofer?.perfiles_usuario);
  const nombresPerfil = orden.chofer_id
    ? await getNombresPerfilByIds([orden.chofer_id])
    : {};
  const choferNombre =
    perfilChofer?.nombre_completo ??
    (orden.chofer_id ? nombresPerfil[orden.chofer_id] : null) ??
    chofer?.cedula_licencia ??
    null;

  const detalle = [...(orden.detalle_distribucion ?? [])].sort(
    (a, b) => (a.secuencia_entrega ?? 0) - (b.secuencia_entrega ?? 0),
  );

  const totalRecaudar = detalle.reduce(
    (sum, linea) => sum + linea.subtotal_recaudar,
    0,
  );

  return (
    <div className="lt-print-document space-y-6">
      <PrintDocumentHeader
        title={`Orden de distribución #${orden.correlativo}`}
        subtitle={`Factura origen: ${orden.factura_origen_numero}`}
        meta={`Estado: ${labelOrdenEstado(orden.estado as OrdenEstado)}`}
      />

      <div className="lt-no-print">
        <PageHeader
          title={`Orden #${orden.correlativo}`}
          description={`Factura origen: ${orden.factura_origen_numero}`}
          action={
            <div className="flex flex-wrap gap-2">
              <PrintButton />
              <OrdenEstadoActions
                ordenId={orden.id}
                estadoActual={orden.estado as OrdenEstado}
                rol={rol}
                esCreador={!!user && orden.creado_por === user.id}
              />
            </div>
          }
        />
      </div>

      <div className="grid gap-4 lg:grid-cols-3">
        <Card title="Estado" className="lt-print-keep-together">
          <Badge tone={ordenEstadoTone(orden.estado)}>
            {labelOrdenEstado(orden.estado as OrdenEstado)}
          </Badge>
          <dl className="mt-4 space-y-2 text-sm">
            <div className="flex justify-between gap-4">
              <dt className="text-lt-text-muted">Creada</dt>
              <dd>{formatDate(orden.created_at)}</dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt className="text-lt-text-muted">Despacho</dt>
              <dd>{formatDate(orden.fecha_despacho)}</dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt className="text-lt-text-muted">Peso total</dt>
              <dd>{formatNumber(orden.peso_total_calculado)} kg</dd>
            </div>
          </dl>
        </Card>

        <Card title="Cliente" className="lt-print-keep-together">
          <p className="font-medium">{cliente?.razon_social}</p>
          <p className="text-sm text-lt-text-muted">{cliente?.rif_nit}</p>
          <p className="mt-2 text-sm">{cliente?.direccion_fiscal}</p>
        </Card>

        <Card title="Logística" className="lt-print-keep-together">
          <dl className="space-y-2 text-sm">
            <div>
              <dt className="text-lt-text-muted">Camión</dt>
              <dd className="font-medium">
                {camion?.placa} — {camion?.modelo}
              </dd>
            </div>
            <div>
              <dt className="text-lt-text-muted">Chofer</dt>
              <dd className="font-medium">{choferNombre ?? "—"}</dd>
            </div>
          </dl>
        </Card>
      </div>

      <Card title="Detalle de distribución" className="lt-print-allow-break">
        <DataTable
          columns={[
            { key: "sec", label: "Sec." },
            { key: "codigo", label: "Código" },
            { key: "producto", label: "Producto" },
            { key: "solicitada", label: "Solicitada" },
            { key: "despachada", label: "Despachada" },
            { key: "unitario", label: "Unit. recaudar" },
            { key: "subtotal", label: "Subtotal" },
            { key: "entrega", label: "Estado entrega" },
          ]}
          rows={detalle.map((linea) => {
            const producto = joinOne(linea.productos);
            return {
              id: linea.id,
              cells: {
                sec: linea.secuencia_entrega ?? "—",
                codigo: producto?.codigo_producto ?? "—",
                producto: producto?.nombre ?? "—",
                solicitada: formatNumber(linea.cantidad_solicitada),
                despachada: formatNumber(linea.cantidad_despachada),
                unitario: formatCurrency(linea.valor_unitario_recaudar),
                subtotal: formatCurrency(linea.subtotal_recaudar),
                entrega: labelEstadoEntrega(linea.estado_entrega),
              },
            };
          })}
        />
        <p className="mt-4 text-right text-sm font-medium">
          Total a recaudar: {formatCurrency(totalRecaudar)}
        </p>
      </Card>
    </div>
  );
}
