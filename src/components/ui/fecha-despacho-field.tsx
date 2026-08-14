"use client";

import { useRef } from "react";

/** Día de despacho con botón que abre el calendario nativo. Conserva la hora (default 08:00). */
export function FechaDespachoField({
  label = "Fecha de despacho",
  value,
  onChange,
  required,
  name,
}: {
  label?: string;
  value: string;
  onChange: (value: string) => void;
  required?: boolean;
  name?: string;
}) {
  const dateRef = useRef<HTMLInputElement>(null);
  const datePart = value.slice(0, 10);
  const timePart =
    value.includes("T") && value.length >= 16 ? value.slice(11, 16) : "08:00";

  function openCalendar() {
    const el = dateRef.current;
    if (!el) return;
    if (typeof el.showPicker === "function") {
      try {
        el.showPicker();
        return;
      } catch {
        /* algunos navegadores bloquean showPicker sin gesto directo */
      }
    }
    el.focus();
    el.click();
  }

  return (
    <div className="space-y-1.5">
      <label
        htmlFor={name ?? "fecha_despacho_dia"}
        className="block text-sm font-medium text-lt-text"
      >
        {label}
        {required ? <span className="text-lt-danger-text"> *</span> : null}
      </label>
      <div className="flex gap-2">
        <input
          ref={dateRef}
          id={name ?? "fecha_despacho_dia"}
          name={name}
          type="date"
          required={required}
          value={datePart}
          onChange={(e) => {
            const day = e.target.value;
            if (!day) {
              onChange("");
              return;
            }
            onChange(`${day}T${timePart}`);
          }}
          className="lt-input min-w-0 flex-1 rounded-xl border border-lt-border bg-lt-surface px-3.5 py-2.5 text-sm text-lt-text outline-none transition-colors duration-200 focus:border-lt-primary focus:ring-2 focus:ring-lt-primary/25"
        />
        <button
          type="button"
          onClick={openCalendar}
          className="inline-flex shrink-0 items-center justify-center gap-2 rounded-xl border border-lt-border bg-lt-surface px-3.5 py-2.5 text-sm font-medium text-lt-text transition hover:border-lt-primary hover:bg-lt-primary-muted"
          title="Abrir calendario"
          aria-label="Abrir calendario"
        >
          <CalendarIcon />
          <span className="hidden sm:inline">Calendario</span>
        </button>
      </div>
      <p className="text-[11px] text-lt-text-subtle">
        Hora de despacho: {timePart} (hora local del vendedor).
      </p>
    </div>
  );
}

function CalendarIcon() {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.75"
      strokeLinecap="round"
      strokeLinejoin="round"
      className="h-5 w-5"
      aria-hidden
    >
      <rect x="3" y="4" width="18" height="18" rx="2" />
      <path d="M16 2v4M8 2v4M3 10h18" />
    </svg>
  );
}
