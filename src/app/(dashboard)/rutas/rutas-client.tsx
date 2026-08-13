"use client";

import { useState, useTransition } from "react";
import {
  actualizaRegistroRutaAction,
  crearRutaAction,
} from "@/lib/actions/rutas";
import { formatDate } from "@/lib/format";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Card } from "@/components/ui/card";
import { DataTable } from "@/components/ui/data-table";
import type { Ruta } from "@/types/database";

export function RutasClient({
  rutasIniciales,
  puedeGestionar,
}: {
  rutasIniciales: Ruta[];
  puedeGestionar: boolean;
}) {
  const [rutas, setRutas] = useState<Ruta[]>(rutasIniciales);
  const [nombreNuevo, setNombreNuevo] = useState("");
  const [descNueva, setDescNueva] = useState("");
  const [editId, setEditId] = useState<string | null>(null);
  const [editNombre, setEditNombre] = useState("");
  const [editDesc, setEditDesc] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [okMsg, setOkMsg] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  function startEdit(ruta: Ruta) {
    setEditId(ruta.id_ruta);
    setEditNombre(ruta.nombre_ruta);
    setEditDesc(ruta.descripcion_ruta ?? "");
    setError(null);
    setOkMsg(null);
  }

  function cancelEdit() {
    setEditId(null);
    setEditNombre("");
    setEditDesc("");
  }

  const rows = rutas.map((ruta) => {
    const editing = editId === ruta.id_ruta;
    return {
      id: ruta.id_ruta,
      cells: {
        nombre: editing ? (
          <Input
            value={editNombre}
            onChange={(e) => setEditNombre(e.target.value)}
            disabled={pending}
            aria-label="Nombre de ruta"
          />
        ) : (
          ruta.nombre_ruta
        ),
        descripcion: editing ? (
          <Input
            value={editDesc}
            onChange={(e) => setEditDesc(e.target.value)}
            disabled={pending}
            aria-label="Descripción de ruta"
          />
        ) : (
          ruta.descripcion_ruta || "—"
        ),
        creado: formatDate(ruta.created_at),
        acciones: puedeGestionar ? (
          editing ? (
            <div className="flex flex-wrap gap-2">
              <Button
                type="button"
                className="px-3 py-1.5 text-xs"
                disabled={pending}
                onClick={() => {
                  setError(null);
                  setOkMsg(null);
                  startTransition(async () => {
                    const result = await actualizaRegistroRutaAction({
                      id_ruta: ruta.id_ruta,
                      nombre_ruta: editNombre,
                      descripcion_ruta: editDesc,
                    });
                    if (!result.ok) {
                      setError(result.error);
                      return;
                    }
                    setRutas((prev) =>
                      prev.map((r) =>
                        r.id_ruta === result.ruta.id_ruta ? result.ruta : r,
                      ),
                    );
                    setOkMsg(result.ruta.nombre_ruta + " actualizada.");
                    cancelEdit();
                  });
                }}
              >
                Guardar
              </Button>
              <Button
                type="button"
                className="px-3 py-1.5 text-xs"
                variant="ghost"
                disabled={pending}
                onClick={cancelEdit}
              >
                Cancelar
              </Button>
            </div>
          ) : (
            <Button
              type="button"
              className="px-3 py-1.5 text-xs"
              variant="ghost"
              disabled={pending || editId !== null}
              onClick={() => startEdit(ruta)}
            >
              Editar
            </Button>
          )
        ) : (
          "—"
        ),
      },
    };
  });

  return (
    <div className="space-y-6">
      {error ? <p className="lt-alert-error">{error}</p> : null}
      {okMsg ? <p className="lt-alert-success">{okMsg}</p> : null}

      {puedeGestionar ? (
        <Card className="space-y-4">
          <h2 className="text-sm font-semibold text-lt-text">Nueva ruta</h2>
          <div className="grid gap-3 sm:grid-cols-2">
            <Input
              label="Nombre"
              value={nombreNuevo}
              onChange={(e) => setNombreNuevo(e.target.value)}
              disabled={pending}
              required
            />
            <Input
              label="Descripción"
              value={descNueva}
              onChange={(e) => setDescNueva(e.target.value)}
              disabled={pending}
            />
          </div>
          <Button
            type="button"
            disabled={pending || !nombreNuevo.trim()}
            onClick={() => {
              setError(null);
              setOkMsg(null);
              startTransition(async () => {
                const result = await crearRutaAction({
                  nombre_ruta: nombreNuevo,
                  descripcion_ruta: descNueva,
                });
                if (!result.ok) {
                  setError(result.error);
                  return;
                }
                setRutas((prev) =>
                  [...prev, result.ruta].sort((a, b) =>
                    a.nombre_ruta.localeCompare(b.nombre_ruta, "es"),
                  ),
                );
                setNombreNuevo("");
                setDescNueva("");
                setOkMsg(`Ruta “${result.ruta.nombre_ruta}” creada.`);
              });
            }}
          >
            Crear ruta
          </Button>
        </Card>
      ) : null}

      <Card>
        <DataTable
          columns={[
            { key: "nombre", label: "Nombre" },
            { key: "descripcion", label: "Descripción" },
            { key: "creado", label: "Creada" },
            { key: "acciones", label: "" },
          ]}
          rows={rows}
          emptyMessage="No hay rutas registradas."
        />
      </Card>
    </div>
  );
}
