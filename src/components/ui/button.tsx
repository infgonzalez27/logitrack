import Link from "next/link";
import type { ReactNode } from "react";

const base =
  "lt-btn inline-flex cursor-pointer items-center justify-center rounded-xl px-4 py-2.5 text-sm font-medium transition-all duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-lt-primary focus-visible:ring-offset-2 disabled:pointer-events-none disabled:opacity-50";

const variants = {
  primary: "lt-btn-primary bg-lt-primary text-white shadow-sm hover:bg-lt-primary-hover active:bg-lt-primary-active",
  secondary:
    "border border-lt-border bg-lt-surface text-lt-text hover:border-lt-primary-pastel hover:bg-lt-surface-muted",
  danger:
    "bg-lt-danger-text text-white shadow-sm hover:opacity-90 active:opacity-95",
  ghost:
    "text-lt-text-muted hover:bg-lt-primary-muted hover:text-lt-text",
};

type ButtonProps = {
  variant?: keyof typeof variants;
  href?: string;
  className?: string;
  children: ReactNode;
} & React.ButtonHTMLAttributes<HTMLButtonElement>;

export function Button({
  variant = "primary",
  href,
  className = "",
  children,
  ...props
}: ButtonProps) {
  const classes = `${base} ${variants[variant]} ${className}`;

  if (href) {
    return (
      <Link href={href} className={classes}>
        {children}
      </Link>
    );
  }

  return (
    <button className={classes} {...props}>
      {children}
    </button>
  );
}
