"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import {
  actualizarPorcentajeDescuentoAction,
  guardarDescuentoClienteAction,
  toggleDescuentoProductoAction,
  type DescuentoConProducto,
} from "@/lib/actions/descuentos";
import type { ProductoListaRpc } from "@/types/database";

export function DescuentosClienteDetalleClient({
  clienteId,
  descuentosIniciales,
  productos,
}: {
  clienteId: string;
  descuentosIniciales: DescuentoConProducto[];
  productos: ProductoListaRpc[];
}) {
  const router = useRouter();
  const [busqueda, setBusqueda] = useState("");
  const [porcentajesEdit, setPorcentajesEdit] = useState<
    Record<string, string | undefined>
  >({});
  const [savingId, setSavingId] = useState<string | null>(null);
  const [togglingId, setTogglingId] = useState<string | null>(null);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [successMsg, setSuccessMsg] = useState<string | null>(null);

  // Modal para agregar producto con descuento
  const [modalOpen, setModalOpen] = useState(false);
  const [modalErrorMsg, setModalErrorMsg] = useState<string | null>(null);
  const [busquedaProd, setBusquedaProd] = useState("");
  const [selectedProdId, setSelectedProdId] = useState("");
  const [nuevoPorcentaje, setNuevoPorcentaje] = useState("");
  const [nuevoPrecioPactado, setNuevoPrecioPactado] = useState("");
  const [adding, setAdding] = useState(false);

  const descuentosFiltrados = useMemo(() => {
    const term = busqueda.trim().toLowerCase();
    if (!term) return descuentosIniciales;
    return descuentosIniciales.filter(
      (d) =>
        d.producto_nombre.toLowerCase().includes(term) ||
        d.producto_codigo.toLowerCase().includes(term),
    );
  }, [descuentosIniciales, busqueda]);

  const productosFiltrados = useMemo(() => {
    const term = busquedaProd.trim().toLowerCase();
    if (!term) return productos;
    return productos.filter(
      (p) =>
        p.nombre.toLowerCase().includes(term) ||
        (p.codigo_producto ?? p.codigo_barras ?? "").toLowerCase().includes(term),
    );
  }, [productos, busquedaProd]);

  async function handleGuardarPorcentaje(d: DescuentoConProducto) {
    const raw = porcentajesEdit[d.id] ?? String(d.porcentaje_descuento);
    const pct = Number(raw);
    if (raw.trim() === "" || Number.isNaN(pct) || pct < 0 || pct > 100) {
      setErrorMsg("El porcentaje debe ser un número entre 0 y 100.");
      return;
    }

    setSavingId(d.id);
    setErrorMsg(null);
    setSuccessMsg(null);

    try {
      const res = await actualizarPorcentajeDescuentoAction({
        id: d.id,
        cliente_id: clienteId,
        porcentaje_descuento: pct,
      });

      if (!res.ok) {
        setErrorMsg(res.error);
        return;
      }

      setPorcentajesEdit((prev) => {
        const next = { ...prev };
        delete next[d.id];
        return next;
      });
      setSuccessMsg(
        `Porcentaje de "${d.producto_nombre}" actualizado a ${pct}%.`,
      );
      router.refresh();
    } catch (err) {
      setErrorMsg(
        err instanceof Error
          ? err.message
          : "No se pudo actualizar el porcentaje.",
      );
    } finally {
      setSavingId(null);
    }
  }

  async function handleToggleProducto(d: DescuentoConProducto) {
    const activar = !d.activo;
    setTogglingId(d.id);
    setErrorMsg(null);
    setSuccessMsg(null);

    try {
      const res = await toggleDescuentoProductoAction({
        id: d.id,
        cliente_id: clienteId,
        activo: activar,
      });

      if (!res.ok) {
        setErrorMsg(res.error);
        return;
      }

      setSuccessMsg(
        activar
          ? `Descuento de "${d.producto_nombre}" activado.`
          : `Descuento de "${d.producto_nombre}" desactivado.`,
      );
      router.refresh();
    } catch (err) {
      setErrorMsg(
        err instanceof Error
          ? err.message
          : "No se pudo cambiar el estado del descuento.",
      );
    } finally {
      setTogglingId(null);
    }
  }

  async function handleAgregarProducto(e: React.FormEvent) {
    e.preventDefault();
    const pct = Number(nuevoPorcentaje || 0);
    const pactado =
      nuevoPrecioPactado.trim() !== "" ? Number(nuevoPrecioPactado) : null;

    if (!selectedProdId) {
      setModalErrorMsg("Selecciona un producto.");
      return;
    }
    if (Number.isNaN(pct) || pct < 0 || pct > 100) {
      setModalErrorMsg("El porcentaje debe estar entre 0% y 100%.");
      return;
    }
    if (pactado !== null && (Number.isNaN(pactado) || pactado <= 0)) {
      setModalErrorMsg("El precio pactado en USD debe ser mayor a 0.");
      return;
    }
    if (pct === 0 && (pactado === null || pactado <= 0)) {
      setModalErrorMsg(
        "Ingresa un porcentaje mayor a 0 o un precio pactado válido.",
      );
      return;
    }

    setAdding(true);
    setModalErrorMsg(null);
    setErrorMsg(null);
    setSuccessMsg(null);

    try {
      const res = await guardarDescuentoClienteAction({
        cliente_id: clienteId,
        producto_id: selectedProdId,
        porcentaje_descuento: pct,
        precio_pactado_usd: pactado,
      });

      if (!res.ok) {
        setModalErrorMsg(res.error);
        return;
      }

      setPorcentajesEdit((prev) => {
        const next = { ...prev };
        delete next[res.id];
        return next;
      });
      setModalOpen(false);
      setModalErrorMsg(null);
      setSelectedProdId("");
      setNuevoPorcentaje("");
      setNuevoPrecioPactado("");
      setBusquedaProd("");
      setSuccessMsg("Producto con descuento agregado correctamente.");
      router.refresh();
    } catch (err) {
      setModalErrorMsg(
        err instanceof Error
          ? err.message
          : "No se pudo guardar el descuento.",
      );
    } finally {
      setAdding(false);
    }
  }

  return (
    <div className="space-y-4">
      <Card className="p-4 sm:p-5">
        <div className="flex flex-col gap-3 md:flex-row md:items-end md:justify-between">
          <div className="flex-1">
            <Input
              label="Buscar producto"
              name="q"
              placeholder="Buscar por nombre o código..."
              value={busqueda}
              onChange={(e) => setBusqueda(e.target.value)}
              autoComplete="off"
            />
          </div>

          <Button
            type="button"
            onClick={() => {
              setModalErrorMsg(null);
              setModalOpen(true);
            }}
          >
            Agregar producto con descuento
          </Button>
        </div>

        {errorMsg ? (
          <p className="mt-3 rounded-lg border border-rose-500/30 bg-rose-500/10 px-3 py-2 text-xs text-rose-700 dark:text-rose-400">
            {errorMsg}
          </p>
        ) : null}
        {successMsg ? (
          <p className="mt-3 rounded-lg border border-emerald-500/30 bg-emerald-500/10 px-3 py-2 text-xs text-emerald-700 dark:text-emerald-400">
            {successMsg}
          </p>
        ) : null}
      </Card>

      {descuentosFiltrados.length === 0 ? (
        <Card className="p-8 text-center text-sm text-lt-text-muted">
          Este cliente no tiene productos con descuento registrados.
        </Card>
      ) : (
        <Card className="overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-left text-sm">
              <thead className="border-b border-lt-border bg-lt-surface-muted/60 text-xs uppercase text-lt-text-muted">
                <tr>
                  <th className="px-4 py-3 font-medium">Producto</th>
                  <th className="px-4 py-3 font-medium">Precio lista</th>
                  <th className="px-4 py-3 font-medium">Descuento (%)</th>
                  <th className="px-4 py-3 font-medium">Precio pactado</th>
                  <th className="px-4 py-3 font-medium">Estado</th>
                  <th className="px-4 py-3 text-right font-medium">
                    Acciones
                  </th>
                </tr>
              </thead>
              <tbody className="divide-y divide-lt-border">
                {descuentosFiltrados.map((d) => {
                  const valActual =
                    porcentajesEdit[d.id] ?? String(d.porcentaje_descuento);
                  const cambioPendiente =
                    Number(valActual) !== d.porcentaje_descuento;

                  return (
                    <tr key={d.id}>
                      <td className="px-4 py-3">
                        <div className="font-medium text-lt-text">
                          {d.producto_nombre}
                        </div>
                        {d.producto_codigo ? (
                          <div className="text-xs text-lt-text-muted">
                            {d.producto_codigo}
                          </div>
                        ) : null}
                      </td>
                      <td className="px-4 py-3 text-lt-text-muted">
                        ${d.precio_lista1.toFixed(2)}
                      </td>
                      <td className="px-4 py-3">
                        <div className="flex items-center gap-2">
                          <input
                            type="number"
                            min={0}
                            max={100}
                            step="0.01"
                            aria-label={`Porcentaje de descuento para ${d.producto_nombre}`}
                            value={valActual}
                            onChange={(e) =>
                              setPorcentajesEdit((prev) => ({
                                ...prev,
                                [d.id]: e.target.value,
                              }))
                            }
                            className="w-24 rounded-lg border border-lt-border bg-lt-surface px-2.5 py-1.5 text-sm text-lt-text focus:border-lt-primary focus:outline-none"
                          />
                          <Button
                            type="button"
                            className="px-3 py-1.5 text-xs"
                            variant="secondary"
                            disabled={
                              !cambioPendiente || savingId === d.id
                            }
                            onClick={() => handleGuardarPorcentaje(d)}
                          >
                            {savingId === d.id ? "..." : "Guardar"}
                          </Button>
                        </div>
                      </td>
                      <td className="px-4 py-3 text-lt-text-muted">
                        {d.precio_pactado_usd !== null
                          ? `$${d.precio_pactado_usd.toFixed(2)}`
                          : "—"}
                      </td>
                      <td className="px-4 py-3">
                        <Badge tone={d.activo ? "success" : "danger"}>
                          {d.activo ? "Activo" : "Inactivo"}
                        </Badge>
                      </td>
                      <td className="px-4 py-3 text-right">
                        <Button
                          type="button"
                          className="px-3 py-1.5 text-xs"
                          variant={d.activo ? "danger" : "primary"}
                          disabled={togglingId === d.id}
                          onClick={() => handleToggleProducto(d)}
                        >
                          {togglingId === d.id
                            ? "..."
                            : d.activo
                              ? "Desactivar"
                              : "Activar"}
                        </Button>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </Card>
      )}

      {modalOpen ? (
        <div className="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-black/60 p-4 backdrop-blur-sm">
          <form
            onSubmit={handleAgregarProducto}
            className="relative w-full max-w-lg space-y-4 rounded-2xl border border-lt-border bg-lt-surface p-6 shadow-2xl"
          >
            <div className="flex items-start justify-between border-b border-lt-border pb-3">
              <h2 className="font-display text-lg font-bold text-lt-text">
                Agregar producto con descuento
              </h2>
              <button
                type="button"
                onClick={() => {
                  setModalErrorMsg(null);
                  setModalOpen(false);
                }}
                disabled={adding}
                className="rounded-lg p-1 text-lg font-bold text-lt-text-muted hover:bg-lt-surface-muted hover:text-lt-text disabled:opacity-50"
                title="Cerrar"
              >
                ✕
              </button>
            </div>

            {modalErrorMsg ? (
              <p className="rounded-lg border border-rose-500/30 bg-rose-500/10 px-3 py-2 text-xs text-rose-700 dark:text-rose-400">
                {modalErrorMsg}
              </p>
            ) : null}

            <Input
              label="Filtrar productos"
              name="buscar_prod"
              placeholder="Nombre o código..."
              value={busquedaProd}
              onChange={(e) => setBusquedaProd(e.target.value)}
              disabled={adding}
            />

            <div className="space-y-1.5">
              <label className="block text-xs font-medium text-lt-text">
                Producto
              </label>
              <select
                value={selectedProdId}
                onChange={(e) => setSelectedProdId(e.target.value)}
                disabled={adding}
                className="w-full rounded-xl border border-lt-border bg-lt-surface px-3 py-2 text-sm text-lt-text focus:border-lt-primary focus:outline-none"
                required
              >
                <option value="">Selecciona un producto...</option>
                {productosFiltrados.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.nombre} (${Number(p.precio_lista1 ?? p.precio ?? 0).toFixed(2)})
                  </option>
                ))}
              </select>
            </div>

            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
              <Input
                label="Porcentaje (%)"
                name="porcentaje"
                type="number"
                min="0"
                max="100"
                step="0.01"
                placeholder="Ej: 10"
                value={nuevoPorcentaje}
                onChange={(e) => {
                  setNuevoPorcentaje(e.target.value);
                  if (Number(e.target.value) > 0) setNuevoPrecioPactado("");
                }}
                disabled={adding}
              />
              <Input
                label="Precio pactado USD (opcional)"
                name="precio_pactado"
                type="number"
                min="0"
                step="0.01"
                placeholder="Ej: 15.50"
                value={nuevoPrecioPactado}
                onChange={(e) => {
                  setNuevoPrecioPactado(e.target.value);
                  if (Number(e.target.value) > 0) setNuevoPorcentaje("");
                }}
                disabled={adding}
              />
            </div>

            <div className="flex justify-end gap-2 border-t border-lt-border pt-4">
              <Button
                type="button"
                variant="secondary"
                disabled={adding}
                onClick={() => {
                  setModalErrorMsg(null);
                  setModalOpen(false);
                }}
              >
                Cancelar
              </Button>
              <Button type="submit" disabled={adding}>
                {adding ? "Guardando..." : "Guardar descuento"}
              </Button>
            </div>
          </form>
        </div>
      ) : null}
    </div>
  );
}
