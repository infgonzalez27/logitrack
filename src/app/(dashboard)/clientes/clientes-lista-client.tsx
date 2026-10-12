"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import { DataTable } from "@/components/ui/data-table";
import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { ModalDescuentosCliente } from "@/components/forms/modal-descuentos-cliente";
import type { Cliente } from "@/types/database";

function normalizar(texto: string): string {
  return texto
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .trim();
}

export function ClientesListaClient({
  clientes,
  initialQuery = "",
}: {
  clientes: Cliente[];
  initialQuery?: string;
}) {
  const [busqueda, setBusqueda] = useState(initialQuery);
  const [filtroEstado, setFiltroEstado] = useState<"todos" | "activos" | "inactivos">("todos");
  const [selectedCliente, setSelectedCliente] = useState<{
    id: string;
    razon_social: string;
  } | null>(null);

  const conteoActivos = useMemo(
    () => clientes.filter((c) => c.activo).length,
    [clientes],
  );
  const conteoInactivos = clientes.length - conteoActivos;

  const filtrados = useMemo(() => {
    let res = clientes;

    if (filtroEstado === "activos") {
      res = res.filter((c) => c.activo);
    } else if (filtroEstado === "inactivos") {
      res = res.filter((c) => !c.activo);
    }

    const term = normalizar(busqueda);
    if (!term) return res;

    return res.filter((c) =>
      [
        c.razon_social,
        c.rif_nit,
        c.telefono,
        c.movil1,
        c.movil2,
        c.movil3,
        c.correo_e,
        c.direccion_fiscal,
      ].some((campo) => campo && normalizar(campo).includes(term)),
    );
  }, [clientes, filtroEstado, busqueda]);

  return (
    <div className="space-y-4">
      {/* Barra de búsqueda y filtros */}
      <Card className="p-4 sm:p-5">
        <div className="flex flex-col gap-3 md:flex-row md:items-end md:justify-between">
          <div className="flex-1">
            <Input
              label="Buscar cliente"
              name="q"
              placeholder="Buscar por razón social, RIF/NIT, teléfono, correo o dirección..."
              value={busqueda}
              onChange={(e) => setBusqueda(e.target.value)}
              autoComplete="off"
            />
          </div>

          <div className="flex flex-wrap items-center gap-2">
            <button
              type="button"
              onClick={() => setFiltroEstado("todos")}
              className={`rounded-xl px-3 py-2 text-xs font-medium transition-colors ${
                filtroEstado === "todos"
                  ? "bg-lt-primary text-white"
                  : "bg-lt-surface-muted text-lt-text-muted hover:text-lt-text"
              }`}
            >
              Todos ({clientes.length})
            </button>
            <button
              type="button"
              onClick={() => setFiltroEstado("activos")}
              className={`rounded-xl px-3 py-2 text-xs font-medium transition-colors ${
                filtroEstado === "activos"
                  ? "bg-emerald-600 text-white"
                  : "bg-emerald-500/10 text-emerald-700 dark:text-emerald-400 hover:bg-emerald-500/20"
              }`}
            >
              Activos ({conteoActivos})
            </button>
            <button
              type="button"
              onClick={() => setFiltroEstado("inactivos")}
              className={`rounded-xl px-3 py-2 text-xs font-medium transition-colors ${
                filtroEstado === "inactivos"
                  ? "bg-rose-600 text-white"
                  : "bg-rose-500/10 text-rose-700 dark:text-rose-400 hover:bg-rose-500/20"
              }`}
            >
              Inactivos ({conteoInactivos})
            </button>
            {busqueda && (
              <button
                type="button"
                onClick={() => setBusqueda("")}
                className="text-xs text-lt-text-muted hover:text-lt-text underline"
              >
                Limpiar búsqueda
              </button>
            )}
          </div>
        </div>

        <p className="mt-2 text-xs text-lt-text-subtle">
          Mostrando {filtrados.length} de {clientes.length} cliente{clientes.length === 1 ? "" : "s"}
        </p>
      </Card>

      {/* Tabla de clientes */}
      <Card>
        <DataTable
          emptyMessage="No se encontraron clientes que coincidan con la búsqueda."
          columns={[
            { key: "rif", label: "RIF/NIT" },
            { key: "razon", label: "Razón social" },
            { key: "telefono", label: "Teléfono" },
            { key: "estado", label: "Estado" },
            { key: "acciones", label: "Acciones" },
          ]}
          rows={filtrados.map((c) => ({
            id: c.id,
            cells: {
              rif: <span className="font-mono text-xs font-semibold">{c.rif_nit}</span>,
              razon: (
                <div>
                  <div className="font-medium text-lt-text">{c.razon_social}</div>
                  {c.direccion_fiscal ? (
                    <div className="line-clamp-1 text-xs text-lt-text-subtle">
                      {c.direccion_fiscal}
                    </div>
                  ) : null}
                </div>
              ),
              telefono: c.telefono ?? c.movil1 ?? "—",
              estado: (
                <Badge tone={c.activo ? "success" : "danger"}>
                  {c.activo ? "Activo" : "Inactivo"}
                </Badge>
              ),
              acciones: (
                <div className="flex flex-wrap items-center gap-3">
                  <Button
                    type="button"
                    variant="secondary"
                    className="px-2.5 py-1 text-xs"
                    onClick={() =>
                      setSelectedCliente({
                        id: c.id,
                        razon_social: c.razon_social,
                      })
                    }
                  >
                    Descuentos
                  </Button>
                  <Link
                    href={`/clientes/${c.id}`}
                    className="text-sm font-medium text-lt-primary underline-offset-2 hover:underline"
                  >
                    Editar
                  </Link>
                </div>
              ),
            },
          }))}
        />
      </Card>

      {selectedCliente ? (
        <ModalDescuentosCliente
          clienteId={selectedCliente.id}
          clienteNombre={selectedCliente.razon_social}
          isOpen={!!selectedCliente}
          onClose={() => setSelectedCliente(null)}
        />
      ) : null}
    </div>
  );
}

