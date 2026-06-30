"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { NAV_SECTIONS } from "@/lib/constants";
import { logoutAction } from "@/lib/actions/auth";

function LogoMark() {
  return (
    <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-lt-primary shadow-sm">
      <svg
        viewBox="0 0 24 24"
        fill="none"
        className="h-5 w-5 text-white"
        aria-hidden
      >
        <path
          d="M3 7h11v8H3V7zm11 2h4l3 3v3h-7V9z"
          stroke="currentColor"
          strokeWidth="1.75"
          strokeLinejoin="round"
        />
        <circle cx="7" cy="17" r="2" fill="currentColor" />
        <circle cx="17" cy="17" r="2" fill="currentColor" />
      </svg>
    </div>
  );
}

export function Sidebar({ userName }: { userName: string }) {
  const pathname = usePathname();

  return (
    <aside
      className="flex w-64 shrink-0 flex-col border-r border-lt-border-light bg-lt-surface"
      style={{ boxShadow: "var(--lt-shadow-sidebar)" }}
    >
      <div className="border-b border-lt-border-light px-5 py-5">
        <div className="flex items-center gap-3">
          <LogoMark />
          <div>
            <p className="font-display text-sm font-bold tracking-tight text-lt-text">
              LogiTrack
            </p>
            <p className="text-xs text-lt-text-muted">Distribución</p>
          </div>
        </div>
        <p className="mt-4 truncate text-sm font-medium text-lt-text">
          {userName}
        </p>
      </div>

      <nav className="flex-1 overflow-y-auto px-3 py-4">
        {NAV_SECTIONS.map((section) => (
          <div key={section.title} className="mb-5">
            <p className="mb-2 px-2 text-[11px] font-semibold uppercase tracking-wider text-lt-text-subtle">
              {section.title}
            </p>
            <ul className="space-y-0.5">
              {section.items.map((item) => {
                const active =
                  pathname === item.href ||
                  pathname.startsWith(`${item.href}/`);
                return (
                  <li key={item.href}>
                    <Link
                      href={item.href}
                      className={`block cursor-pointer rounded-xl px-3 py-2 text-sm transition-all duration-200 ${
                        active
                          ? "bg-lt-primary font-medium text-white shadow-sm"
                          : "text-lt-text-muted hover:bg-lt-primary-muted hover:text-lt-text"
                      }`}
                    >
                      {item.label}
                    </Link>
                  </li>
                );
              })}
            </ul>
          </div>
        ))}
      </nav>

      <form action={logoutAction} className="border-t border-lt-border-light p-3">
        <button
          type="submit"
          className="w-full cursor-pointer rounded-xl px-3 py-2 text-left text-sm text-lt-text-muted transition-colors duration-200 hover:bg-lt-primary-muted hover:text-lt-text"
        >
          Cerrar sesión
        </button>
      </form>
    </aside>
  );
}
