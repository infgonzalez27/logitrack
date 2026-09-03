"use client";

import { useEffect, useState } from "react";
import { usePathname } from "next/navigation";
import { Logo } from "@/components/brand/logo";
import type { NavSection } from "@/lib/constants";
import { SidebarNav } from "@/components/layout/sidebar-nav";
import { UserMenu } from "@/components/layout/user-menu";

export function DashboardShell({
  userName,
  roleLabel,
  navSections,
  homeHref = "/",
  children,
}: {
  userName: string;
  roleLabel?: string;
  navSections: NavSection[];
  homeHref?: string;
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
      <header className="lt-no-print sticky top-0 z-40 flex items-center gap-3 border-b border-lt-border-light bg-lt-surface/95 px-4 pb-3 pt-[max(0.75rem,env(safe-area-inset-top))] backdrop-blur-sm lg:px-6">
        <button
          type="button"
          onClick={() => setMenuOpen(true)}
          aria-label="Abrir menú"
          aria-expanded={menuOpen}
          className="cursor-pointer rounded-xl border border-lt-border-light p-2.5 text-lt-text transition-colors hover:bg-lt-primary-muted lg:hidden"
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
        <Logo href={homeHref} size="sm" showWordmark className="lg:hidden" />
        <div className="ml-auto">
          <UserMenu userName={userName} roleLabel={roleLabel} />
        </div>
      </header>

      {menuOpen ? (
        <div className="lt-no-print fixed inset-0 z-50 lg:hidden">
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
              navSections={navSections}
              homeHref={homeHref}
              onNavigate={() => setMenuOpen(false)}
              showClose
              onClose={() => setMenuOpen(false)}
            />
          </aside>
        </div>
      ) : null}

      <div className="flex min-h-[calc(100dvh-3.75rem)]">
        <aside
          className="lt-no-print sticky top-[3.75rem] hidden h-[calc(100dvh-3.75rem)] w-64 shrink-0 flex-col border-r border-lt-border-light bg-lt-surface lg:flex"
          style={{ boxShadow: "var(--lt-shadow-sidebar)" }}
        >
          <SidebarNav navSections={navSections} homeHref={homeHref} />
        </aside>

        <div className="flex min-w-0 flex-1 flex-col">{children}</div>
      </div>
    </div>
  );
}
