import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { getCurrentProfile } from "@/lib/auth";
import { resolveUserEmpresa } from "@/lib/supabase/central";
import {
  canAccessHref,
  getNavSectionsForRole,
  getRoleNameFromProfile,
  homeHrefForRole,
  labelRol,
} from "@/lib/auth/roles";
import { DashboardShell } from "@/components/layout/dashboard-shell";
import { StorageBaseProvider } from "@/components/media/storage-context";
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
  const empresa = profile ? await resolveUserEmpresa(profile.id) : null;
  const activeSupabaseUrl = (
    empresa?.supabase_url ||
    process.env.NEXT_PUBLIC_SUPABASE_URL ||
    ""
  ).replace(/\/$/, "");
  const storageBaseUrl = activeSupabaseUrl
    ? `${activeSupabaseUrl}/storage/v1/object/public`
    : "";

  return (
    <StorageBaseProvider baseUrl={storageBaseUrl}>
      <DashboardShell
        userName={profile?.nombre_completo ?? "Usuario"}
        empresaNombre={empresa?.nombre_empresa ?? null}
        roleLabel={labelRol(rol)}
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
    </StorageBaseProvider>
  );
}
