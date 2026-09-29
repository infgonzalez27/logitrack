"use client";

import { useEffect, useId, useMemo, useRef, useState } from "react";

export type ClienteComboboxOption = {
  value: string;
  label: string;
  hint?: string | null;
};

const MAX_RESULTADOS = 50;

function normalizar(texto: string): string {
  return texto
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .trim();
}

export function ClienteCombobox({
  label = "Cliente",
  options,
  value,
  onChange,
  required = false,
  disabled = false,
  placeholder = "Buscar por nombre o RIF…",
  name,
  emptyMessage = "Sin clientes que coincidan.",
  minChars = 0,
}: {
  label?: string;
  name?: string;
  emptyMessage?: string;
  /** Letras mínimas antes de listar opciones (0 = lista al enfocar). */
  minChars?: number;
  options: ClienteComboboxOption[];
  value: string;
  onChange: (value: string) => void;
  required?: boolean;
  disabled?: boolean;
  placeholder?: string;
}) {
  const inputId = useId();
  const listId = useId();
  const containerRef = useRef<HTMLDivElement>(null);
  const seleccionado = options.find((o) => o.value === value) ?? null;
  const [query, setQuery] = useState(seleccionado?.label ?? "");
  const [abierto, setAbierto] = useState(false);
  const [activo, setActivo] = useState(0);

  useEffect(() => {
    if (!abierto) setQuery(seleccionado?.label ?? "");
  }, [seleccionado, abierto]);

  useEffect(() => {
    function onClickFuera(e: MouseEvent) {
      if (!containerRef.current?.contains(e.target as Node)) setAbierto(false);
    }
    document.addEventListener("mousedown", onClickFuera);
    return () => document.removeEventListener("mousedown", onClickFuera);
  }, []);

  const faltanLetras =
    minChars > 0 &&
    normalizar(query).length < minChars &&
    !(seleccionado && query === seleccionado.label);

  const resultados = useMemo(() => {
    if (faltanLetras) return [];
    const q = normalizar(query);
    const filtrados =
      !q || (seleccionado && query === seleccionado.label)
        ? options
        : options.filter(
            (o) =>
              normalizar(o.label).includes(q) ||
              normalizar(o.hint ?? "").includes(q),
          );
    return filtrados.slice(0, MAX_RESULTADOS);
  }, [options, query, seleccionado, faltanLetras]);

  function elegir(option: ClienteComboboxOption) {
    onChange(option.value);
    setQuery(option.label);
    setAbierto(false);
  }

  function onKeyDown(e: React.KeyboardEvent<HTMLInputElement>) {
    if (e.key === "ArrowDown") {
      e.preventDefault();
      setAbierto(true);
      setActivo((i) => Math.min(i + 1, resultados.length - 1));
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      setActivo((i) => Math.max(i - 1, 0));
    } else if (e.key === "Enter" && abierto) {
      e.preventDefault();
      const option = resultados[activo];
      if (option) elegir(option);
    } else if (e.key === "Escape") {
      setAbierto(false);
    }
  }

  return (
    <div ref={containerRef} className="relative space-y-1.5">
      <label htmlFor={inputId} className="block text-sm font-medium text-lt-text">
        {label}
      </label>
      <input
        id={inputId}
        type="text"
        role="combobox"
        aria-expanded={abierto}
        aria-controls={listId}
        autoComplete="off"
        disabled={disabled}
        placeholder={placeholder}
        value={query}
        onFocus={(e) => {
          setAbierto(true);
          setActivo(0);
          e.target.select();
        }}
        onChange={(e) => {
          setQuery(e.target.value);
          setAbierto(true);
          setActivo(0);
          if (value) onChange("");
        }}
        onKeyDown={onKeyDown}
        className="lt-input w-full rounded-xl border border-lt-border bg-lt-surface px-3.5 py-2.5 text-sm text-lt-text transition-colors duration-200 placeholder:text-lt-text-subtle outline-none focus:border-lt-primary focus:ring-2 focus:ring-lt-primary/25 disabled:cursor-not-allowed disabled:opacity-70"
      />
      {/* Validación nativa del formulario: el texto visible no es el valor. */}
      <input
        tabIndex={-1}
        aria-hidden
        name={name}
        required={required}
        value={value}
        onChange={() => {}}
        onFocus={() => document.getElementById(inputId)?.focus()}
        className="pointer-events-none absolute bottom-0 left-4 h-px w-px opacity-0"
      />
      {abierto && !disabled ? (
        <ul
          id={listId}
          role="listbox"
          className="absolute z-30 mt-1 max-h-72 w-full overflow-y-auto rounded-xl border border-lt-border bg-lt-surface py-1 shadow-lg"
        >
          {faltanLetras ? (
            <li className="px-3.5 py-2.5 text-sm text-lt-text-muted">
              Escribe al menos {minChars} letras para buscar.
            </li>
          ) : resultados.length === 0 ? (
            <li className="px-3.5 py-2.5 text-sm text-lt-text-muted">
              {emptyMessage}
            </li>
          ) : (
            resultados.map((o, i) => (
              <li
                key={o.value}
                role="option"
                aria-selected={o.value === value}
                onMouseDown={(e) => e.preventDefault()}
                onMouseEnter={() => setActivo(i)}
                onClick={() => elegir(o)}
                className={`cursor-pointer px-3.5 py-2 text-sm ${
                  i === activo ? "bg-lt-surface-muted" : ""
                } ${o.value === value ? "font-semibold text-lt-primary" : "text-lt-text"}`}
              >
                <span className="block truncate">{o.label}</span>
                {o.hint ? (
                  <span className="block text-xs text-lt-text-muted">{o.hint}</span>
                ) : null}
              </li>
            ))
          )}
          {resultados.length === MAX_RESULTADOS ? (
            <li className="px-3.5 py-2 text-xs text-lt-text-muted">
              Mostrando los primeros {MAX_RESULTADOS}. Escribe más para afinar.
            </li>
          ) : null}
        </ul>
      ) : null}
    </div>
  );
}
