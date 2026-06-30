"use client";

import { useEffect, useState } from "react";
import { usePathname } from "next/navigation";
import { Logo } from "@/components/brand/logo";
import { SidebarNav } from "@/components/layout/sidebar-nav";

export function DashboardShell({
  userName,
  children,
}: {
  userName: string;
  children: React.ReactNode;
}) {
  const [menuOpen, setMenuOpen] = useState(false);
  const pathname = usePathname();

  useEffect(() => {
    document.body.style.overflow = menuOpen ? "hidden" : "";
    return () => {
      document.body.style.overflow = "";
    };
  }, [menuOpen]);

  useEffect(() => {
    setMenuOpen(false);
  }, [pathname]);

  return (
    <div className="min-h-screen bg-lt-bg">
      <header className="sticky top-0 z-40 flex items-center gap-3 border-b border-lt-border-light bg-lt-surface/95 px-4 pb-3 pt-[max(0.75rem,env(safe-area-inset-top))] backdrop-blur-sm lg:hidden">
        <button
          type="button"
          onClick={() => setMenuOpen(true)}
          aria-label="Abrir menú"
          aria-expanded={menuOpen}
          className="cursor-pointer rounded-xl border border-lt-border-light p-2.5 text-lt-text transition-colors hover:bg-lt-primary-muted"
        >
          <svg
            viewBox="0 0 24 24"
            fill="none"
            className="h-5 w-5"
            aria-hidden
          >
            <path
              d="M4 7h16M4 12h16M4 17h16"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
            />
          </svg>
        </button>
        <Logo href="/ordenes" size="sm" showWordmark />
        <p className="ml-auto max-w-[40%] truncate text-right text-xs font-medium text-lt-text-muted">
          {userName}
        </p>
      </header>

      {menuOpen ? (
        <div className="fixed inset-0 z-50 lg:hidden">
          <button
            type="button"
            aria-label="Cerrar menú"
            className="absolute inset-0 cursor-pointer bg-lt-text/40"
            onClick={() => setMenuOpen(false)}
          />
          <aside
            className="relative flex h-full w-[min(100%,18rem)] flex-col bg-lt-surface shadow-2xl"
            style={{ boxShadow: "var(--lt-shadow-sidebar)" }}
          >
            <SidebarNav
              userName={userName}
              onNavigate={() => setMenuOpen(false)}
              showClose
              onClose={() => setMenuOpen(false)}
            />
          </aside>
        </div>
      ) : null}

      <div className="flex min-h-[calc(100dvh-3.5rem)] lg:min-h-screen">
        <aside
          className="hidden w-64 shrink-0 flex-col border-r border-lt-border-light bg-lt-surface lg:flex"
          style={{ boxShadow: "var(--lt-shadow-sidebar)" }}
        >
          <SidebarNav userName={userName} />
        </aside>

        <div className="flex min-w-0 flex-1 flex-col">{children}</div>
      </div>
    </div>
  );
}
