import type { InputHTMLAttributes } from "react";

type InputProps = InputHTMLAttributes<HTMLInputElement> & {
  label?: string;
  error?: string;
};

export function Input({ label, error, className = "", id, ...props }: InputProps) {
  const inputId = id ?? props.name;

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
        id={inputId}
        className={`lt-input w-full rounded-xl border border-lt-border bg-lt-surface px-3.5 py-2.5 text-sm text-lt-text transition-colors duration-200 placeholder:text-lt-text-subtle outline-none focus:border-lt-primary focus:ring-2 focus:ring-lt-primary/25 ${className}`}
        {...props}
      />
      {error && <p className="text-xs text-lt-danger-text">{error}</p>}
    </div>
  );
}
