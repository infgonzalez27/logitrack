import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { getCurrentProfile } from "@/lib/auth";
import {
  canAccessHref,
  getNavSectionsForRole,
  getRoleNameFromProfile,
  homeHrefForRole,
} from "@/lib/auth/roles";
import { DashboardShell } from "@/components/layout/dashboard-shell";
import { InstallPwaPrompt } from "@/components/pwa/install-prompt";
import { TasaDelDiaGuard } from "@/components/dashboard/tasa-del-dia-guard";

export default async function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);
  const navSections = getNavSectionsForRole(rol);
  const homeHref = homeHrefForRole(rol);
  const pathname = (await headers()).get("x-lt-pathname");
  if (pathname && rol && !canAccessHref(rol, pathname)) {
    redirect(homeHref);
  }

  return (
    <DashboardShell
      userName={profile?.nombre_completo ?? "Usuario"}
      navSections={navSections}
      homeHref={homeHref}
    >
      <main className="flex-1 overflow-x-hidden overflow-y-auto p-4 pb-[max(1rem,env(safe-area-inset-bottom))] sm:p-6 lg:p-8">
        <div className="lt-no-print">
          <InstallPwaPrompt />
          <TasaDelDiaGuard
            puedeGestionar={rol === "admin" || rol === "gerente"}
          />
        </div>
        {children}
      </main>
    </DashboardShell>
  );
}
