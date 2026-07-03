"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Logo } from "@/components/brand/logo";
import type { NavSection } from "@/lib/constants";
import { logoutAction } from "@/lib/actions/auth";

export function SidebarNav({
  userName,
  navSections,
  onNavigate,
  showClose,
  onClose,
}: {
  userName: string;
  navSections: NavSection[];
  onNavigate?: () => void;
  showClose?: boolean;
  onClose?: () => void;
}) {
  const pathname = usePathname();

  return (
    <>
      <div className="border-b border-lt-border-light px-4 py-4 sm:px-5 sm:py-5">
        <div className="flex items-start justify-between gap-3">
          <Logo
            href="/"
            size="md"
            subtitle="Distribución"
            onNavigate={onNavigate}
          />
          {showClose ? (
            <button
              type="button"
              onClick={onClose}
              aria-label="Cerrar menú"
              className="cursor-pointer rounded-lg p-2 text-lt-text-muted transition-colors hover:bg-lt-primary-muted hover:text-lt-text"
            >
              <svg
                viewBox="0 0 24 24"
                fill="none"
                className="h-5 w-5"
                aria-hidden
              >
                <path
                  d="M6 6l12 12M18 6L6 18"
                  stroke="currentColor"
                  strokeWidth="2"
                  strokeLinecap="round"
                />
              </svg>
            </button>
          ) : null}
        </div>
        <p className="mt-4 truncate text-sm font-medium text-lt-text">
          {userName}
        </p>
      </div>

      <nav className="flex-1 overflow-y-auto px-3 py-4">
        {navSections.map((section) => (
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
                      onClick={onNavigate}
                      className={`block cursor-pointer rounded-xl px-3 py-2.5 text-sm transition-all duration-200 ${
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
          className="w-full cursor-pointer rounded-xl px-3 py-2.5 text-left text-sm text-lt-text-muted transition-colors duration-200 hover:bg-lt-primary-muted hover:text-lt-text"
        >
          Cerrar sesión
        </button>
      </form>
    </>
  );
}
