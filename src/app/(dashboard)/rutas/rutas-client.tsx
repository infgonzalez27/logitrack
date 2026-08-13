"use client";

import { useState, useTransition } from "react";
import { actualizaRegistroRutaAction } from "@/lib/actions/rutas";
import { formatDate } from "@/lib/format";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Card } from "@/components/ui/card";
import { DataTable } from "@/components/ui/data-table";
import type { Ruta } from "@/types/database";

export function RutasClient({
  rutasIniciales,
  puedeEditar,
}: {
  rutasIniciales: Ruta[];
  puedeEditar: boolean;
}) {
  const [rutas, setRutas] = useState<Ruta[]>(rutasIniciales);
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
        acciones: puedeEditar ? (
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
                    setOkMsg(`${result.ruta.nombre_ruta} actualizada.`);
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
    <div className="space-y-4">
      {error ? <p className="lt-alert-error">{error}</p> : null}
      {okMsg ? <p className="lt-alert-success">{okMsg}</p> : null}
      {!puedeEditar ? (
        <p className="text-sm text-lt-text-muted">
          Solo consulta. La creación de rutas la gestiona el administrador de
          BD (no hay RPC de alta en INTEGRACION-RPC).
        </p>
      ) : (
        <p className="text-sm text-lt-text-muted">
          Edición vía <code>actualiza_registro_rutas_segun_uuid</code>. El alta
          de rutas nuevas la aplica el admin de BD (sin RPC de creación).
        </p>
      )}
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
