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
import { resolverMontosOrden } from "@/lib/rendiciones/moneda";
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
  const perfilIds = [
    orden.despachador_id,
    orden.chofer_id,
    orden.vendedor_id,
  ].filter((id): id is string => !!id);
  const nombresPerfil = perfilIds.length
    ? await getNombresPerfilByIds(perfilIds)
    : {};
  const choferNombre =
    (orden.despachador_id
      ? nombresPerfil[orden.despachador_id]
      : null) ??
    (orden.chofer_id ? nombresPerfil[orden.chofer_id] : null) ??
    null;

  const detalle = [...(orden.detalle_distribucion ?? [])].sort(
    (a, b) => (a.secuencia_entrega ?? 0) - (b.secuencia_entrega ?? 0),
  );

  const totalRecaudar = detalle.reduce(
    (sum, linea) => sum + Number(linea.subtotal_recaudar ?? 0),
    0,
  );
  const totalRecaudarUsd = detalle.reduce(
    (sum, linea) => sum + Number(linea.subtotal_recaudar_usd ?? 0),
    0,
  );
  const { usd: totalUsd, bs: totalBs } = resolverMontosOrden({
    total_recaudar_usd: orden.total_recaudar_usd,
    total_recaudar_bs: orden.total_recaudar_bs,
    tasa_cambio: orden.tasa_cambio,
    sum_lineas_recaudar: totalRecaudar,
    sum_lineas_usd: totalRecaudarUsd,
  });
  const tasa =
    orden.tasa_cambio != null && Number(orden.tasa_cambio) > 0
      ? Number(orden.tasa_cambio)
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
    rol !== "despachador" &&
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
                {totalUsd > 0 ? formatCurrency(totalUsd) : "—"}
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
              <dt className="text-lt-text-muted">Despachador</dt>
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
            { key: "unitario_usd", label: "Unit. USD" },
            { key: "subtotal_usd", label: "Subtotal USD" },
            { key: "entrega", label: "Estado entrega" },
          ]}
          rows={detalle.map((linea) => {
            const producto = joinOne(linea.productos);
            const { usd: unitUsd } = resolverMontosOrden({
              total_recaudar_bs: linea.valor_unitario_recaudar,
              total_recaudar_usd: linea.valor_unitario_usd,
              tasa_cambio: tasa,
            });
            const { usd: subUsd } = resolverMontosOrden({
              total_recaudar_bs: linea.subtotal_recaudar,
              total_recaudar_usd: linea.subtotal_recaudar_usd,
              tasa_cambio: tasa,
            });
            return {
              id: linea.id,
              cells: {
                sec: linea.secuencia_entrega ?? "—",
                codigo: producto?.codigo_producto ?? "—",
                producto: producto?.nombre ?? "—",
                solicitada: formatNumber(linea.cantidad_solicitada),
                despachada: formatNumber(linea.cantidad_despachada),
                unitario_usd: unitUsd > 0 ? formatCurrency(unitUsd) : "—",
                subtotal_usd: subUsd > 0 ? formatCurrency(subUsd) : "—",
                entrega: labelEstadoEntrega(linea.estado_entrega),
              },
            };
          })}
        />
        <p className="mt-4 text-right text-sm font-medium">
          Total a recaudar (Bs): {formatNumber(totalBs)}
          {totalUsd > 0 ? (
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
            registradas, la orden pasa a <strong>despachada</strong>.
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
          Esta orden se liquida mediante{" "}
          <a href="/rendiciones/nuevo" className="text-lt-primary underline">
            Rendición de cuentas
          </a>
          .
        </p>
      ) : null}
    </div>
  );
}
