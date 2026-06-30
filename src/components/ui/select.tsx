import type { SelectHTMLAttributes } from "react";

type SelectProps = SelectHTMLAttributes<HTMLSelectElement> & {
  label?: string;
  error?: string;
  options: { value: string; label: string }[];
  placeholder?: string;
};

export function Select({
  label,
  error,
  options,
  placeholder,
  className = "",
  id,
  ...props
}: SelectProps) {
  const selectId = id ?? props.name;

  return (
    <div className="space-y-1.5">
      {label && (
        <label
          htmlFor={selectId}
          className="block text-sm font-medium text-lt-text"
        >
          {label}
        </label>
      )}
      <select
        id={selectId}
        className={`lt-input w-full cursor-pointer rounded-xl border border-lt-border bg-lt-surface px-3.5 py-2.5 text-sm text-lt-text transition-colors duration-200 outline-none focus:border-lt-primary focus:ring-2 focus:ring-lt-primary/25 ${className}`}
        {...props}
      >
        {placeholder && <option value="">{placeholder}</option>}
        {options.map((opt) => (
          <option key={opt.value} value={opt.value}>
            {opt.label}
          </option>
        ))}
      </select>
      {error && <p className="text-xs text-lt-danger-text">{error}</p>}
    </div>
  );
}
