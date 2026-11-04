"use client";

import { useState } from "react";

export const DIAS_SEMANA_OPCIONES = [
  { value: "lunes", label: "Lunes" },
  { value: "martes", label: "Martes" },
  { value: "miercoles", label: "Miércoles" },
  { value: "jueves", label: "Jueves" },
  { value: "viernes", label: "Viernes" },
  { value: "sabado", label: "Sábado" },
  { value: "domingo", label: "Domingo" },
] as const;

export function SelectorDiasVisita({
  defaultCualquierDia = true,
  defaultDias = [],
  onChange,
}: {
  defaultCualquierDia?: boolean;
  defaultDias?: string[];
  onChange?: (val: { visitaCualquierDia: boolean; diasVisita: string[] }) => void;
}) {
  const [visitaCualquierDia, setVisitaCualquierDia] = useState<boolean>(
    defaultCualquierDia || defaultDias.length === 0,
  );
  const [diasVisita, setDiasVisita] = useState<string[]>(
    defaultCualquierDia ? [] : defaultDias.slice(0, 2),
  );

  function handleToggleCualquierDia(checked: boolean) {
    setVisitaCualquierDia(checked);
    const nuevosDias = checked ? [] : diasVisita.length ? diasVisita : ["lunes"];
    if (!checked && !diasVisita.length) {
      setDiasVisita(nuevosDias);
    }
    onChange?.({ visitaCualquierDia: checked, diasVisita: checked ? [] : nuevosDias });
  }

  function handleToggleDia(diaVal: string) {
    let nuevos: string[];
    if (diasVisita.includes(diaVal)) {
      nuevos = diasVisita.filter((d) => d !== diaVal);
      // Si desmarca todos, pasamos a cualquier día automáticamente
      if (nuevos.length === 0) {
        setVisitaCualquierDia(true);
        setDiasVisita([]);
        onChange?.({ visitaCualquierDia: true, diasVisita: [] });
        return;
      }
    } else {
      if (diasVisita.length >= 2) return; // Máximo 2 días permitidos
      nuevos = [...diasVisita, diaVal];
    }
    setDiasVisita(nuevos);
    setVisitaCualquierDia(false);
    onChange?.({ visitaCualquierDia: false, diasVisita: nuevos });
  }

  return (
    <div className="space-y-3 rounded-xl border border-lt-border bg-lt-surface p-4">
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2">
        <div>
          <label className="text-sm font-semibold text-lt-text">
            Días de Visita programados
          </label>
          <p className="text-xs text-lt-text-muted">
            Configura la jornada de atención para la cartera del vendedor en la App.
          </p>
        </div>

        <label className="inline-flex items-center gap-2 cursor-pointer select-none">
          <input
            type="checkbox"
            checked={visitaCualquierDia}
            onChange={(e) => handleToggleCualquierDia(e.target.checked)}
            className="h-4 w-4 rounded border-lt-border text-lt-primary focus:ring-lt-primary"
          />
          <span className="text-sm font-medium text-lt-text">
            Cualquier día de la semana
          </span>
        </label>
      </div>

      {/* Inputs ocultos para enviar en FormData */}
      <input
        type="hidden"
        name="visita_cualquier_dia"
        value={visitaCualquierDia ? "true" : "false"}
      />
      {!visitaCualquierDia &&
        diasVisita.map((d) => (
          <input key={d} type="hidden" name="dias_visita" value={d} />
        ))}

      {visitaCualquierDia ? (
        <div className="rounded-lg bg-lt-surface-muted p-2.5 text-xs text-lt-text-subtle">
          El cliente podrá ser visitado todos los días de la semana sin restricción de filtro en la APK.
        </div>
      ) : (
        <div className="space-y-2">
          <div className="flex items-center justify-between text-xs text-lt-text-muted">
            <span>Selecciona hasta 2 días de la semana:</span>
            <span
              className={`font-semibold ${
                diasVisita.length === 2 ? "text-amber-800" : "text-lt-primary"
              }`}
            >
              {diasVisita.length} de 2 días seleccionados
            </span>
          </div>

          <div className="grid grid-cols-2 sm:grid-cols-4 md:grid-cols-7 gap-2">
            {DIAS_SEMANA_OPCIONES.map((dia) => {
              const seleccionado = diasVisita.includes(dia.value);
              const deshabilitado = !seleccionado && diasVisita.length >= 2;

              return (
                <button
                  key={dia.value}
                  type="button"
                  onClick={() => handleToggleDia(dia.value)}
                  disabled={deshabilitado}
                  className={`rounded-lg py-2 px-3 text-xs font-semibold border transition-all ${
                    seleccionado
                      ? "bg-lt-primary text-white border-lt-primary shadow-xs"
                      : deshabilitado
                        ? "bg-gray-100 text-gray-400 border-gray-200 cursor-not-allowed"
                        : "bg-lt-surface text-lt-text border-lt-border hover:bg-lt-surface-muted"
                  }`}
                >
                  {dia.label}
                </button>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
}

