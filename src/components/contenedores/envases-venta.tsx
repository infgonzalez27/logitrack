"use client";

import { Input } from "@/components/ui/input";
import { formatNumber } from "@/lib/format";
import type { EnvaseResumenVenta, TipoEnvase } from "@/lib/contenedores/envases-venta";

/** Envases de una venta: entregados calculados, retirados los indica el usuario. */
export function EnvasesVentaFields({
  tipos,
  clienteSeleccionado,
  cargandoSaldos,
  saldos,
  entregados,
  retirados,
  onRetiradosChange,
}: {
  tipos: TipoEnvase[];
  clienteSeleccionado: boolean;
  cargandoSaldos: boolean;
  saldos: Record<string, number> | null;
  entregados: Record<string, number>;
  retirados: Record<string, string>;
  onRetiradosChange: (contenedorId: string, valor: string) => void;
}) {
  return (
    <div className="space-y-3">
      <div>
        <h3 className="text-sm font-semibold text-lt-text">Envases</h3>
        <p className="text-xs text-lt-text-muted">
          Los entregados se calculan con los productos de la venta. Indica solo los vacíos que
          devuelve el cliente.
        </p>
      </div>
      {!clienteSeleccionado ? (
        <p className="text-sm text-lt-text-muted">Selecciona un cliente para ver su saldo de envases.</p>
      ) : cargandoSaldos ? (
        <p className="text-sm text-lt-text-muted">Consultando saldo de envases…</p>
      ) : !tipos.length ? (
        <p className="text-sm text-lt-text-muted">No hay tipos de envase registrados.</p>
      ) : (
        tipos.map((t) => {
          const saldo = saldos?.[t.id] ?? 0;
          const ent = entregados[t.id] ?? 0;
          const ret = Number(retirados[t.id]) || 0;
          const excede = ret > saldo + ent;
          const final = Math.max(0, saldo + ent - ret);
          return (
            <div
              key={t.id}
              className="grid gap-2 rounded-xl border border-lt-border p-3 sm:grid-cols-12 sm:items-end"
            >
              <div className="sm:col-span-4">
                <p className="text-sm font-medium text-lt-text">
                  {t.codigo ? `${t.codigo} — ` : ""}
                  {t.nombre}
                </p>
                <p className="text-xs text-lt-text-muted">
                  Saldo anterior:{" "}
                  <span className="font-semibold text-lt-text">{formatNumber(saldo)}</span>
                </p>
              </div>
              <div className="sm:col-span-2">
                <p className="text-xs text-lt-text-muted">Entregados</p>
                <p className="py-2 text-lg font-semibold tabular-nums text-lt-text">
                  {formatNumber(ent)}
                </p>
              </div>
              <div className="sm:col-span-3">
                <Input
                  label="Retirados"
                  inputMode="numeric"
                  placeholder="0"
                  value={retirados[t.id] ?? ""}
                  onChange={(e) =>
                    onRetiradosChange(t.id, e.target.value.replace(/\D/g, "").slice(0, 6))
                  }
                />
              </div>
              <div className="sm:col-span-3 sm:text-right">
                <p className="text-xs text-lt-text-muted">Saldo actual</p>
                <p
                  className={`text-lg font-bold tabular-nums ${
                    excede ? "text-lt-danger-text" : "text-lt-text"
                  }`}
                >
                  {formatNumber(final)}
                </p>
              </div>
              {excede ? (
                <p className="text-xs text-lt-danger-text sm:col-span-12">
                  Los retirados superan el saldo del cliente más lo entregado; el saldo quedará en 0.
                </p>
              ) : null}
            </div>
          );
        })
      )}
    </div>
  );
}

/** Resumen de envases devuelto por la BD al registrar la venta. */
export function EnvasesResumenTabla({ filas }: { filas: EnvaseResumenVenta[] }) {
  if (!filas.length) return null;
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead>
          <tr className="text-left text-xs text-lt-text-muted">
            <th className="py-1 pr-3 font-medium">Envase</th>
            <th className="py-1 pr-3 text-right font-medium">Saldo anterior</th>
            <th className="py-1 pr-3 text-right font-medium">Entregados</th>
            <th className="py-1 pr-3 text-right font-medium">Retirados</th>
            <th className="py-1 text-right font-medium">Saldo actual</th>
          </tr>
        </thead>
        <tbody>
          {filas.map((f) => (
            <tr key={f.contenedor_id} className="border-t border-lt-border-light">
              <td className="py-1 pr-3">
                {f.codigo ? `${f.codigo} — ` : ""}
                {f.nombre}
              </td>
              <td className="py-1 pr-3 text-right tabular-nums">{formatNumber(f.saldo_anterior)}</td>
              <td className="py-1 pr-3 text-right tabular-nums">{formatNumber(f.entregados)}</td>
              <td className="py-1 pr-3 text-right tabular-nums">{formatNumber(f.retirados)}</td>
              <td className="py-1 text-right font-semibold tabular-nums">
                {formatNumber(f.saldo_actual)}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
