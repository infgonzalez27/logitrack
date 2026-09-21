"use client";

import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import {
  obtenerDescuentosClienteAction,
  guardarDescuentoClienteAction,
  eliminarDescuentoClienteAction,
  type DescuentoConProducto,
} from "@/lib/actions/descuentos";
import { listarProductosAction } from "@/lib/actions/productos";
import type { ProductoListaRpc } from "@/types/database";

interface ModalDescuentosClienteProps {
  clienteId: string;
  clienteNombre: string;
  isOpen: boolean;
  onClose: () => void;
}

export function ModalDescuentosCliente({
  clienteId,
  clienteNombre,
  isOpen,
  onClose,
}: ModalDescuentosClienteProps) {
  const [descuentos, setDescuentos] = useState<DescuentoConProducto[]>([]);
  const [productos, setProductos] = useState<ProductoListaRpc[]>([]);
  const [loading, setLoading] = useState<boolean>(true);
  const [saving, setSaving] = useState<boolean>(false);
  const [deletingId, setDeletingId] = useState<string | null>(null);

  const [selectedProductoId, setSelectedProductoId] = useState<string>("");
  const [porcentajeDescuento, setPorcentajeDescuento] = useState<string>("");
  const [precioPactadoUsd, setPrecioPactadoUsd] = useState<string>("");
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [successMsg, setSuccessMsg] = useState<string | null>(null);

  useEffect(() => {
    if (!isOpen || !clienteId) return;

    let mounted = true;
    setLoading(true);
    setErrorMsg(null);
    setSuccessMsg(null);

    async function loadData() {
      const [resDesc, resProd] = await Promise.all([
        obtenerDescuentosClienteAction(clienteId),
        listarProductosAction(""),
      ]);

      if (!mounted) return;

      if (resDesc.ok) {
        setDescuentos(resDesc.descuentos);
      } else {
        setErrorMsg(resDesc.error);
      }

      if (resProd.ok) {
        setProductos(resProd.productos);
      }

      setLoading(false);
    }

    loadData();

    return () => {
      mounted = false;
    };
  }, [isOpen, clienteId]);

  if (!isOpen) return null;

  const handleGuardarDescuento = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMsg(null);
    setSuccessMsg(null);

    if (!selectedProductoId) {
      setErrorMsg("Selecciona un producto.");
      return;
    }

    const pct = parseFloat(porcentajeDescuento || "0");
    const pactado = precioPactadoUsd ? parseFloat(precioPactadoUsd) : null;

    if (isNaN(pct) || pct < 0 || pct > 100) {
      setErrorMsg("El porcentaje debe ser un número entre 0 y 100.");
      return;
    }

    if (pactado !== null && (isNaN(pactado) || pactado < 0)) {
      setErrorMsg("El precio pactado en USD debe ser un número positivo.");
      return;
    }

    setSaving(true);
    const res = await guardarDescuentoClienteAction({
      cliente_id: clienteId,
      producto_id: selectedProductoId,
      porcentaje_descuento: pct,
      precio_pactado_usd: pactado,
    });

    setSaving(false);

    if (res.ok) {
      setSuccessMsg("Descuento guardado exitosamente.");
      setSelectedProductoId("");
      setPorcentajeDescuento("");
      setPrecioPactadoUsd("");
      
      // Recargar lista de descuentos
      const resDesc = await obtenerDescuentosClienteAction(clienteId);
      if (resDesc.ok) {
        setDescuentos(resDesc.descuentos);
      }
    } else {
      setErrorMsg(res.error);
    }
  };

  const handleEliminarDescuento = async (id: string) => {
    setDeletingId(id);
    setErrorMsg(null);
    setSuccessMsg(null);

    const res = await eliminarDescuentoClienteAction(id, clienteId);
    setDeletingId(null);

    if (res.ok) {
      setSuccessMsg("Descuento eliminado.");
      setDescuentos((prev) => prev.filter((d) => d.id !== id));
    } else {
      setErrorMsg(res.error);
    }
  };

  const productoSeleccionado = productos.find((p) => p.id === selectedProductoId);

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4 overflow-y-auto">
      <div className="relative w-full max-w-2xl rounded-2xl border border-lt-border bg-lt-surface shadow-2xl p-6 space-y-6">
        {/* Cabecera Modal */}
        <div className="flex items-start justify-between border-b border-lt-border pb-4">
          <div>
            <h2 className="font-display text-xl font-bold text-lt-text flex items-center gap-2">
              <span>🏷️ Descuentos por Producto</span>
            </h2>
            <p className="text-sm text-lt-text-muted mt-1">
              Cliente: <strong className="text-lt-text font-semibold">{clienteNombre}</strong>
            </p>
          </div>
          <button
            onClick={onClose}
            className="text-lt-text-muted hover:text-lt-text p-1.5 rounded-lg hover:bg-lt-surface-muted transition-colors text-xl font-bold"
            title="Cerrar"
          >
            ✕
          </button>
        </div>

        {/* Mensajes de feedback */}
        {errorMsg && (
          <div className="rounded-xl border border-lt-danger-border bg-lt-danger-surface p-3 text-sm text-lt-danger-text">
            ⚠️ {errorMsg}
          </div>
        )}
        {successMsg && (
          <div className="rounded-xl border border-emerald-500/20 bg-emerald-500/10 p-3 text-sm text-emerald-400">
            ✅ {successMsg}
          </div>
        )}

        {/* Formulario de Agregar / Editar Descuento */}
        <form onSubmit={handleGuardarDescuento} className="rounded-xl border border-lt-border p-4 bg-lt-surface-muted/40 space-y-4">
          <h3 className="text-sm font-semibold text-lt-text">Asignar o Modificar Descuento</h3>
          
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div className="space-y-1 sm:col-span-2">
              <label className="text-xs font-medium text-lt-text-muted">Producto</label>
              <select
                value={selectedProductoId}
                onChange={(e) => setSelectedProductoId(e.target.value)}
                className="w-full rounded-xl border border-lt-border bg-lt-surface px-3 py-2 text-sm text-lt-text focus:outline-none focus:ring-2 focus:ring-lt-primary"
                disabled={saving}
              >
                <option value="">-- Seleccionar Producto --</option>
                {productos.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.nombre} {p.codigo_producto ? `(${p.codigo_producto})` : ""} - Precio Lista: ${Number(p.precio_lista1 || p.precio).toFixed(2)} USD
                  </option>
                ))}
              </select>
            </div>

            <div className="space-y-1">
              <label className="text-xs font-medium text-lt-text-muted">Descuento (%)</label>
              <Input
                type="number"
                step="0.01"
                min="0"
                max="100"
                placeholder="Ej. 10.00"
                value={porcentajeDescuento}
                onChange={(e) => {
                  setPorcentajeDescuento(e.target.value);
                  if (e.target.value) setPrecioPactadoUsd("");
                }}
                disabled={saving}
              />
            </div>

            <div className="space-y-1">
              <label className="text-xs font-medium text-lt-text-muted">Precio Fijo Pactado ($ USD)</label>
              <Input
                type="number"
                step="0.01"
                min="0"
                placeholder="Ej. 8.50"
                value={precioPactadoUsd}
                onChange={(e) => {
                  setPrecioPactadoUsd(e.target.value);
                  if (e.target.value) setPorcentajeDescuento("");
                }}
                disabled={saving}
              />
            </div>
          </div>

          {productoSeleccionado && (porcentajeDescuento || precioPactadoUsd) && (
            <div className="text-xs text-lt-text-muted bg-lt-surface p-2.5 rounded-lg border border-lt-border flex items-center justify-between">
              <span>Vista previa de precio final:</span>
              <span className="font-bold text-emerald-400 text-sm">
                $
                {precioPactadoUsd
                  ? parseFloat(precioPactadoUsd).toFixed(2)
                  : (
                      (productoSeleccionado.precio_lista1 || productoSeleccionado.precio) *
                      (1 - parseFloat(porcentajeDescuento || "0") / 100)
                    ).toFixed(2)}{" "}
                USD
              </span>
            </div>
          )}

          <div className="flex justify-end">
            <Button type="submit" disabled={saving || !selectedProductoId}>
              {saving ? "Guardando..." : "Guardar Descuento"}
            </Button>
          </div>
        </form>

        {/* Lista de Descuentos Configurados */}
        <div className="space-y-3">
          <h3 className="text-sm font-semibold text-lt-text flex items-center justify-between">
            <span>Descuentos Configurados ({descuentos.length})</span>
          </h3>

          {loading ? (
            <div className="py-8 text-center text-sm text-lt-text-muted">
              Cargando descuentos...
            </div>
          ) : descuentos.length === 0 ? (
            <div className="py-8 text-center text-sm text-lt-text-muted border border-dashed border-lt-border rounded-xl">
              Este cliente no tiene descuentos por producto configurados.
            </div>
          ) : (
            <div className="max-h-60 overflow-y-auto space-y-2 pr-1">
              {descuentos.map((desc) => {
                const precioLista = desc.precio_lista1 || 0;
                let precioNeto = precioLista;
                if (desc.precio_pactado_usd !== null) {
                  precioNeto = desc.precio_pactado_usd;
                } else if (desc.porcentaje_descuento > 0) {
                  precioNeto = precioLista * (1 - desc.porcentaje_descuento / 100);
                }

                return (
                  <div
                    key={desc.id}
                    className="flex items-center justify-between p-3 rounded-xl border border-lt-border bg-lt-surface hover:bg-lt-surface-muted/50 transition-colors"
                  >
                    <div className="min-w-0 flex-1">
                      <div className="font-medium text-sm text-lt-text truncate">
                        {desc.producto_nombre}
                      </div>
                      <div className="text-xs text-lt-text-muted flex items-center gap-2 mt-0.5">
                        <span>Lista: ${precioLista.toFixed(2)} USD</span>
                        <span>•</span>
                        <span className="text-emerald-400 font-semibold">
                          Neto: ${precioNeto.toFixed(2)} USD
                        </span>
                      </div>
                    </div>

                    <div className="flex items-center gap-3 shrink-0">
                      {desc.precio_pactado_usd !== null ? (
                        <Badge tone="info">Precio Pactado: ${desc.precio_pactado_usd.toFixed(2)}</Badge>
                      ) : (
                        <Badge tone="success">-{desc.porcentaje_descuento}% OFF</Badge>
                      )}

                      <Button
                        variant="ghost"
                        className="text-lt-danger-text hover:bg-lt-danger-surface p-1.5 h-8 w-8"
                        disabled={deletingId === desc.id}
                        onClick={() => handleEliminarDescuento(desc.id)}
                        title="Eliminar descuento"
                      >
                        {deletingId === desc.id ? "..." : "🗑️"}
                      </Button>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>

        {/* Pie del Modal */}
        <div className="flex justify-end border-t border-lt-border pt-4">
          <Button variant="secondary" onClick={onClose}>
            Cerrar
          </Button>
        </div>
      </div>
    </div>
  );
}
