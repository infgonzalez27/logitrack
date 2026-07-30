"use client";

import { useState, useTransition } from "react";
import {
  eliminaTasaCambioAction,
  insertaTasaCambioAction,
  retornaTasasCambioPorRangoAction,
} from "@/lib/actions/tasa-cambio";
import { obtenerTasaBcvAction } from "@/lib/actions/bcv";
import { formatDateOnly, formatNumber } from "@/lib/format";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Card } from "@/components/ui/card";
import { DataTable } from "@/components/ui/data-table";
import type { TasaCambio } from "@/types/database";

function todayInputValue() {
  const now = new Date();
  const y = now.getFullYear();
  const m = String(now.getMonth() + 1).padStart(2, "0");
  const d = String(now.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

function daysAgoInputValue(days: number) {
  const d = new Date();
  d.setDate(d.getDate() - days);
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

export function TasasCambioClient({
  ultimaInicial,
  puedeGestionar,
}: {
  ultimaInicial: TasaCambio | null;
  puedeGestionar: boolean;
}) {
  const [ultima, setUltima] = useState<TasaCambio | null>(ultimaInicial);
  const [fecha, setFecha] = useState(todayInputValue());
  const [tasa, setTasa] = useState(
    ultimaInicial ? String(ultimaInicial.tasa_cambio) : "",
  );
  const [desde, setDesde] = useState(daysAgoInputValue(30));
  const [hasta, setHasta] = useState(todayInputValue());
  const [historial, setHistorial] = useState<TasaCambio[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [okMsg, setOkMsg] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();
  const [bcvPending, setBcvPending] = useState(false);

  const historialRows = historial.map((row) => ({
    id: row.fecha_tasa,
    cells: {
      fecha: formatDateOnly(row.fecha_tasa),
      tasa: formatNumber(Number(row.tasa_cambio)),
      acciones: puedeGestionar ? (
        <Button
          type="button"
          variant="ghost"
          disabled={pending}
          onClick={() => {
            setError(null);
            setOkMsg(null);
            startTransition(async () => {
              const result = await eliminaTasaCambioAction(row.fecha_tasa);
              if (!result.ok) {
                setError(result.error);
                return;
              }
              setOkMsg(`Tasa del ${row.fecha_tasa} eliminada.`);
              setHistorial((prev) =>
                prev.filter((r) => r.fecha_tasa !== row.fecha_tasa),
              );
              if (ultima?.fecha_tasa === row.fecha_tasa) {
                setUltima(null);
              }
            });
          }}
        >
          Eliminar
        </Button>
      ) : (
        "—"
      ),
    },
  }));

  function registrar(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setOkMsg(null);
    startTransition(async () => {
      const result = await insertaTasaCambioAction({
        fecha_tasa: fecha,
        tasa: Number(tasa),
      });
      if (!result.ok) {
        setError(result.error);
        return;
      }
      setOkMsg(`Tasa registrada: ${result.tasa.fecha_tasa}.`);
      setUltima(result.tasa);
    });
  }

  function consultarRango(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setOkMsg(null);
    startTransition(async () => {
      const result = await retornaTasasCambioPorRangoAction(desde, hasta);
      if (!result.ok) {
        setError(result.error);
        return;
      }
      setHistorial(result.tasas);
      if (result.tasas.length === 0) {
        setOkMsg("No hay tasas en ese rango.");
      }
    });
  }

  async function traerBcv() {
    setError(null);
    setOkMsg(null);
    setBcvPending(true);
    const result = await obtenerTasaBcvAction();
    setBcvPending(false);
    if (!result.ok) {
      setError(result.error);
      return;
    }
    setFecha(result.fecha_tasa);
    setTasa(String(result.tasa));
    setOkMsg(
      `BCV (${result.fuente}): ${formatNumber(result.tasa)}. Confirma y guarda.`,
    );
  }

  return (
    <div className="space-y-6">
      <Card title="Última tasa registrada">
        {ultima ? (
          <dl className="grid gap-3 sm:grid-cols-2 text-sm">
            <div>
              <dt className="text-lt-text-muted">Fecha</dt>
              <dd className="font-medium">{formatDateOnly(ultima.fecha_tasa)}</dd>
            </div>
            <div>
              <dt className="text-lt-text-muted">Tasa Bs / USD</dt>
              <dd className="font-medium text-lg">
                {formatNumber(Number(ultima.tasa_cambio))}
              </dd>
            </div>
          </dl>
        ) : (
          <p className="text-sm text-lt-text-muted">
            Aún no hay tasas. Registra la del día (manual o desde BCV).
          </p>
        )}
      </Card>

      {puedeGestionar ? (
        <Card title="Registrar tasa">
          <form onSubmit={registrar} className="space-y-4">
            <div className="grid gap-3 sm:grid-cols-2">
              <Input
                label="Fecha"
                type="date"
                required
                value={fecha}
                onChange={(e) => setFecha(e.target.value)}
              />
              <Input
                label="Tasa (Bs / USD)"
                type="number"
                min={0}
                step="0.0001"
                required
                value={tasa}
                onChange={(e) => setTasa(e.target.value)}
              />
            </div>
            <p className="text-xs text-lt-text-muted">
              No se permiten fechas duplicadas. Para corregir: elimina la fecha y
              vuelve a insertar.
            </p>
            <div className="flex flex-col gap-2 sm:flex-row">
              <Button type="submit" disabled={pending}>
                {pending ? "Guardando…" : "Guardar tasa"}
              </Button>
              <Button
                type="button"
                variant="secondary"
                disabled={bcvPending || pending}
                onClick={() => void traerBcv()}
              >
                {bcvPending ? "Consultando BCV…" : "Traer tasa BCV"}
              </Button>
            </div>
          </form>
        </Card>
      ) : null}

      <Card title="Histórico por rango">
        <form onSubmit={consultarRango} className="mb-4 space-y-4">
          <div className="grid gap-3 sm:grid-cols-2">
            <Input
              label="Desde"
              type="date"
              required
              value={desde}
              onChange={(e) => setDesde(e.target.value)}
            />
            <Input
              label="Hasta"
              type="date"
              required
              value={hasta}
              onChange={(e) => setHasta(e.target.value)}
            />
          </div>
          <Button type="submit" variant="secondary" disabled={pending}>
            Consultar rango
          </Button>
        </form>
        {historial.length > 0 ? (
          <DataTable
            columns={[
              { key: "fecha", label: "Fecha" },
              { key: "tasa", label: "Tasa" },
              { key: "acciones", label: "Acciones" },
            ]}
            rows={historialRows}
          />
        ) : (
          <p className="text-sm text-lt-text-muted">
            Consulta un rango para ver el historial.
          </p>
        )}
      </Card>

      {error ? <p className="lt-alert-error">{error}</p> : null}
      {okMsg ? <p className="lt-alert-success">{okMsg}</p> : null}
    </div>
  );
}
