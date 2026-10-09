"use client";

import { useEffect, useRef, type InputHTMLAttributes } from "react";

type InputProps = InputHTMLAttributes<HTMLInputElement> & {
  label?: string;
  error?: string;
};

export function Input({ label, error, className = "", id, ...props }: InputProps) {
  const inputId = id ?? props.name;
  const ref = useRef<HTMLInputElement>(null);

  useEffect(() => {
    const el = ref.current;
    if (props.type === "number" && el) {
      const handleFocus = () => {
        if (el.value === "0") {
          el.value = "";
          el.dispatchEvent(new Event("input", { bubbles: true }));
        }
      };

      const handleBlur = () => {
        if (el.value === "") {
          el.value = "0";
          el.dispatchEvent(new Event("input", { bubbles: true }));
        }
      };

      el.addEventListener("focus", handleFocus);
      el.addEventListener("blur", handleBlur);
      return () => {
        el.removeEventListener("focus", handleFocus);
        el.removeEventListener("blur", handleBlur);
      };
    }
  }, [props.type]);

  return (
    <div className="space-y-1.5">
      {label && (
        <label
          htmlFor={inputId}
          className="block text-sm font-medium text-lt-text"
        >
          {label}
        </label>
      )}
      <input
        ref={ref}
        id={inputId}
        className={`lt-input w-full rounded-xl border border-lt-border bg-lt-surface px-3.5 py-2.5 text-sm text-lt-text transition-colors duration-200 placeholder:text-lt-text-subtle outline-none focus:border-lt-primary focus:ring-2 focus:ring-lt-primary/25 ${className}`}
        {...props}
      />
      {error && <p className="text-xs text-lt-danger-text">{error}</p>}
    </div>
  );
}
