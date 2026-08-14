"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { registrarDespachoClienteRadarAction } from "@/lib/actions/radar";
import { LogiImage } from "@/components/media/logi-image";
import { resolveProductoImage } from "@/lib/product-images";
import { Badge, ordenEstadoTone } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { labelOrdenEstado } from "@/lib/constants";
import { formatCurrency, formatDate, formatNumber } from "@/lib/format";
import type { OrdenEstado, RadarOrden } from "@/types/database";

const ENTREGA_OPTIONS = [
  { value: "entregado", label: "Entregado" },
  { value: "entregado_parcial", label: "Parcial" },
  { value: "rechazado", label: "Rechazado" },
];

type LineaForm = {
  cantidad: string;
  estado: string;
  motivo: string;
  contenedores: string;
  contenedorId: string;
};

function emptyLinea(orden: RadarOrden, detalleId: string): LineaForm {
  const det = (orden.detalles ?? []).find((d) => d.detalle_id === detalleId);
  const saldoDefault = (orden.saldo_contenedores ?? [])[0]?.contenedor_id ?? "";
  return {
    cantidad: String(det?.cantidad_solicitada ?? 0),
    estado: "entregado",
    motivo: "",
    contenedores: "0",
    contenedorId: det?.contenedor_id ?? saldoDefault,
  };
}

function RadarOrdenCard({ orden }: { orden: RadarOrden }) {
  const router = useRouter();
  const detalles = orden.detalles ?? [];
  const saldos = orden.saldo_contenedores ?? [];
  const pendientes = detalles.filter(
    (d) => (d.estado_entrega ?? "pendiente") === "pendiente",
  );
  const [lineas, setLineas] = useState<Record<string, LineaForm>>(() => {
    const init: Record<string, LineaForm> = {};
    for (const det of pendientes) {
      init[det.detalle_id] = emptyLinea(orden, det.detalle_id);
    }
    return init;
  });
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  const contenedorOptions = useMemo(
    () =>
      saldos.map((c) => ({
        value: c.contenedor_id,
        label: `${c.nombre_contenedor} (saldo ${c.saldo_pendiente})`,
      })),
    [saldos],
  );

  function patchLinea(id: string, patch: Partial<LineaForm>) {
    setLineas((prev) => ({
      ...prev,
      [id]: { ...prev[id], ...patch },
    }));
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setPending(true);
    setError(null);

    const detalles = pendientes.map((det) => {
      const form = lineas[det.detalle_id] ?? emptyLinea(orden, det.detalle_id);
      const cantidad = Number(form.cantidad);
      const contenedores = Number(form.contenedores || 0);
      return {
        detalle_id: det.detalle_id,
        cantidad_despachada: form.estado === "rechazado" ? 0 : cantidad,
        estado_entrega: form.estado,
        motivo_rechazo: form.motivo.trim() || null,
        contenedores_retirados: Number.isFinite(contenedores) ? contenedores : 0,
        contenedor_id: form.contenedorId || null,
      };
    });

    const result = await registrarDespachoClienteRadarAction({
      orden_id: orden.orden_id,
      detalles,
    });

    if (!result.ok) {
      setError(result.error);
      setPending(false);
      return;
    }

    router.refresh();
    setPending(false);
  }

  return (
    <Card>
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className="font-display text-lg text-lt-text">
            #{orden.correlativo} · {orden.cliente.razon_social}
          </p>
          <p className="mt-1 text-sm text-lt-text-muted">
            {orden.cliente.nombre_ruta ?? "Sin ruta"} ·{" "}
            {orden.cliente.rif_nit}
          </p>
          <p className="mt-1 text-sm text-lt-text-muted">
            {orden.cliente.direccion_fiscal ?? "Sin dirección"}
          </p>
          <p className="mt-1 text-sm text-lt-text-muted">
            {orden.cliente.movil1 || orden.cliente.telefono || "Sin teléfono"}
          </p>
        </div>
        <Badge tone={ordenEstadoTone(String(orden.estado))}>
          {labelOrdenEstado(orden.estado as OrdenEstado)}
        </Badge>
      </div>

      <div className="mt-3 flex flex-wrap gap-4 text-sm text-lt-text-muted">
        <span>Despacho: {formatDate(orden.fecha_despacho)}</span>
        <span>
          Total: {formatCurrency(Number(orden.total_recaudar_usd ?? 0))} / Bs{" "}
          {formatNumber(Number(orden.total_recaudar_bs ?? 0))}
        </span>
      </div>

      {pendientes.length === 0 ? (
        <p className="mt-4 text-sm text-lt-success-text">
          Entrega registrada. Pendiente de aprobación en almacén.
        </p>
      ) : (
        <form onSubmit={handleSubmit} className="mt-4 space-y-4">
          {pendientes.map((det) => {
            const form = lineas[det.detalle_id] ?? emptyLinea(orden, det.detalle_id);
            const fallback = resolveProductoImage(det.nombre_producto);
            return (
              <div
                key={det.detalle_id}
                className="rounded-2xl border border-lt-border-light p-3 sm:p-4"
              >
                <div className="flex gap-3">
                  <LogiImage
                    path={det.imagen_path}
                    type="producto"
                    alt={det.nombre_producto}
                    fallbackSrc={fallback}
                    width={72}
                    height={72}
                    className="h-[72px] w-[72px] shrink-0 rounded-xl object-contain bg-lt-surface-muted"
                  />
                  <div className="min-w-0 flex-1">
                    <p className="font-medium text-lt-text">{det.nombre_producto}</p>
                    <p className="text-xs text-lt-text-subtle">
                      {det.codigo_producto ?? "Sin código"} · Pedido{" "}
                      {formatNumber(det.cantidad_solicitada)}
                    </p>
                  </div>
                </div>

                <div className="mt-3 grid gap-3 sm:grid-cols-2">
                  <Input
                    label="Cantidad entregada"
                    type="number"
                    min={0}
                    max={det.cantidad_solicitada}
                    required
                    value={form.cantidad}
                    onChange={(e) =>
                      patchLinea(det.detalle_id, { cantidad: e.target.value })
                    }
                  />
                  <Select
                    label="Resultado"
                    options={ENTREGA_OPTIONS}
                    value={form.estado}
                    onChange={(e) =>
                      patchLinea(det.detalle_id, { estado: e.target.value })
                    }
                  />
                </div>

                {form.estado !== "entregado" ? (
                  <div className="mt-3">
                    <Input
                      label="Motivo"
                      required
                      value={form.motivo}
                      onChange={(e) =>
                        patchLinea(det.detalle_id, { motivo: e.target.value })
                      }
                    />
                  </div>
                ) : null}

                {contenedorOptions.length > 0 ? (
                  <div className="mt-3 grid gap-3 sm:grid-cols-2">
                    <Select
                      label="Envase a retirar"
                      placeholder="Sin retiro"
                      options={contenedorOptions}
                      value={form.contenedorId}
                      onChange={(e) =>
                        patchLinea(det.detalle_id, {
                          contenedorId: e.target.value,
                        })
                      }
                    />
                    <Input
                      label="Cantidad retirada"
                      type="number"
                      min={0}
                      value={form.contenedores}
                      onChange={(e) =>
                        patchLinea(det.detalle_id, {
                          contenedores: e.target.value,
                        })
                      }
                    />
                  </div>
                ) : null}
              </div>
            );
          })}

          {error ? <p className="lt-alert-error">{error}</p> : null}

          <Button type="submit" disabled={pending}>
            {pending ? "Registrando…" : "Registrar despacho"}
          </Button>
        </form>
      )}
    </Card>
  );
}

export function RadarClient({ ordenes }: { ordenes: RadarOrden[] }) {
  if (ordenes.length === 0) {
    return (
      <Card>
        <p className="text-sm text-lt-text-muted">
          No hay despachos en tránsito para tus clientes.
        </p>
      </Card>
    );
  }

  return (
    <div className="space-y-4">
      {ordenes.map((orden) => (
        <RadarOrdenCard key={orden.orden_id} orden={orden} />
      ))}
    </div>
  );
}
