import { getCurrentProfile } from "@/lib/auth";
import {
  getNavSectionsForRole,
  getRoleNameFromProfile,
} from "@/lib/auth/roles";
import { DashboardShell } from "@/components/layout/dashboard-shell";
import { InstallPwaPrompt } from "@/components/pwa/install-prompt";

export default async function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);
  const navSections = getNavSectionsForRole(rol);

  return (
    <DashboardShell
      userName={profile?.nombre_completo ?? "Usuario"}
      navSections={navSections}
    >
      <main className="flex-1 overflow-x-hidden overflow-y-auto p-4 pb-[max(1rem,env(safe-area-inset-bottom))] sm:p-6 lg:p-8">
        <div className="lt-no-print">
          <InstallPwaPrompt />
        </div>
        {children}
      </main>
    </DashboardShell>
  );
}
