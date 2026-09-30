"use client";

import { useMemo, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import {
  ClienteCombobox,
  type ClienteComboboxOption,
} from "@/components/clientes/cliente-combobox";
import { registrarMovimientoEspecialAction } from "@/lib/actions/movimientos-inventario";
import {
  MOVIMIENTO_CONCEPTOS,
  type MovimientoInventario,
  type MovimientoTipo,
} from "@/lib/inventario/movimientos-especiales";
import { formatCurrency, formatNumber } from "@/lib/format";

const inputClass =
  "w-full rounded-xl border border-lt-border bg-lt-surface px-3 py-2 text-sm text-lt-text outline-none focus:border-lt-primary focus:ring-2 focus:ring-lt-primary/25";

type Producto = { id: string; nombre: string; codigo: string | null };
type Linea = { productoId: string; cantidad: string; costo: string };

function soloEnteros(valor: string): string {
  return valor.replace(/\D/g, "");
}

function decimal(valor: string): number {
  const n = Number(valor.replace(",", "."));
  return Number.isFinite(n) ? n : NaN;
}

function Opcion({
  activo,
  onClick,
  children,
}: {
  activo: boolean;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`rounded-xl px-3 py-2 text-sm font-medium transition ${
        activo
          ? "bg-lt-primary text-white"
          : "bg-lt-surface-muted text-lt-text hover:bg-lt-primary-muted"
      }`}
    >
      {children}
    </button>
  );
}

export function MovimientoForm({
  productos,
  camiones,
  clientes,
  stockAlmacen,
  stockMovil,
  ultimoCosto,
}: {
  productos: Producto[];
  camiones: Array<{ id: string; label: string }>;
  clientes: ClienteComboboxOption[];
  stockAlmacen: Record<string, number>;
  stockMovil: Record<string, Record<string, number>>;
  ultimoCosto: Record<string, number>;
}) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);

  const [tipo, setTipo] = useState<MovimientoTipo>("SALIDA");
  const [inventario, setInventario] = useState<MovimientoInventario>("ALMACEN");
  const [camionId, setCamionId] = useState("");
  const [concepto, setConcepto] = useState(MOVIMIENTO_CONCEPTOS[0].value);
  const [conceptoOtro, setConceptoOtro] = useState("");
  const [clienteId, setClienteId] = useState("");
  const [observaciones, setObservaciones] = useState("");
  const [lineas, setLineas] = useState<Linea[]>([]);
  const [productoBuscado, setProductoBuscado] = useState("");

  const productosPorId = useMemo(
    () => new Map(productos.map((p) => [p.id, p])),
    [productos],
  );
  const productoOptions = useMemo(
    () =>
      productos
        .filter((p) => !lineas.some((l) => l.productoId === p.id))
        .map((p) => ({ value: p.id, label: p.nombre, hint: p.codigo })),
    [productos, lineas],
  );

  function disponible(productoId: string): number {
    if (inventario === "ALMACEN") return stockAlmacen[productoId] ?? 0;
    return stockMovil[camionId]?.[productoId] ?? 0;
  }

  function agregarProducto(id: string) {
    if (!id) return;
    setLineas((prev) => [
      ...prev,
      { productoId: id, cantidad: "", costo: String(ultimoCosto[id] ?? 0) },
    ]);
    setProductoBuscado("");
  }

  function editarLinea(index: number, cambio: Partial<Linea>) {
    setLineas((prev) => prev.map((l, i) => (i === index ? { ...l, ...cambio } : l)));
  }

  const totalCosto = lineas.reduce((s, l) => {
    const c = decimal(l.costo);
    return s + (Number(l.cantidad) || 0) * (Number.isFinite(c) ? c : 0);
  }, 0);

  const excedidas = tipo === "SALIDA"
    ? lineas.filter((l) => (Number(l.cantidad) || 0) > disponible(l.productoId))
    : [];

  function guardar() {
    setError(null);
    const conceptoFinal = concepto === "OTRO" ? conceptoOtro.trim() : concepto;
    if (!conceptoFinal) return setError("Indica el concepto del movimiento.");
    if (inventario === "MOVIL" && !camionId) return setError("Selecciona el camión.");
    const detalles = lineas
      .map((l) => ({
        producto_id: l.productoId,
        cantidad: Number(l.cantidad) || 0,
        costo_unitario: decimal(l.costo),
      }))
      .filter((d) => d.cantidad > 0);
    if (!detalles.length) {
      return setError("Agrega al menos un producto con cantidad mayor a 0.");
    }
    if (detalles.some((d) => !(d.costo_unitario >= 0))) {
      return setError("Revisa los costos unitarios: deben ser números mayores o iguales a 0.");
    }
    if (excedidas.length) {
      const p = productosPorId.get(excedidas[0].productoId);
      return setError(
        `${p?.nombre ?? "Producto"}: solo hay ${formatNumber(disponible(excedidas[0].productoId))} disponible(s).`,
      );
    }

    const destino =
      inventario === "ALMACEN"
        ? "el almacén"
        : `el camión ${camiones.find((c) => c.id === camionId)?.label ?? ""}`;
    const unidades = detalles.reduce((s, d) => s + d.cantidad, 0);
    if (
      !confirm(
        `¿Registrar ${tipo === "ENTRADA" ? "ENTRADA" : "SALIDA"} de ${formatNumber(unidades)} unidad(es) en ${destino}?`,
      )
    ) {
      return;
    }

    startTransition(async () => {
      const res = await registrarMovimientoEspecialAction({
        tipo,
        concepto: conceptoFinal,
        inventario,
        camionId: inventario === "MOVIL" ? camionId : null,
        clienteId: clienteId || null,
        observaciones,
        detalles,
      });
      if (!res.ok) {
        setError(res.error);
        return;
      }
      router.push("/inventario-movimientos");
      router.refresh();
    });
  }

  return (
    <div className="space-y-4">
      <Card className="space-y-4 p-4">
        <div className="grid gap-4 sm:grid-cols-2">
          <div className="space-y-1.5">
            <p className="text-sm font-medium text-lt-text">Tipo de movimiento</p>
            <div className="flex gap-2">
              <Opcion activo={tipo === "SALIDA"} onClick={() => setTipo("SALIDA")}>
                Salida
              </Opcion>
              <Opcion activo={tipo === "ENTRADA"} onClick={() => setTipo("ENTRADA")}>
                Entrada
              </Opcion>
            </div>
          </div>
          <div className="space-y-1.5">
            <p className="text-sm font-medium text-lt-text">Inventario afectado</p>
            <div className="flex gap-2">
              <Opcion
                activo={inventario === "ALMACEN"}
                onClick={() => setInventario("ALMACEN")}
              >
                Almacén
              </Opcion>
              <Opcion
                activo={inventario === "MOVIL"}
                onClick={() => setInventario("MOVIL")}
              >
                Camión
              </Opcion>
            </div>
          </div>
        </div>

        {inventario === "MOVIL" ? (
          <div className="space-y-1.5">
            <label className="block text-sm font-medium text-lt-text">Camión</label>
            <select
              value={camionId}
              onChange={(e) => setCamionId(e.target.value)}
              className={inputClass}
            >
              <option value="">Selecciona un camión…</option>
              {camiones.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.label}
                </option>
              ))}
            </select>
          </div>
        ) : null}

        <div className="grid gap-4 sm:grid-cols-2">
          <div className="space-y-1.5">
            <label className="block text-sm font-medium text-lt-text">Concepto</label>
            <select
              value={concepto}
              onChange={(e) => setConcepto(e.target.value)}
              className={inputClass}
            >
              {MOVIMIENTO_CONCEPTOS.map((c) => (
                <option key={c.value} value={c.value}>
                  {c.label}
                </option>
              ))}
              <option value="OTRO">Otro…</option>
            </select>
            {concepto === "OTRO" ? (
              <input
                value={conceptoOtro}
                onChange={(e) => setConceptoOtro(e.target.value)}
                maxLength={100}
                placeholder="Escribe el concepto"
                className={inputClass}
              />
            ) : null}
          </div>
          <ClienteCombobox
            label="Cliente (opcional)"
            options={clientes}
            value={clienteId}
            onChange={setClienteId}
            minChars={2}
          />
        </div>

        <div className="space-y-1.5">
          <label className="block text-sm font-medium text-lt-text">Observaciones</label>
          <textarea
            value={observaciones}
            onChange={(e) => setObservaciones(e.target.value)}
            rows={2}
            className={inputClass}
          />
        </div>
      </Card>

      <Card className="space-y-4 p-4">
        <h2 className="text-base font-semibold text-lt-text">Productos</h2>
        {inventario === "MOVIL" && !camionId ? (
          <p className="text-sm text-lt-text-muted">
            Selecciona el camión para ver su disponible.
          </p>
        ) : null}
        <ClienteCombobox
          label="Agregar producto"
          placeholder="Buscar producto por nombre o código…"
          emptyMessage="Sin productos que coincidan."
          options={productoOptions}
          value={productoBuscado}
          onChange={agregarProducto}
        />

        {lineas.length ? (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-lt-border text-left text-lt-text-muted">
                  <th className="px-2 py-2 font-medium">Producto</th>
                  <th className="px-2 py-2 text-right font-medium">Disponible</th>
                  <th className="px-2 py-2 text-right font-medium">Cantidad</th>
                  <th className="px-2 py-2 text-right font-medium">Costo unit.</th>
                  <th className="px-2 py-2 text-right font-medium">Subtotal</th>
                  <th className="px-2 py-2" />
                </tr>
              </thead>
              <tbody>
                {lineas.map((l, i) => {
                  const p = productosPorId.get(l.productoId);
                  const disp = disponible(l.productoId);
                  const cant = Number(l.cantidad) || 0;
                  const costo = decimal(l.costo);
                  const excede = tipo === "SALIDA" && cant > disp;
                  return (
                    <tr key={l.productoId} className="border-b border-lt-border-light">
                      <td className="px-2 py-2">
                        <p className="font-medium text-lt-text">{p?.nombre ?? "—"}</p>
                        {p?.codigo ? (
                          <p className="text-xs text-lt-text-muted">{p.codigo}</p>
                        ) : null}
                      </td>
                      <td className="px-2 py-2 text-right tabular-nums">
                        {formatNumber(disp)}
                      </td>
                      <td className="px-2 py-2 text-right">
                        <input
                          inputMode="numeric"
                          value={l.cantidad}
                          onChange={(e) =>
                            editarLinea(i, { cantidad: soloEnteros(e.target.value) })
                          }
                          className={`${inputClass} w-24 text-right ${
                            excede ? "border-lt-danger-text" : ""
                          }`}
                        />
                      </td>
                      <td className="px-2 py-2 text-right">
                        <input
                          inputMode="decimal"
                          value={l.costo}
                          onChange={(e) => editarLinea(i, { costo: e.target.value })}
                          className={`${inputClass} w-28 text-right`}
                        />
                      </td>
                      <td className="px-2 py-2 text-right tabular-nums">
                        {formatCurrency(cant * (Number.isFinite(costo) ? costo : 0))}
                      </td>
                      <td className="px-2 py-2 text-right">
                        <button
                          type="button"
                          onClick={() =>
                            setLineas((prev) => prev.filter((_, j) => j !== i))
                          }
                          className="text-lt-text-muted hover:text-lt-danger-text"
                          aria-label={`Quitar ${p?.nombre ?? "producto"}`}
                        >
                          ×
                        </button>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
              <tfoot>
                <tr>
                  <td colSpan={4} className="px-2 py-2 text-right font-medium">
                    Costo total
                  </td>
                  <td className="px-2 py-2 text-right font-semibold tabular-nums">
                    {formatCurrency(totalCosto)}
                  </td>
                  <td />
                </tr>
              </tfoot>
            </table>
            <p className="mt-2 text-xs text-lt-text-muted">
              El costo unitario propuesto es el último precio de compra del producto; puedes
              cambiarlo.
            </p>
          </div>
        ) : (
          <p className="text-sm text-lt-text-muted">Aún no agregaste productos.</p>
        )}
      </Card>

      {error ? <p className="lt-alert-error">{error}</p> : null}

      <div className="flex flex-wrap gap-2">
        <Button type="button" onClick={guardar} disabled={pending}>
          {pending ? "Registrando…" : "Registrar movimiento"}
        </Button>
        <Button type="button" variant="secondary" href="/inventario-movimientos">
          Cancelar
        </Button>
      </div>
    </div>
  );
}
