import { notFound } from "next/navigation";
import { getCurrentProfile, getSessionUser } from "@/lib/auth";
import {
  canEditarOrdenBorrador,
  canRegistrarContenedores,
  canRegistrarEntrega,
} from "@/lib/auth/orden-permissions";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { getOrdenDistribucionDetalle } from "@/lib/data/ordenes";
import { listarTiposContenedoresAction } from "@/lib/actions/ordenes";
import { getNombresPerfilByIds } from "@/lib/data/perfiles";
import { joinOne } from "@/lib/supabase/join";
import { labelOrdenEstado, labelEstadoEntrega } from "@/lib/constants";
import { formatDate, formatCurrency, formatNumber } from "@/lib/format";
import { PageHeader } from "@/components/layout/page-header";
import { DataTable } from "@/components/ui/data-table";
import { Badge, ordenEstadoTone } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { PrintButton } from "@/components/print/print-button";
import { PrintDocumentHeader } from "@/components/print/print-document-header";
import { OrdenEstadoActions } from "./orden-estado-actions";
import { RegistrarEntregaForm } from "./registrar-entrega-form";
import { RegistrarContenedoresForm } from "./registrar-contenedores-form";
import type { OrdenEstado } from "@/types/database";

export default async function OrdenDetallePage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const [user, profile, contenedoresResult] = await Promise.all([
    getSessionUser(),
    getCurrentProfile(),
    listarTiposContenedoresAction(),
  ]);
  const rol = getRoleNameFromProfile(profile);

  const orden = await getOrdenDistribucionDetalle(id, {
    userId: user?.id,
    rol,
  });

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
  const totalBs =
    orden.total_recaudar_bs != null
      ? Number(orden.total_recaudar_bs)
      : totalRecaudar;
  const totalUsd =
    orden.total_recaudar_usd != null
      ? Number(orden.total_recaudar_usd)
      : null;

  const puedeEditar = canEditarOrdenBorrador(rol, orden.estado, {
    esCreador: !!user && orden.creado_por === user.id,
  });
  const puedeRegistrarEntregas =
    canRegistrarEntrega(rol) && orden.estado === "en_transito";
  const lineasPendientes = detalle.filter(
    (linea) => (linea.estado_entrega ?? "pendiente") === "pendiente",
  );
  const puedeRegistrarContenedores =
    canRegistrarContenedores(rol) &&
    (orden.estado === "en_transito" || orden.estado === "por_liquidar");
  const tiposContenedores = contenedoresResult.ok
    ? contenedoresResult.contenedores
    : [];

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
              {puedeEditar ? (
                <Button href={`/ordenes/${orden.id}/editar`} variant="secondary">
                  Editar
                </Button>
              ) : null}
              <PrintButton label="Imprimir orden" />
              <PrintButton
                label="Ticket"
                href={`/ordenes/${orden.id}/imprimir`}
              />
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
            <div className="flex justify-between gap-4">
              <dt className="text-lt-text-muted">Tasa BCV</dt>
              <dd>
                {orden.tasa_cambio != null
                  ? formatNumber(Number(orden.tasa_cambio))
                  : "—"}
              </dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt className="text-lt-text-muted">Total Bs</dt>
              <dd>{formatNumber(totalBs)}</dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt className="text-lt-text-muted">Total USD</dt>
              <dd>
                {totalUsd != null ? formatCurrency(totalUsd) : "—"}
              </dd>
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
          Total a recaudar (Bs): {formatNumber(totalBs)}
          {totalUsd != null ? (
            <>
              {" "}
              · USD: {formatCurrency(totalUsd)}
            </>
          ) : null}
        </p>
      </Card>

      {puedeRegistrarEntregas && lineasPendientes.length > 0 ? (
        <Card title="Registrar entregas en ruta" className="lt-no-print">
          <p className="mb-4 text-sm text-lt-text-muted">
            Registra la entrega en ruta. Cuando todas las líneas queden
            registradas, la orden pasa a <strong>por liquidar</strong>.
          </p>
          <div className="space-y-4">
            {lineasPendientes.map((linea) => {
              const producto = joinOne(linea.productos);
              return (
                <RegistrarEntregaForm
                  key={linea.id}
                  detalleId={linea.id}
                  cantidadSolicitada={linea.cantidad_solicitada}
                  productoNombre={
                    producto?.nombre ??
                    producto?.codigo_producto ??
                    "Producto"
                  }
                />
              );
            })}
          </div>
        </Card>
      ) : null}

      {puedeRegistrarContenedores ? (
        <Card title="Movimiento de contenedores" className="lt-no-print">
          <p className="mb-4 text-sm text-lt-text-muted">
            Al despachar, los vacíos de productos con empaque se acreditan solos
            al cliente. Aquí registra principalmente el{" "}
            <strong>retiro</strong> de envases que el cliente devolvió en ruta
            (también puedes ajustar entregas manualmente).
          </p>
          {!contenedoresResult.ok ? (
            <p className="text-sm text-lt-danger-text">
              {contenedoresResult.error}
            </p>
          ) : (
            <RegistrarContenedoresForm
              ordenId={orden.id}
              clienteId={orden.cliente_id}
              contenedores={tiposContenedores}
            />
          )}
        </Card>
      ) : null}

      {orden.estado === "por_liquidar" ? (
        <p className="lt-no-print text-sm text-lt-text-muted">
          Para liquidar: debe existir una{" "}
          <a href="/rendiciones" className="text-lt-primary underline">
            rendición de cuentas
          </a>{" "}
          vinculada a esta orden y en estado <strong>aprobada</strong>. Luego
          usa el botón <strong>Liquidar (recaudación aprobada)</strong>.
        </p>
      ) : null}
    </div>
  );
}
