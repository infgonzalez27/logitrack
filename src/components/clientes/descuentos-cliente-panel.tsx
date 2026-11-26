"use client";

import { useEffect, useMemo, useState } from "react";
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
import {
  PRODUCTO_MARCAS,
  detectProductoMarca,
} from "@/lib/product-images";
import type { ProductoListaRpc } from "@/types/database";

type TipoFiltroLista = "todos" | "porcentaje" | "pactado";

function coincideBusqueda(
  texto: string,
  codigo: string | null | undefined,
  q: string,
) {
  const term = q.trim().toLowerCase();
  if (!term) return true;
  return (
    texto.toLowerCase().includes(term) ||
    (codigo ?? "").toLowerCase().includes(term)
  );
}

export function DescuentosClientePanel({
  clienteId,
}: {
  clienteId: string;
}) {
  const [descuentos, setDescuentos] = useState<DescuentoConProducto[]>([]);
  const [productos, setProductos] = useState<ProductoListaRpc[]>([]);
  const [loadedClienteId, setLoadedClienteId] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [deletingId, setDeletingId] = useState<string | null>(null);

  const [selectedProductoId, setSelectedProductoId] = useState("");
  const [porcentajeDescuento, setPorcentajeDescuento] = useState("");
  const [precioPactadoUsd, setPrecioPactadoUsd] = useState("");
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [successMsg, setSuccessMsg] = useState<string | null>(null);

  const [busquedaProducto, setBusquedaProducto] = useState("");
  const [marcaProducto, setMarcaProducto] = useState("");
  const [busquedaLista, setBusquedaLista] = useState("");
  const [tipoLista, setTipoLista] = useState<TipoFiltroLista>("todos");

  const loading = Boolean(clienteId) && loadedClienteId !== clienteId;

  useEffect(() => {
    if (!clienteId) return;

    let mounted = true;

    void Promise.all([
      obtenerDescuentosClienteAction(clienteId),
      listarProductosAction(""),
    ])
      .then(([resDesc, resProd]) => {
        if (!mounted) return;
        if (resDesc.ok) {
          setDescuentos(resDesc.descuentos);
        } else {
          setErrorMsg(resDesc.error);
        }
        if (resProd.ok) {
          setProductos(resProd.productos);
        }
      })
      .catch((err: unknown) => {
        if (!mounted) return;
        setErrorMsg(
          err instanceof Error
            ? err.message
            : "No se pudieron cargar los descuentos.",
        );
      })
      .finally(() => {
        if (mounted) setLoadedClienteId(clienteId);
      });

    return () => {
      mounted = false;
    };
  }, [clienteId]);

  const productosFiltrados = useMemo(() => {
    return productos.filter((p) => {
      if (
        !coincideBusqueda(p.nombre, p.codigo_producto ?? p.codigo_barras, busquedaProducto)
      ) {
        return false;
      }
      if (!marcaProducto) return true;
      return detectProductoMarca(p.nombre) === marcaProducto;
    });
  }, [productos, busquedaProducto, marcaProducto]);

  const descuentosFiltrados = useMemo(() => {
    return descuentos.filter((d) => {
      if (
        !coincideBusqueda(d.producto_nombre, d.producto_codigo, busquedaLista)
      ) {
        return false;
      }
      if (tipoLista === "porcentaje") {
        return d.precio_pactado_usd == null && d.porcentaje_descuento > 0;
      }
      if (tipoLista === "pactado") {
        return d.precio_pactado_usd != null;
      }
      return true;
    });
  }, [descuentos, busquedaLista, tipoLista]);

  const productoSeleccionado = productos.find(
    (p) => p.id === selectedProductoId,
  );

  // Si el producto seleccionado sale del filtro, mantenerlo visible en el select.
  const opcionesProducto = useMemo(() => {
    if (
      selectedProductoId &&
      !productosFiltrados.some((p) => p.id === selectedProductoId)
    ) {
      const selected = productos.find((p) => p.id === selectedProductoId);
      return selected ? [selected, ...productosFiltrados] : productosFiltrados;
    }
    return productosFiltrados;
  }, [productos, productosFiltrados, selectedProductoId]);

  async function handleGuardarDescuento() {
    setErrorMsg(null);
    setSuccessMsg(null);

    if (!selectedProductoId) {
      setErrorMsg("Selecciona un producto.");
      return;
    }

    const pct = parseFloat(porcentajeDescuento || "0");
    const pactado = precioPactadoUsd ? parseFloat(precioPactadoUsd) : null;

    if (Number.isNaN(pct) || pct < 0 || pct > 100) {
      setErrorMsg("El porcentaje debe ser un número entre 0 y 100.");
      return;
    }

    if (pactado !== null && (Number.isNaN(pactado) || pactado < 0)) {
      setErrorMsg("El precio pactado en USD debe ser un número positivo.");
      return;
    }

    if (pct <= 0 && pactado == null) {
      setErrorMsg("Indica un porcentaje de descuento o un precio pactado.");
      return;
    }

    setSaving(true);
    try {
      const res = await guardarDescuentoClienteAction({
        cliente_id: clienteId,
        producto_id: selectedProductoId,
        porcentaje_descuento: pct,
        precio_pactado_usd: pactado,
      });

      if (!res.ok) {
        setErrorMsg(res.error);
        return;
      }

      setSuccessMsg("Descuento guardado.");
      setSelectedProductoId("");
      setPorcentajeDescuento("");
      setPrecioPactadoUsd("");
      const resDesc = await obtenerDescuentosClienteAction(clienteId);
      if (resDesc.ok) setDescuentos(resDesc.descuentos);
    } catch (err) {
      setErrorMsg(
        err instanceof Error
          ? err.message
          : "No se pudo guardar el descuento.",
      );
    } finally {
      setSaving(false);
    }
  }

  function handleInputKeyDown(e: React.KeyboardEvent<HTMLInputElement>) {
    if (e.key === "Enter") {
      e.preventDefault();
      e.stopPropagation();
      if (!saving && selectedProductoId) {
        void handleGuardarDescuento();
      }
    }
  }

  async function handleEliminarDescuento(id: string) {
    setDeletingId(id);
    setErrorMsg(null);
    setSuccessMsg(null);
    try {
      const res = await eliminarDescuentoClienteAction(id, clienteId);

      if (!res.ok) {
        setErrorMsg(res.error);
        return;
      }
      setSuccessMsg("Descuento eliminado.");
      setDescuentos((prev) => prev.filter((d) => d.id !== id));
    } catch (err) {
      setErrorMsg(
        err instanceof Error
          ? err.message
          : "No se pudo eliminar el descuento.",
      );
    } finally {
      setDeletingId(null);
    }
  }

  return (
    <div className="space-y-4">
      <p className="text-sm text-lt-text-muted">
        Productos con descuento o precio pactado para este cliente. Al crear una
        orden, el sistema aplica estos precios automáticamente.
      </p>

      {errorMsg ? (
        <div className="rounded-xl border border-lt-danger-border bg-lt-danger-surface p-3 text-sm text-lt-danger-text">
          {errorMsg}
        </div>
      ) : null}
      {successMsg ? (
        <div className="rounded-xl border border-emerald-500/20 bg-emerald-500/10 p-3 text-sm text-emerald-800">
          {successMsg}
        </div>
      ) : null}

      <div className="space-y-4 rounded-xl border border-lt-border bg-lt-surface-muted/40 p-4">
        <h3 className="text-sm font-semibold text-lt-text">
          Asignar o modificar descuento
        </h3>

        <div className="space-y-3">
          <Input
            label="Buscar producto"
            placeholder="Nombre, código o código de barras…"
            value={busquedaProducto}
            onChange={(e) => setBusquedaProducto(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter") {
                e.preventDefault();
                e.stopPropagation();
              }
            }}
            disabled={loading}
            autoComplete="off"
          />

          <div className="flex flex-wrap gap-2">
            <button
              type="button"
              onClick={() => setMarcaProducto("")}
              className={`rounded-full px-3 py-1.5 text-xs font-medium transition-colors ${
                !marcaProducto
                  ? "bg-lt-primary text-white"
                  : "bg-lt-surface text-lt-text hover:bg-lt-primary-muted"
              }`}
            >
              Todas
            </button>
            {PRODUCTO_MARCAS.map((m) => (
              <button
                key={m}
                type="button"
                onClick={() =>
                  setMarcaProducto((prev) => (prev === m ? "" : m))
                }
                className={`rounded-full px-3 py-1.5 text-xs font-medium transition-colors ${
                  marcaProducto === m
                    ? "bg-lt-primary text-white"
                    : "bg-lt-surface text-lt-text hover:bg-lt-primary-muted"
                }`}
              >
                {m}
              </button>
            ))}
          </div>

          <p className="text-xs text-lt-text-muted">
            Mostrando {opcionesProducto.length} de {productos.length} productos
            {busquedaProducto.trim() || marcaProducto
              ? " (filtrados)"
              : ""}
            .
          </p>
        </div>

        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <div className="space-y-1 sm:col-span-2">
            <label className="text-xs font-medium text-lt-text-muted">
              Producto
            </label>
            <select
              value={selectedProductoId}
              onChange={(e) => setSelectedProductoId(e.target.value)}
              className="w-full rounded-xl border border-lt-border bg-lt-surface px-3 py-2 text-sm text-lt-text focus:outline-none focus:ring-2 focus:ring-lt-primary"
              disabled={saving || loading}
            >
              <option value="">— Seleccionar producto —</option>
              {opcionesProducto.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.codigo_producto ? `${p.codigo_producto} — ` : ""}
                  {p.nombre} (lista $
                  {Number(p.precio_lista1 || p.precio).toFixed(2)})
                </option>
              ))}
            </select>
            {!loading && opcionesProducto.length === 0 ? (
              <p className="text-xs text-lt-text-muted">
                Sin coincidencias para la búsqueda o filtro de marca.
              </p>
            ) : null}
          </div>

          <div className="space-y-1">
            <label className="text-xs font-medium text-lt-text-muted">
              Descuento (%)
            </label>
            <Input
              type="number"
              step="0.01"
              min="0"
              max="100"
              placeholder="Ej. 10"
              value={porcentajeDescuento}
              onChange={(e) => {
                setPorcentajeDescuento(e.target.value);
                if (Number(e.target.value) > 0) setPrecioPactadoUsd("");
              }}
              onKeyDown={handleInputKeyDown}
              disabled={saving}
            />
          </div>

          <div className="space-y-1">
            <label className="text-xs font-medium text-lt-text-muted">
              Precio fijo pactado ($ USD)
            </label>
            <Input
              type="number"
              step="0.01"
              min="0"
              placeholder="Ej. 8.50"
              value={precioPactadoUsd}
              onChange={(e) => {
                setPrecioPactadoUsd(e.target.value);
                if (Number(e.target.value) > 0) setPorcentajeDescuento("");
              }}
              onKeyDown={handleInputKeyDown}
              disabled={saving}
            />
          </div>
        </div>

        {productoSeleccionado && (porcentajeDescuento || precioPactadoUsd) ? (
          <div className="flex items-center justify-between rounded-lg border border-lt-border bg-lt-surface p-2.5 text-xs text-lt-text-muted">
            <span>Vista previa de precio final</span>
            <span className="text-sm font-bold text-emerald-700">
              $
              {precioPactadoUsd
                ? parseFloat(precioPactadoUsd).toFixed(2)
                : (
                    (productoSeleccionado.precio_lista1 ||
                      productoSeleccionado.precio) *
                    (1 - parseFloat(porcentajeDescuento || "0") / 100)
                  ).toFixed(2)}{" "}
              USD
            </span>
          </div>
        ) : null}

        <div className="flex justify-end">
          <Button
            type="button"
            disabled={saving || !selectedProductoId}
            onClick={() => void handleGuardarDescuento()}
          >
            {saving ? "Guardando…" : "Guardar descuento"}
          </Button>
        </div>
      </div>

      <div className="space-y-3">
        <div className="flex flex-wrap items-end justify-between gap-3">
          <h3 className="text-sm font-semibold text-lt-text">
            Productos con descuento ({descuentosFiltrados.length}
            {descuentosFiltrados.length !== descuentos.length
              ? ` de ${descuentos.length}`
              : ""}
            )
          </h3>
        </div>

        {descuentos.length > 0 ? (
          <div className="space-y-3 rounded-xl border border-lt-border bg-lt-surface p-3">
            <Input
              label="Buscar en la lista"
              placeholder="Filtrar por nombre o código…"
              value={busquedaLista}
              onChange={(e) => setBusquedaLista(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter") {
                  e.preventDefault();
                  e.stopPropagation();
                }
              }}
              autoComplete="off"
            />
            <div className="flex flex-wrap gap-2">
              {(
                [
                  ["todos", "Todos"],
                  ["porcentaje", "% Descuento"],
                  ["pactado", "Precio pactado"],
                ] as const
              ).map(([value, label]) => (
                <button
                  key={value}
                  type="button"
                  onClick={() => setTipoLista(value)}
                  className={`rounded-full px-3 py-1.5 text-xs font-medium transition-colors ${
                    tipoLista === value
                      ? "bg-lt-primary text-white"
                      : "bg-lt-surface-muted text-lt-text hover:bg-lt-primary-muted"
                  }`}
                >
                  {label}
                </button>
              ))}
            </div>
          </div>
        ) : null}

        {loading ? (
          <p className="py-6 text-center text-sm text-lt-text-muted">
            Cargando descuentos…
          </p>
        ) : descuentos.length === 0 ? (
          <p className="rounded-xl border border-dashed border-lt-border py-6 text-center text-sm text-lt-text-muted">
            Este cliente aún no tiene productos con descuento.
          </p>
        ) : descuentosFiltrados.length === 0 ? (
          <p className="rounded-xl border border-dashed border-lt-border py-6 text-center text-sm text-lt-text-muted">
            Sin coincidencias para el buscador o filtro.
          </p>
        ) : (
          <ul className="max-h-72 space-y-2 overflow-y-auto pr-1">
            {descuentosFiltrados.map((desc) => {
              const precioLista = desc.precio_lista1 || 0;
              let precioNeto = precioLista;
              if (desc.precio_pactado_usd !== null) {
                precioNeto = desc.precio_pactado_usd;
              } else if (desc.porcentaje_descuento > 0) {
                precioNeto =
                  precioLista * (1 - desc.porcentaje_descuento / 100);
              }

              return (
                <li
                  key={desc.id}
                  className="flex items-center justify-between gap-3 rounded-xl border border-lt-border bg-lt-surface p-3"
                >
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-medium text-lt-text">
                      {desc.producto_codigo
                        ? `${desc.producto_codigo} — `
                        : ""}
                      {desc.producto_nombre}
                    </p>
                    <p className="mt-0.5 text-xs text-lt-text-muted">
                      Lista: ${precioLista.toFixed(2)} ·{" "}
                      <span className="font-semibold text-emerald-700">
                        Neto: ${precioNeto.toFixed(2)}
                      </span>
                    </p>
                  </div>
                  <div className="flex shrink-0 items-center gap-2">
                    {desc.precio_pactado_usd !== null ? (
                      <Badge tone="info">
                        Pactado ${desc.precio_pactado_usd.toFixed(2)}
                      </Badge>
                    ) : (
                      <Badge tone="success">
                        -{desc.porcentaje_descuento}% OFF
                      </Badge>
                    )}
                    <Button
                      type="button"
                      variant="ghost"
                      className="h-8 px-2 text-lt-danger-text hover:bg-lt-danger-surface"
                      disabled={deletingId === desc.id}
                      onClick={() => void handleEliminarDescuento(desc.id)}
                    >
                      {deletingId === desc.id ? "…" : "Quitar"}
                    </Button>
                  </div>
                </li>
              );
            })}
          </ul>
        )}
      </div>
    </div>
  );
}
