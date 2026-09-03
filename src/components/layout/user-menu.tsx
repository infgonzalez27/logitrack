"use client";

import { useEffect, useId, useRef, useState } from "react";
import { logoutAction } from "@/lib/actions/auth";

function initialsFromName(name: string): string {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (!parts.length) return "?";
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return `${parts[0][0] ?? ""}${parts[1][0] ?? ""}`.toUpperCase();
}

export function UserMenu({
  userName,
  roleLabel,
}: {
  userName: string;
  roleLabel?: string;
}) {
  const [open, setOpen] = useState(false);
  const rootRef = useRef<HTMLDivElement>(null);
  const menuId = useId();
  const initials = initialsFromName(userName);

  useEffect(() => {
    if (!open) return;

    function onPointerDown(e: MouseEvent) {
      if (!rootRef.current?.contains(e.target as Node)) {
        setOpen(false);
      }
    }
    function onKeyDown(e: KeyboardEvent) {
      if (e.key === "Escape") setOpen(false);
    }

    document.addEventListener("mousedown", onPointerDown);
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.removeEventListener("mousedown", onPointerDown);
      document.removeEventListener("keydown", onKeyDown);
    };
  }, [open]);

  return (
    <div ref={rootRef} className="relative">
      <button
        type="button"
        aria-haspopup="menu"
        aria-expanded={open}
        aria-controls={menuId}
        onClick={() => setOpen((v) => !v)}
        className="flex cursor-pointer items-center gap-2 rounded-full p-0.5 transition-colors hover:bg-lt-primary-muted focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-lt-primary"
      >
        <span className="flex h-9 w-9 items-center justify-center rounded-full bg-lt-primary text-sm font-semibold text-white shadow-sm">
          {initials}
        </span>
        <span className="hidden max-w-[9rem] truncate text-left text-sm font-medium text-lt-text sm:block">
          {userName.split(" ")[0]}
        </span>
        <svg
          viewBox="0 0 20 20"
          fill="currentColor"
          className={`hidden h-4 w-4 text-lt-text-muted transition-transform sm:block ${open ? "rotate-180" : ""}`}
          aria-hidden
        >
          <path
            fillRule="evenodd"
            d="M5.23 7.21a.75.75 0 011.06.02L10 11.17l3.71-3.94a.75.75 0 111.08 1.04l-4.25 4.5a.75.75 0 01-1.08 0l-4.25-4.5a.75.75 0 01.02-1.06z"
            clipRule="evenodd"
          />
        </svg>
      </button>

      {open ? (
        <div
          id={menuId}
          role="menu"
          className="absolute right-0 z-50 mt-2 w-64 origin-top-right rounded-2xl border border-lt-border bg-lt-surface p-2 shadow-lg"
        >
          <div className="rounded-xl bg-lt-surface-muted px-3 py-3">
            <p className="truncate text-sm font-semibold text-lt-text">
              {userName}
            </p>
            {roleLabel ? (
              <p className="mt-0.5 text-xs text-lt-text-muted">{roleLabel}</p>
            ) : null}
          </div>

          <form action={logoutAction} className="mt-1">
            <button
              type="submit"
              role="menuitem"
              className="flex w-full cursor-pointer items-center gap-2 rounded-xl px-3 py-2.5 text-left text-sm font-medium text-lt-danger-text transition-colors hover:bg-lt-danger-bg"
            >
              <svg
                viewBox="0 0 24 24"
                fill="none"
                className="h-4 w-4 shrink-0"
                aria-hidden
              >
                <path
                  d="M10 7V6a2 2 0 012-2h7a2 2 0 012 2v12a2 2 0 01-2 2h-7a2 2 0 01-2-2v-1M15 12H4m0 0l3-3m-3 3l3 3"
                  stroke="currentColor"
                  strokeWidth="2"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                />
              </svg>
              Cerrar sesión
            </button>
          </form>
        </div>
      ) : null}
    </div>
  );
}
