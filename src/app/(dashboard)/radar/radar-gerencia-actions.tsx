"use client";

import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";
import { Button } from "@/components/ui/button";
import {
  solicitaAprobarRadarAction,
  solicitaCargarInventarioMovilDesdeAlmacenAction,
  solicitaReversarCargaInventarioMovilAction,
} from "@/lib/actions/radar";

export function RadarGerenciaActions({
  radarId,
  yaAprobado = false,
  cargaInventarioMovil = false,
}: {
  radarId: string;
  yaAprobado?: boolean;
  cargaInventarioMovil?: boolean;
}) {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  if (yaAprobado) {
    return (
      <p className="lt-alert-success text-sm">
        Radar ya aprobado por gerencia.
      </p>
    );
  }

  function onAprobar() {
    const ok = window.confirm(
      "¿Aprobar este radar?\nSe acreditarán vacíos entregados y retirados, se restituirá inventario no despachado (móvil → almacén) y las órdenes de vuelta pasarán a anuladas.",
    );
    if (!ok) return;

    setError(null);
    setSuccess(null);
    startTransition(async () => {
      const result = await solicitaAprobarRadarAction(radarId);
      if (!result.ok) {
        setError(result.error);
        return;
      }
      const d = result.data;
      const entregados =
        d?.contenedores_entregados_procesados ?? d?.contenedores_procesados ?? 0;
      const retirados = d?.contenedores_retirados_procesados ?? 0;
      const anuladas = d?.ordenes_anuladas ?? 0;
      const extra = d
        ? ` Entregados: ${entregados}. Retirados: ${retirados}. Órdenes anuladas: ${anuladas}.`
        : "";
      setSuccess(
        (result.message ?? "Radar aprobado exitosamente.") + extra,
      );
      router.refresh();
    });
  }

  function onCargarCamion() {
    const ok = window.confirm(
      "¿Cargar camión desde el almacén?\nSe descontará el resumen de productos solicitados del almacén, se cargará el inventario móvil y las órdenes pasarán a en tránsito.",
    );
    if (!ok) return;

    setError(null);
    setSuccess(null);
    startTransition(async () => {
      const result =
        await solicitaCargarInventarioMovilDesdeAlmacenAction(radarId);
      if (!result.ok) {
        setError(result.error);
        return;
      }
      const d = result.data;
      const extra = d
        ? ` Productos: ${d.total_productos_cargados ?? 0}. Unidades: ${d.unidades_totales ?? 0}. Órdenes: ${d.ordenes_despachadas ?? 0}.`
        : "";
      setSuccess(
        (result.message ?? "Camión cargado exitosamente.") + extra,
      );
      router.refresh();
    });
  }

  function onReversarInventario() {
    const ok = window.confirm(
      "¿Reversar inventario al almacén?\nSe devolverá la mercancía del camión al almacén y las órdenes en tránsito volverán a aprobada. No se puede reversar si ya hay entregas registradas.",
    );
    if (!ok) return;

    setError(null);
    setSuccess(null);
    startTransition(async () => {
      const result = await solicitaReversarCargaInventarioMovilAction(radarId);
      if (!result.ok) {
        setError(result.error);
        return;
      }
      const d = result.data;
      const extra = d
        ? ` Productos: ${d.total_productos_reversados ?? 0}. Unidades: ${d.unidades_totales ?? 0}. Órdenes: ${d.ordenes_reversadas ?? 0}.`
        : "";
      setSuccess(
        (result.message ?? "Inventario reversado al almacén.") + extra,
      );
      router.refresh();
    });
  }

  return (
    <div className="space-y-2">
      <div className="flex flex-wrap gap-3">
        <Button type="button" disabled={pending} onClick={onAprobar}>
          {pending ? "Procesando…" : "Aprobar radar"}
        </Button>
        <Button
          type="button"
          variant="secondary"
          className="border-lt-primary text-lt-primary hover:bg-lt-primary-muted"
          disabled={pending || cargaInventarioMovil}
          onClick={onCargarCamion}
          title={
            cargaInventarioMovil
              ? "El inventario móvil ya está cargado"
              : undefined
          }
        >
          Cargar camión
        </Button>
        <Button
          type="button"
          variant="secondary"
          className="border-lt-primary text-lt-primary hover:bg-lt-primary-muted"
          disabled={pending || !cargaInventarioMovil}
          onClick={onReversarInventario}
          title={
            !cargaInventarioMovil
              ? "Primero debe cargar el camión"
              : undefined
          }
        >
          Reversar inventario
        </Button>
      </div>
      {cargaInventarioMovil ? (
        <p className="text-sm text-lt-text-muted">
          Inventario móvil cargado. Para editar el radar debe reversar primero.
        </p>
      ) : null}
      {error ? <p className="lt-alert-error text-sm">{error}</p> : null}
      {success ? <p className="lt-alert-success text-sm">{success}</p> : null}
    </div>
  );
}
