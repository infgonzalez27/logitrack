"use client";

import { useEffect, useState, useTransition } from "react";
import { actualizaRegistroRutaAction } from "@/lib/actions/rutas";
import { formatDate } from "@/lib/format";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Card } from "@/components/ui/card";
import type { Ruta } from "@/types/database";

type Draft = {
  nombre_ruta: string;
  descripcion_ruta: string;
};

export function RutasClient({
  rutasIniciales,
  puedeEditar,
}: {
  rutasIniciales: Ruta[];
  puedeEditar: boolean;
}) {
  const [rutas, setRutas] = useState<Ruta[]>(rutasIniciales);
  const [drafts, setDrafts] = useState<Record<string, Draft>>(() =>
    Object.fromEntries(
      rutasIniciales.map((r) => [
        r.id_ruta,
        {
          nombre_ruta: r.nombre_ruta,
          descripcion_ruta: r.descripcion_ruta ?? "",
        },
      ]),
    ),
  );
  const [savingId, setSavingId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [okMsg, setOkMsg] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  useEffect(() => {
    setRutas(rutasIniciales);
    setDrafts(
      Object.fromEntries(
        rutasIniciales.map((r) => [
          r.id_ruta,
          {
            nombre_ruta: r.nombre_ruta,
            descripcion_ruta: r.descripcion_ruta ?? "",
          },
        ]),
      ),
    );
  }, [rutasIniciales]);

  function updateDraft(id: string, patch: Partial<Draft>) {
    setDrafts((prev) => ({
      ...prev,
      [id]: { ...prev[id], ...patch },
    }));
  }

  function isDirty(ruta: Ruta): boolean {
    const draft = drafts[ruta.id_ruta];
    if (!draft) return false;
    return (
      draft.nombre_ruta.trim() !== ruta.nombre_ruta ||
      (draft.descripcion_ruta.trim() || "") !== (ruta.descripcion_ruta ?? "")
    );
  }

  function guardar(ruta: Ruta) {
    const draft = drafts[ruta.id_ruta];
    if (!draft) return;

    setError(null);
    setOkMsg(null);
    setSavingId(ruta.id_ruta);

    startTransition(async () => {
      const result = await actualizaRegistroRutaAction({
        id_ruta: ruta.id_ruta,
        nombre_ruta: draft.nombre_ruta,
        descripcion_ruta: draft.descripcion_ruta,
      });

      setSavingId(null);

      if (!result.ok) {
        setError(result.error);
        return;
      }

      setRutas((prev) =>
        prev.map((r) => (r.id_ruta === result.ruta.id_ruta ? result.ruta : r)),
      );
      setDrafts((prev) => ({
        ...prev,
        [result.ruta.id_ruta]: {
          nombre_ruta: result.ruta.nombre_ruta,
          descripcion_ruta: result.ruta.descripcion_ruta ?? "",
        },
      }));
      setOkMsg(`Ruta “${result.ruta.nombre_ruta}” actualizada.`);
    });
  }

  if (!rutas.length) {
    return (
      <p className="rounded-xl border border-dashed border-lt-border px-4 py-10 text-center text-sm text-lt-text-muted">
        No hay rutas registradas.
      </p>
    );
  }

  return (
    <div className="space-y-4">
      {error ? <p className="lt-alert-error">{error}</p> : null}
      {okMsg ? <p className="lt-alert-success">{okMsg}</p> : null}
      <p className="text-sm text-lt-text-muted">
        {puedeEditar
          ? "Puedes cambiar el nombre y la descripción de cada ruta. No se pueden crear rutas nuevas desde la app."
          : "Solo consulta. Para editar nombre o descripción necesitas rol admin o gerente."}
      </p>

      <div className="space-y-4">
        {rutas.map((ruta) => {
          const draft = drafts[ruta.id_ruta] ?? {
            nombre_ruta: ruta.nombre_ruta,
            descripcion_ruta: ruta.descripcion_ruta ?? "",
          };
          const dirty = isDirty(ruta);
          const saving = pending && savingId === ruta.id_ruta;

          return (
            <Card key={ruta.id_ruta} className="space-y-4">
              {puedeEditar ? (
                <>
                  <Input
                    label="Nombre"
                    value={draft.nombre_ruta}
                    onChange={(e) =>
                      updateDraft(ruta.id_ruta, {
                        nombre_ruta: e.target.value,
                      })
                    }
                    disabled={saving}
                    required
                  />
                  <Input
                    label="Descripción"
                    value={draft.descripcion_ruta}
                    onChange={(e) =>
                      updateDraft(ruta.id_ruta, {
                        descripcion_ruta: e.target.value,
                      })
                    }
                    disabled={saving}
                  />
                </>
              ) : (
                <dl className="grid gap-3 sm:grid-cols-2">
                  <div>
                    <dt className="text-xs font-medium uppercase tracking-wide text-lt-text-subtle">
                      Nombre
                    </dt>
                    <dd className="mt-1 text-sm text-lt-text">
                      {ruta.nombre_ruta}
                    </dd>
                  </div>
                  <div>
                    <dt className="text-xs font-medium uppercase tracking-wide text-lt-text-subtle">
                      Descripción
                    </dt>
                    <dd className="mt-1 text-sm text-lt-text">
                      {ruta.descripcion_ruta || "—"}
                    </dd>
                  </div>
                </dl>
              )}

              <div className="flex flex-wrap items-center justify-between gap-3">
                <p className="text-xs text-lt-text-muted">
                  Creada: {formatDate(ruta.created_at)}
                </p>
                {puedeEditar ? (
                  <Button
                    type="button"
                    disabled={saving || !dirty || !draft.nombre_ruta.trim()}
                    onClick={() => guardar(ruta)}
                  >
                    {saving ? "Guardando…" : "Guardar cambios"}
                  </Button>
                ) : null}
              </div>
            </Card>
          );
        })}
      </div>
    </div>
  );
}
