"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import {
  finalizarEntregaRadarAction,
  reportarIncidenciaRadarAction,
} from "@/lib/actions/radar";
import { LogiImage } from "@/components/media/logi-image";
import { resolveProductoImage } from "@/lib/product-images";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { formatNumber } from "@/lib/format";
import type { RadarOrden } from "@/types/database";

type ContenedorOption = { id: string; codigo: string; nombre: string };

type RetiroRow = {
  key: string;
  contenedor_id: string;
  cantidad: string;
};

const INCIDENCIA_OPTIONS = [
  { value: "Cliente cerrado", label: "Cliente cerrado" },
  { value: "Dirección incorrecta", label: "Dirección incorrecta" },
  { value: "Cliente no disponible", label: "Cliente no disponible" },
  { value: "Otro", label: "Otro (especificar en notas)" },
];

function deriveLineaEstado(
  asignada: number,
  entregada: number,
): { label: string; tone: "success" | "warning" | "danger" } {
  if (entregada <= 0) return { label: "No entregado", tone: "danger" };
  if (entregada >= asignada) return { label: "Completo", tone: "success" };
  return { label: "Parcial", tone: "warning" };
}

function paradaEstadoLabel(detalles: RadarOrden["detalles"]): {
  label: string;
  tone: "success" | "warning" | "default" | "danger";
} {
  if (!detalles.length) return { label: "Sin líneas", tone: "default" };
  const pendientes = detalles.filter(
    (d) => (d.estado_entrega ?? "pendiente") === "pendiente",
  );
  if (pendientes.length === 0) return { label: "Completado", tone: "success" };
  if (pendientes.length < detalles.length) {
    return { label: "En proceso", tone: "warning" };
  }
  return { label: "Pendiente", tone: "warning" };
}

export function RadarEntregaForm({
  orden,
  contenedores,
  backHref = "/radar",
}: {
  orden: RadarOrden;
  contenedores: ContenedorOption[];
  backHref?: string;
}) {
  const router = useRouter();
  const pendientes = (orden.detalles ?? []).filter(
    (d) => (d.estado_entrega ?? "pendiente") === "pendiente",
  );

  const [cantidades, setCantidades] = useState<Record<string, string>>(() => {
    const init: Record<string, string> = {};
    for (const det of pendientes) {
      init[det.detalle_id] = String(det.cantidad_solicitada ?? 0);
    }
    return init;
  });
  const [retiros, setRetiros] = useState<RetiroRow[]>([]);
  const [notas, setNotas] = useState("");
  const [incidenciaOpen, setIncidenciaOpen] = useState(false);
  const [incidenciaTipo, setIncidenciaTipo] = useState(INCIDENCIA_OPTIONS[0].value);
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  const estadoParada = paradaEstadoLabel(orden.detalles ?? []);

  const totalEntregado = useMemo(
    () =>
      pendientes.reduce(
        (s, d) => s + (Number(cantidades[d.detalle_id]) || 0),
        0,
      ),
    [pendientes, cantidades],
  );
  const totalAsignado = useMemo(
    () =>
      pendientes.reduce((s, d) => s + Number(d.cantidad_solicitada ?? 0), 0),
    [pendientes],
  );
  const totalRetiros = useMemo(
    () => retiros.reduce((s, r) => s + (Number(r.cantidad) || 0), 0),
    [retiros],
  );

  const mapsUrl = orden.cliente.direccion_fiscal
    ? `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(orden.cliente.direccion_fiscal)}`
    : null;

  const contenedorOptions = useMemo(() => {
    const fromCatalog = contenedores.map((c) => ({
      value: c.id,
      label: c.codigo ? `${c.codigo} — ${c.nombre}` : c.nombre,
    }));
    if (fromCatalog.length) return fromCatalog;
    return (orden.saldo_contenedores ?? []).map((c) => ({
      value: c.contenedor_id,
      label: `${c.nombre_contenedor} (saldo ${c.saldo_pendiente})`,
    }));
  }, [contenedores, orden.saldo_contenedores]);

  function setCantidad(detalleId: string, value: number, max: number) {
    const next = Math.max(0, Math.min(max, value));
    setCantidades((prev) => ({ ...prev, [detalleId]: String(next) }));
  }

  function addRetiro() {
    setRetiros((prev) => [
      ...prev,
      {
        key: `r-${Date.now()}-${prev.length}`,
        contenedor_id: contenedorOptions[0]?.value ?? "",
        cantidad: "1",
      },
    ]);
  }

  function patchRetiro(key: string, patch: Partial<RetiroRow>) {
    setRetiros((prev) =>
      prev.map((r) => (r.key === key ? { ...r, ...patch } : r)),
    );
  }

  function removeRetiro(key: string) {
    setRetiros((prev) => prev.filter((r) => r.key !== key));
  }

  async function handleFinalizar(e: React.FormEvent) {
    e.preventDefault();
    setError(null);

    const resumen = `Entregado: ${formatNumber(totalEntregado)} de ${formatNumber(totalAsignado)} items.\nRetirado: ${formatNumber(totalRetiros)} contenedores.\n¿Desea confirmar?`;
    if (typeof window !== "undefined" && !window.confirm(resumen)) {
      return;
    }

    setPending(true);
    const result = await finalizarEntregaRadarAction({
      orden_id: orden.orden_id,
      cliente_id: orden.cliente.id,
      entregas: pendientes.map((det) => ({
        detalle_id: det.detalle_id,
        cantidad_asignada: Number(det.cantidad_solicitada ?? 0),
        cantidad_entregada: Number(cantidades[det.detalle_id] ?? 0),
      })),
      retiros: retiros
        .filter((r) => r.contenedor_id && Number(r.cantidad) > 0)
        .map((r) => ({
          contenedor_id: r.contenedor_id,
          cantidad: Number(r.cantidad),
        })),
      notas,
    });

    if (!result.ok) {
      setError(result.error);
      setPending(false);
      return;
    }

    router.push(backHref);
    router.refresh();
  }

  async function handleIncidencia() {
    setError(null);
    const motivo =
      incidenciaTipo === "Otro"
        ? notas.trim() || "Otro"
        : notas.trim()
          ? `${incidenciaTipo}. ${notas.trim()}`
          : incidenciaTipo;

    if (incidenciaTipo === "Otro" && !notas.trim()) {
      setError("Especifica el motivo de la incidencia en notas.");
      return;
    }

    const ok = window.confirm(
      `Reportar incidencia: "${motivo}".\nSe marcará la parada como no entregada. ¿Continuar?`,
    );
    if (!ok) return;

    setPending(true);
    const result = await reportarIncidenciaRadarAction({
      orden_id: orden.orden_id,
      detalle_ids: pendientes.map((d) => d.detalle_id),
      motivo,
    });

    if (!result.ok) {
      setError(result.error);
      setPending(false);
      return;
    }

    router.push(backHref);
    router.refresh();
  }

  if (pendientes.length === 0) {
    return (
      <div className="space-y-4">
        <Button variant="secondary" href={backHref}>
          Volver a paradas
        </Button>
        <Card className="p-4">
          <p className="text-lg font-semibold text-lt-text">
            {orden.cliente.razon_social}
          </p>
          <p className="mt-2 text-sm text-lt-success-text">
            Entrega registrada. Pendiente de aprobación en almacén.
          </p>
        </Card>
      </div>
    );
  }

  return (
    <form onSubmit={handleFinalizar} className="space-y-4">
      {/* Encabezado */}
      <Card className="p-4">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div className="min-w-0 flex-1">
            <p className="font-display text-2xl leading-tight text-lt-text">
              {orden.cliente.razon_social}
            </p>
            <p className="mt-1 text-sm text-lt-text-muted">
              Orden #{orden.correlativo}
              {orden.cliente.nombre_ruta ? ` · ${orden.cliente.nombre_ruta}` : ""}
            </p>
            {orden.cliente.direccion_fiscal ? (
              <p className="mt-1 text-sm text-lt-text-muted">
                {orden.cliente.direccion_fiscal}
              </p>
            ) : null}
          </div>
          <Badge tone={estadoParada.tone}>{estadoParada.label}</Badge>
        </div>
        <div className="mt-4 flex flex-wrap gap-2">
          <Button type="button" variant="secondary" href={backHref}>
            Volver
          </Button>
          {mapsUrl ? (
            <a
              href={mapsUrl}
              target="_blank"
              rel="noopener noreferrer"
              className="lt-btn inline-flex items-center rounded-xl border border-lt-border px-4 py-2.5 text-sm font-medium text-lt-text hover:bg-lt-surface-muted"
            >
              Navegar
            </a>
          ) : null}
        </div>
      </Card>

      {/* Sección A */}
      <Card className="space-y-3 p-4">
        <div>
          <h3 className="text-base font-semibold text-lt-text">
            Productos a entregar
          </h3>
          <p className="mt-1 text-sm text-lt-text-muted">
            Asignado vs entregado. Por defecto coincide con la salida.
          </p>
        </div>

        {pendientes.map((det) => {
          const asignada = Number(det.cantidad_solicitada ?? 0);
          const entregada = Number(cantidades[det.detalle_id] ?? 0);
          const lineaEstado = deriveLineaEstado(asignada, entregada);
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
                  className="h-[72px] w-[72px] shrink-0 rounded-xl bg-lt-surface-muted object-contain"
                />
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-start justify-between gap-2">
                    <p className="font-medium text-lt-text">
                      {det.nombre_producto}
                    </p>
                    <Badge tone={lineaEstado.tone}>{lineaEstado.label}</Badge>
                  </div>
                  <p className="text-xs text-lt-text-subtle">
                    {det.codigo_producto ?? "Sin código"} · Asignado{" "}
                    {formatNumber(asignada)}
                  </p>
                </div>
              </div>

              <div className="mt-3">
                <p className="mb-1.5 text-sm font-medium text-lt-text">
                  Cantidad entregada
                </p>
                <div className="flex items-center gap-2">
                  <button
                    type="button"
                    className="inline-flex h-11 w-11 items-center justify-center rounded-xl border border-lt-border text-lg font-semibold text-lt-text hover:bg-lt-surface-muted"
                    onClick={() =>
                      setCantidad(det.detalle_id, entregada - 1, asignada)
                    }
                    aria-label="Disminuir"
                  >
                    −
                  </button>
                  <input
                    type="number"
                    min={0}
                    max={asignada}
                    required
                    value={cantidades[det.detalle_id] ?? "0"}
                    onChange={(e) =>
                      setCantidad(
                        det.detalle_id,
                        Number(e.target.value) || 0,
                        asignada,
                      )
                    }
                    className="lt-input w-full max-w-[7rem] text-center text-lg font-semibold"
                  />
                  <button
                    type="button"
                    className="inline-flex h-11 w-11 items-center justify-center rounded-xl border border-lt-border text-lg font-semibold text-lt-text hover:bg-lt-surface-muted"
                    onClick={() =>
                      setCantidad(det.detalle_id, entregada + 1, asignada)
                    }
                    aria-label="Aumentar"
                  >
                    +
                  </button>
                  <button
                    type="button"
                    className="ml-1 text-sm font-medium text-lt-primary"
                    onClick={() =>
                      setCantidad(det.detalle_id, asignada, asignada)
                    }
                  >
                    Todo
                  </button>
                </div>
              </div>
            </div>
          );
        })}
      </Card>

      {/* Sección B */}
      <Card className="space-y-3 p-4">
        <div>
          <h3 className="text-base font-semibold text-lt-text">
            Contenedores a retirar
          </h3>
          <p className="mt-1 text-sm text-lt-text-muted">
            Devoluciones de envases del cliente (independiente de productos).
          </p>
        </div>

        {(orden.saldo_contenedores ?? []).length > 0 ? (
          <p className="rounded-xl bg-lt-surface-muted px-3 py-2 text-sm text-lt-text-muted">
            Saldo pendiente:{" "}
            {(orden.saldo_contenedores ?? [])
              .map((s) => `${s.nombre_contenedor} (${s.saldo_pendiente})`)
              .join(" · ")}
          </p>
        ) : null}

        {retiros.map((row) => (
          <div
            key={row.key}
            className="grid gap-2 rounded-2xl border border-lt-border-light p-3 sm:grid-cols-[1fr_7rem_auto]"
          >
            <Select
              label="Tipo de contenedor"
              options={contenedorOptions}
              value={row.contenedor_id}
              onChange={(e) =>
                patchRetiro(row.key, { contenedor_id: e.target.value })
              }
              required
            />
            <Input
              label="Cantidad"
              type="number"
              min={1}
              required
              value={row.cantidad}
              onChange={(e) =>
                patchRetiro(row.key, { cantidad: e.target.value })
              }
            />
            <div className="flex items-end">
              <Button
                type="button"
                variant="secondary"
                onClick={() => removeRetiro(row.key)}
              >
                Eliminar
              </Button>
            </div>
          </div>
        ))}

        <Button
          type="button"
          variant="secondary"
          onClick={addRetiro}
          disabled={!contenedorOptions.length}
          className="w-full sm:w-auto"
        >
          Añadir retiro
        </Button>

        {!contenedorOptions.length ? (
          <p className="text-sm text-lt-warning-text">
            No hay tipos de contenedores en catálogo.
          </p>
        ) : null}

        <p className="text-sm font-medium text-lt-text">
          Total retiro: {formatNumber(totalRetiros)} contenedores
        </p>
      </Card>

      {/* Sección C */}
      <Card className="space-y-3 p-4">
        <h3 className="text-base font-semibold text-lt-text">
          Finalización de entrega
        </h3>
        <div className="space-y-1.5">
          <label
            htmlFor="notas_entrega"
            className="block text-sm font-medium text-lt-text"
          >
            Notas / observaciones
          </label>
          <textarea
            id="notas_entrega"
            rows={3}
            value={notas}
            onChange={(e) => setNotas(e.target.value)}
            placeholder="Ej. dejó en puerta, cliente pidió parcial…"
            className="lt-input w-full resize-y"
          />
        </div>

        {error ? <p className="lt-alert-error text-sm">{error}</p> : null}

        <Button type="submit" disabled={pending} className="w-full sm:w-auto">
          {pending ? "Guardando…" : "Finalizar entrega y retiro"}
        </Button>

        <div className="border-t border-lt-border pt-3">
          {!incidenciaOpen ? (
            <Button
              type="button"
              variant="secondary"
              disabled={pending}
              onClick={() => setIncidenciaOpen(true)}
            >
              Reportar incidencia
            </Button>
          ) : (
            <div className="space-y-3">
              <Select
                label="Motivo de incidencia"
                options={INCIDENCIA_OPTIONS}
                value={incidenciaTipo}
                onChange={(e) => setIncidenciaTipo(e.target.value)}
              />
              <div className="flex flex-wrap gap-2">
                <Button
                  type="button"
                  disabled={pending}
                  onClick={handleIncidencia}
                >
                  {pending ? "Reportando…" : "Confirmar incidencia"}
                </Button>
                <Button
                  type="button"
                  variant="secondary"
                  disabled={pending}
                  onClick={() => setIncidenciaOpen(false)}
                >
                  Cancelar
                </Button>
              </div>
            </div>
          )}
        </div>
      </Card>
    </form>
  );
}
