"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import {
  toggleTodosDescuentosAction,
  type ClienteConDescuentosResumen,
} from "@/lib/actions/descuentos";

export function DescuentosClientesListaClient({
  clientes,
  hayAlgunDescuentoActivo,
}: {
  clientes: ClienteConDescuentosResumen[];
  hayAlgunDescuentoActivo: boolean;
}) {
  const router = useRouter();
  const [busqueda, setBusqueda] = useState("");
  const [activoGlobal, setActivoGlobal] = useState(hayAlgunDescuentoActivo);
  const [pendingGlobal, setPendingGlobal] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [successMsg, setSuccessMsg] = useState<string | null>(null);

  const filtrados = useMemo(() => {
    const term = busqueda.trim().toLowerCase();
    if (!term) return clientes;
    return clientes.filter(
      (c) =>
        c.razon_social.toLowerCase().includes(term) ||
        (c.rif_nit ?? "").toLowerCase().includes(term),
    );
  }, [clientes, busqueda]);

  async function handleToggleTodos() {
    const activar = !activoGlobal;
    const accionTexto = activar
      ? "activar todos los descuentos de todos los clientes"
      : "desactivar todos los descuentos de todos los clientes";

    if (!window.confirm(`¿Confirmas que deseas ${accionTexto}?`)) {
      return;
    }

    setPendingGlobal(true);
    setErrorMsg(null);
    setSuccessMsg(null);

    const res = await toggleTodosDescuentosAction(activar);
    setPendingGlobal(false);

    if (!res.ok) {
      setErrorMsg(res.error);
      return;
    }

    setActivoGlobal(activar);
    setSuccessMsg(
      activar
        ? "Todos los descuentos fueron activados."
        : "Todos los descuentos fueron desactivados.",
    );
    router.refresh();
  }

  return (
    <div className="space-y-4">
      <Card className="p-4 sm:p-5">
        <div className="flex flex-col gap-3 md:flex-row md:items-end md:justify-between">
          <div className="flex-1">
            <Input
              label="Buscar cliente con descuento"
              name="q"
              placeholder="Buscar por razón social o RIF/NIT..."
              value={busqueda}
              onChange={(e) => setBusqueda(e.target.value)}
              autoComplete="off"
            />
          </div>

          <div className="flex items-center gap-2">
            <Button
              type="button"
              variant={activoGlobal ? "danger" : "primary"}
              disabled={pendingGlobal || clientes.length === 0}
              onClick={handleToggleTodos}
            >
              {pendingGlobal
                ? "Procesando..."
                : activoGlobal
                  ? "Desactivar descuentos"
                  : "Activar descuentos"}
            </Button>
          </div>
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

      {filtrados.length === 0 ? (
        <Card className="p-8 text-center text-sm text-lt-text-muted">
          No se encontraron clientes con descuentos registrados.
        </Card>
      ) : (
        <Card className="overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-left text-sm">
              <thead className="border-b border-lt-border bg-lt-surface-muted/60 text-xs uppercase text-lt-text-muted">
                <tr>
                  <th className="px-4 py-3 font-medium">Cliente</th>
                  <th className="px-4 py-3 font-medium">RIF / NIT</th>
                  <th className="px-4 py-3 font-medium">Productos</th>
                  <th className="px-4 py-3 font-medium">Estado</th>
                  <th className="px-4 py-3 text-right font-medium">Acción</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-lt-border">
                {filtrados.map((c) => (
                  <tr
                    key={c.cliente_id}
                    onClick={() =>
                      router.push(`/clientes/descuentos/${c.cliente_id}`)
                    }
                    className="cursor-pointer transition-colors hover:bg-lt-surface-muted/50"
                  >
                    <td className="px-4 py-3 font-medium text-lt-text">
                      {c.razon_social}
                    </td>
                    <td className="px-4 py-3 text-lt-text-muted">
                      {c.rif_nit || "—"}
                    </td>
                    <td className="px-4 py-3 text-lt-text">
                      {c.total_productos}
                    </td>
                    <td className="px-4 py-3">
                      <div className="flex flex-wrap gap-1.5">
                        {c.productos_activos > 0 ? (
                          <Badge tone="success">
                            {c.productos_activos} activos
                          </Badge>
                        ) : null}
                        {c.productos_inactivos > 0 ? (
                          <Badge tone="danger">
                            {c.productos_inactivos} inactivos
                          </Badge>
                        ) : null}
                      </div>
                    </td>
                    <td className="px-4 py-3 text-right">
                      <span className="text-xs font-medium text-lt-primary">
                        Ver productos →
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Card>
      )}
    </div>
  );
}
